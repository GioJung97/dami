import LocalFlowCore
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
