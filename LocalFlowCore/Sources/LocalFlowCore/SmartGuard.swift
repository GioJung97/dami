import Foundation

/// Decides whether a Smart result may be pasted, or Light's text instead (`docs/plans/v0.4.md` §4.1). The same rule runs in the
/// offline eval and in the app.
///
/// The result must be the input with whole words deleted and nothing added, ignoring spacing, the punctuation at the edges of words,
/// and letter case. Every deleted word needs a reason: a filler, a word repeated right after itself, or a self-correction (a marker
/// such as "아니" or "no" with at most 4 words before it, and words after it). Negations are never deleted, and numbers only inside a
/// self-correction.
public enum SmartGuard {
    public enum Verdict: Equatable, Sendable {
        case pass(deleted: [Deletion])
        /// Nothing in the rules explains the result: something was added, changed, or deleted without a reason.
        case fail
    }

    public struct Deletion: Equatable, Sendable {
        public enum Reason: String, Sendable { case filler, repeated, selfCorrection }
        public let words: [String]
        public let reason: Reason

        public init(words: [String], reason: Reason) {
            self.words = words
            self.reason = reason
        }
    }

    public static let maxWordsBeforeMarker = 4

    public static func check(input: String, output: String) -> Verdict {
        let words = tokens(input)
        let target = Array(tokens(output).map(\.core).joined())
        let n = words.count

        // reach[i][j]: the first i input words can become the first j characters of the output.
        var reach = Array(repeating: Array(repeating: false, count: target.count + 1), count: n + 1)
        var step = Array(repeating: Array(repeating: Step?.none, count: target.count + 1), count: n + 1)
        reach[0][0] = true
        for i in 0..<n {
            for j in 0...target.count where reach[i][j] {
                let core = Array(words[i].core)
                if j + core.count <= target.count, Array(target[j..<(j + core.count)]) == core, !reach[i + 1][j + core.count] {
                    reach[i + 1][j + core.count] = true
                    step[i + 1][j + core.count] = Step(from: i, at: j, deletion: nil)
                }
                if let reason = singleDeletion(words, i), !reach[i + 1][j] {
                    reach[i + 1][j] = true
                    step[i + 1][j] = Step(from: i, at: j, deletion: reason)
                }
                for end in correctionEnds(words, from: i) where !reach[end][j] {
                    reach[end][j] = true
                    step[end][j] = Step(from: i, at: j, deletion: .selfCorrection)
                }
            }
        }
        guard reach[n][target.count] else { return .fail }

        var deletions: [Deletion] = []
        var i = n, j = target.count
        while i > 0, let s = step[i][j] {
            if let reason = s.deletion { deletions.append(Deletion(words: words[s.from..<i].map(\.text), reason: reason)) }
            i = s.from
            j = s.at
        }
        return .pass(deleted: deletions.reversed())
    }

    // MARK: Words

    struct Token {
        let text: String
        /// Lowercased, without the punctuation at its edges. Punctuation inside stays: "1.2.3", "auth.ts", "don't".
        let core: String
        /// As spoken, edges stripped but case kept, for "HMM" against "hmm".
        let bare: String
        let endsWithPause: Bool
    }

    private struct Step {
        let from: Int
        let at: Int
        let deletion: Deletion.Reason?
    }

    /// Only these may change at a word's edges. `$`, `%`, `/`, `#` and `@` are part of the word.
    private static let edgePunctuation = CharacterSet(charactersIn: ".,!?;:…\"'“”‘’()[]{}-–—·、。，！？")
    private static let pauses = CharacterSet(charactersIn: ",;:…-–—，、")

    static func tokens(_ text: String) -> [Token] {
        text.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .compactMap { word in
                let bare = word.trimmingCharacters(in: edgePunctuation)
                guard !bare.isEmpty else { return nil }
                let trailing = word.unicodeScalars.last.map { pauses.contains($0) } ?? false
                let ellipsis = word.hasSuffix("...")
                return Token(text: word, core: bare.lowercased(), bare: bare, endsWithPause: trailing || ellipsis)
            }
    }

    // MARK: Reasons

    private static let englishFillers: Set<String> = ["um", "umm", "uh", "uhh", "uhm", "er", "erm", "hmm"]
    private static let koreanFillers: Set<String> = ["음", "어", "아", "에", "으"]
    /// Fillers only when a pause follows or another filler does, since "그 사람" means "that person".
    private static let koreanPausedFillers: Set<String> = ["그", "저"]
    /// Longer first is not needed: every marker that fits is tried.
    private static let markers: [[String]] = [
        ["no"], ["actually"], ["sorry"], ["i", "mean"], ["no", "actually"], ["no", "wait"], ["actually", "no"], ["아니"], ["아", "아니"],
    ]

    private static func singleDeletion(_ words: [Token], _ i: Int) -> Deletion.Reason? {
        let word = words[i]
        guard !isProtected(word) else { return nil }
        if i + 1 < words.count, words[i + 1].core == word.core { return .repeated }
        guard isFiller(words, i) else { return nil }
        return .filler
    }

    private static func isFiller(_ words: [Token], _ i: Int) -> Bool {
        let word = words[i]
        // "HMM" is an acronym, and "3 um" a unit.
        if word.bare.count > 1, word.bare == word.bare.uppercased(), word.bare != word.bare.lowercased() { return false }
        if i > 0, words[i - 1].core.contains(where: \.isNumber) { return false }
        let nextIsFiller = i + 1 < words.count && (koreanFillers.contains(words[i + 1].core) || englishFillers.contains(words[i + 1].core))
        if englishFillers.contains(word.core) || koreanFillers.contains(word.core) { return true }
        if koreanPausedFillers.contains(word.core) { return word.endsWithPause || nextIsFiller }
        // "like" only between pauses: "Can you, like, check".
        if word.core == "like" { return i > 0 && words[i - 1].endsWithPause && word.endsWithPause }
        return false
    }

    /// Where a self-correction starting at `start` could end: 1–4 words, then a marker, with words still after it.
    private static func correctionEnds(_ words: [Token], from start: Int) -> [Int] {
        var ends: [Int] = []
        for before in 1...maxWordsBeforeMarker {
            let markerStart = start + before
            guard markerStart < words.count else { break }
            let span = words[start..<markerStart]
            guard !span.contains(where: isNegation) else { break }
            for marker in markers {
                let markerEnd = markerStart + marker.count
                guard markerEnd < words.count, words[markerStart..<markerEnd].map(\.core) == marker else { continue }
                // A marker follows a pause ("3, no, 4"), or a number is corrected by a number without one ("5 sorry 6"). Otherwise
                // "I have 3, but no 4 is left" would lose "but no".
                let paused = words[markerStart - 1].endsWithPause
                let numberForNumber = words[markerEnd].core.first?.isNumber == true && span.contains(where: isNumber)
                if paused || numberForNumber { ends.append(markerEnd) }
            }
        }
        return ends
    }

    private static func isProtected(_ word: Token) -> Bool {
        isNegation(word) || isNumber(word)
    }

    private static let englishNegations: Set<String> = [
        "not", "no", "never", "none", "nothing", "nobody", "nowhere", "neither", "nor", "cannot", "without",
    ]
    private static let koreanNegations: Set<String> = ["안", "못", "마", "말", "아니", "아니야", "아니요", "아뇨"]
    private static let koreanNegationStems = ["없", "않", "말아", "말고", "말라", "마라", "못하", "안 "]

    static func isNegation(_ word: Token) -> Bool {
        let core = word.core
        if englishNegations.contains(core) || core.hasSuffix("n't") { return true }
        if koreanNegations.contains(core) { return true }
        return koreanNegationStems.contains { core.hasPrefix($0) }
    }

    private static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "hundred",
        "thousand", "million", "billion", "하나", "둘", "셋", "넷", "다섯", "여섯", "일곱", "여덟", "아홉", "열",
    ]

    static func isNumber(_ word: Token) -> Bool {
        word.core.contains(where: \.isNumber) || numberWords.contains(word.core)
    }
}
