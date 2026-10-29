import Foundation

/// Whisper was trained on subtitles, so on silence or noise it sometimes "hears" stock phrases.
/// Drop a transcript that is only one of these. Short phrases people really dictate
/// ("Thank you", "감사합니다") are deliberately not listed.
enum HallucinationFilter {
    private static let phrases: Set<String> = [
        "thank you for watching", "thanks for watching", "thank you so much for watching",
        "please subscribe", "you", "the end",
        "시청해 주셔서 감사합니다", "시청해주셔서 감사합니다", "구독과 좋아요 부탁드립니다",
        "구독과 좋아요", "mbc 뉴스 이덕영입니다",
    ]

    static func isHallucination(_ text: String) -> Bool {
        let normalized = text.lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters.union(.symbols)).joined()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return normalized.isEmpty || phrases.contains(normalized)
    }
}
