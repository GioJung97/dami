import LocalFlowCore
import XCTest

final class DropStatsTests: XCTestCase {
    func testLengthRanges() {
        XCTAssertEqual(DropStats.key(.hallucination, audioSeconds: 0.9), "hallucination.under1s")
        XCTAssertEqual(DropStats.key(.promptEcho, audioSeconds: 1), "promptEcho.1to3s")
        XCTAssertEqual(DropStats.key(.onlyFillers, audioSeconds: 9.9), "onlyFillers.3to10s")
        XCTAssertEqual(DropStats.key(.failed, audioSeconds: 10), "failed.over10s")
        XCTAssertEqual(DropStats.key(.silent, audioSeconds: 2), "silent.1to3s")
    }

    func testAddingCounts() {
        var counts: [String: Int] = [:]
        counts = DropStats.adding(.hallucination, audioSeconds: 2, to: counts)
        counts = DropStats.adding(.hallucination, audioSeconds: 2, to: counts)
        counts = DropStats.adding(.failed, audioSeconds: 2, to: counts)
        XCTAssertEqual(counts, ["hallucination.1to3s": 2, "failed.1to3s": 1])
    }
}
