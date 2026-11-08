import DamiCore
import XCTest

final class ReplacementEngineTests: XCTestCase {
    private func apply(_ text: String, _ rules: (String, String)...) -> String {
        ReplacementEngine.apply(rules.map { ReplacementRule(find: $0.0, replace: $0.1) }, to: text).text
    }

    func testMatchesWholeWordsOnly() {
        XCTAssertEqual(apply("a cloudy cloud", ("cloud", "Cloud")), "a cloudy Cloud")
        XCTAssertEqual(apply("subcloud cloud9", ("cloud", "Cloud")), "subcloud cloud9")
    }

    func testLatinRulesIgnoreCase() {
        XCTAssertEqual(apply("SUPER base and super Base", ("super base", "Supabase")), "Supabase and Supabase")
    }

    func testLatinRuleBeforeKoreanParticle() {
        XCTAssertEqual(apply("cloud code로 했어요", ("cloud code", "Cloud Code")), "Cloud Code로 했어요")
        XCTAssertEqual(apply("클로드 코드로 했어요", ("클로드 코드", "Claude Code")), "Claude Code로 했어요")
    }

    func testHangulRulesMatchInsideWords() {
        XCTAssertEqual(apply("다미를 켰어요", ("다미", "Dami")), "Dami를 켰어요")
    }

    func testLongestRuleFirst() {
        XCTAssertEqual(apply("cloud code", ("cloud", "X"), ("cloud code", "Claude Code")), "Claude Code")
    }

    func testRegexCharactersAreLiteral() {
        XCTAssertEqual(apply("node.js and nodexjs", ("node.js", "Node.js")), "Node.js and nodexjs")
        XCTAssertEqual(apply("c++ rocks", ("c++", "C++")), "C++ rocks")
        XCTAssertEqual(apply("price", ("price", "$1 \\0")), "$1 \\0")
    }

    func testCountsUsesById() {
        let rules = [
            ReplacementRule(id: 1, find: "cat", replace: "dog"),
            ReplacementRule(id: 2, find: "bird", replace: "fish"),
            ReplacementRule(id: nil, find: "cow", replace: "pig"),
        ]
        let outcome = ReplacementEngine.apply(rules, to: "cat cat cow")
        XCTAssertEqual(outcome.text, "dog dog pig")
        XCTAssertEqual(outcome.uses, [1: 2])
    }

    func testNoRules() {
        XCTAssertEqual(apply("unchanged"), "unchanged")
    }
}
