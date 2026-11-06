import LocalFlowCore
import XCTest

final class DropStatsTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let day = Date(timeIntervalSince1970: 1_793_923_200) // 2026-11-06 00:00 UTC

    func testKeysHaveRangeAndDay() {
        XCTAssertEqual(DropStats.key(.hallucination, audioSeconds: 0.9, on: day, timeZone: utc), "hallucination.under1s.2026-11-06")
        XCTAssertEqual(DropStats.key(.promptEcho, audioSeconds: 1, on: day, timeZone: utc), "promptEcho.1to3s.2026-11-06")
        XCTAssertEqual(DropStats.key(.onlyFillers, audioSeconds: 9.9, on: day, timeZone: utc), "onlyFillers.3to10s.2026-11-06")
        XCTAssertEqual(DropStats.key(.failed, audioSeconds: 10, on: day, timeZone: utc), "failed.over10s.2026-11-06")
    }

    func testEmptyIsCountedApartFromHallucination() {
        XCTAssertEqual(DropStats.key(.empty, audioSeconds: 2, on: day, timeZone: utc), "empty.1to3s.2026-11-06")
        XCTAssertNotEqual(DropStats.key(.empty, audioSeconds: 2, on: day), DropStats.key(.hallucination, audioSeconds: 2, on: day))
    }

    func testNextDayIsAnotherKey() {
        let next = day.addingTimeInterval(86_400)
        XCTAssertEqual(DropStats.key(.empty, audioSeconds: 2, on: next, timeZone: utc), "empty.1to3s.2026-11-07")
    }

    func testRetryKeys() {
        XCTAssertEqual(DropStats.retryKey(.text, on: day, timeZone: utc), "retry.text.2026-11-06")
        XCTAssertEqual(DropStats.retryKey(.stillEmpty, on: day, timeZone: utc), "retry.stillEmpty.2026-11-06")
    }

    func testAddingCounts() {
        var counts: [String: Int] = [:]
        counts = DropStats.adding("empty.1to3s.2026-11-06", to: counts)
        counts = DropStats.adding("empty.1to3s.2026-11-06", to: counts)
        counts = DropStats.adding("failed.1to3s.2026-11-06", to: counts)
        XCTAssertEqual(counts, ["empty.1to3s.2026-11-06": 2, "failed.1to3s.2026-11-06": 1])
    }

    func testRetryUsesTheOtherLanguage() {
        XCTAssertEqual(DropRetry.language(after: "en", second: "ko"), "ko")
        XCTAssertEqual(DropRetry.language(after: "ko", second: "ko"), "en")
        XCTAssertEqual(DropRetry.language(after: "en", second: nil), "en")
    }
}
