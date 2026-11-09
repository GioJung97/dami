import Foundation

/// Rules for fixes Dami sees in the app the text was pasted into (v0.3 §5, M2).
public enum AutoFix {
    /// What kind of change a fix is, computed from the stored before and after, so the policy can change later.
    public enum Signal: Equatable, Sendable {
        /// A few words replaced by others: the strongest sign Whisper got a word wrong.
        case substitution
        /// Spacing, punctuation or a short deletion.
        case cleanup
        /// Words only added, or most of the text rewritten. Not about what Whisper heard.
        case rewrite
        case unchanged
    }

    public static func signal(before: String, after: String) -> Signal {
        let old = normalized(before)
        let new = normalized(after)
        guard old != new else { return .unchanged }
        let oldWords = words(old)
        let newWords = words(new)
        if oldWords.joined() == newWords.joined() { return .cleanup }
        if strippingPunctuation(oldWords) == strippingPunctuation(newWords) { return .cleanup }

        var prefix = 0
        while prefix < oldWords.count, prefix < newWords.count, oldWords[prefix] == newWords[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < oldWords.count - prefix, suffix < newWords.count - prefix,
              oldWords[oldWords.count - 1 - suffix] == newWords[newWords.count - 1 - suffix] { suffix += 1 }
        let removed = oldWords.count - prefix - suffix
        let added = newWords.count - prefix - suffix
        if added == 0 { return removed <= 2 ? .cleanup : .rewrite }
        if removed == 0 { return .rewrite }
        if removed <= FixSuggestion.maxWords, added <= FixSuggestion.maxWords { return .substitution }
        return .rewrite
    }

    /// Times the same fix must be seen before Dami suggests it. A fix typed in History needs no repeat.
    public static let repeatsToSuggest = 2
    /// Whisper's confidence under which a word counts as one it wasn't sure of.
    public static let unsureBelow: Float = 0.5

    /// Whether Whisper was unsure of a word in `find`. Words are Whisper's own, before cleanup. With no words measured, no.
    public static func wasUnsure(of find: String, words: [(word: String, probability: Float)]) -> Bool {
        let targets = self.words(normalized(find)).map(bare)
        return words.contains { word in
            let text = bare(normalized(word.word))
            guard !text.isEmpty, word.probability < unsureBelow else { return false }
            // Whisper may split or join words differently from the text, so a part of the word counts, but not a single letter.
            return targets.contains { $0 == text || (text.count >= 2 && ($0.contains(text) || text.contains($0))) }
        }
    }

    /// Composed Unicode, so Hangul read from another app compares equal to the text Dami pasted.
    public static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func bare(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)).lowercased()
    }

    private static func strippingPunctuation(_ words: [String]) -> [String] {
        words.map(bare).filter { !$0.isEmpty }
    }
}
