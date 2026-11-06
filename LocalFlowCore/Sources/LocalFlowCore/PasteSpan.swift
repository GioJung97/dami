import Foundation

/// Where pasted text sits in a field, followed across edits. Offsets are UTF-16, like Accessibility ranges.
/// Only the span is ever kept: the rest of the field is read to follow it and then dropped.
public struct PasteSpan: Equatable, Sendable {
    public private(set) var start: Int
    public private(set) var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    /// What one change to the field did to the span.
    public enum Change: Equatable, Sendable {
        /// Nothing changed, or only text before or after the span. Typing right after it counts as after.
        case outside
        /// The change was inside the span.
        case inside
        /// The change crossed the span's edges, so where the pasted text ends can't be told.
        case lost
    }

    /// Finds `pasted` in `value`, ending at the caret if it can, else the occurrence nearest the caret.
    public static func locate(_ pasted: String, in value: String, caret: Int?) -> PasteSpan? {
        let text = Array(pasted.utf16)
        let field = Array(value.utf16)
        guard !text.isEmpty, text.count <= field.count else { return nil }
        if let caret, caret >= text.count, caret <= field.count, Array(field[(caret - text.count)..<caret]) == text {
            return PasteSpan(start: caret - text.count, end: caret)
        }
        var best: Int?
        var index = 0
        while index + text.count <= field.count {
            if field[index] == text[0], Array(field[index..<(index + text.count)]) == text {
                let distance = abs(index + text.count - (caret ?? field.count))
                if best.map({ distance < abs($0 + text.count - (caret ?? field.count)) }) ?? true { best = index }
            }
            index += 1
        }
        return best.map { PasteSpan(start: $0, end: $0 + text.count) }
    }

    /// Follows the span from the field's previous value to its new one.
    public mutating func update(from old: String, to new: String) -> Change {
        let before = Array(old.utf16)
        let after = Array(new.utf16)
        guard end <= before.count else { return .lost }
        var prefix = 0
        while prefix < before.count, prefix < after.count, before[prefix] == after[prefix] { prefix += 1 }
        if prefix == before.count, prefix == after.count { return .outside }
        var suffix = 0
        while suffix < before.count - prefix, suffix < after.count - prefix,
              before[before.count - 1 - suffix] == after[after.count - 1 - suffix] { suffix += 1 }
        let changedEnd = before.count - suffix
        let delta = after.count - before.count

        if prefix >= end { return .outside }
        if changedEnd <= start {
            start += delta
            end += delta
            return .outside
        }
        if prefix >= start, changedEnd <= end {
            end += delta
            return end > start ? .inside : .lost
        }
        return .lost
    }

    /// The span's text in `value`.
    public func text(in value: String) -> String? {
        let field = Array(value.utf16)
        guard start >= 0, end <= field.count, start < end else { return nil }
        return String(decoding: field[start..<end], as: UTF16.self)
    }

    /// A result much longer than the pasted text probably isn't the same text, and could hold something unrelated.
    public static func isPlausibleEdit(of before: String, to after: String) -> Bool {
        after.count <= before.count * 2 + 20
    }
}
