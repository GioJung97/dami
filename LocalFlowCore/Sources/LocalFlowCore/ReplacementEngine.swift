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
            let escaped = NSRegularExpression.escapedPattern(for: rule.find)
            let isLatin = rule.find.range(of: "^[A-Za-z0-9 .'-]+$", options: .regularExpression) != nil
            let pattern = isLatin ? "(?<![A-Za-z0-9])\(escaped)(?![A-Za-z0-9])" : escaped
            guard let regex = try? NSRegularExpression(pattern: pattern, options: isLatin ? [.caseInsensitive] : []) else {
                continue
            }
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
}
