import DamiCore
import XCTest

final class InsertionSpacingTests: XCTestCase {
    private func spaced(_ text: String, before: Character, language: String = "en") -> Bool {
        InsertionSpacing.needsLeadingSpace(newText: text, language: language, context: .readable(before: before))
    }

    private func spacedUnreadable(_ previous: InsertionSpacing.PreviousDictation?, _ text: String = "Then") -> Bool {
        InsertionSpacing.needsLeadingSpace(newText: text, language: "en", context: .unreadable(previousDictation: previous))
    }

    func testAfterSentenceGetsSpace() {
        XCTAssertTrue(spaced("Then I ate.", before: "."))
        XCTAssertTrue(spaced("그리고", before: "요", language: "ko"))
    }

    func testAfterWhitespaceGetsNone() {
        XCTAssertFalse(spaced("Hello", before: " "))
        XCTAssertFalse(spaced("Hello", before: "\n"))
        XCTAssertFalse(spaced("Hello", before: "\t"))
    }

    func testAfterOpeningGetsNone() {
        for character: Character in ["(", "[", "\"", "“", "「"] {
            XCTAssertFalse(spaced("Hello", before: character), String(character))
        }
    }

    func testClosingPunctuationAtStartGetsNone() {
        for text in [", then", ". Then", ")", "? ok", "。"] {
            XCTAssertFalse(spaced(text, before: "a"), text)
        }
    }

    func testEmptyTextGetsNone() {
        XCTAssertFalse(spaced("", before: "a"))
    }

    func testLanguagesWithoutSpacesGetNone() {
        XCTAssertFalse(spaced("今日は", before: "。", language: "ja"))
        XCTAssertFalse(spaced("今天", before: "。", language: "zh"))
        XCTAssertTrue(spaced("Hola", before: ".", language: "es"))
        XCTAssertTrue(spaced("Hello", before: ".", language: "xx"), "Unknown languages are assumed to use spaces")
    }

    func testUnreadableFieldSpacesOnlyAfterUntouchedDictationInSameApp() {
        let good = InsertionSpacing.PreviousDictation(isSameApp: true, secondsAgo: 10, keyPressedSince: false)
        XCTAssertTrue(spacedUnreadable(good))
        XCTAssertTrue(spacedUnreadable(.init(isSameApp: true, secondsAgo: 120, keyPressedSince: false)))

        XCTAssertFalse(spacedUnreadable(nil))
        XCTAssertFalse(spacedUnreadable(.init(isSameApp: false, secondsAgo: 10, keyPressedSince: false)))
        XCTAssertFalse(spacedUnreadable(.init(isSameApp: true, secondsAgo: 121, keyPressedSince: false)))
        XCTAssertFalse(spacedUnreadable(.init(isSameApp: true, secondsAgo: 10, keyPressedSince: true)))
        XCTAssertFalse(spacedUnreadable(good, ", then"))
    }

    func testLanguageRuleAlsoAppliesWhenUnreadable() {
        let good = InsertionSpacing.PreviousDictation(isSameApp: true, secondsAgo: 10, keyPressedSince: false)
        XCTAssertFalse(InsertionSpacing.needsLeadingSpace(newText: "今日は", language: "ja", context: .unreadable(previousDictation: good)))
    }
}
