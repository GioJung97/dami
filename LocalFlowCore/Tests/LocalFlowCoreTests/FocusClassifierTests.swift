import LocalFlowCore
import XCTest

/// The Chrome cases are what Chrome actually reported in testing.
final class FocusClassifierTests: XCTestCase {
    private typealias E = FocusClassifier.Element

    func testChromePageWithNothingFocusedIsNotAField() {
        XCTAssertEqual(FocusClassifier.classify(E(role: "AXWebArea", hasSelectedRange: true, isWebContent: true)), .none)
        XCTAssertEqual(FocusClassifier.classify(E(role: "AXGroup", hasSelectedRange: true, isWebContent: true)), .none)
    }

    func testChromeFieldsAreText() {
        XCTAssertEqual(FocusClassifier.classify(E(role: "AXTextField", isValueSettable: true, hasSelectedRange: true, hasEditableAncestor: true)), .text)
        XCTAssertEqual(FocusClassifier.classify(E(role: "AXTextArea", isValueSettable: true, hasSelectedRange: true, hasEditableAncestor: true, isWebContent: true)), .text)
    }

    func testContentEditableInAGroupIsText() {
        XCTAssertEqual(FocusClassifier.classify(E(role: "AXGroup", hasEditableAncestor: true, isWebContent: true)), .text)
    }

    func testGoogleDocsHiddenTargetIsText() {
        XCTAssertEqual(FocusClassifier.classify(E(role: "AXGroup", subrole: "AXEmptyGroup", hasSelectedRange: true, isWebContent: true)), .text)
    }

    func testTerminalIsText() {
        XCTAssertEqual(FocusClassifier.classify(E(role: "AXTextArea", isValueSettable: true, hasSelectedRange: true)), .text)
    }

    func testPasswordFieldsAreSecure() {
        XCTAssertEqual(FocusClassifier.classify(E(role: "AXSecureTextField")), .secure)
        XCTAssertEqual(FocusClassifier.classify(E(role: "AXTextField", subrole: "AXSecureTextField")), .secure)
    }

    func testNativeNonTextElementIsNotAField() {
        XCTAssertEqual(FocusClassifier.classify(E(role: "AXButton")), .none)
        XCTAssertEqual(FocusClassifier.classify(E(role: "AXList")), .none)
    }

    func testUnknownNativeElementsGetTheBenefitOfTheDoubt() {
        XCTAssertEqual(FocusClassifier.classify(E(role: nil)), .text)
        XCTAssertEqual(FocusClassifier.classify(E(role: "AXGroup", hasSelectedRange: true)), .text)
        XCTAssertEqual(FocusClassifier.classify(E(role: "AXCustom", isValueSettable: true)), .text)
    }
}
