import XCTest
@testable import LocalFlowCore

final class SetupStepTests: XCTestCase {
    func testResumesAtTheSavedStep() {
        XCTAssertEqual(SetupStep.resume(saved: SetupStep.permissions.rawValue, permissionsGranted: false, modelReady: false), .permissions)
        XCTAssertEqual(SetupStep.resume(saved: SetupStep.practice.rawValue, permissionsGranted: true, modelReady: true), .practice)
    }

    func testAFreshInstallStartsAtWelcome() {
        XCTAssertEqual(SetupStep.resume(saved: 0, permissionsGranted: false, modelReady: false), .welcome)
    }

    func testAnUnknownSavedValueStartsAtWelcome() {
        XCTAssertEqual(SetupStep.resume(saved: 99, permissionsGranted: true, modelReady: true), .welcome)
    }

    func testNeverLandsPastMissingPermissions() {
        XCTAssertEqual(SetupStep.resume(saved: SetupStep.practice.rawValue, permissionsGranted: false, modelReady: true), .permissions)
    }

    func testNeverLandsPastAModelThatIsNotReady() {
        XCTAssertEqual(SetupStep.resume(saved: SetupStep.done.rawValue, permissionsGranted: true, modelReady: false), .model)
    }

    func testEarlierStepsDoNotJumpForwardOrBack() {
        XCTAssertEqual(SetupStep.resume(saved: SetupStep.language.rawValue, permissionsGranted: false, modelReady: false), .language)
        XCTAssertEqual(SetupStep.resume(saved: SetupStep.model.rawValue, permissionsGranted: true, modelReady: false), .model)
    }

    func testTheShortcutWorksFromPracticeOn() {
        XCTAssertEqual(SetupStep.allCases.filter(\.allowsShortcut), [.practice, .done])
    }
}
