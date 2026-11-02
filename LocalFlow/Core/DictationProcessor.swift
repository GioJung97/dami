import Foundation
import LocalFlowCore
import os

/// What happens to a finished recording: transcribe → `TextPipeline` → paste → history, one at a
/// time and in order. Runs on its own while the next recording goes on.
@MainActor
final class DictationProcessor {
    enum Outcome {
        case pasted
        case copied(TextInserter.Outcome.Reason)
        case noSpeech
        case failed(FailedDictation)
    }

    /// One recording and everything needed to process it, fixed when the recording ended.
    struct Job: Sendable {
        let audio: [Float]
        let seconds: Double
        let options: Transcriber.Options
        let appName: String?
        let appBundleID: String?
    }

    /// A dictation that can be tried again. Its audio stays in memory only, until then.
    struct FailedDictation: Identifiable, Sendable {
        let id = UUID()
        let job: Job
        let message: String
    }

    private struct Transcribed: Sendable {
        let result: Transcriber.Result
        let latency: TimeInterval
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
    private let log = Logger(subsystem: "com.localflow.app", category: "dictation")
    private var queue: DictationQueue<Job, Transcribed>!
    private var slowTask: Task<Void, Never>?

    init(transcriber: Transcriber) {
        queue = DictationQueue(
            process: { [weak self] job in
                try await transcriber.waitUntilReady()
                await self?.startSlowTimer()
                do {
                    let started = Date()
                    let result = try await Self.withTimeout(ProcessingLimits.timeout(audioSeconds: job.seconds)) {
                        try await transcriber.transcribe(job.audio, options: job.options)
                    }
                    await self?.stopSlowTimer()
                    return Transcribed(result: result, latency: Date().timeIntervalSince(started))
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

    /// Tries a failed dictation again. The result pastes at the current cursor.
    func retry(_ id: FailedDictation.ID) {
        guard let index = failed.firstIndex(where: { $0.id == id }) else { return }
        let job = failed.remove(at: index).job
        onChange?()
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
        let result = transcribed.result
        log.info("[\(result.language, privacy: .public)] \(String(format: "%.1f", job.seconds))s audio → \(String(format: "%.2f", transcribed.latency))s")

        guard !HallucinationFilter.isHallucination(result.text) else {
            onOutcome?(.noSpeech)
            return
        }
        let processed = TextPipeline.process(
            raw: result.text, mode: .light, language: result.language, rules: store.replacements.map(\.rule)
        )
        let insertion = await TextInserter.insert(processed.final)
        record(Dictation(
            createdAt: Date(),
            appName: job.appName,
            appBundleID: job.appBundleID,
            language: result.language,
            audioSeconds: job.seconds,
            latencySeconds: transcribed.latency,
            rawText: result.text,
            finalText: processed.final,
            note: Self.note(for: processed.replacementUses)
        ), audio: job.audio, uses: processed.replacementUses)
        switch insertion {
        case .pasted: onOutcome?(.pasted)
        case .copied(let reason): onOutcome?(.copied(reason))
        }
    }

    private func fail(_ job: Job, _ error: Error) {
        guard !(error is CancellationError) else { return }
        log.error("Dictation failed: \(error.localizedDescription, privacy: .public)")
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

    private func record(_ dictation: Dictation, audio: [Float], uses: [Int64: Int]) {
        store.recordUses(uses)
        var saved = dictation
        if settings.retentionDays >= 0 {
            saved = store.add(dictation)
            if settings.saveAudio, let id = saved.id {
                try? AudioRecorder.writeWAV(audio, to: Store.audioURL(for: id))
            }
        }
        onRecorded?(saved)
    }

    private static func note(for uses: [Int64: Int]) -> String? {
        let total = uses.values.reduce(0, +)
        guard total > 0 else { return nil }
        return total == 1 ? "1 replacement applied from your Dictionary." : "\(total) replacements applied from your Dictionary."
    }
}
