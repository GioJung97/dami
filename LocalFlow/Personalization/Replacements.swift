import Foundation

/// Applies the Dictionary's replacement rules to a transcript.
/// Latin-script rules match whole words, case-insensitively. Hangul rules match exactly.
enum ReplacementEngine {
    struct Outcome {
        var text: String
        /// Replacement id → how many times it fired.
        var uses: [Int64: Int]
    }

    static func apply(_ rules: [Replacement], to text: String) -> Outcome {
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
