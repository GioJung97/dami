import Foundation

/// Runs dictations one at a time, strictly in order, while new recordings can start.
///
/// - A result never gets delivered during a recording. It waits until the recording ends, since
///   pasting then would type into the wrong moment.
/// - Cancelling drops everything pending. The speech engine stops cooperatively, so a job already
///   running may carry on briefly: its result is ignored, and the next job waits for it to end.
@MainActor
public final class DictationQueue<Job: Sendable, Output: Sendable> {
    /// Called when `isBusy` or `waitingCount` may have changed.
    public var onChange: (() -> Void)?
    /// Holds back delivery while true.
    public var isRecording = false {
        didSet { if !isRecording { openGate() } }
    }

    private let process: @Sendable (Job) async throws -> Output
    private let deliver: @MainActor (Job, Output) async -> Void
    private let failed: @MainActor (Job, Error) -> Void

    private var waiting: [Job] = []
    private var worker: Task<Void, Never>?
    private var isCurrentJobLive = false
    /// Bumped by `cancelAll`. A job that started under an older value is ignored.
    private var generation = 0
    private var gate: CheckedContinuation<Void, Never>?

    public init(
        process: @escaping @Sendable (Job) async throws -> Output,
        deliver: @escaping @MainActor (Job, Output) async -> Void,
        failed: @escaping @MainActor (Job, Error) -> Void
    ) {
        self.process = process
        self.deliver = deliver
        self.failed = failed
    }

    /// True while any job that hasn't been cancelled is waiting or running.
    public var isBusy: Bool { isCurrentJobLive || !waiting.isEmpty }
    /// Jobs not started yet.
    public var waitingCount: Int { waiting.count }

    public func add(_ job: Job) {
        waiting.append(job)
        onChange?()
        runNext()
    }

    public func cancelAll() {
        generation += 1
        waiting.removeAll()
        isCurrentJobLive = false
        worker?.cancel()
        openGate()
        onChange?()
    }

    private func runNext() {
        guard worker == nil, !waiting.isEmpty else { return }
        let job = waiting.removeFirst()
        isCurrentJobLive = true
        worker = Task {
            await run(job)
            worker = nil
            isCurrentJobLive = false
            onChange?()
            runNext()
        }
    }

    private func run(_ job: Job) async {
        let started = generation
        do {
            let output = try await process(job)
            while isRecording, started == generation {
                await withCheckedContinuation { gate = $0 }
            }
            guard started == generation else { return }
            await deliver(job, output)
        } catch {
            guard started == generation else { return }
            failed(job, error)
        }
    }

    private func openGate() {
        gate?.resume()
        gate = nil
    }
}
