import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics

/// Types text into whatever app is focused: put it on the clipboard, send ⌘V, then put the
/// user's previous clipboard back. Needs the Accessibility permission to post key events.
@MainActor
enum TextInserter {
    enum Outcome {
        case pasted
        /// Couldn't paste, so the text was left on the clipboard.
        case copied(Reason)

        enum Reason {
            case passwordField, noTextField, noAccessibility

            var message: String {
                switch self {
                case .passwordField: "Password field · Copied, press ⌘V"
                case .noTextField: "No text field · Copied, press ⌘V"
                case .noAccessibility: "Copied · press ⌘V (Accessibility is off)"
                }
            }
        }
    }

    /// How long to wait before restoring the clipboard. Slow apps read the paste late.
    static let restoreDelay: Duration = .milliseconds(300)

    static func insert(_ text: String) async -> Outcome {
        let pasteboard = NSPasteboard.general

        if let reason = reasonNotToPaste() {
            copy(text)
            return .copied(reason)
        }

        let saved = snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChange = pasteboard.changeCount

        sendCommandV()
        try? await Task.sleep(for: restoreDelay)

        // Only restore if nothing else touched the clipboard in the meantime.
        if pasteboard.changeCount == ourChange {
            restore(saved, to: pasteboard)
        }
        return .pasted
    }

    private static func reasonNotToPaste() -> Outcome.Reason? {
        guard AXIsProcessTrusted() else { return .noAccessibility }
        if IsSecureEventInputEnabled() { return .passwordField }
        switch FocusedField.current() {
        case .text: return nil
        case .secure: return .passwordField
        case .none: return .noTextField
        }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        for event in [down, up] {
            event?.flags = .maskCommand
            event?.setIntegerValueField(.eventSourceUserData, value: HotkeyMonitor.syntheticEventTag)
        }
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                data[type] = item.data(forType: type)
            }
            return data
        }
    }

    private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restored.isEmpty {
            pasteboard.writeObjects(restored)
        }
    }
}

/// Reads the focused UI element through Accessibility.
enum FocusedField {
    private static let textRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField", "AXWebArea",
    ]

    enum Kind {
        case text, secure, none
    }

    /// `.none` only when we're sure there's nowhere to type. If Accessibility can't tell
    /// (many Electron and custom-drawn apps), assume text and paste.
    static func current() -> Kind {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var focused: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        if error == .noValue { return .none }
        guard error == .success, let focused else { return .text }
        let element = focused as! AXUIElement

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        if let role = role as? String {
            if role == "AXSecureTextField" || (role == kAXTextFieldRole && subrole(of: element) == kAXSecureTextFieldSubrole) {
                return .secure
            }
            if textRoles.contains(role) { return .text }
        }
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue {
            return .text
        }
        var range: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success {
            return .text
        }
        // A known, non-text element (a button, a list) has focus.
        return role == nil ? .text : .none
    }

    private static func subrole(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value)
        return value as? String
    }
}
