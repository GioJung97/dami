import DamiCore
import XCTest

final class HealthStatsTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let seoul = TimeZone(identifier: "Asia/Seoul")!

    func testKeyUsesTheLocalDay() {
        let lateUTC = Date(timeIntervalSince1970: 1_793_836_800 - 60) // One minute before a UTC midnight.
        let utcKey = HealthStats.key(.micLost, on: lateUTC, timeZone: utc)
        let seoulKey = HealthStats.key(.micLost, on: lateUTC, timeZone: seoul)
        XCTAssertTrue(utcKey.hasPrefix("micLost."))
        XCTAssertNotEqual(utcKey, seoulKey)
    }

    func testAddingCountsByKindAndDay() {
        let day = Date(timeIntervalSince1970: 1_793_836_800)
        var counts: [String: Int] = [:]
        counts = HealthStats.adding(.tapTimedOut, on: day, timeZone: utc, to: counts)
        counts = HealthStats.adding(.tapTimedOut, on: day, timeZone: utc, to: counts)
        counts = HealthStats.adding(.tapTimedOut, on: day.addingTimeInterval(86400), timeZone: utc, to: counts)
        counts = HealthStats.adding(.historySaveFailed, on: day, timeZone: utc, to: counts)
        XCTAssertEqual(counts[HealthStats.key(.tapTimedOut, on: day, timeZone: utc)], 2)
        XCTAssertEqual(counts[HealthStats.key(.tapTimedOut, on: day.addingTimeInterval(86400), timeZone: utc)], 1)
        XCTAssertEqual(counts[HealthStats.key(.historySaveFailed, on: day, timeZone: utc)], 1)
        XCTAssertEqual(counts.count, 3)
    }
}
