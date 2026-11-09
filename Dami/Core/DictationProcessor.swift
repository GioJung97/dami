import Foundation
import DamiCore
import os

/// What happens to a finished recording: transcribe → `TextPipeline` → paste → history, one at a
/// time and in order. Runs on its own while the next recording goes on.
@MainActor
final class DictationProcessor {
    enum Outcome {
        case pasted
        case copied(TextInserter.Outcome.Reason)
        case noSpeech
        /// A retry of a drop came back empty again.
        case stillNoSpeech
        case failed(FailedDictation)
        /// Dropped, but kept to retry or paste anyway.
        case dropped(FailedDictation)
    }

    /// One recording and everything needed to process it, fixed when the recording ended.
    struct Job: Sendable {
        let audio: [Float]
        let seconds: Double
        let options: Transcriber.Options
        let mode: CleanupMode
        let inputTransport: String?
        let appName: String?
        let appBundleID: String?
        /// When the shortcut was let go, before the tail: the start of the wait the person feels.
        var stoppedAt = Date()
        /// The first dictation after a while idle, timed apart.
        var isFirstAfterIdle = false
        /// Set for "Paste anyway": what Whisper already returned, so it goes through the order without transcribing again.
        var pasteAnyway: PasteAnyway?
    }

    struct PasteAnyway: Sendable {
        let result: Transcriber.Result
        let latency: TimeInterval
    }

    /// A dictation that can be tried again. Its audio, and a filtered text, stay in memory only, until then.
    struct FailedDictation: Identifiable, Sendable {
        enum Kind: Sendable {
            /// Transcription failed or timed out. Retry runs the same job.
            case failed
            /// Whisper returned nothing. `job` is already the retry with the other language.
            case empty
            /// Only a stock phrase, which the person may really have said. It can be pasted anyway.
            case filtered(text: String)
        }

        let id = UUID()
        let job: Job
        let message: String
        var kind: Kind = .failed
        /// What Whisper returned, for "Paste anyway".
        fileprivate var transcribed: Transcribed?
    }

    fileprivate struct Transcribed: Sendable {
        let result: Transcriber.Result
        let latency: TimeInterval
        /// When transcription started, after waiting for earlier jobs and the model.
        var started = Date()
    }

    private struct TimedOut: Error {}

    /// Say so when a dictation takes this long.
    private static let slowAfter: Duration = .seconds(5)
    private static let maxFailed = 3

    /// Called for each job that ends, unless it was cancelled.
    var onOutcome: ((Outcome) -> Void)?
    /// Called with what was stored, for "paste again".
    var onRecorded: ((Dictation) -> Void)?
    var onChange: (() -> Void)?
    /// The current dictation just became slow.
    var onSlow: (() -> Void)?

    /// Results wait while this is true.
    var isRecording: Bool {
        get { queue.isRecording }
        set { queue.isRecording = newValue }
    }

    var isBusy: Bool { queue.isBusy }
    var waitingCount: Int { queue.waitingCount }
    private(set) var isSlow = false
    private(set) var failed: [FailedDictation] = []

    private let settings = AppSettings.shared
    private let store = Store.shared
    private let log = Logger(subsystem: "io.github.giojung97.dami", category: "dictation")
    private let latencyLog = Logger(subsystem: "io.github.giojung97.dami", category: "latency")
    private var queue: DictationQueue<Job, Transcribed>!
    private var slowTask: Task<Void, Never>?

    init(transcriber: Transcriber) {
        queue = DictationQueue(
            process: { [weak self] job in
                if let earlier = job.pasteAnyway { return Transcribed(result: earlier.result, latency: earlier.latency) }
                try await transcriber.waitUntilReady()
                await self?.startSlowTimer()
                do {
                    let started = Date()
                    let result = try await Self.withTimeout(ProcessingLimits.timeout(audioSeconds: job.seconds)) {
                        try await transcriber.transcribe(job.audio, options: job.options)
                    }
                    await self?.stopSlowTimer()
                    return Transcribed(result: result, latency: Date().timeIntervalSince(started), started: started)
                } catch {
                    await self?.stopSlowTimer()
                    throw error
                }
            },
            deliver: { [weak self] job, transcribed in await self?.deliver(job, transcribed) },
            failed: { [weak self] job, error in self?.fail(job, error) }
        )
        queue.onChange = { [weak self] in self?.onChange?() }
    }

    func add(_ job: Job) {
        queue.add(job)
    }

    /// Drops everything pending. A job already running may finish in the background; its result is ignored.
    func cancelAll() {
        stopSlowTimer()
        queue.cancelAll()
    }

    /// Tries a failed dictation again, or pastes a filtered one anyway. The result pastes at the current cursor.
    func retry(_ id: FailedDictation.ID) {
        guard let index = failed.firstIndex(where: { $0.id == id }) else { return }
        let dictation = failed.remove(at: index)
        onChange?()
        var job = dictation.job
        job.stoppedAt = Date()
        // Through the queue either way, so it keeps the order and waits while a recording is on.
        if case .filtered = dictation.kind, let transcribed = dictation.transcribed {
            job.pasteAnyway = PasteAnyway(result: transcribed.result, latency: transcribed.latency)
        }
        queue.add(job)
    }

    func dismiss(_ id: FailedDictation.ID) {
        failed.removeAll { $0.id == id }
        onChange?()
    }

    private func startSlowTimer() {
        slowTask?.cancel()
        slowTask = Task {
            try? await Task.sleep(for: Self.slowAfter)
            guard !Task.isCancelled else { return }
            isSlow = true
            onSlow?()
        }
    }

    private func stopSlowTimer() {
        slowTask?.cancel()
        isSlow = false
    }

    private func deliver(_ job: Job, _ transcribed: Transcribed) async {
        let pastingAnyway = job.pasteAnyway != nil
        let result = transcribed.result
        log.info("[\(result.language, privacy: .public)] \(String(format: "%.1f", job.seconds))s audio → \(String(format: "%.2f", transcribed.latency))s")

        if !pastingAnyway, HallucinationFilter.isHallucination(result.text) {
            drop(job, transcribed)
            return
        }
        if PromptLeak.isLeak(output: result.text, prompt: result.prompt, vocabulary: result.promptVocabulary) {
            Self.countDrop(.promptEcho, audioSeconds: job.seconds)
            onOutcome?(.noSpeech)
            return
        }
        let cleanupStarted = Date()
        let processed = TextPipeline.process(
            raw: result.text, mode: job.mode, language: result.language, rules: store.replacements.map(\.rule)
        )
        let cleanupSeconds = Date().timeIntervalSince(cleanupStarted)
        // Nothing but fillers.
        guard !processed.final.isEmpty else {
            Self.countDrop(.onlyFillers, audioSeconds: job.seconds)
            if job.options.isDropRetry { Self.countRetry(.stillEmpty) }
            onOutcome?(.noSpeech)
            return
        }
        if pastingAnyway { Self.countRetry(.pastedAnyway) } else if job.options.isDropRetry { Self.countRetry(.text) }
        let pasteStarted = Date()
        let insertion = await TextInserter.insert(processed.final, language: result.language)
        if case .pasted = insertion, !pastingAnyway, let sent = TextInserter.lastSentAt {
            logLatency(job, transcribed, cleanup: cleanupSeconds, paste: sent.timeIntervalSince(pasteStarted), total: sent.timeIntervalSince(job.stoppedAt))
        }
        let target = TextInserter.takeLastTarget()
        let saved = record(Dictation(
            createdAt: Date(),
            appName: job.appName,
            appBundleID: job.appBundleID,
            language: result.language,
            audioSeconds: job.seconds,
            latencySeconds: transcribed.latency,
            rawText: result.text,
            finalText: processed.final,
            note: Self.note(for: processed),
            mode: job.mode.rawValue,
            rulesText: job.mode == .light ? processed.final : nil,
            rulesApplied: job.mode == .light ? Self.json(processed.rulesApplied.map(\.rawValue)) : nil,
            insertOutcome: insertion.recordName,
            modelName: Transcriber.modelName,
            pipelineVersion: TextPipeline.version,
            inputTransport: job.inputTransport,
            wordsJSON: result.words.isEmpty ? nil : Self.json(result.words)
        ), audio: job.audio, uses: processed.replacementUses)
        if case .pasted = insertion {
            PasteWatcher.shared.watch(saved, target: target)
        } else {
            PasteWatcher.shared.watch(saved, target: nil)
        }
        switch insertion {
        case .pasted: onOutcome?(.pasted)
        case .copied(let reason): onOutcome?(.copied(reason))
        }
    }

    /// Numbers only: where the time went, from letting go of the shortcut to ⌘V being sent (v0.4 M1). `wait` includes the
    /// recording tail and any earlier dictation still running. Info logs aren't kept on disk, so the last `latencyKept` lines also
    /// go in UserDefaults `latencySamples`, read by `scripts/health-check.sh`. Read with
    /// `log show --predicate 'subsystem == "io.github.giojung97.dami" && category == "latency"'`.
    private func logLatency(_ job: Job, _ transcribed: Transcribed, cleanup: Double, paste: Double, total: Double) {
        let t = transcribed.result.timings
        let wait = transcribed.started.timeIntervalSince(job.stoppedAt)
        let mode = job.options.forcedLanguage == nil ? "auto" : "fixed"
        let line = String(
            format: "audio=%.2f lang=%@ mode=%@ firstAfterIdle=%d wait=%.3f detect=%.3f transcribe=%.3f runs=%d reused=%d cleanup=%.4f paste=%.3f total=%.3f",
            job.seconds, transcribed.result.language, mode, job.isFirstAfterIdle ? 1 : 0, wait, t.detect, t.transcribe, t.runs, t.reused,
            cleanup, paste, total
        )
        latencyLog.notice("\(line, privacy: .public)")
        let defaults = UserDefaults.standard
        let samples = defaults.stringArray(forKey: "latencySamples") ?? []
        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)"
        defaults.set(Array((samples + [stamped]).suffix(Self.latencyKept)), forKey: "latencySamples")
    }

    private static let latencyKept = 500

    /// An empty result or a stock phrase. Kept in memory for a retry or "Paste anyway" when it's long enough to be speech.
    private func drop(_ job: Job, _ transcribed: Transcribed) {
        let result = transcribed.result
        let isEmpty = result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        Self.countDrop(isEmpty ? .empty : .hallucination, audioSeconds: job.seconds)
        if job.options.isDropRetry { Self.countRetry(isEmpty ? .stillEmpty : .filtered) }

        if isEmpty, job.options.isDropRetry {
            onOutcome?(.stillNoSpeech)
            return
        }
        guard job.seconds >= DropRetry.minimumSeconds else {
            onOutcome?(.noSpeech)
            return
        }
        let dictation: FailedDictation
        if isEmpty {
            var options = job.options
            options.isDropRetry = true
            options.forcedLanguage = DropRetry.language(after: result.language, second: options.secondLanguage?.code)
            let retry = Job(
                audio: job.audio, seconds: job.seconds, options: options, mode: job.mode,
                inputTransport: job.inputTransport, appName: job.appName, appBundleID: job.appBundleID
            )
            dictation = FailedDictation(job: retry, message: "No speech recognized", kind: .empty)
        } else {
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            dictation = FailedDictation(job: job, message: "Filtered “\(text)”", kind: .filtered(text: text), transcribed: transcribed)
        }
        failed = Array((failed + [dictation]).suffix(Self.maxFailed))
        onOutcome?(.dropped(dictation))
    }

    /// Numbers only, read with `scripts/health-check.sh`. See `DropStats`. The undated `dropCounts` from before v0.3.1 stays as it was.
    static func countDrop(_ reason: DropStats.Reason, audioSeconds: Double) {
        count(DropStats.key(reason, audioSeconds: audioSeconds, on: Date()))
    }

    static func countRetry(_ result: DropStats.RetryResult) {
        count(DropStats.retryKey(result, on: Date()))
    }

    private static func count(_ key: String) {
        let defaults = UserDefaults.standard
        let counts = defaults.dictionary(forKey: "dropCountsByDay") as? [String: Int] ?? [:]
        defaults.set(DropStats.adding(key, to: counts), forKey: "dropCountsByDay")
    }

    private func fail(_ job: Job, _ error: Error) {
        guard !(error is CancellationError) else { return }
        log.error("Dictation failed: \(error.localizedDescription, privacy: .public)")
        Self.countDrop(.failed, audioSeconds: job.seconds)
        if job.options.isDropRetry { Self.countRetry(.failed) }
        let dictation = FailedDictation(job: job, message: error is TimedOut ? "Took too long" : "Couldn't transcribe")
        failed = Array((failed + [dictation]).suffix(Self.maxFailed))
        onOutcome?(.failed(dictation))
    }

    /// Runs `work`, cancelling it after `seconds`. Waits for a cancelled `work` to end, so the
    /// speech engine is never used by two dictations at once.
    private nonisolated static func withTimeout<T: Sendable>(
        _ seconds: TimeInterval, _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(operation: work)
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TimedOut()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TimedOut() }
            return first
        }
    }

    @discardableResult
    private func record(_ dictation: Dictation, audio: [Float], uses: [Int64: Int]) -> Dictation {
        store.recordUses(uses)
        var saved = dictation
        if settings.retentionDays >= 0 {
            saved = store.add(dictation)
            if settings.saveAudio, let id = saved.id {
                try? AudioRecorder.writeWAV(audio, to: store.audioURL(for: id))
            }
        }
        onRecorded?(saved)
        return saved
    }

    private static func json<T: Encodable>(_ values: [T]) -> String? {
        (try? JSONEncoder().encode(values)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// What changed between what Whisper wrote and what was pasted, for History.
    private static func note(for processed: ProcessedText) -> String? {
        var parts: [String] = []
        let total = processed.replacementUses.values.reduce(0, +)
        if total > 0 {
            parts.append(total == 1 ? "1 replacement applied from your Dictionary." : "\(total) replacements applied from your Dictionary.")
        }
        for summary in processed.rulesApplied.map(\.summary) where !parts.contains(summary) {
            parts.append(summary)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
