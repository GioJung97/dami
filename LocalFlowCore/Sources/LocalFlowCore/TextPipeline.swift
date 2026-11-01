import Foundation

/// How much LocalFlow changes what Whisper wrote.
public enum CleanupMode: String, CaseIterable, Sendable {
    /// Exactly what Whisper wrote.
    case raw
    /// Replacements.
    case light
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
}

/// Turns a transcript into the text to paste.
public enum TextPipeline {
    /// - Parameter language: Whisper code of the detected language, e.g. "ko".
    public static func process(raw: String, mode: CleanupMode, language: String, rules: [ReplacementRule]) -> ProcessedText {
        guard mode == .light else {
            return ProcessedText(raw: raw, afterReplacements: raw, final: raw, replacementUses: [:])
        }
        let replaced = ReplacementEngine.apply(rules, to: raw)
        return ProcessedText(raw: raw, afterReplacements: replaced.text, final: replaced.text, replacementUses: replaced.uses)
    }
}
