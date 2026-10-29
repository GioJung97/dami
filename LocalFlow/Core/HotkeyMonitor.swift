import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Watches the keyboard system-wide for the dictation shortcut.
///
/// - Modifier-only shortcuts (Right ⌘ + Right ⌥): pressed when exactly those modifiers are held.
///   If another key is pressed meanwhile, it was an app shortcut, so the press is cancelled.
/// - Key shortcuts (⌃ Space): the key events are swallowed so they don't also type into the app.
/// - Esc is swallowed and reported while `isRecording` is true.
///
/// Needs Input Monitoring (to listen) and Accessibility (to swallow keys).
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?
    var onEscape: (() -> Void)?

    /// Set from the main thread; read on the event tap's callback (also the main run loop).
    var shortcut: Shortcut = .defaultDictation { didSet { held = false } }
    var isRecording = false
    /// While the shortcut recorder in Settings is open, the monitor stays quiet.
    var isSuspended = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var held = false

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
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Returns true to swallow the event.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard !isSuspended else { return false }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let current = Shortcut.Modifiers(eventFlags: event.flags.rawValue)

        if type == .keyDown, keyCode == UInt16(kVK_Escape), isRecording {
            fire(onEscape)
            return true
        }

        if shortcut.isModifierOnly {
            switch type {
            case .flagsChanged:
                let matches = current == shortcut.modifiers
                if matches && !held {
                    held = true
                    fire(onPress)
                } else if !matches && held {
                    held = false
                    fire(onRelease)
                }
            case .keyDown:
                if held {
                    held = false
                    fire(onCancel)
                }
            default:
                break
            }
            return false
        }

        guard keyCode == shortcut.keyCode else { return false }
        switch type {
        case .keyDown where current == shortcut.modifiers:
            if !held {
                held = true
                fire(onPress)
            }
            return true // also swallows key repeats
        case .keyUp where held:
            held = false
            fire(onRelease)
            return true
        default:
            return false
        }
    }

    private func fire(_ handler: (() -> Void)?) {
        DispatchQueue.main.async { handler?() }
    }
}
