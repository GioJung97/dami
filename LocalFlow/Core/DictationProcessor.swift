import Foundation
import LocalFlowCore
import os

/// What happens to a finished recording: transcribe → `TextPipeline` → paste → history, one at a
/// time and in order. Runs on its own while the next recording goes on.
@MainActor
final class DictationProcessor {
    enum Outcome {
        case pasted, copiedOnly, noSpeech
        case failed(String)
    }

    /// One recording and everything needed to process it, fixed when the recording ended.
    struct Job: Sendable {
        let audio: [Float]
        let seconds: Double
        let options: Transcriber.Options
        let appName: String?
        let appBundleID: String?
    }

    private struct Transcribed: Sendable {
        let result: Transcriber.Result
        let latency: TimeInterval
    }

    /// Called for each job that ends, unless it was cancelled.
    var onOutcome: ((Outcome) -> Void)?
    /// Called with what was stored, for "paste again".
    var onRecorded: ((Dictation) -> Void)?
    var onChange: (() -> Void)? {
        didSet { queue.onChange = onChange }
    }

    /// Results wait while this is true.
    var isRecording: Bool {
        get { queue.isRecording }
        set { queue.isRecording = newValue }
    }

    var isBusy: Bool { queue.isBusy }
    var waitingCount: Int { queue.waitingCount }

    private let settings = AppSettings.shared
    private let store = Store.shared
    private let log = Logger(subsystem: "com.localflow.app", category: "dictation")
    private var queue: DictationQueue<Job, Transcribed>!

    init(transcriber: Transcriber) {
        queue = DictationQueue(
            process: { job in
                let started = Date()
                let result = try await transcriber.transcribe(job.audio, options: job.options)
                return Transcribed(result: result, latency: Date().timeIntervalSince(started))
            },
            deliver: { [weak self] job, transcribed in await self?.deliver(job, transcribed) },
            failed: { [weak self] _, error in self?.fail(error) }
        )
    }

    func add(_ job: Job) {
        queue.add(job)
    }

    /// Drops everything pending. A job already running may finish in the background; its result is ignored.
    func cancelAll() {
        queue.cancelAll()
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
        onOutcome?(insertion == .pasted ? .pasted : .copiedOnly)
    }

    private func fail(_ error: Error) {
        guard !(error is CancellationError) else { return }
        log.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
        onOutcome?(.failed(error.localizedDescription))
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
