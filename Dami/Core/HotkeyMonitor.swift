import Carbon.HIToolbox
import CoreGraphics
import Foundation
import DamiCore
import os

/// Watches the keyboard system-wide for the dictation shortcut. `HotkeyMachine` decides what each
/// event means; this feeds it from an event tap.
///
/// Every keystroke on the Mac passes through the tap, so it has its own thread: a stall on the main
/// thread must never delay typing elsewhere. Handlers are called on the main thread.
///
/// Needs Input Monitoring (to listen) and Accessibility (to swallow keys).
final class HotkeyMonitor {
    /// Marks events Dami posts itself, so the tap can tell them from real typing.
    static let syntheticEventTag: Int64 = 0x4C46_4C57

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?
    var onEscape: (() -> Void)?

    var shortcut: Shortcut = .defaultDictation {
        didSet {
            let converted = Self.machineShortcut(shortcut)
            machine.withLock { $0.shortcut = converted }
        }
    }

    /// True while Esc should reach `onEscape` rather than the focused app.
    var capturesEscape: Bool {
        get { machine.withLock { $0.capturesEscape } }
        set { machine.withLock { $0.capturesEscape = newValue } }
    }

    /// While the shortcut recorder in Settings is open, the monitor stays quiet.
    var isSuspended: Bool {
        get { machine.withLock { $0.isSuspended } }
        set { machine.withLock { $0.isSuspended = newValue } }
    }

    /// Whether a key was pressed since the last call. Only that: which key is never recorded.
    func takeKeyPressed() -> Bool {
        machine.withLock { machine in
            defer { machine.clearKeyPressed() }
            return machine.keyPressed
        }
    }

    private let machine = OSAllocatedUnfairLock(
        initialState: HotkeyMachine(shortcut: HotkeyMonitor.machineShortcut(.defaultDictation))
    )
    private var tap: CFMachPort?

    /// Returns false if the tap couldn't be created (usually missing permissions).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            return monitor.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "io.github.giojung97.dami.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    /// Runs on the tap's thread. Returns true to swallow the event.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            HealthCounter.count(type == .tapDisabledByTimeout ? .tapTimedOut : .tapDisabledByInput)
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            let action = machine.withLock { machine in
                machine.tapRestored(isStillHeld: Self.isHeldNow(machine.shortcut))
            }
            fire(action.signal)
            return false
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = Shortcut.Modifiers(eventFlags: event.flags.rawValue).rawValue
        let keyEvent: HotkeyMachine.Event
        switch type {
        case .flagsChanged: keyEvent = .flagsChanged(modifiers: modifiers)
        case .keyDown: keyEvent = .keyDown(keyCode: keyCode, modifiers: modifiers)
        case .keyUp: keyEvent = .keyUp(keyCode: keyCode, modifiers: modifiers)
        default: return false
        }
        let isSynthetic = event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventTag
        let action = machine.withLock { $0.handle(keyEvent, isSynthetic: isSynthetic) }
        fire(action.signal)
        return action.swallow
    }

    private func fire(_ signal: HotkeyMachine.Signal?) {
        let handler: (() -> Void)?
        switch signal {
        case .press: handler = onPress
        case .release: handler = onRelease
        case .cancel: handler = onCancel
        case .escape: handler = onEscape
        case nil: return
        }
        DispatchQueue.main.async { handler?() }
    }

    /// Checks the keyboard directly, for when the tap missed events. Uses the generic modifier flags,
    /// which are always reported: at worst, letting go of one side while still holding the other
    /// counts as held, which a later real event corrects.
    private static func isHeldNow(_ shortcut: HotkeyMachine.Shortcut) -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let modifiers = Shortcut.Modifiers(rawValue: shortcut.modifiers)
        let required: [(Shortcut.Modifiers, CGEventFlags)] = [
            ([.leftCommand, .rightCommand], .maskCommand),
            ([.leftOption, .rightOption], .maskAlternate),
            ([.leftControl, .rightControl], .maskControl),
            ([.leftShift, .rightShift], .maskShift),
            (.function, .maskSecondaryFn),
        ]
        for (group, flag) in required where !modifiers.isDisjoint(with: group) && !flags.contains(flag) {
            return false
        }
        if let keyCode = shortcut.keyCode {
            return CGEventSource.keyState(.combinedSessionState, key: keyCode)
        }
        return true
    }

    private static func machineShortcut(_ shortcut: Shortcut) -> HotkeyMachine.Shortcut {
        HotkeyMachine.Shortcut(modifiers: shortcut.modifiers.rawValue, keyCode: shortcut.keyCode)
    }
}
