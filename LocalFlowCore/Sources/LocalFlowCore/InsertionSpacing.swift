import Foundation

/// Decides whether pasted text needs a space in front, so consecutive dictations don't join:
/// "I went home.Then I ate."
public enum InsertionSpacing {
    /// What's known about where the text is going.
    public enum Context: Equatable, Sendable {
        /// Accessibility could read the character before the caret.
        case readable(before: Character)
        /// Accessibility couldn't read one (terminals, some Electron apps, or the start of a field), so go
        /// by the last dictation.
        case unreadable(previousDictation: PreviousDictation?)
    }

    public struct PreviousDictation: Equatable, Sendable {
        public var isSameApp: Bool
        public var secondsAgo: TimeInterval
        /// Any key pressed since it was pasted. The caret may have moved.
        public var keyPressedSince: Bool

        public init(isSameApp: Bool, secondsAgo: TimeInterval, keyPressedSince: Bool) {
            self.isSameApp = isSameApp
            self.secondsAgo = secondsAgo
            self.keyPressedSince = keyPressedSince
        }
    }

    /// Beyond this, a previous dictation says nothing about where the caret is.
    static let previousDictationWindow: TimeInterval = 120

    private static let opening: Set<Character> = ["(", "[", "{", "<", "\"", "'", "“", "‘", "「", "『", "（", "【", "《", "〈"]
    private static let closing: Set<Character> = [
        ".", ",", "!", "?", ";", ":", ")", "]", "}", ">", "%", "…", "”", "’",
        "。", "、", "，", "！", "？", "；", "：", "）", "」", "』", "】", "》", "〉",
    ]

    /// - Parameter language: Whisper code of the new text's language.
    public static func needsLeadingSpace(newText: String, language: String, context: Context) -> Bool {
        guard SpokenLanguage.usesSpaces(language), let first = newText.first,
              !first.isWhitespace, !closing.contains(first) else { return false }
        switch context {
        case .readable(let before):
            return !before.isWhitespace && !opening.contains(before)
        case .unreadable(let previous):
            guard let previous else { return false }
            return previous.isSameApp && previous.secondsAgo <= previousDictationWindow && !previous.keyPressedSince
        }
    }
}
