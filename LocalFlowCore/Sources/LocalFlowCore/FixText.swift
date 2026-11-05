import Foundation

/// A fix the user typed for a dictation's text.
public enum FixText {
    /// The text to save, or nil when there's nothing to save: empty, or the same as what's shown now.
    /// Only the outer whitespace is trimmed, since line breaks and spacing inside are part of the fix.
    public static func normalized(_ text: String, replacing current: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != current.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return trimmed
    }
}
