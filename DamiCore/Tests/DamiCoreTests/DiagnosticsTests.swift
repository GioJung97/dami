import DamiCore
import XCTest

final class DiagnosticsTests: XCTestCase {
    private let sample = "2026-11-08T07:33:33Z audio=5.00 lang=ko mode=auto firstAfterIdle=0 wait=0.274 detect=0.441 transcribe=0.716 runs=1 reused=1 cleanup=0.0035 paste=0.002 total=1.437"

    private func input(latency: [String] = [], drops: [String: Int] = [:], settings: [(String, String)] = []) -> Diagnostics.Input {
        Diagnostics.Input(
            appVersion: "1.0.0 (4)", macOS: "15.3", mac: "M3 · 16 GB", settings: settings, healthCounts: ["micLost.2026-11-05": 2],
            dropCounts: drops, latencySamples: latency, pasteWatches: ["edited.fieldChanged": 3], database: "ok", dictations: 12,
            crashReports: []
        )
    }

    func testLatencyLineAsWrittenPasses() {
        XCTAssertEqual(Diagnostics.safeLatencyLine(sample), sample)
    }

    func testLatencyLineWithTextIsDropped() {
        XCTAssertNil(Diagnostics.safeLatencyLine(sample + " text=hello"))
        XCTAssertNil(Diagnostics.safeLatencyLine(sample.replacingOccurrences(of: "lang=ko", with: "lang=회의")))
        XCTAssertNil(Diagnostics.safeLatencyLine("meet me at 3 audio=1.0"))
    }

    func testReportHoldsNoTextFromStorage() {
        let report = Diagnostics.report(input(
            latency: [sample, "2026-11-08T07:33:33Z audio=1 note=secret plan"],
            drops: ["empty.1to3s.2026-11-08": 1, "Send the contract to Jake": 1],
            settings: [("cleanupMode", "light"), ("secondLanguage", "ko"), ("leak", "내일 회의 잡아줘"), ("leak2", "meet at 3")]
        ))
        XCTAssertTrue(report.contains("empty.1to3s.2026-11-08: 1"))
        XCTAssertTrue(report.contains("reused=1"))
        XCTAssertTrue(report.contains("cleanupMode: light"))
        XCTAssertFalse(report.contains("secret"))
        XCTAssertFalse(report.contains("Jake"))
        XCTAssertFalse(report.contains("회의"))
        XCTAssertTrue(report.contains("leak: ?"))
        XCTAssertTrue(report.contains("leak2: ?"))
    }

    func testOnlyTheLatestLatencySamplesGoIn() {
        let many = Array(repeating: sample, count: Diagnostics.latencyLimit + 20)
        let report = Diagnostics.report(input(latency: many))
        XCTAssertEqual(report.components(separatedBy: "audio=").count - 1, Diagnostics.latencyLimit)
    }
}
