import Foundation

/// Korean particles that follow a word, shared by suggestions and Replacement matching.
public enum KoreanParticles {
    /// Longest first, so "으로" wins over "로".
    public static let all = [
        "에서는", "에게서", "이랑", "한테", "에게", "에서", "까지", "부터", "처럼", "보다", "으로", "로는", "은", "는", "이", "가", "을", "를",
        "에", "의", "와", "과", "도", "만", "로", "랑",
    ].sorted { $0.count > $1.count }

    /// Particles allowed in a row after a Replacement's word, as in "클라우드에서도".
    public static let maxInARow = 2

    public static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { isHangul($0) }
    }

    /// One Hangul syllable, such as "세". Too short to tell apart from part of another word.
    public static func isSingleSyllable(_ text: String) -> Bool {
        text.count == 1 && text.unicodeScalars.allSatisfy(isHangul)
    }

    static func isHangul(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0xAC00...0xD7A3, 0x1100...0x11FF, 0x3130...0x318F: true
        default: false
        }
    }
}
