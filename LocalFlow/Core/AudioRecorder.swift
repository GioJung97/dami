import AVFoundation

/// Records the default microphone into memory as 16 kHz mono Float32, the format Whisper expects.
/// Nothing is written to disk unless "Save audio recordings" is on.
final class AudioRecorder {
    static let sampleRate: Double = 16_000

    /// Called on the audio thread with a 0…1 loudness value roughly every 50 ms.
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []

    func start() throws {
        lock.withLock { samples.removeAll(keepingCapacity: true) }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.unsupportedFormat
        }

        let bufferSize = AVAudioFrameCount(inputFormat.sampleRate * 0.05)
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer, using: converter, to: targetFormat)
        }
        engine.prepare()
        try engine.start()
    }

    /// Stops recording and returns everything captured since `start()`.
    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return lock.withLock { samples }
    }

    private func append(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter, to format: AVAudioFormat) {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }

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
        lock.withLock { samples.append(contentsOf: chunk) }
        onLevel?(Self.loudness(chunk))
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
        case unsupportedFormat
        var errorDescription: String? { "The microphone's audio format isn't supported." }
    }
}
