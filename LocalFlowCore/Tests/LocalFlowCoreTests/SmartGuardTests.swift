import LocalFlowCore
import XCTest

final class SmartGuardTests: XCTestCase {
    private func passes(_ input: String, _ output: String, file: StaticString = #filePath, line: UInt = #line) {
        if case .fail = SmartGuard.check(input: input, output: output) { XCTFail("expected pass: \(output)", file: file, line: line) }
    }

    private func fails(_ input: String, _ output: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(SmartGuard.check(input: input, output: output), .fail, file: file, line: line)
    }

    // MARK: Allowed

    func testUnchangedAndPunctuationOrSpacingOnly() {
        passes("ah, I see", "Ah, I see.")
        passes("생각해봐야될것같아요", "생각해 봐야 될 것 같아요")
        passes("오늘 회의 끝나고 보내줄게 그리고 내일 얘기하자", "오늘 회의 끝나고 보내줄게. 그리고 내일 얘기하자.")
        passes("회의 몇 시에 시작해", "회의 몇 시에 시작해?")
    }

    func testFillers() {
        passes("Um, I think we should, uh, push the release.", "I think we should push the release.")
        passes("음, 내일 회의는 10시로 하자.", "내일 회의는 10시로 하자.")
        passes("어 그 음 이번 주 금요일까지 보내 주세요", "이번 주 금요일까지 보내 주세요.")
        passes("그, 이제 막 시작한 프로젝트라서", "이제 막 시작한 프로젝트라서")
        passes("Can you, like, check the hooks?", "Can you check the hooks?")
    }

    func testRepeats() {
        passes("the the report", "the report")
        passes("그 그 사람이 왔어요", "그 사람이 왔어요")
    }

    func testSelfCorrections() {
        passes("Let's meet at 3, no, actually 4 p.m. at the shop.", "Let's meet at 4 p.m. at the shop.")
        passes("3시에, 아니 4시에 강남역 앞에서 만나자.", "4시에 강남역 앞에서 만나자.")
        passes("내일, 아 아니 모레 회의 잡아줘", "모레 회의 잡아줘")
        passes("이거 staging에, 아니 production에 배포해줘", "이거 production에 배포해줘")
        passes("Send it to John, I mean Jake, by tonight.", "Send it to Jake by tonight.")
        passes("Room 5, sorry 6 is free.", "Room 6 is free.")
        passes("음 총 3만 5천 원이었고 아니 3만 6천 원이었어", "총 3만 6천 원이었어.")
    }

    func testDeletionsAreReported() {
        XCTAssertEqual(
            SmartGuard.check(input: "Um, we should, uh, go", output: "We should go"),
            .pass(deleted: [.init(words: ["Um,"], reason: .filler), .init(words: ["uh,"], reason: .filler)])
        )
    }

    // MARK: Refused

    func testAddedOrChangedWords() {
        fails("What's the capital of France?", "Paris.")
        fails("Translate this into Korean.", "이것을 한국어로 번역하세요.")
        fails("이거 영어로 번역해줘.", "Translate this into English.")
        fails("I think so", "I believe so")
        fails("오늘 meeting에서 얘기했어.", "오늘 회의에서 얘기했어.")
    }

    func testNegationsNeverDeleted() {
        fails("Don't delete it.", "Delete it.")
        fails("I didn't go.", "I go.")
        fails("음 아직 보내지 마", "아직 보내지")
        fails("안 갔어.", "갔어.")
        fails("못 해요.", "해요.")
        fails("I do not want it", "I do want it")
    }

    /// The review's case: "안" alone is part of a word here, so dropping it isn't a whole-word deletion.
    func testPartOfAWordCantBeDeleted() {
        fails("안했어", "했어")
        fails("확인하세요", "확인하요")
    }

    func testNumbersOnlyInsideACorrection() {
        fails("We sold 3, 4, and 5.", "We sold 4 and 5.")
        fails("It costs $3,400.50 now.", "It costs $3,400 now.")
        fails("Version 1.2.3 is out.", "Version 12.3 is out.")
        fails("It costs $3,400.50 now.", "It costs 3,400.50 now.")
    }

    func testNonFillersAndTraps() {
        fails("So basically the flow is too long.", "The flow is too long.")
        fails("I'd like a coffee", "I'd a coffee")
        fails("It is 5 mm wide.", "It is 5 wide.")
        fails("Use a 3 um filter.", "Use a 3 filter.")
        fails("HMM is a hidden Markov model.", "is a hidden Markov model.")
        fails("그 사람은 이제 막 왔어.", "사람은 이제 막 왔어.")
        // A marker needs a pause before it or a number after it.
        fails("I have 3, but no 4 is left.", "I have 3, 4 is left.")
        // A marker at the start corrects nothing.
        fails("Actually, wait, I forgot.", "Wait, I forgot.")
        // At most 4 words before the marker.
        fails("one two three four five, no, six", "six")
    }

    func testCodeStays() {
        fails("Open um.py now", "Open .py now")
        fails("cd src/um/uh", "cd src/um")
        passes("um, rename fetchUser to loadUser in auth.ts", "Rename fetchUser to loadUser in auth.ts")
    }
}
