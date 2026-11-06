import Foundation

/// "When Whisper writes `find`, write `replace` instead."
public struct ReplacementRule: Equatable, Sendable {
    /// Database id, used to count uses. Nil for a rule that isn't stored.
    public var id: Int64?
    public var find: String
    public var replace: String

    public init(id: Int64? = nil, find: String, replace: String) {
        self.id = id
        self.find = find
        self.replace = replace
    }
}

/// Applies the Dictionary's replacement rules to a transcript.
/// Rules for languages that put spaces between words (English, Spanish, Vietnamese, Hindi…) match whole words, ignoring case.
/// Hangul rules match whole words with up to two particles after. Japanese, Chinese and Thai, which don't put spaces between words,
/// match exactly.
public enum ReplacementEngine {
    public struct Outcome: Equatable, Sendable {
        public var text: String
        /// Replacement id → how many times it fired.
        public var uses: [Int64: Int]
    }

    public static func apply(_ rules: [ReplacementRule], to text: String) -> Outcome {
        var result = text
        var uses: [Int64: Int] = [:]
        // Longest first, so "Cloud Code" wins over a rule for "Cloud".
        for rule in rules.sorted(by: { $0.find.count > $1.find.count }) {
            guard let regex = regex(for: rule.find) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            let count = regex.numberOfMatches(in: result, range: range)
            guard count > 0 else { continue }
            result = regex.stringByReplacingMatches(
                in: result, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: rule.replace)
            )
            if let id = rule.id { uses[id, default: 0] += count }
        }
        return Outcome(text: result, uses: uses)
    }

    /// The words a rule for `find` would change in `text`, each the whole word around the match, so a preview can show
    /// "제안서" when the rule is for "제안".
    public static func matchedWords(_ find: String, in text: String) -> [String] {
        guard let regex = regex(for: find) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            var start = match.range.location
            var end = match.range.location + match.range.length
            while start > 0, !isBoundary(ns.character(at: start - 1)) { start -= 1 }
            while end < ns.length, !isBoundary(ns.character(at: end)) { end += 1 }
            return ns.substring(with: NSRange(location: start, length: end - start))
        }
    }

    private static func isBoundary(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).contains(scalar)
    }

    /// Scripts written without spaces between words, where a word can't be told apart inside text.
    private static let unspacedScripts = "\\p{Script=Han}\\p{Script=Hiragana}\\p{Script=Katakana}\\p{Script=Thai}\\p{Script=Lao}\\p{Script=Khmer}\\p{Script=Myanmar}"
    /// A letter, mark or digit of a spaced language: what continues a word. Hangul and unspaced scripts don't, so "cloud code로"
    /// still matches a rule for "cloud code".
    private static let wordCharacter = "[[\\p{L}\\p{M}\\p{N}]--[\\p{Script=Hangul}\(unspacedScripts)]]"

    private static func regex(for find: String) -> NSRegularExpression? {
        let escaped = NSRegularExpression.escapedPattern(for: find)
        let isUnspaced = find.range(of: "[\(unspacedScripts)]", options: .regularExpression) != nil
        let isSpaced = !isUnspaced && !KoreanParticles.containsHangul(find)
        let pattern: String
        if isSpaced {
            pattern = "(?<!\(wordCharacter))\(escaped)(?!\(wordCharacter))"
        } else if KoreanParticles.containsHangul(find) {
            // No Hangul right before, and after it the end of the word or particles, so "세" leaves "확인하세요" alone. The
            // particles stay in the text: only `find` is replaced.
            let particles = KoreanParticles.all.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            pattern = "(?<!\\p{Script=Hangul})\(escaped)(?=(?:\(particles)){0,\(KoreanParticles.maxInARow)}(?!\\p{Script=Hangul}))"
        } else {
            pattern = escaped
        }
        return try? NSRegularExpression(pattern: pattern, options: isSpaced ? [.caseInsensitive] : [])
    }
}
