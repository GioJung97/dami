import LocalFlowCore
import XCTest

/// A job that finishes when the test says so.
private actor Switchboard {
    private var released: Set<Int> = []
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var started: [Int] = []

    func wait(for id: Int) async {
        started.append(id)
        if released.contains(id) { return }
        await withCheckedContinuation { waiters[id] = $0 }
    }

    func release(_ id: Int) {
        released.insert(id)
        waiters.removeValue(forKey: id)?.resume()
    }
}

private struct Failure: Error {}

@MainActor
final class DictationQueueTests: XCTestCase {
    private var delivered: [Int] = []
    private var failures: [Int] = []
    private let board = Switchboard()

    private func makeQueue() -> DictationQueue<Int, Int> {
        let board = board
        return DictationQueue<Int, Int>(
            process: { id in
                await board.wait(for: id)
                if id < 0 { throw Failure() }
                return id
            },
            deliver: { [weak self] _, output in self?.delivered.append(output) },
            failed: { [weak self] job, _ in self?.failures.append(job) }
        )
    }

    /// Lets queue work run until `condition` holds.
    private func settle(_ condition: @escaping () async -> Bool) async {
        for _ in 0..<2000 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out")
    }

    func testResultsArriveInOrderEvenIfReleasedOutOfOrder() async {
        let queue = makeQueue()
        queue.add(1)
        queue.add(2)
        queue.add(3)
        await board.release(3)
        await board.release(2)
        await board.release(1)
        await settle { self.delivered.count == 3 }
        XCTAssertEqual(delivered, [1, 2, 3])
        await settle { !queue.isBusy }
    }

    func testRunsOneAtATime() async {
        let queue = makeQueue()
        queue.add(1)
        queue.add(2)
        await settle { await self.board.started == [1] }
        XCTAssertEqual(queue.waitingCount, 1)
        await board.release(1)
        await settle { await self.board.started == [1, 2] }
        await board.release(2)
        await settle { !queue.isBusy }
    }

    func testNoDeliveryDuringRecording() async {
        let queue = makeQueue()
        queue.isRecording = true
        queue.add(1)
        queue.add(2)
        await board.release(1)
        await board.release(2)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(delivered, [])
        XCTAssertTrue(queue.isBusy)

        queue.isRecording = false
        await settle { self.delivered == [1, 2] }
    }

    func testRecordingStartedAgainKeepsHolding() async {
        let queue = makeQueue()
        queue.isRecording = true
        queue.add(1)
        await board.release(1)
        try? await Task.sleep(for: .milliseconds(20))
        queue.isRecording = false
        queue.isRecording = true
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(delivered, [])
        queue.isRecording = false
        await settle { self.delivered == [1] }
    }

    func testCancelAllDropsWaitingAndIgnoresRunningResult() async {
        let queue = makeQueue()
        queue.add(1)
        queue.add(2)
        await settle { await self.board.started == [1] }
        queue.cancelAll()
        XCTAssertFalse(queue.isBusy)
        await board.release(1)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(delivered, [])
        let started = await board.started
        XCTAssertEqual(started, [1])
    }

    func testCancelDropsResultWaitingForRecordingToEnd() async {
        let queue = makeQueue()
        queue.isRecording = true
        queue.add(1)
        await board.release(1)
        try? await Task.sleep(for: .milliseconds(20))
        queue.cancelAll()
        queue.isRecording = false
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(delivered, [])
    }

    func testNewJobAfterCancelWaitsForTheRunningOne() async {
        let queue = makeQueue()
        queue.add(1)
        await settle { await self.board.started == [1] }
        queue.cancelAll()
        queue.add(2)
        XCTAssertTrue(queue.isBusy)
        try? await Task.sleep(for: .milliseconds(30))
        let started = await board.started
        XCTAssertEqual(started, [1], "Job 2 must not run alongside the cancelled job")

        await board.release(1)
        await board.release(2)
        await settle { self.delivered == [2] }
    }

    func testFailureDoesNotStopTheNextJob() async {
        let queue = makeQueue()
        queue.add(-1)
        queue.add(2)
        await board.release(-1)
        await board.release(2)
        await settle { self.delivered == [2] }
        XCTAssertEqual(failures, [-1])
    }

    func testCancelledFailureIsNotReported() async {
        let queue = makeQueue()
        queue.add(-1)
        await settle { await self.board.started == [-1] }
        queue.cancelAll()
        await board.release(-1)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(failures, [])
    }
}
