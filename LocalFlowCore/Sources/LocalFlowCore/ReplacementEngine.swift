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
/// Latin-script rules match whole words, case-insensitively. Hangul rules match exactly.
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

    /// Latin-script rules match whole words, case-insensitively. Anything else matches exactly.
    private static func regex(for find: String) -> NSRegularExpression? {
        let escaped = NSRegularExpression.escapedPattern(for: find)
        let isLatin = find.range(of: "^[A-Za-z0-9 .'-]+$", options: .regularExpression) != nil
        let pattern = isLatin ? "(?<![A-Za-z0-9])\(escaped)(?![A-Za-z0-9])" : escaped
        return try? NSRegularExpression(pattern: pattern, options: isLatin ? [.caseInsensitive] : [])
    }
}
