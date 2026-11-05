import Foundation

/// Decides from Accessibility attributes whether the focused element can take a paste. A paste into
/// nothing still looks like success, so it matters: a browser reports a role for the page itself, even
/// when no field is focused.
public enum FocusClassifier {
    public enum Kind: Equatable, Sendable {
        case text, secure, none
    }

    public struct Element: Equatable, Sendable {
        public var role: String?
        public var subrole: String?
        public var isValueSettable = false
        public var hasSelectedRange = false
        /// `AXEditableAncestor`: web content inside something editable.
        public var hasEditableAncestor = false
        /// `AXSelectedTextMarkerRange`: only web content has this.
        public var isWebContent = false

        public init(
            role: String?, subrole: String? = nil, isValueSettable: Bool = false, hasSelectedRange: Bool = false,
            hasEditableAncestor: Bool = false, isWebContent: Bool = false
        ) {
            self.role = role
            self.subrole = subrole
            self.isValueSettable = isValueSettable
            self.hasSelectedRange = hasSelectedRange
            self.hasEditableAncestor = hasEditableAncestor
            self.isWebContent = isWebContent
        }
    }

    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    /// `.none` only when we're sure there's nowhere to type. If Accessibility can't tell
    /// (many Electron and custom-drawn apps), assume text and paste. On a web page, unsure means
    /// `.none`, because that's the common state of a page with no field focused, and the text stays on
    /// the clipboard either way.
    public static func classify(_ element: Element) -> Kind {
        if element.role == "AXSecureTextField" || (element.role == "AXTextField" && element.subrole == "AXSecureTextField") {
            return .secure
        }
        if let role = element.role, textRoles.contains(role) { return .text }
        if element.hasEditableAncestor || element.isValueSettable { return .text }
        if element.isWebContent || element.role == "AXWebArea" {
            // Google Docs types into a hidden empty group.
            return element.subrole == "AXEmptyGroup" ? .text : .none
        }
        if element.hasSelectedRange { return .text }
        // A known, non-text element (a button, a list) has focus.
        return element.role == nil ? .text : .none
    }
}
