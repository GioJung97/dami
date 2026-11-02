import LocalFlowCore
import XCTest

final class CleanupRulesTests: XCTestCase {
    func testWhichRulesApply() {
        XCTAssertEqual(CleanupRules.rules(forLanguage: "en"), [.englishFillers, .englishRepeats, .numberCorrection])
        XCTAssertEqual(
            CleanupRules.rules(forLanguage: "ko"),
            [.englishFillers, .englishRepeats, .numberCorrection, .koreanFillers, .koreanRepeats]
        )
        // Own script, no rules of its own yet: mixed sentences still get the English ones.
        for code in ["ja", "zh", "hi"] {
            XCTAssertEqual(CleanupRules.rules(forLanguage: code), [.englishFillers, .englishRepeats, .numberCorrection], code)
        }
        // German "er" means "he", Portuguese "um" means "a".
        for code in ["es", "fr", "de", "pt", "vi"] {
            XCTAssertEqual(CleanupRules.rules(forLanguage: code), [], code)
        }
        XCTAssertEqual(CleanupRules.rules(forLanguage: "ru"), [], "A language Whisper's own detection returned")
    }

    func testReportsOnlyRulesThatChangedSomething() {
        XCTAssertEqual(CleanupRules.apply(to: "All good.", language: "en").applied, [])
        XCTAssertEqual(CleanupRules.apply(to: "Um, the the report", language: "en").applied, [.englishFillers, .englishRepeats])
    }

    func testOnlyAFillerLeavesNothing() {
        XCTAssertEqual(CleanupRules.apply(to: "Um.", language: "en").text, "")
        XCTAssertEqual(CleanupRules.apply(to: "음...", language: "ko").text, "")
    }

    func testRepairTouchesNothingElse() {
        XCTAssertEqual(CleanupRules.apply(to: "keep  two  spaces, uh, here", language: "en").text, "keep  two  spaces here")
    }
}

/// `bench/cleanup_cases.tsv` is the contract for the rules: every must_keep case comes through unchanged.
final class CleanupEvalTests: XCTestCase {
    private func results() throws -> [CleanupEval.Result] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let tsv = try String(contentsOf: root.appendingPathComponent("bench/cleanup_cases.tsv"), encoding: .utf8)
        return CleanupEval.run(CleanupEval.parse(tsv))
    }

    func testEveryMustKeepCaseIsUnchanged() throws {
        let keep = try results().filter { $0.testCase.category == "must_keep" }
        XCTAssertGreaterThanOrEqual(keep.count, 30)
        for result in keep where !result.passed {
            XCTFail("\(result.testCase.id): \(result.testCase.input) → \(result.output)")
        }
    }

    func testEveryMustFixCaseNotLeftByDesignIsFixed() throws {
        let fix = try results().filter { $0.testCase.category == "must_fix" && !$0.isDeliberatelyUnfixed }
        XCTAssertFalse(fix.isEmpty)
        for result in fix where !result.passed {
            XCTFail("\(result.testCase.id): \(result.testCase.input) → \(result.output), expected \(result.testCase.expectedLight)")
        }
    }
}
