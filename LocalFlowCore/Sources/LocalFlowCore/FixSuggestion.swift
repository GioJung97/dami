import Foundation

/// Turns one fix into at most one Replacement to suggest: "When Whisper writes X, write Y instead."
public enum FixSuggestion {
    public struct Pair: Equatable, Sendable {
        public let find: String
        public let replace: String
        public init(find: String, replace: String) {
            self.find = find
            self.replace = replace
        }
    }

    /// Words on either side of a suggestion, at most. A bigger change is a rewrite, not a word Whisper got wrong.
    public static let maxWords = 3

    /// Nil for a deletion, an addition, or a rewrite of more than a few words, which aren't word mistakes.
    public static func from(before: String, after: String) -> Pair? {
        let old = before.split(whereSeparator: \.isWhitespace).map(String.init)
        let new = after.split(whereSeparator: \.isWhitespace).map(String.init)
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        let removed = Array(old[prefix..<(old.count - suffix)])
        let added = Array(new[prefix..<(new.count - suffix)])
        guard !removed.isEmpty, !added.isEmpty, removed.count <= maxWords, added.count <= maxWords else { return nil }

        var find = removed.joined(separator: " ")
        var replace = added.joined(separator: " ")
        // A Korean particle follows the word: "로컬플로우로" → "LocalFlow로" should learn "로컬플로우" → "LocalFlow". Only for one word
        // on each side, and only a known particle, since a shared ending like "어" in "끝났어" → "끝냈어" is part of the verb.
        if removed.count == 1, added.count == 1,
           let particle = particles.first(where: { find.hasSuffix($0) && replace.hasSuffix($0) && find.count > $0.count && replace.count > $0.count }) {
            find.removeLast(particle.count)
            replace.removeLast(particle.count)
        }
        // Punctuation around the words isn't part of the mistake.
        find = find.trimmingCharacters(in: .punctuationCharacters)
        replace = replace.trimmingCharacters(in: .punctuationCharacters)
        guard !find.isEmpty, !replace.isEmpty, find != replace else { return nil }
        return Pair(find: find, replace: replace)
    }

    /// Longest first, so "으로" wins over "로".
    private static let particles = [
        "에서는", "에게서", "이랑", "한테", "에게", "에서", "까지", "부터", "처럼", "보다", "으로", "로는", "은", "는", "이", "가", "을", "를",
        "에", "의", "와", "과", "도", "만", "로", "랑",
    ].sorted { $0.count > $1.count }
}

/// Vocabulary that fits in Whisper's prompt. Past its limit WhisperKit keeps only the last tokens, cutting terms silently, so this
/// keeps whole terms, newest first.
public enum VocabularyPrompt {
    /// WhisperKit keeps `maxTokenContext / 2 - 1` prompt tokens.
    public static let maxTokens = 111

    public static func text(_ terms: [String]) -> String {
        terms.joined(separator: ", ") + "."
    }

    /// - Parameters:
    ///   - terms: oldest first, as stored.
    ///   - tokenCount: tokens for a prompt text.
    /// - Returns: the terms that fit, oldest first.
    public static func fitting(_ terms: [String], limit: Int = maxTokens, tokenCount: (String) -> Int) -> [String] {
        var kept: [String] = []
        for term in terms.reversed() {
            let candidate = [term] + kept
            if tokenCount(" " + text(candidate)) <= limit { kept = candidate }
        }
        return kept
    }
}
