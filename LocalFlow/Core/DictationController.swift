import AppKit
import Combine
import LocalFlowCore
import os

/// The shortcut and the current recording. A finished recording goes to `DictationProcessor`, so
/// the next one can start right away.
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
    static let limitWarningSeconds: TimeInterval = 240
    static let limitSeconds: TimeInterval = 300
    static let pruneIntervalSeconds: TimeInterval = 86_400

    /// Whether the speech model can be used, apart from anything a single dictation does.
    enum ModelStatus: Equatable {
        case downloading(Double)
        case loading
        case ready
        case failed(ModelProblem)
    }

    @Published private(set) var state: State = .loadingModel(progress: 0)
    @Published private(set) var modelStatus: ModelStatus = .loading
    /// Dictations that can be tried again, oldest first.
    @Published private(set) var failedDictations: [DictationProcessor.FailedDictation] = []
    @Published private(set) var hotkeyActive = false
    /// Recent results kept in memory, so "paste again" works even when history is off.
    @Published private(set) var recent: [RecentDictation] = []

    /// With history off, dictations have no database id, so each entry gets its own.
    struct RecentDictation: Identifiable {
        let id = UUID()
        let dictation: Dictation
    }

    let hud = HUDController()

    private let settings = AppSettings.shared
    private let store = Store.shared
    private let hotkey = HotkeyMonitor()
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let processor: DictationProcessor
    private let log = Logger(subsystem: "com.localflow.app", category: "dictation")
    private var cancellables: Set<AnyCancellable> = []

    private var pressStartedAt: Date?
    private var lastTapAt: Date?
    private var handsFree = false
    private var isRecording = false
    private var failureMessage: String?
    /// Silent recordings in a row. A second one suggests the wrong microphone.
    private var silentRecordings = 0
    private var microphoneName: String?
    private var microphoneTransport: String?
    /// Recordings stopped but not yet handed over: the tail is still running.
    private var stoppingRecordings: Set<Int> = []
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

    var isModelReady: Bool { modelStatus == .ready }

    /// Judged by the hotkey really running rather than by what the Input Monitoring check says.
    var permissionsReady: Bool { Permissions.shared.coreGranted && hotkeyActive }

    init() {
        processor = DictationProcessor(transcriber: transcriber)
        processor.onOutcome = { [weak self] in self?.dictationEnded($0) }
        processor.onRecorded = { [weak self] saved in
            guard let self else { return }
            recent = Array(([RecentDictation(dictation: saved)] + recent).prefix(3))
        }
        processor.onChange = { [weak self] in self?.refreshState() }
        processor.onSlow = { [weak self] in self?.showWork() }
        hud.restingPhase = { [weak self] in self?.restingPhase ?? .hidden }

        TextInserter.keyboard = hotkey
        hotkey.shortcut = settings.shortcut
        hotkey.onPress = { [weak self] in self?.shortcutPressed() }
        hotkey.onRelease = { [weak self] in self?.shortcutReleased() }
        hotkey.onCancel = { [weak self] in self?.cancelRecording() }
        hotkey.onEscape = { [weak self] in self?.escapePressed() }
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

        startPruning()
        recent = store.dictations.prefix(3).map(RecentDictation.init)
        startHotkeyWhenPermitted()

        loadModel()
    }

    /// Tries again after the model failed: another download, or replacing bad files.
    func retryModel() {
        guard case .failed(let problem) = modelStatus else { return }
        loadModel(deletingFirst: problem.needsRedownload)
    }

    func retry(_ dictation: DictationProcessor.FailedDictation) {
        processor.retry(dictation.id)
    }

    func dismiss(_ dictation: DictationProcessor.FailedDictation) {
        processor.dismiss(dictation.id)
    }

    /// At launch and every day after, since the app can run for weeks.
    private func startPruning() {
        Task {
            while !Task.isCancelled {
                store.prune(retentionDays: settings.retentionDays, audioRetentionDays: settings.audioRetentionDays)
                try? await Task.sleep(for: .seconds(Self.pruneIntervalSeconds))
            }
        }
    }

    private func loadModel(deletingFirst: Bool = false) {
        setModelStatus(Transcriber.isModelDownloaded && !deletingFirst ? .loading : .downloading(0))
        Task {
            do {
                if deletingFirst { await transcriber.deleteModel() }
                try await transcriber.load { progress in
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading = modelStatus else { return }
                        setModelStatus(progress < 1 ? .downloading(progress) : .loading)
                    }
                }
                setModelStatus(.ready)
                log.info("Model loaded")
            } catch {
                setModelStatus(.failed(error as? ModelProblem ?? .loadFailed))
                log.error("Model unavailable: \(error.localizedDescription, privacy: .public)")
                HealthCounter.count(.modelUnavailable)
            }
            // Dictations made while it loaded are moving now, or just failed.
            if !isRecording, isWorking { showWork() }
        }
    }

    private func setModelStatus(_ status: ModelStatus) {
        modelStatus = status
        refreshState()
    }

    /// Settings' shortcut recorder needs the real shortcut to stay quiet while it listens.
    func suspendHotkey(_ suspended: Bool) {
        hotkey.isSuspended = suspended
    }

    func pasteAgain(_ dictation: Dictation) {
        Task {
            // Give the menu or window time to close so focus returns to the previous app.
            try? await Task.sleep(for: .milliseconds(150))
            if case .copied(let reason) = await TextInserter.insert(dictation.finalText, language: dictation.language) {
                hud.show(.copied(reason.message))
            }
        }
    }

    // MARK: Hotkey

    /// The event tap needs Input Monitoring + Accessibility; retry until they're granted. Creating it makes macOS ask for Accessibility,
    /// so during first-time setup it waits for the Allow buttons. After setup, it keeps trying whatever the permission checks say.
    /// Input Monitoring isn't waited for: setup asks for it only if this doesn't start.
    private func startHotkeyWhenPermitted() {
        if (settings.hasCompletedOnboarding || Permissions.shared.coreGranted) && hotkey.start() {
            hotkeyActive = true
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            startHotkeyWhenPermitted()
        }
    }

    private func shortcutPressed() {
        if isRecording && handsFree {
            handsFree = false
            finish()
            return
        }
        if !stoppingRecordings.isEmpty { recorder.endTail() }
        guard !isRecording, !settings.paused else { return }
        guard settings.hasCompletedOnboarding || SetupStep(rawValue: settings.setupStep)?.allowsShortcut == true else {
            report("Finish setup first")
            Navigation.shared.openSetup()
            return
        }
        switch modelStatus {
        case .downloading(let progress):
            report("Downloading speech model · \(Int(progress * 100))%")
            return
        case .failed:
            report("Speech model isn't ready", actionTitle: "Open") {
                Navigation.shared.openSettings(tab: "Models")
            }
            return
        case .loading, .ready:
            break // While loading, record anyway: the dictation waits for the model.
        }
        pressStartedAt = Date()
        startRecording()
    }

    private func shortcutReleased() {
        guard isRecording, !handsFree, let started = pressStartedAt else { return }
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
        setRecording(true)
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
        guard number == recordingNumber, isRecording else { return }
        switch result {
        case .success(let started):
            // The sound means "go ahead", so it waits until the microphone is really on.
            if settings.playSounds { NSSound(named: "Tink")?.play() }
            microphoneName = started.device.name
            microphoneTransport = started.device.transportName
            if let note = InputDevices.shared.note(for: started, chosen: chosen) { hud.show(note: note) }
        case .failure(let error):
            log.error("Recording failed: \(error.localizedDescription, privacy: .public)")
            HealthCounter.count(.recordingFailed)
            handsFree = false
            discardRecording()
            if case AudioRecorder.RecorderError.permissionMissing = error {
                report(error.localizedDescription, actionTitle: "Open") { Permissions.shared.requestMicrophone() }
            } else {
                report(error.localizedDescription)
            }
            showFailure(error.localizedDescription)
        }
    }

    private func startLimitTimer() {
        limitTask?.cancel()
        let started = Date()
        limitTask = Task {
            await Self.waitUntil(started.addingTimeInterval(Self.limitWarningSeconds))
            guard !Task.isCancelled else { return }
            hud.show(note: "1 minute left")
            await Self.waitUntil(started.addingTimeInterval(Self.limitSeconds))
            guard !Task.isCancelled, isRecording else { return }
            handsFree = false
            hud.show(note: "5 minute limit reached")
            finish()
        }
    }

    /// One long sleep ran about 6% late in a 10-minute recording, so check the clock every second.
    private static func waitUntil(_ deadline: Date) async {
        while !Task.isCancelled, Date() < deadline {
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func microphoneLost() {
        guard isRecording else { return }
        handsFree = false
        hud.show(note: "Microphone disconnected · kept what you said")
        finish(tail: 0)
    }

    private func finishBeforeSleep() {
        guard isRecording else { return }
        handsFree = false
        finish(tail: 0)
    }

    private func discardRecording() {
        limitTask?.cancel()
        recorder.stop { _ in }
        setRecording(false)
        showWorkOrHide()
    }

    private func cancelRecording() {
        guard isRecording else { return }
        handsFree = false
        discardRecording()
    }

    /// Esc cancels the recording if there is one, otherwise everything still being processed.
    private func escapePressed() {
        if isRecording {
            cancelRecording()
        } else if isWorking {
            stoppingRecordings.removeAll()
            recorder.endTail()
            processor.cancelAll()
            refreshState()
            hud.hide()
        }
    }

    private func finish(tail: TimeInterval? = nil) {
        limitTask?.cancel()
        setRecording(false)

        let number = recordingNumber
        let app = targetApp
        stoppingRecordings.insert(number)
        refreshState()
        showWork()
        recorder.stop(tail: tail ?? Self.tailSeconds) { [weak self] audio in
            MainActor.assumeIsolated { self?.recordingStopped(audio, number: number, app: app) }
        }
    }

    private func recordingStopped(_ audio: [Float], number: Int, app: NSRunningApplication?) {
        // Esc may have cancelled it during the tail.
        guard stoppingRecordings.remove(number) != nil else { return }
        // After the tail, so the microphone doesn't pick up the sound.
        if settings.playSounds, !isRecording { NSSound(named: "Pop")?.play() }

        let seconds = Double(audio.count) / AudioRecorder.sampleRate
        guard seconds >= Self.minimumSeconds else {
            refreshState()
            showWorkOrHide()
            return
        }
        guard !AudioRecorder.isSilent(audio) else {
            refreshState()
            silentRecordings += 1
            DictationProcessor.countDrop(.silent, audioSeconds: seconds)
            let text = microphoneName.map { "No sound heard · Mic: \($0)" } ?? "No sound heard"
            if silentRecordings >= 2 {
                report(text, actionTitle: "Check microphone") { Navigation.shared.openSettings(tab: "General") }
            } else {
                report(text)
            }
            return
        }
        silentRecordings = 0

        let second = settings.secondLanguage
        let forced: String? = switch settings.language {
        case .auto: nil
        case .english: "en"
        case .second: second?.code ?? "en"
        }
        processor.add(DictationProcessor.Job(
            audio: audio,
            seconds: seconds,
            options: Transcriber.Options(
                secondLanguage: second,
                forcedLanguage: forced,
                keepEnglishTerms: settings.keepEnglishTerms,
                vocabulary: store.vocabulary.map(\.term).filter { term in second?.script?.matches(term) != true },
                wordTimestamps: true
            ),
            mode: settings.cleanupMode,
            inputTransport: microphoneTransport,
            appName: app?.localizedName,
            appBundleID: app?.bundleIdentifier
        ))
    }

    private func dictationEnded(_ outcome: DictationProcessor.Outcome) {
        switch outcome {
        case .pasted:
            // The job that just ended still counts as busy, so look only at what comes after it.
            guard !isRecording else { return }
            if processor.waitingCount > 0 || !stoppingRecordings.isEmpty { showWork() } else { hud.show(.pasted) }
        case .copied(let reason):
            if isRecording { hud.show(note: reason.message) } else { hud.show(.copied(reason.message)) }
        case .noSpeech:
            report("No speech recognized")
        case .failed(let dictation):
            report(dictation.message, actionTitle: "Retry") { [weak self] in self?.processor.retry(dictation.id) }
        }
    }

    // MARK: State

    /// Work that hasn't been cancelled: a tail still running, or dictations in the processor.
    private var isWorking: Bool { processor.isBusy || !stoppingRecordings.isEmpty }

    private func setRecording(_ recording: Bool) {
        isRecording = recording
        processor.isRecording = recording
        refreshState()
    }

    private func refreshState() {
        hotkey.capturesEscape = isRecording || isWorking
        failedDictations = processor.failed
        if isRecording {
            state = .recording
        } else if isWorking {
            state = .transcribing
        } else {
            switch modelStatus {
            case .downloading(let progress): state = .loadingModel(progress: progress)
            case .loading: state = .loadingModel(progress: 1)
            case .failed(let problem): state = .failed(problem.message)
            case .ready: state = failureMessage.map(State.failed) ?? .idle
            }
        }
        if case .transcribing = hud.phase, isWorking { showWork() }
    }

    /// What the indicator shows for work in progress.
    private var workPhase: HUDController.Phase {
        if modelStatus == .loading { return .message(.init(text: "Getting ready…", isSticky: true)) }
        if processor.isSlow { return .message(.init(text: "Still working… Esc to cancel", isSticky: true)) }
        return .transcribing(waiting: processor.waitingCount)
    }

    /// What to show once a timed message is over.
    private var restingPhase: HUDController.Phase {
        if isRecording { return .recording(handsFree: handsFree) }
        return isWorking ? workPhase : .hidden
    }

    private func showWork() {
        guard !isRecording else { return }
        hud.show(workPhase)
    }

    private func showWorkOrHide() {
        if isWorking { showWork() } else { hud.hide() }
    }

    /// Tells the user something. During a recording it goes above the meter, without a button.
    private func report(_ text: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        if isRecording {
            hud.show(note: text)
        } else {
            hud.show(message: text, actionTitle: actionTitle, action: action)
        }
    }

    private func showFailure(_ message: String) {
        failureMessage = message
        refreshState()
        Task {
            try? await Task.sleep(for: .seconds(3))
            failureMessage = nil
            refreshState()
        }
    }
}
