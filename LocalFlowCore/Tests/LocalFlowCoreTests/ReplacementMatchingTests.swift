import LocalFlowCore
import XCTest

final class ReplacementMatchingTests: XCTestCase {
    private func apply(_ find: String, _ replace: String, _ text: String) -> String {
        ReplacementEngine.apply([ReplacementRule(find: find, replace: replace)], to: text).text
    }

    func testOneSyllableFixGivesNoSuggestion() {
        XCTAssertNil(FixSuggestion.from(before: "오늘 회의는 세 시에 시작해요", after: "오늘 회의는 네 시에 시작해요"))
    }

    /// The review's case: a "세" → "네" rule must not turn "확인하세요" into "확인하네요".
    func testOneSyllableRuleLeavesOtherWordsAlone() {
        XCTAssertEqual(apply("세", "네", "확인하세요"), "확인하세요")
        XCTAssertEqual(apply("세", "네", "세상에"), "세상에")
        XCTAssertEqual(apply("세", "네", "세 시에 봐요"), "네 시에 봐요")
    }

    func testParticleAfterIsKept() {
        XCTAssertEqual(apply("클라우드 코드", "Claude Code", "클라우드 코드로 했어요"), "Claude Code로 했어요")
        XCTAssertEqual(apply("로컬플로우", "LocalFlow", "로컬플로우를 켰어요"), "LocalFlow를 켰어요")
    }

    func testTwoParticlesInARow() {
        XCTAssertEqual(apply("클라우드", "Claude", "클라우드에서도 돼요"), "Claude에서도 돼요")
    }

    func testThreeSyllablesAfterAreAnotherWord() {
        XCTAssertEqual(apply("클라우드", "Claude", "클라우드펀딩"), "클라우드펀딩")
    }

    func testEndOfSentenceWithPunctuation() {
        XCTAssertEqual(apply("로컬플로우", "LocalFlow", "이건 로컬플로우."), "이건 LocalFlow.")
        XCTAssertEqual(apply("로컬플로우", "LocalFlow", "로컬플로우가?"), "LocalFlow가?")
    }

    func testHangulBeforeMeansInsideAWord() {
        XCTAssertEqual(apply("제안", "재현", "제안서를 봤어요"), "제안서를 봤어요")
        XCTAssertEqual(apply("제안", "재현", "새제안"), "새제안")
        XCTAssertEqual(apply("제안", "재현", "그 제안은 좋아요"), "그 재현은 좋아요")
    }

    func testPreviewCountsTheSameMatches() {
        XCTAssertEqual(ReplacementEngine.matchedWords("세", in: "확인하세요. 세 시에 봐요"), ["세"])
    }

    func testLatinRulesUnchanged() {
        XCTAssertEqual(apply("cloud code", "Claude Code", "I use Cloud Code daily"), "I use Claude Code daily")
        XCTAssertEqual(apply("cloud", "Claude", "cloudy"), "cloudy")
    }

    func testAccentedWordsMatchWholeWords() {
        XCTAssertEqual(apply("más", "mas", "Quiero más, no lo demás"), "Quiero mas, no lo demás")
        XCTAssertEqual(apply("café", "Café Nero", "Un café. Cafés no."), "Un Café Nero. Cafés no.")
        XCTAssertEqual(apply("müller", "Mueller", "Herr Müller und Müllers"), "Herr Mueller und Müllers")
        XCTAssertEqual(apply("việt", "Việt Nam", "tiếng việt"), "tiếng Việt Nam")
    }

    func testHindiMatchesWholeWords() {
        XCTAssertEqual(apply("कल", "आज", "कल मिलते हैं, कलम लाना"), "आज मिलते हैं, कलम लाना")
    }

    /// The owner mixes English into Korean: an English rule still matches right before a particle.
    func testEnglishRuleBeforeKoreanParticle() {
        XCTAssertEqual(apply("cloud code", "Claude Code", "cloud code로 했어요"), "Claude Code로 했어요")
    }

    func testThaiStillMatchesInsideText() {
        XCTAssertEqual(apply("ไทย", "Thai", "ภาษาไทยดี"), "ภาษาThaiดี")
    }

    func testJapaneseStillMatchesInsideText() {
        XCTAssertEqual(apply("東京", "Tokyo", "明日東京へ行きます"), "明日Tokyoへ行きます")
    }
}
