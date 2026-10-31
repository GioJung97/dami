import AppKit
import Combine
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
        do {
            targetApp = NSWorkspace.shared.frontmostApplication
            try recorder.start()
            state = .recording
            hotkey.isRecording = true
            hud.show(.recording(handsFree: false))
            if settings.playSounds { NSSound(named: "Tink")?.play() }
        } catch {
            log.error("Recording failed: \(error.localizedDescription, privacy: .public)")
            showFailure(error.localizedDescription)
        }
    }

    private func discardRecording() {
        _ = recorder.stop()
        hotkey.isRecording = false
        state = .idle
        hud.hide()
    }

    private func cancel() {
        guard state == .recording else { return }
        handsFree = false
        discardRecording()
    }

    private func finish() {
        let audio = recorder.stop()
        hotkey.isRecording = false
        if settings.playSounds { NSSound(named: "Pop")?.play() }

        let seconds = Double(audio.count) / AudioRecorder.sampleRate
        guard seconds >= Self.minimumSeconds, !AudioRecorder.isSilent(audio) else {
            state = .idle
            hud.hide()
            return
        }

        state = .transcribing
        hud.show(.transcribing)
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
                let replaced = ReplacementEngine.apply(store.replacements, to: result.text)
                let outcome = await TextInserter.insert(replaced.text)
                hud.show(outcome == .pasted ? .pasted : .copiedOnly)

                record(Dictation(
                    createdAt: Date(),
                    appName: app?.localizedName,
                    appBundleID: app?.bundleIdentifier,
                    language: result.language,
                    audioSeconds: seconds,
                    latencySeconds: latency,
                    rawText: result.text,
                    finalText: replaced.text,
                    note: Self.note(for: replaced.uses)
                ), audio: audio, uses: replaced.uses)
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
