import DamiCore
import XCTest

final class ModelFilesTests: XCTestCase {
    func testCompleteOnlyWithEveryFile() {
        XCTAssertTrue(ModelFiles.isComplete { _ in true })
        for missing in ModelFiles.required {
            XCTAssertFalse(ModelFiles.isComplete { $0 != missing }, missing)
        }
    }

    /// The old check looked at this file alone, so an interrupted download passed.
    func testAudioEncoderAloneIsIncomplete() {
        XCTAssertFalse(ModelFiles.isComplete { $0 == "AudioEncoder.mlmodelc" })
    }
}

final class ProcessingLimitsTests: XCTestCase {
    func testTimeoutIsAtLeast30SecondsOrAudioLength() {
        XCTAssertEqual(ProcessingLimits.timeout(audioSeconds: 2), 30)
        XCTAssertEqual(ProcessingLimits.timeout(audioSeconds: 600), 600)
    }
}
