import AppKit
import Combine
import LocalFlowCore
import os

/// Runs dictation: shortcut → record → transcribe → replacements → paste → history.
@MainActor
final class DictationController: ObservableObject {
    enum State: Equatable {
        case loadingModel(progress: Double)
        case idle
        case recording
        case transcribing
        case failed(String)

        var symbolName: String {
            switch self {
            case .loadingModel: "hourglass"
            case .idle: "waveform"
            case .recording: "record.circle.fill"
            case .transcribing: "ellipsis.circle"
            case .failed: "exclamationmark.triangle"
            }
        }
    }

    /// Shorter presses are accidental taps (or the first half of a double-tap).
    static let minimumSeconds = 0.3
    /// Two taps closer than this start hands-free recording.
    static let doubleTapWindow = 0.45
    /// Keep recording this long after release, so last syllables survive.
    static let tailSeconds = 0.2
    /// Recording limit, in every mode.
    static let limitWarningSeconds: TimeInterval = 540
    static let limitSeconds: TimeInterval = 600

    @Published private(set) var state: State = .loadingModel(progress: 0)
    @Published private(set) var hotkeyActive = false
    /// Recent results kept in memory, so "paste again" works even when history is off.
    @Published private(set) var recent: [Dictation] = []

    let hud = HUDController()

    private let settings = AppSettings.shared
    private let store = Store.shared
    private let hotkey = HotkeyMonitor()
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let log = Logger(subsystem: "com.localflow.app", category: "dictation")
    private var cancellables: Set<AnyCancellable> = []

    private var pressStartedAt: Date?
    private var lastTapAt: Date?
    private var handsFree = false
    private var targetApp: NSRunningApplication?
    private var limitTask: Task<Void, Never>?
    /// Tells a late result from `recorder.start` which recording it belongs to.
    private var recordingNumber = 0

    var statusText: String {
        switch state {
        case .loadingModel(let progress):
            progress < 1 ? "Downloading speech model… \(Int(progress * 100))%" : "Loading speech model…"
        case .idle:
            if settings.paused { "Paused" } else if !hotkeyActive { "Waiting for permissions" } else { "Ready" }
        case .recording: handsFree ? "Listening (hands-free)…" : "Listening…"
        case .transcribing: "Transcribing…"
        case .failed(let message): "Error: \(message)"
        }
    }

    var isModelReady: Bool {
        switch state {
        case .loadingModel: false
        default: true
        }
    }

    init() {
        hotkey.shortcut = settings.shortcut
        hotkey.onPress = { [weak self] in self?.shortcutPressed() }
        hotkey.onRelease = { [weak self] in self?.shortcutReleased() }
        hotkey.onCancel = { [weak self] in self?.cancel() }
        hotkey.onEscape = { [weak self] in self?.cancel() }
        recorder.onLevel = { [weak self] level in
            Task { @MainActor in self?.hud.push(level: level) }
        }
        recorder.onDeviceLost = { [weak self] in
            MainActor.assumeIsolated { self?.microphoneLost() }
        }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.finishBeforeSleep() }
            .store(in: &cancellables)

        settings.$shortcut
            .sink { [weak self] in self?.hotkey.shortcut = $0 }
            .store(in: &cancellables)
        settings.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        store.prune(retentionDays: settings.retentionDays)
        recent = Array(store.dictations.prefix(3))
        startHotkeyWhenPermitted()

        Task {
            do {
                try await transcriber.load { progress in
                    Task { @MainActor [weak self] in
                        if case .loadingModel = self?.state { self?.state = .loadingModel(progress: progress) }
                    }
                }
                state = .idle
                log.info("Model loaded")
            } catch {
                state = .failed(error.localizedDescription)
                log.error("Model load failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Settings' shortcut recorder needs the real shortcut to stay quiet while it listens.
    func suspendHotkey(_ suspended: Bool) {
        hotkey.isSuspended = suspended
    }

    func pasteAgain(_ dictation: Dictation) {
        Task {
            // Give the menu or window time to close so focus returns to the previous app.
            try? await Task.sleep(for: .milliseconds(150))
            if await TextInserter.insert(dictation.finalText) == .copiedOnly {
                hud.show(.copiedOnly)
            }
        }
    }

    // MARK: Hotkey

    /// The event tap needs Input Monitoring + Accessibility; retry until they're granted.
    private func startHotkeyWhenPermitted() {
        if hotkey.start() {
            hotkeyActive = true
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            startHotkeyWhenPermitted()
        }
    }

    private func shortcutPressed() {
        if state == .recording && handsFree {
            handsFree = false
            finish()
            return
        }
        if state == .transcribing { recorder.endTail() }
        guard state == .idle, !settings.paused else { return }
        pressStartedAt = Date()
        startRecording()
    }

    private func shortcutReleased() {
        guard state == .recording, !handsFree, let started = pressStartedAt else { return }
        let held = Date().timeIntervalSince(started)
        if held >= Self.minimumSeconds {
            finish()
            return
        }
        // A quick tap.
        if settings.shortcutMode == .holdOrDoubleTap,
           let lastTap = lastTapAt, Date().timeIntervalSince(lastTap) < Self.doubleTapWindow {
            handsFree = true
            lastTapAt = nil
            hud.show(.recording(handsFree: true))
            objectWillChange.send()
        } else {
            lastTapAt = Date()
            discardRecording()
        }
    }

    // MARK: Recording

    private func startRecording() {
        targetApp = NSWorkspace.shared.frontmostApplication
        state = .recording
        hotkey.isRecording = true
        hud.show(.recording(handsFree: false))
        startLimitTimer()

        recordingNumber += 1
        let number = recordingNumber
        let chosen = settings.inputDeviceUID
        recorder.start(deviceUID: chosen) { [weak self] result in
            MainActor.assumeIsolated { self?.recordingStarted(result, number: number, chosen: chosen) }
        }
    }

    private func recordingStarted(_ result: Result<AudioRecorder.Started, Error>, number: Int, chosen: String?) {
        guard number == recordingNumber, state == .recording else { return }
        switch result {
        case .success(let started):
            // The sound means "go ahead", so it waits until the microphone is really on.
            if settings.playSounds { NSSound(named: "Tink")?.play() }
            if let note = InputDevices.shared.note(for: started, chosen: chosen) { hud.show(note: note) }
        case .failure(let error):
            log.error("Recording failed: \(error.localizedDescription, privacy: .public)")
            handsFree = false
            discardRecording()
            hud.show(note: error.localizedDescription)
            showFailure(error.localizedDescription)
        }
    }

    private func startLimitTimer() {
        limitTask?.cancel()
        limitTask = Task {
            try? await Task.sleep(for: .seconds(Self.limitWarningSeconds))
            guard !Task.isCancelled else { return }
            hud.show(note: "1 minute left")
            try? await Task.sleep(for: .seconds(Self.limitSeconds - Self.limitWarningSeconds))
            guard !Task.isCancelled, state == .recording else { return }
            handsFree = false
            hud.show(note: "10 minute limit reached")
            finish()
        }
    }

    private func microphoneLost() {
        guard state == .recording else { return }
        handsFree = false
        hud.show(note: "Microphone disconnected · kept what you said")
        finish(tail: 0)
    }

    private func finishBeforeSleep() {
        guard state == .recording else { return }
        handsFree = false
        finish(tail: 0)
    }

    private func discardRecording() {
        limitTask?.cancel()
        recorder.stop { _ in }
        hotkey.isRecording = false
        state = .idle
        hud.hide()
    }

    private func cancel() {
        guard state == .recording else { return }
        handsFree = false
        discardRecording()
    }

    private func finish(tail: TimeInterval? = nil) {
        limitTask?.cancel()
        hotkey.isRecording = false
        state = .transcribing
        hud.show(.transcribing)
        recorder.stop(tail: tail ?? Self.tailSeconds) { [weak self] audio in
            MainActor.assumeIsolated { self?.transcribe(audio) }
        }
    }

    private func transcribe(_ audio: [Float]) {
        // After the tail, so the microphone doesn't pick up the sound.
        if settings.playSounds { NSSound(named: "Pop")?.play() }

        let seconds = Double(audio.count) / AudioRecorder.sampleRate
        guard seconds >= Self.minimumSeconds, !AudioRecorder.isSilent(audio) else {
            state = .idle
            hud.hide()
            return
        }

        let second = settings.secondLanguage
        let forced: String? = switch settings.language {
        case .auto: nil
        case .english: "en"
        case .second: second?.code ?? "en"
        }
        let options = Transcriber.Options(
            secondLanguage: second,
            forcedLanguage: forced,
            keepEnglishTerms: settings.keepEnglishTerms,
            vocabulary: store.vocabulary.map(\.term).filter { term in second?.script?.matches(term) != true }
        )
        let app = targetApp

        Task {
            let started = Date()
            do {
                let result = try await transcriber.transcribe(audio, options: options)
                let latency = Date().timeIntervalSince(started)
                log.info("[\(result.language, privacy: .public)] \(String(format: "%.1f", seconds))s audio → \(String(format: "%.2f", latency))s")

                guard !HallucinationFilter.isHallucination(result.text) else {
                    state = .idle
                    hud.hide()
                    return
                }
                let processed = TextPipeline.process(
                    raw: result.text, mode: .light, language: result.language, rules: store.replacements.map(\.rule)
                )
                let outcome = await TextInserter.insert(processed.final)
                hud.show(outcome == .pasted ? .pasted : .copiedOnly)

                record(Dictation(
                    createdAt: Date(),
                    appName: app?.localizedName,
                    appBundleID: app?.bundleIdentifier,
                    language: result.language,
                    audioSeconds: seconds,
                    latencySeconds: latency,
                    rawText: result.text,
                    finalText: processed.final,
                    note: Self.note(for: processed.replacementUses)
                ), audio: audio, uses: processed.replacementUses)
                state = .idle
            } catch {
                log.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
                showFailure(error.localizedDescription)
            }
        }
    }

    private func record(_ dictation: Dictation, audio: [Float], uses: [Int64: Int]) {
        store.recordUses(uses)
        var saved = dictation
        if settings.retentionDays >= 0 {
            saved = store.add(dictation)
            if settings.saveAudio, let id = saved.id {
                try? AudioRecorder.writeWAV(audio, to: Store.audioURL(for: id))
            }
        }
        recent = Array(([saved] + recent).prefix(3))
    }

    private static func note(for uses: [Int64: Int]) -> String? {
        let total = uses.values.reduce(0, +)
        guard total > 0 else { return nil }
        return total == 1 ? "1 replacement applied from your Dictionary." : "\(total) replacements applied from your Dictionary."
    }

    private func showFailure(_ message: String) {
        state = .failed(message)
        hud.hide()
        Task {
            try? await Task.sleep(for: .seconds(3))
            if case .failed = state { state = .idle }
        }
    }
}
