import Foundation

/// Conservative text cleanup without a model. Deliberately narrow: a filler left behind is fine, a
/// changed meaning is not.
public enum CleanupRules {
    public enum Rule: String, CaseIterable, Sendable {
        case englishFillers = "en.fillers"
        case koreanFillers = "ko.fillers"
        case englishRepeats = "en.repeats"
        case koreanRepeats = "ko.repeats"
        case numberCorrection = "numbers.correction"

        /// What it did, for History.
        public var summary: String {
            switch self {
            case .englishFillers, .koreanFillers: "Removed filler words."
            case .englishRepeats, .koreanRepeats: "Removed a repeated word."
            case .numberCorrection: "Kept the corrected number."
            }
        }
    }

    public struct Outcome: Equatable, Sendable {
        public var text: String
        /// Rules that changed something, in the order they ran.
        public var applied: [Rule]
    }

    /// Which rules apply to a dictation. German "er" means "he" and Portuguese "um" means "a", so
    /// Latin-script languages get nothing. A language with its own script gets the English rules too,
    /// since its sentences can mix in English. Only English and Korean have rules of their own so far.
    public static func rules(forLanguage language: String) -> [Rule] {
        let english: [Rule] = [.englishFillers, .englishRepeats, .numberCorrection]
        if language == "en" { return english }
        guard SpokenLanguage.find(language)?.script != nil else { return [] }
        return language == "ko" ? english + [.koreanFillers, .koreanRepeats] : english
    }

    public static func apply(to text: String, language: String) -> Outcome {
        var result = text
        var applied: [Rule] = []
        for rule in rules(forLanguage: language) {
            let changed = run(rule, on: result)
            if changed != result {
                result = changed
                applied.append(rule)
            }
        }
        return Outcome(text: result, applied: applied)
    }

    private static func run(_ rule: Rule, on text: String) -> String {
        switch rule {
        case .englishFillers: removeFillers(englishFillers, in: text) { _, _ in true }
        case .koreanFillers: removeFillers(koreanFillers, in: text) { hasComma, startsSentence in hasComma || startsSentence }
        case .englishRepeats: removeRepeats(englishRepeatable, in: text)
        case .koreanRepeats: removeRepeats(koreanRepeatable, in: text)
        case .numberCorrection: correctNumbers(in: text)
        }
    }

    // MARK: Fillers

    private static let englishFillers = ["um", "umm", "uh", "uhh", "er", "erm", "hmm", "mm"]
    private static let koreanFillers = ["음", "으음"]
    /// Characters that make a word part of something bigger: "uh-oh", "um.py", "er_diagram", "mm's".
    private static let notBefore = #"(?<![\p{L}\p{N}_\-./'’@#])"#
    private static let notAfter = #"(?![\p{L}\p{N}_\-/'’@]|\.[\p{L}\p{N}])"#

    /// - Parameter accept: Whether to remove a match, given whether a comma or ellipsis touches it and
    ///   whether it starts a sentence. Korean "음" is also a noun ("이 음 좋다"), so it needs one of those.
    private static func removeFillers(
        _ words: [String], in text: String, accept: (_ hasComma: Bool, _ startsSentence: Bool) -> Bool
    ) -> String {
        let pattern = "(,[ \\t]*)?" + notBefore + "(" + words.joined(separator: "|") + ")" + notAfter + "([ \\t]*(?:,|\\.{2,}|…))?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let result = NSMutableString(string: text)
        // From the end, so earlier ranges stay valid.
        for match in regex.matches(in: text, range: NSRange(location: 0, length: result.length)).reversed() {
            let word = result.substring(with: match.range(at: 2))
            let lead = match.range(at: 1), trail = match.range(at: 3)
            let hasLead = lead.location != NSNotFound, hasTrail = trail.location != NSNotFound
            // All caps is an acronym: "the ER doctor".
            if word.count > 1, word == word.uppercased(), word != word.lowercased() { continue }
            // A unit: "5 mm".
            if followsNumber(result, match.range(at: 2)) { continue }

            var removal = match.range(at: 2)
            if hasTrail { removal = NSUnionRange(removal, trail) }
            let startsSentence = isSentenceStart(result, at: hasLead ? lead.location : removal.location)
            guard accept(hasLead || hasTrail, startsSentence) else { continue }
            // "should, uh, push" loses both commas. "well, uh I think" keeps the first.
            if hasLead, hasTrail, result.substring(with: trail).hasSuffix(",") { removal = NSUnionRange(removal, lead) }

            result.deleteCharacters(in: removal)
            repair(result, at: removal.location)
        }
        return result as String
    }

    private static func followsNumber(_ text: NSMutableString, _ range: NSRange) -> Bool {
        let before = text.substring(to: range.location).trimmingCharacters(in: .whitespaces)
        return before.last?.isNumber == true
    }

    private static func isSentenceStart(_ text: NSMutableString, at location: Int) -> Bool {
        let before = text.substring(to: location).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = before.last else { return true }
        return ".?!。？！".contains(last)
    }

    /// Tidies the spot where a filler was removed, touching nothing else.
    private static func repair(_ text: NSMutableString, at location: Int) {
        func character(_ index: Int) -> Character? {
            guard index >= 0, index < text.length else { return nil }
            return Character(text.substring(with: NSRange(location: index, length: 1)))
        }
        var location = location
        let startsSentence = isSentenceStart(text, at: location)
        if startsSentence {
            // "Um. Yes" and "Okay. Um, yes".
            while let next = character(location), next.isWhitespace || ".,?!".contains(next) {
                text.deleteCharacters(in: NSRange(location: location, length: 1))
            }
            if let next = character(location), next.isLowercase, next.isASCII {
                text.replaceCharacters(in: NSRange(location: location, length: 1), with: String(next).uppercased())
            }
            return
        }
        // "think um." → "think."
        if let next = character(location), ".,?!;:".contains(next) || next.isNewline {
            while let previous = character(location - 1), previous == " " || previous == "\t" {
                text.deleteCharacters(in: NSRange(location: location - 1, length: 1))
                location -= 1
            }
            if character(location - 1) == ",", let next = character(location), ".?!".contains(next) {
                text.deleteCharacters(in: NSRange(location: location - 1, length: 1))
            }
            return
        }
        guard location < text.length else {
            // "I think um" at the end.
            while let previous = character(location - 1), previous.isWhitespace || previous == "," {
                text.deleteCharacters(in: NSRange(location: location - 1, length: 1))
                location -= 1
            }
            return
        }
        // Two spaces left behind.
        if character(location - 1)?.isWhitespace == true, character(location)?.isWhitespace == true {
            text.deleteCharacters(in: NSRange(location: location, length: 1))
        }
    }

    // MARK: Repeated words

    /// Only words that are never repeated on purpose: not "that that", "had had", "very very", "bye bye".
    private static let englishRepeatable = ["a", "an", "the", "i", "to", "of", "in", "on", "at", "and", "or", "but", "is", "it"]
    /// Not "네 네", "그래 그래" or "진짜 진짜".
    private static let koreanRepeatable = ["그", "이", "저"]

    private static func removeRepeats(_ words: [String], in text: String) -> String {
        let pattern = notBefore + "(" + words.joined(separator: "|") + ")(?:[ \\t]+\\1)+" + notAfter
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "$1")
    }

    // MARK: Number self-correction

    /// `X, MARKER Y` where X and Y both start with a digit: "at 3, no, actually 4 p.m." Words on either
    /// side mean it's not a correction: "I told him, no, we can't".
    private static func correctNumbers(in text: String) -> String {
        let number = #"\p{N}[^\s,]*"#
        let marker = #"(?:no,?[ \t]+actually|no|actually|wait|sorry|아니요|아니다|아니)"#
        let pattern = #"(?<![\p{L}\p{N}_\-./])"# + number + #"[ \t]*,[ \t]*"# + marker + #"[ \t]*,?[ \t]+("# + number + ")"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "$1")
    }
}
