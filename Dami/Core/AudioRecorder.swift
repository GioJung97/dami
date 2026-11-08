import AVFoundation
import CoreAudio
import os

/// Records a microphone into memory as 16 kHz mono Float32, the format Whisper expects.
/// Nothing is written to disk unless "Save audio recordings" is on.
///
/// Engine work can block, particularly on Bluetooth, so it runs on a serial queue: `stop` naturally
/// waits for a `start` in progress, and the main thread never does. Each capture gets a new
/// `AVAudioEngine`, since a format cached from before a device change can crash `installTap`.
///
/// Call `start`, `stop` and `endTail` on the main thread. Completions and `onDeviceLost` arrive there.
final class AudioRecorder {
    static let sampleRate: Double = 16_000
    /// Attempts to resume after the engine stopped on a configuration change. Beyond this, the device
    /// counts as lost.
    private static let maxRestarts = 3

    struct Started {
        let device: InputDevice
        /// The saved microphone wasn't available, so this is the system default.
        let chosenMissing: Bool
    }

    /// Called on the audio thread with a 0…1 loudness value roughly every 50 ms.
    var onLevel: ((Float) -> Void)?
    /// The microphone went away while recording. What was captured is still there for `stop`.
    var onDeviceLost: (() -> Void)?

    private let queue = DispatchQueue(label: "io.github.giojung97.dami.audio", qos: .userInteractive)
    private let log = Logger(subsystem: "io.github.giojung97.dami", category: "audio")
    private var session: Session?
    private var pendingStop: DispatchWorkItem?

    /// - Parameter deviceUID: The saved microphone, or nil for the system default.
    func start(deviceUID: String?, completion: @escaping (Result<Started, Error>) -> Void) {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            completion(.failure(RecorderError.permissionMissing))
            return
        }
        let session = Session()
        session.onLevel = { [weak self] in self?.onLevel?($0) }
        self.session = session

        queue.async { [self] in
            do {
                let chosen = deviceUID.flatMap { uid in CoreAudioDevices.inputDevices().first { $0.id == uid } }
                guard let device = chosen ?? CoreAudioDevices.defaultInput() else { throw RecorderError.noMicrophone }
                session.device = device
                let began = Date()
                try beginCapture(session)
                log.notice("Mic started in \(Int(Date().timeIntervalSince(began) * 1000), privacy: .public) ms, wireless: \(device.isBluetooth || device.isContinuity, privacy: .public)")
                let started = Started(device: device, chosenMissing: deviceUID != nil && chosen == nil)
                DispatchQueue.main.async { completion(.success(started)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// Stops recording after `tail` seconds and returns everything captured since `start`.
    func stop(tail: TimeInterval = 0, completion: @escaping ([Float]) -> Void) {
        guard let session else {
            completion([])
            return
        }
        self.session = nil
        let stop = DispatchWorkItem { [self] in
            guard !session.isFinished else { return }
            session.isFinished = true
            endCapture(session)
            let samples = session.takeSamples()
            DispatchQueue.main.async { completion(samples) }
        }
        pendingStop = stop
        if tail > 0 {
            queue.asyncAfter(deadline: .now() + tail, execute: stop)
        } else {
            queue.async(execute: stop)
        }
    }

    /// Ends a tail started by `stop(tail:)` right away.
    func endTail() {
        guard let pendingStop else { return }
        queue.async(execute: pendingStop)
    }

    // MARK: Capture (on the queue)

    private func beginCapture(_ session: Session) throws {
        guard let device = session.device else { throw RecorderError.noMicrophone }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        guard let unit = input.audioUnit else { throw RecorderError.noMicrophone }
        var deviceID = device.audioID
        let selected = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        let format = input.outputFormat(forBus: 0)
        guard selected == noErr, format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noMicrophone }

        // With a nil format the tap uses the node's own format, which can't mismatch and crash.
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(format.sampleRate * 0.05), format: nil) { [weak session] buffer, _ in
            session?.append(buffer)
        }
        session.engine = engine
        session.configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self, weak session] _ in
            guard let self, let session else { return }
            self.queue.async { self.deviceChanged(session) }
        }
        // Not every removal produces a configuration change.
        let aliveListener: AudioObjectPropertyListenerBlock = { [weak self, weak session] _, _ in
            guard let self, let session else { return }
            self.deviceChanged(session)
        }
        var address = CoreAudioDevices.propertyAddress(kAudioDevicePropertyDeviceIsAlive)
        AudioObjectAddPropertyListenerBlock(deviceID, &address, queue, aliveListener)
        session.aliveListener = aliveListener

        do {
            engine.prepare()
            try engine.start()
        } catch {
            endCapture(session)
            throw error
        }
    }

    private func endCapture(_ session: Session) {
        if let observer = session.configurationObserver {
            NotificationCenter.default.removeObserver(observer)
            session.configurationObserver = nil
        }
        if let aliveListener = session.aliveListener, let device = session.device {
            var address = CoreAudioDevices.propertyAddress(kAudioDevicePropertyDeviceIsAlive)
            AudioObjectRemovePropertyListenerBlock(device.audioID, &address, queue, aliveListener)
            session.aliveListener = nil
        }
        if let engine = session.engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            session.engine = nil
        }
    }

    /// Selecting a device makes the engine report a configuration change just after it starts, while
    /// it keeps running and delivering audio, so a change alone means nothing. If the engine really
    /// stopped, resume on the same device if it's still there; a recording stays on its device even
    /// if the system default moves.
    private func deviceChanged(_ session: Session) {
        guard !session.isFinished, let engine = session.engine, let device = session.device else { return }
        let isAlive = CoreAudioDevices.isAlive(device.audioID)
        if isAlive, engine.isRunning { return }
        endCapture(session)
        session.restarts += 1
        if isAlive, session.restarts <= Self.maxRestarts {
            do {
                try beginCapture(session)
                log.notice("Mic resumed after a configuration change")
                return
            } catch {
                log.error("Mic couldn't resume: \(error.localizedDescription, privacy: .public)")
            }
        }
        log.notice("Mic lost while recording")
        HealthCounter.count(.micLost)
        DispatchQueue.main.async { [self] in
            if self.session === session { onDeviceLost?() }
        }
    }

    /// One recording: its samples outlive any engines used to capture them. Engine fields are only
    /// touched on the queue; `samples` is also written from the audio thread.
    private final class Session {
        var onLevel: ((Float) -> Void)?
        var device: InputDevice?
        var engine: AVAudioEngine?
        var configurationObserver: NSObjectProtocol?
        var aliveListener: AudioObjectPropertyListenerBlock?
        var restarts = 0
        var isFinished = false

        private let lock = NSLock()
        private var captured: [Float] = []
        /// Only touched on the audio thread. Recreated if the buffer format changes.
        private var converter: AVAudioConverter?
        private let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: AudioRecorder.sampleRate, channels: 1, interleaved: false
        )

        /// Hands over the audio, so a finished session doesn't keep up to 5 minutes of it in memory.
        func takeSamples() -> [Float] {
            lock.withLock {
                defer { captured = [] }
                return captured
            }
        }

        func append(_ buffer: AVAudioPCMBuffer) {
            guard let targetFormat else { return }
            if converter?.inputFormat != buffer.format {
                converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            }
            guard let converter else { return }
            let ratio = targetFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

            var consumed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, let channel = out.floatChannelData?[0] else { return }
            let chunk = UnsafeBufferPointer(start: channel, count: Int(out.frameLength))
            lock.withLock { captured.append(contentsOf: chunk) }
            onLevel?(AudioRecorder.loudness(chunk))
        }
    }

    /// RMS mapped from about -55…-10 dBFS onto 0…1, so normal speech fills the meter.
    static func loudness<C: Collection>(_ samples: C) -> Float where C.Element == Float {
        guard !samples.isEmpty else { return 0 }
        let meanSquare = samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)
        let db = 10 * log10(max(meanSquare, 1e-10))
        return min(1, max(0, (db + 55) / 45))
    }

    /// True if no 100 ms window is louder than a quiet room. Used to skip silent recordings,
    /// which Whisper otherwise "hears" as "Thank you for watching" and the like.
    static func isSilent(_ samples: [Float]) -> Bool {
        let window = Int(sampleRate / 10)
        var index = 0
        while index < samples.count {
            let end = min(index + window, samples.count)
            if loudness(samples[index..<end]) > 0.25 { return false }
            index = end
        }
        return true
    }

    /// 16-bit mono WAV, for the optional "Save audio recordings" setting.
    static func writeWAV(_ samples: [Float], to url: URL) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw RecorderError.unsupportedFormat
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }

    enum RecorderError: LocalizedError {
        case unsupportedFormat, noMicrophone, permissionMissing
        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: "The microphone's audio format isn't supported."
            case .noMicrophone: "No microphone found"
            case .permissionMissing: "Microphone permission needed"
            }
        }
    }
}
