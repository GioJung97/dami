import DamiCore
import XCTest

final class HotkeyMachineTests: XCTestCase {
    private let rightCommandOption: UInt64 = 0x10 | 0x40
    private let vKey: UInt16 = 0x09
    private let escape: UInt16 = 0x35

    private func modifierOnly() -> HotkeyMachine {
        HotkeyMachine(shortcut: .init(modifiers: rightCommandOption, keyCode: nil))
    }

    func testModifierOnlyPressAndRelease() {
        var machine = modifierOnly()
        XCTAssertEqual(machine.handle(.flagsChanged(modifiers: 0x10)), .init())
        XCTAssertEqual(machine.handle(.flagsChanged(modifiers: rightCommandOption)), .init(signal: .press))
        XCTAssertEqual(machine.handle(.flagsChanged(modifiers: 0x10)), .init(signal: .release))
        XCTAssertFalse(machine.isHeld)
    }

    func testRealKeyWhileHeldCancels() {
        var machine = modifierOnly()
        _ = machine.handle(.flagsChanged(modifiers: rightCommandOption))
        XCTAssertEqual(machine.handle(.keyDown(keyCode: vKey, modifiers: rightCommandOption)), .init(signal: .cancel))
        XCTAssertFalse(machine.isHeld)
    }

    func testKeyWithinTheWindowCancels() {
        var machine = modifierOnly()
        _ = machine.handle(.flagsChanged(modifiers: rightCommandOption), at: 10)
        XCTAssertEqual(machine.handle(.keyDown(keyCode: vKey, modifiers: rightCommandOption), at: 10.9), .init(signal: .cancel))
        XCTAssertFalse(machine.isHeld)
        // Letting go afterwards reports nothing more.
        XCTAssertEqual(machine.handle(.flagsChanged(modifiers: 0), at: 11.5), .init())
    }

    /// The bug this guards against: a key pressed while talking discarding the recording.
    func testKeyAfterTheWindowKeepsRecordingAndReleaseStillArrives() {
        let space: UInt16 = 0x31
        var machine = modifierOnly()
        _ = machine.handle(.flagsChanged(modifiers: rightCommandOption), at: 10)
        XCTAssertEqual(machine.handle(.keyDown(keyCode: space, modifiers: rightCommandOption), at: 11.0), .init())
        XCTAssertEqual(machine.handle(.keyUp(keyCode: space, modifiers: rightCommandOption), at: 11.1), .init())
        XCTAssertTrue(machine.isHeld)
        XCTAssertEqual(machine.handle(.flagsChanged(modifiers: 0), at: 14), .init(signal: .release))
    }

    func testKeyRepeatAfterTheWindowDoesNotCancel() {
        var machine = modifierOnly()
        _ = machine.handle(.flagsChanged(modifiers: rightCommandOption), at: 10)
        for t in stride(from: 12.0, to: 13.0, by: 0.1) {
            XCTAssertEqual(machine.handle(.keyDown(keyCode: vKey, modifiers: rightCommandOption), at: t), .init())
        }
        XCTAssertTrue(machine.isHeld)
    }

    func testWindowStartsAgainOnTheNextPress() {
        var machine = modifierOnly()
        _ = machine.handle(.flagsChanged(modifiers: rightCommandOption), at: 10)
        _ = machine.handle(.keyDown(keyCode: vKey, modifiers: rightCommandOption), at: 12)
        XCTAssertEqual(machine.handle(.flagsChanged(modifiers: 0), at: 13), .init(signal: .release))
        XCTAssertEqual(machine.handle(.flagsChanged(modifiers: rightCommandOption), at: 20), .init(signal: .press))
        XCTAssertEqual(machine.handle(.keyDown(keyCode: vKey, modifiers: rightCommandOption), at: 20.2), .init(signal: .cancel))
    }

    func testOwnPasteAfterTheWindowStillIgnored() {
        var machine = modifierOnly()
        _ = machine.handle(.flagsChanged(modifiers: rightCommandOption), at: 10)
        XCTAssertEqual(machine.handle(.keyDown(keyCode: vKey, modifiers: 0), isSynthetic: true, at: 10.1), .init())
        XCTAssertTrue(machine.isHeld)
    }

    func testKeyShortcutIgnoresOtherKeysAtAnyTime() {
        let space: UInt16 = 0x31
        var machine = HotkeyMachine(shortcut: .init(modifiers: 0x1, keyCode: space))
        XCTAssertEqual(machine.handle(.keyDown(keyCode: space, modifiers: 0x1), at: 10), .init(swallow: true, signal: .press))
        XCTAssertEqual(machine.handle(.keyDown(keyCode: vKey, modifiers: 0x1), at: 10.2), .init())
        XCTAssertEqual(machine.handle(.keyDown(keyCode: vKey, modifiers: 0x1), at: 12), .init())
        XCTAssertEqual(machine.handle(.keyUp(keyCode: space, modifiers: 0x1), at: 13), .init(swallow: true, signal: .release))
    }

    /// The bug this guards against: our own ⌘V cancelling a recording.
    func testOwnPasteWhileHeldDoesNotCancel() {
        var machine = modifierOnly()
        _ = machine.handle(.flagsChanged(modifiers: rightCommandOption))
        XCTAssertEqual(machine.handle(.keyDown(keyCode: vKey, modifiers: 0), isSynthetic: true), .init())
        XCTAssertEqual(machine.handle(.keyUp(keyCode: vKey, modifiers: 0), isSynthetic: true), .init())
        XCTAssertTrue(machine.isHeld)
        XCTAssertEqual(machine.handle(.flagsChanged(modifiers: 0)), .init(signal: .release))
    }

    func testEscapeOnlyCapturedWhenAsked() {
        var machine = modifierOnly()
        XCTAssertEqual(machine.handle(.keyDown(keyCode: escape, modifiers: 0)), .init())
        machine.capturesEscape = true
        XCTAssertEqual(machine.handle(.keyDown(keyCode: escape, modifiers: 0)), .init(swallow: true, signal: .escape))
        machine.capturesEscape = false
        XCTAssertEqual(machine.handle(.keyDown(keyCode: escape, modifiers: 0)), .init())
    }

    func testKeyShortcutSwallowsPressRepeatsAndRelease() {
        let space: UInt16 = 0x31
        var machine = HotkeyMachine(shortcut: .init(modifiers: 0x1, keyCode: space))
        XCTAssertEqual(machine.handle(.keyDown(keyCode: space, modifiers: 0)), .init())
        XCTAssertEqual(machine.handle(.keyDown(keyCode: space, modifiers: 0x1)), .init(swallow: true, signal: .press))
        XCTAssertEqual(machine.handle(.keyDown(keyCode: space, modifiers: 0x1)), .init(swallow: true))
        XCTAssertEqual(machine.handle(.keyDown(keyCode: vKey, modifiers: 0x1)), .init())
        XCTAssertEqual(machine.handle(.keyUp(keyCode: space, modifiers: 0x1)), .init(swallow: true, signal: .release))
        XCTAssertEqual(machine.handle(.keyUp(keyCode: space, modifiers: 0x1)), .init())
    }

    func testSuspendedDoesNothing() {
        var machine = modifierOnly()
        machine.isSuspended = true
        XCTAssertEqual(machine.handle(.flagsChanged(modifiers: rightCommandOption)), .init())
        XCTAssertFalse(machine.isHeld)
    }

    func testChangingShortcutClearsHeld() {
        var machine = modifierOnly()
        _ = machine.handle(.flagsChanged(modifiers: rightCommandOption))
        machine.shortcut = .init(modifiers: 0x1, keyCode: 0x31)
        XCTAssertFalse(machine.isHeld)
    }

    func testTapRestoredReportsMissedRelease() {
        var machine = modifierOnly()
        _ = machine.handle(.flagsChanged(modifiers: rightCommandOption))
        XCTAssertEqual(machine.tapRestored(isStillHeld: true), .init())
        XCTAssertTrue(machine.isHeld)
        XCTAssertEqual(machine.tapRestored(isStillHeld: false), .init(signal: .release))
        XCTAssertEqual(machine.tapRestored(isStillHeld: false), .init())
    }

    func testKeyPressedFlag() {
        var machine = modifierOnly()
        XCTAssertFalse(machine.keyPressed)
        _ = machine.handle(.flagsChanged(modifiers: rightCommandOption))
        _ = machine.handle(.flagsChanged(modifiers: 0))
        XCTAssertFalse(machine.keyPressed, "The shortcut itself isn't typing")
        _ = machine.handle(.keyDown(keyCode: vKey, modifiers: 0), isSynthetic: true)
        XCTAssertFalse(machine.keyPressed, "Our own paste isn't typing")
        _ = machine.handle(.keyDown(keyCode: vKey, modifiers: 0))
        XCTAssertTrue(machine.keyPressed)
        machine.clearKeyPressed()
        XCTAssertFalse(machine.keyPressed)
    }

    func testSwallowedKeysDontCountAsTyping() {
        let space: UInt16 = 0x31
        var machine = HotkeyMachine(shortcut: .init(modifiers: 0x1, keyCode: space))
        _ = machine.handle(.keyDown(keyCode: space, modifiers: 0x1))
        XCTAssertFalse(machine.keyPressed)
        machine.capturesEscape = true
        _ = machine.handle(.keyDown(keyCode: escape, modifiers: 0))
        XCTAssertFalse(machine.keyPressed)
    }
}
