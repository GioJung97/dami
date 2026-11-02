import Foundation

/// Decides what each keyboard event means for the dictation shortcut.
///
/// - Modifier-only shortcuts (Right ⌘ + Right ⌥): pressed when exactly those modifiers are held.
///   If another key is pressed meanwhile, it was an app shortcut, so the press is cancelled.
/// - Key shortcuts (⌃ Space): the key events are swallowed so they don't also type into the app.
/// - Esc is swallowed and reported while `capturesEscape` is true.
/// - Events LocalFlow posted itself, such as its ⌘V, are ignored. Otherwise a paste near a recording
///   would look like an app shortcut and cancel it.
public struct HotkeyMachine: Sendable {
    public struct Shortcut: Equatable, Sendable {
        /// Device-specific modifier bits.
        public var modifiers: UInt64
        /// Nil for a modifier-only shortcut.
        public var keyCode: UInt16?

        public init(modifiers: UInt64, keyCode: UInt16?) {
            self.modifiers = modifiers
            self.keyCode = keyCode
        }
    }

    public enum Event: Equatable, Sendable {
        case flagsChanged(modifiers: UInt64)
        case keyDown(keyCode: UInt16, modifiers: UInt64)
        case keyUp(keyCode: UInt16, modifiers: UInt64)
    }

    public enum Signal: Equatable, Sendable {
        case press, release, cancel, escape
    }

    public struct Action: Equatable, Sendable {
        public var swallow = false
        public var signal: Signal?

        public init(swallow: Bool = false, signal: Signal? = nil) {
            self.swallow = swallow
            self.signal = signal
        }
    }

    static let escapeKeyCode: UInt16 = 0x35

    public var shortcut: Shortcut { didSet { isHeld = false } }
    /// True while a recording or pending work can be cancelled with Esc.
    public var capturesEscape = false
    /// While the shortcut recorder in Settings is open, the shortcut does nothing.
    public var isSuspended = false
    public private(set) var isHeld = false

    public init(shortcut: Shortcut) {
        self.shortcut = shortcut
    }

    public mutating func handle(_ event: Event, isSynthetic: Bool = false) -> Action {
        guard !isSuspended, !isSynthetic else { return Action() }

        if case .keyDown(Self.escapeKeyCode, _) = event, capturesEscape {
            return Action(swallow: true, signal: .escape)
        }
        return shortcut.keyCode == nil ? handleModifierOnly(event) : handleKey(event)
    }

    /// A timed-out tap misses events. If the shortcut was released meanwhile, report it now, so a
    /// recording can't be left running.
    public mutating func tapRestored(isStillHeld: Bool) -> Action {
        guard isHeld, !isStillHeld else { return Action() }
        isHeld = false
        return Action(signal: .release)
    }

    private mutating func handleModifierOnly(_ event: Event) -> Action {
        switch event {
        case .flagsChanged(let modifiers):
            let matches = modifiers == shortcut.modifiers
            if matches && !isHeld {
                isHeld = true
                return Action(signal: .press)
            }
            if !matches && isHeld {
                isHeld = false
                return Action(signal: .release)
            }
        case .keyDown:
            if isHeld {
                isHeld = false
                return Action(signal: .cancel)
            }
        case .keyUp:
            break
        }
        return Action()
    }

    private mutating func handleKey(_ event: Event) -> Action {
        switch event {
        case .keyDown(let keyCode, let modifiers) where keyCode == shortcut.keyCode && modifiers == shortcut.modifiers:
            guard !isHeld else { return Action(swallow: true) } // key repeat
            isHeld = true
            return Action(swallow: true, signal: .press)
        case .keyUp(let keyCode, _) where keyCode == shortcut.keyCode && isHeld:
            isHeld = false
            return Action(swallow: true, signal: .release)
        default:
            return Action()
        }
    }
}
