import LocalFlowCore
import XCTest

final class PasteSpanTests: XCTestCase {
    private let pasted = " 오늘 회의는 세 시에 시작해요"

    func testLocatesTextEndingAtCaret() {
        let field = "메모:" + pasted
        let span = PasteSpan.locate(pasted, in: field, caret: field.utf16.count)
        XCTAssertEqual(span?.text(in: field), pasted)
    }

    func testLocatesNearestCopyWhenCaretIsElsewhere() {
        let field = "hello world. hello world. end"
        let span = PasteSpan.locate("hello world.", in: field, caret: 25)
        XCTAssertEqual(span, PasteSpan(start: 13, end: 25))
    }

    func testNotFoundWhenFieldIsEmpty() {
        XCTAssertNil(PasteSpan.locate(pasted, in: "", caret: 0))
    }

    func testFollowsAnEditInside() {
        let old = "메모:" + pasted
        var span = PasteSpan.locate(pasted, in: old, caret: old.utf16.count)!
        let new = old.replacingOccurrences(of: "세", with: "네")
        XCTAssertEqual(span.update(from: old, to: new), .inside)
        XCTAssertEqual(span.text(in: new), " 오늘 회의는 네 시에 시작해요")
    }

    func testTypingAfterIsNotPartOfTheSpan() {
        let old = "메모:" + pasted
        var span = PasteSpan.locate(pasted, in: old, caret: old.utf16.count)!
        let new = old + " 그리고 점심"
        XCTAssertEqual(span.update(from: old, to: new), .outside)
        XCTAssertEqual(span.text(in: new), pasted)
    }

    func testTypingBeforeShiftsTheSpan() {
        let old = "메모:" + pasted
        var span = PasteSpan.locate(pasted, in: old, caret: old.utf16.count)!
        let new = "중요 " + old
        XCTAssertEqual(span.update(from: old, to: new), .outside)
        XCTAssertEqual(span.text(in: new), pasted)
    }

    func testDeletingAcrossTheEdgeLosesIt() {
        let old = "메모:" + pasted
        var span = PasteSpan.locate(pasted, in: old, caret: old.utf16.count)!
        XCTAssertEqual(span.update(from: old, to: "메오늘 회의는 세 시에 시작해요"), .lost)
    }

    func testDeletingAllOfItLosesIt() {
        let old = "a" + pasted
        var span = PasteSpan.locate(pasted, in: old, caret: old.utf16.count)!
        XCTAssertEqual(span.update(from: old, to: "a"), .lost)
    }

    func testMuchLongerResultIsNotPlausible() {
        XCTAssertTrue(PasteSpan.isPlausibleEdit(of: "세 시에", to: "네 시에"))
        XCTAssertFalse(PasteSpan.isPlausibleEdit(of: "세 시에", to: String(repeating: "다른 내용 ", count: 10)))
    }
}

final class AutoFixTests: XCTestCase {
    func testSignals() {
        XCTAssertEqual(AutoFix.signal(before: "회의는 세 시에", after: "회의는 네 시에"), .substitution)
        XCTAssertEqual(AutoFix.signal(before: "생각해봐야 해요", after: "생각해 봐야 해요"), .cleanup)
        XCTAssertEqual(AutoFix.signal(before: "Okay sounds good", after: "Okay, sounds good."), .cleanup)
        XCTAssertEqual(AutoFix.signal(before: "um so this is it", after: "this is it"), .cleanup)
        XCTAssertEqual(AutoFix.signal(before: "this is it", after: "this is it and more words"), .rewrite)
        XCTAssertEqual(AutoFix.signal(before: "one two three four five", after: "six seven eight nine ten"), .rewrite)
        XCTAssertEqual(AutoFix.signal(before: "same ", after: "same"), .unchanged)
    }

    func testComposedHangulComparesEqual() {
        let decomposed = "네".decomposedStringWithCanonicalMapping
        XCTAssertEqual(AutoFix.signal(before: "네", after: decomposed), .unchanged)
    }

    func testUnsureWord() {
        let words: [(word: String, probability: Float)] = [(" 로컬", 0.3), ("플로우로", 0.9), (" 시작", 0.95)]
        XCTAssertTrue(AutoFix.wasUnsure(of: "로컬플로우", words: words))
        XCTAssertFalse(AutoFix.wasUnsure(of: "시작", words: words))
    }

    func testSingleLetterDoesNotCount() {
        XCTAssertFalse(AutoFix.wasUnsure(of: "cat", words: [(" a", 0.1)]))
        XCTAssertTrue(AutoFix.wasUnsure(of: "a", words: [(" a", 0.1)]))
    }

    func testNoWordsMeansNotUnsure() {
        XCTAssertFalse(AutoFix.wasUnsure(of: "로컬플로우", words: []))
    }
}
