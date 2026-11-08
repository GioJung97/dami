import DamiCore
import XCTest

final class FixSuggestionTests: XCTestCase {
    private func pair(_ before: String, _ after: String) -> FixSuggestion.Pair? {
        FixSuggestion.from(before: before, after: after)
    }

    func testOneWordInASentence() {
        XCTAssertEqual(pair("오늘 회의는 다섯 시에 시작해요", "오늘 회의는 여섯 시에 시작해요"), .init(find: "다섯", replace: "여섯"))
    }

    func testEnglishWords() {
        XCTAssertEqual(pair("check the Cloud Code hooks", "check the Claude Code hooks"), .init(find: "Cloud", replace: "Claude"))
        XCTAssertEqual(pair("before each comment?", "before each commit?"), .init(find: "comment", replace: "commit"))
    }

    func testKoreanParticleIsDropped() {
        XCTAssertEqual(pair("다미로 받아썼어", "Dami로 받아썼어"), .init(find: "다미", replace: "Dami"))
        XCTAssertEqual(pair("이 버그는 재현이 안 돼", "이 버그는 제안이 안 돼"), .init(find: "재현", replace: "제안"))
    }

    func testParticleChangeKeepsTheWord() {
        XCTAssertEqual(pair("회의는 끝났어", "회의를 끝냈어"), .init(find: "회의는 끝났어", replace: "회의를 끝냈어"))
    }

    func testSpacingFix() {
        XCTAssertEqual(pair("조금 더 생각해봐야 할 것 같아", "조금 더 생각해 봐야 할 것 같아"), .init(find: "생각해봐야", replace: "생각해 봐야"))
    }

    func testPunctuationAroundIsTrimmed() {
        XCTAssertEqual(pair("deploy to Versailles.", "deploy to Vercel."), .init(find: "Versailles", replace: "Vercel"))
    }

    func testNoSuggestionForDeletionsAdditionsOrRewrites() {
        XCTAssertNil(pair("음 내일 보자", "내일 보자"))
        XCTAssertNil(pair("내일 보자", "내일 같이 보자"))
        XCTAssertNil(pair("one two three four five", "six seven eight nine ten"))
        XCTAssertNil(pair("same", "same"))
        XCTAssertNil(pair("말했어.", "말했어!"))
    }

    func testPreviewShowsWholeWords() {
        // "제안서" is another word now, so only "제안을" would change.
        XCTAssertEqual(ReplacementEngine.matchedWords("제안", in: "제안서를 보내고 제안을 들었어"), ["제안을"])
        XCTAssertEqual(ReplacementEngine.matchedWords("cloud", in: "Cloud Code, cloudy day"), ["Cloud"])
    }

    func testVocabularyKeepsNewestWholeTerms() {
        // One token per character, to make the limit easy to see.
        let terms = ["Alpha", "Beta", "Gamma"]
        let count: (String) -> Int = { $0.count }
        XCTAssertEqual(VocabularyPrompt.fitting(terms, limit: 100, tokenCount: count), terms)
        XCTAssertEqual(VocabularyPrompt.fitting(terms, limit: 13, tokenCount: count), ["Beta", "Gamma"])
        XCTAssertEqual(VocabularyPrompt.fitting(terms, limit: 3, tokenCount: count), [])
    }
}
