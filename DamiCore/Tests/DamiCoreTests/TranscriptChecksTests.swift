import DamiCore
import XCTest

final class HallucinationFilterTests: XCTestCase {
    func testStockPhrases() {
        for phrase in ["Thanks for watching!", "thank you for watching.", "시청해 주셔서 감사합니다.", "MBC 뉴스 이덕영입니다.", "You", "the end."] {
            XCTAssertTrue(HallucinationFilter.isHallucination(phrase), phrase)
        }
    }

    func testEmptyOrOnlyPunctuation() {
        for text in ["", "   ", "...", "♪ ♪"] {
            XCTAssertTrue(HallucinationFilter.isHallucination(text), text)
        }
    }

    func testRealShortPhrasesAreKept() {
        for text in ["Thank you", "감사합니다", "Thanks for watching the kids today", "see you"] {
            XCTAssertFalse(HallucinationFilter.isHallucination(text), text)
        }
    }
}

final class PromptLeakTests: XCTestCase {
    private let korean = SpokenLanguage.find("ko")!.mixedPrompt

    func testExactEcho() {
        XCTAssertTrue(PromptLeak.isLeak(output: korean, prompt: korean, vocabulary: []))
    }

    func testEchoWithDifferentSpacingAndPunctuation() {
        let echo = "오늘 meeting 에서 project timeline 얘기 했고 API 관련 bug는 다음 sprint에 fix 할게요"
        XCTAssertTrue(PromptLeak.isLeak(output: echo, prompt: korean, vocabulary: []))
    }

    func testFragmentOfPromptIsRealSpeech() {
        XCTAssertFalse(PromptLeak.isLeak(output: "오늘 meeting에서 얘기했어요", prompt: korean, vocabulary: []))
        XCTAssertFalse(PromptLeak.isLeak(output: "다음 sprint에 fix 할게요.", prompt: korean, vocabulary: []))
    }

    func testVocabularyListEcho() {
        let vocabulary = ["Supabase", "Claude Code", "Railway", "cmux"]
        XCTAssertTrue(PromptLeak.isLeak(output: "Supabase, Claude Code, Railway, cmux.", prompt: nil, vocabulary: vocabulary))
        XCTAssertTrue(PromptLeak.isLeak(output: "Claude Code, Railway, cmux.", prompt: nil, vocabulary: vocabulary))
    }

    func testOneOrTwoTermsAreRealSpeech() {
        let vocabulary = ["Supabase", "Claude Code", "Railway", "cmux"]
        XCTAssertFalse(PromptLeak.isLeak(output: "Supabase.", prompt: nil, vocabulary: vocabulary))
        XCTAssertFalse(PromptLeak.isLeak(output: "Supabase, Railway", prompt: nil, vocabulary: vocabulary))
    }

    func testSentenceUsingTermsIsRealSpeech() {
        let vocabulary = ["Supabase", "Railway", "cmux"]
        XCTAssertFalse(PromptLeak.isLeak(output: "I moved Supabase and Railway into cmux", prompt: nil, vocabulary: vocabulary))
    }

    func testSingleTermVocabularyNeverLeaks() {
        XCTAssertFalse(PromptLeak.isLeak(output: "Supabase", prompt: nil, vocabulary: ["Supabase"]))
    }

    func testEmptyOutputIsNotALeak() {
        XCTAssertFalse(PromptLeak.isLeak(output: "", prompt: korean, vocabulary: ["Supabase"]))
        XCTAssertFalse(PromptLeak.isLeak(output: "Hello there", prompt: nil, vocabulary: []))
    }
}

final class ScriptTests: XCTestCase {
    func testHangul() {
        let script = SpokenLanguage.Script.hangul
        XCTAssertTrue(script.matches("안녕"))
        XCTAssertTrue(script.matches("meeting에서"))
        XCTAssertTrue(script.matches("ㅎㅎ"))
        XCTAssertFalse(script.matches("meeting 123"))
        XCTAssertFalse(script.matches("今日"))
    }

    func testJapaneseIncludesKanaAndKanji() {
        let script = SpokenLanguage.Script.japanese
        XCTAssertTrue(script.matches("こんにちは"))
        XCTAssertTrue(script.matches("カタカナ"))
        XCTAssertTrue(script.matches("今日"))
        XCTAssertFalse(script.matches("hello"))
    }

    func testHan() {
        XCTAssertTrue(SpokenLanguage.Script.han.matches("你好"))
        XCTAssertFalse(SpokenLanguage.Script.han.matches("안녕"))
    }

    func testDevanagari() {
        XCTAssertTrue(SpokenLanguage.Script.devanagari.matches("नमस्ते"))
        XCTAssertFalse(SpokenLanguage.Script.devanagari.matches("namaste"))
    }

    func testEveryLanguageWithAScriptHasMatchingSamples() {
        for language in SpokenLanguage.all {
            guard let script = language.script else { continue }
            XCTAssertTrue(script.matches(language.mixedPrompt), language.code)
            XCTAssertTrue(script.matches(language.practiceSentence), language.code)
        }
    }

    func testLanguageLookup() {
        XCTAssertEqual(SpokenLanguage.find("ko")?.name, "Korean")
        XCTAssertNil(SpokenLanguage.find("en"))
        XCTAssertNil(SpokenLanguage.find(nil))
    }
}

final class TextPipelineTests: XCTestCase {
    private let rules = [ReplacementRule(id: 7, find: "다미", replace: "Dami")]

    func testLightRunsReplacements() {
        let result = TextPipeline.process(raw: "다미 테스트", mode: .light, language: "ko", rules: rules)
        XCTAssertEqual(result.raw, "다미 테스트")
        XCTAssertEqual(result.afterReplacements, "Dami 테스트")
        XCTAssertEqual(result.final, "Dami 테스트")
        XCTAssertEqual(result.replacementUses, [7: 1])
        XCTAssertEqual(result.rulesApplied, [])
    }

    func testRawChangesNothing() {
        let result = TextPipeline.process(raw: "다미 테스트", mode: .raw, language: "ko", rules: rules)
        XCTAssertEqual(result.final, "다미 테스트")
        XCTAssertEqual(result.replacementUses, [:])
    }

    func testLightRunsRulesAfterReplacements() {
        let result = TextPipeline.process(raw: "음, 다미 테스트", mode: .light, language: "ko", rules: rules)
        XCTAssertEqual(result.afterReplacements, "음, Dami 테스트")
        XCTAssertEqual(result.final, "Dami 테스트")
        XCTAssertEqual(result.rulesApplied, [.koreanFillers])
    }

    func testRawRunsNoRules() {
        let result = TextPipeline.process(raw: "Um, the the report", mode: .raw, language: "en", rules: [])
        XCTAssertEqual(result.final, "Um, the the report")
        XCTAssertEqual(result.rulesApplied, [])
    }
}
