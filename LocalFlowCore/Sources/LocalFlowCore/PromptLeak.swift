import Foundation

/// On noise, Whisper can repeat the prompt it was given instead of hearing anything.
/// A false positive throws away real speech, so this only fires when the output is essentially
/// the whole prompt, never on a fragment of it.
public enum PromptLeak {
    /// How close to the whole prompt the output must be, 0…1.
    static let promptSimilarity = 0.85
    /// Distinct vocabulary terms the output must consist of. One or two terms can be real speech.
    static let vocabularyTerms = 3

    /// - Parameters:
    ///   - prompt: The mixed-language sample given to Whisper, if any.
    ///   - vocabulary: The Dictionary terms given to Whisper, if any.
    public static func isLeak(output: String, prompt: String?, vocabulary: [String]) -> Bool {
        let words = normalized(output)
        guard !words.isEmpty else { return false }
        if let prompt, similarity(compact(words), compact(normalized(prompt))) >= promptSimilarity {
            return true
        }
        return consistsOfVocabulary(words, vocabulary)
    }

    /// True if nothing but vocabulary terms remains, with enough different terms to be the list
    /// rather than someone saying a term or two.
    private static func consistsOfVocabulary(_ words: String, _ vocabulary: [String]) -> Bool {
        let terms = Set(vocabulary.map(normalized).filter { !$0.isEmpty })
        guard terms.count >= 2 else { return false }

        var remaining = " \(words) "
        var found = 0
        for term in terms.sorted(by: { $0.count > $1.count }) where remaining.contains(" \(term) ") {
            found += 1
            // Replacing with two spaces keeps the neighbours of a match matchable.
            remaining = remaining.replacingOccurrences(of: " \(term) ", with: "  ")
        }
        return found >= min(vocabularyTerms, terms.count) && remaining.allSatisfy(\.isWhitespace)
    }

    /// Lowercased words without punctuation, separated by single spaces.
    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters.union(.symbols)).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Spacing can differ between the prompt and an echo of it, particularly in Korean.
    private static func compact(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    /// 1 for identical strings, falling towards 0 with edit distance.
    private static func similarity(_ a: String, _ b: String) -> Double {
        let a = Array(a), b = Array(b)
        guard let longest = [a.count, b.count].max(), longest > 0 else { return 0 }
        var row = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var previous = row[0]
            row[0] = i + 1
            for (j, y) in b.enumerated() {
                let current = row[j + 1]
                row[j + 1] = min(current + 1, row[j] + 1, previous + (x == y ? 0 : 1))
                previous = current
            }
        }
        return 1 - Double(row[b.count]) / Double(longest)
    }
}
