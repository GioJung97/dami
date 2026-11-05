import LocalFlowCore
import XCTest

final class FixTextTests: XCTestCase {
    func testTrimsOuterWhitespace() {
        XCTAssertEqual(FixText.normalized("  오늘 회의는 네 시에\n", replacing: "오늘 회의는 세 시에"), "오늘 회의는 네 시에")
    }

    func testKeepsInnerSpacingAndLines() {
        XCTAssertEqual(FixText.normalized("one\ntwo  three", replacing: "one two three"), "one\ntwo  three")
    }

    func testNothingToSaveWhenEmpty() {
        XCTAssertNil(FixText.normalized("  \n ", replacing: "text"))
    }

    func testNothingToSaveWhenUnchanged() {
        XCTAssertNil(FixText.normalized("same text ", replacing: "same text"))
    }

    func testASpacingOnlyFixCounts() {
        XCTAssertEqual(FixText.normalized("생각해 봐야", replacing: "생각해봐야"), "생각해 봐야")
    }
}
