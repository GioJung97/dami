import Foundation

/// How much LocalFlow changes what Whisper wrote.
public enum CleanupMode: String, CaseIterable, Identifiable, Sendable {
    /// Exactly what Whisper wrote.
    case raw
    /// Replacements, then conservative rules.
    case light

    public var id: String { rawValue }
}

/// What each stage of the pipeline produced.
public struct ProcessedText: Equatable, Sendable {
    /// What Whisper wrote.
    public var raw: String
    /// After the Dictionary's replacement rules.
    public var afterReplacements: String
    /// What gets pasted.
    public var final: String
    /// Replacement id → how many times it fired.
    public var replacementUses: [Int64: Int]
    /// Cleanup rules that changed something.
    public var rulesApplied: [CleanupRules.Rule]
}

/// Turns a transcript into the text to paste.
public enum TextPipeline {
    /// Recorded with each dictation, so results can be told apart when the rules change.
    public static let version = "1"

    /// - Parameter language: Whisper code of the detected language, e.g. "ko".
    public static func process(raw: String, mode: CleanupMode, language: String, rules: [ReplacementRule]) -> ProcessedText {
        guard mode == .light else {
            return ProcessedText(raw: raw, afterReplacements: raw, final: raw, replacementUses: [:], rulesApplied: [])
        }
        let replaced = ReplacementEngine.apply(rules, to: raw)
        let cleaned = CleanupRules.apply(to: replaced.text, language: language)
        return ProcessedText(
            raw: raw, afterReplacements: replaced.text, final: cleaned.text,
            replacementUses: replaced.uses, rulesApplied: cleaned.applied
        )
    }
}
