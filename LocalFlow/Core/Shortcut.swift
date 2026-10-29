import AppKit
import Carbon.HIToolbox

/// A dictation shortcut: either modifier keys alone (e.g. Right ⌘ + Right ⌥) or a regular key
/// with optional modifiers (e.g. ⌃ Space, F5). Left and right modifiers are told apart.
struct Shortcut: Codable, Equatable {
    /// Device-specific modifier bits (IOKit NX_DEVICE*KEYMASK) plus the Fn flag.
    struct Modifiers: OptionSet, Codable, Hashable {
        let rawValue: UInt64
        static let leftControl = Modifiers(rawValue: 0x0000_0001)
        static let leftShift = Modifiers(rawValue: 0x0000_0002)
        static let rightShift = Modifiers(rawValue: 0x0000_0004)
        static let leftCommand = Modifiers(rawValue: 0x0000_0008)
        static let rightCommand = Modifiers(rawValue: 0x0000_0010)
        static let leftOption = Modifiers(rawValue: 0x0000_0020)
        static let rightOption = Modifiers(rawValue: 0x0000_0040)
        static let rightControl = Modifiers(rawValue: 0x0000_2000)
        static let function = Modifiers(rawValue: 0x0080_0000)

        static let all: [(Modifiers, String)] = [
            (.function, "fn"),
            (.leftControl, "Left ⌃"), (.rightControl, "Right ⌃"),
            (.leftOption, "Left ⌥"), (.rightOption, "Right ⌥"),
            (.leftShift, "Left ⇧"), (.rightShift, "Right ⇧"),
            (.leftCommand, "Left ⌘"), (.rightCommand, "Right ⌘"),
        ]

        /// Reads the modifiers currently held from an event's raw flags.
        init(eventFlags: UInt64) {
            rawValue = eventFlags & Modifiers.all.reduce(0) { $0 | $1.0.rawValue }
        }

        init(rawValue: UInt64) { self.rawValue = rawValue }
    }

    var modifiers: Modifiers
    /// nil = modifier-only shortcut.
    var keyCode: UInt16?

    static let defaultDictation = Shortcut(modifiers: [.rightCommand, .rightOption], keyCode: nil)

    var isModifierOnly: Bool { keyCode == nil }

    /// Each part as it appears on a keycap, e.g. ["Right ⌘", "Right ⌥"] or ["⌃", "Space"].
    var keycaps: [String] {
        var caps = Modifiers.all.filter { modifiers.contains($0.0) }.map(\.1)
        if let keyCode {
            if !isModifierOnly { caps = caps.map(Self.shortModifierName) }
            caps.append(Self.keyName(keyCode))
        }
        return caps
    }

    var displayName: String { keycaps.joined(separator: " + ") }

    /// Shortcuts that would fire while typing normally.
    var isUnsafe: Bool {
        guard let keyCode else { return modifiers.isEmpty }
        let isFunctionKey = Self.functionKeys.contains(Int(keyCode))
        let hasRealModifier = !modifiers.subtracting([.leftShift, .rightShift]).isEmpty
        return !isFunctionKey && !hasRealModifier
    }

    private static func shortModifierName(_ name: String) -> String {
        name.replacingOccurrences(of: "Left ", with: "").replacingOccurrences(of: "Right ", with: "")
    }

    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    static func keyName(_ keyCode: UInt16) -> String {
        let named: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
            kVK_Escape: "Esc", kVK_ForwardDelete: "⌦", kVK_Home: "Home", kVK_End: "End",
            kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
            kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        ]
        if let name = named[Int(keyCode)] { return name }
        return characterForKeyCode(keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    /// Uses the current keyboard layout to turn a key code into its character.
    private static func characterForKeyCode(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
