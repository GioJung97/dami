import Foundation

/// A language the user can speak next to English. Everyone speaks English; at most one other
/// language is picked in onboarding or Settings (PLAN §5).
public struct SpokenLanguage: Identifiable, Hashable, Sendable {
    /// Whisper language code, e.g. "ko".
    public let code: String
    /// English name, e.g. "Korean".
    public let name: String
    /// Name in the language itself, e.g. "한국어".
    public let nativeName: String
    /// Short mixed sample in a dictation style, used as the Whisper prompt so English terms stay in
    /// Latin script. Keep it short: adding an English word list made Whisper translate (Phase 0).
    public let mixedPrompt: String
    /// Sentence to read aloud in onboarding.
    public let practiceSentence: String
    /// The language's own script, if it isn't Latin. Lets us notice when Whisper translated to
    /// English instead of transcribing, and tell mixed dictations from English ones.
    public let script: Script?
    /// Tested on real recordings. The others have prompts that haven't been benchmarked yet.
    public let verified: Bool
    /// False for languages written without spaces between words, like Japanese and Chinese.
    public var usesSpaces: Bool { Self.usesSpaces(code) }

    public var id: String { code }
    public var label: String { code.uppercased() }

    public enum Script: Sendable {
        case hangul, japanese, han, devanagari

        public func matches(_ text: String) -> Bool {
            text.unicodeScalars.contains { scalar in
                ranges.contains { $0.contains(scalar.value) }
            }
        }

        private var ranges: [ClosedRange<UInt32>] {
            switch self {
            case .hangul: [0xAC00...0xD7A3, 0x1100...0x11FF, 0x3130...0x318F]
            case .japanese: [0x3040...0x30FF, 0x4E00...0x9FFF]
            case .han: [0x4E00...0x9FFF, 0x3400...0x4DBF]
            case .devanagari: [0x0900...0x097F]
            }
        }
    }

    public static let english = SpokenLanguage(
        code: "en", name: "English", nativeName: "English",
        mixedPrompt: "", practiceSentence: "Hi, I'm trying out LocalFlow for the first time.",
        script: nil, verified: true
    )

    /// Second languages offered in the picker, verified first.
    public static let all: [SpokenLanguage] = [
        SpokenLanguage(
            code: "ko", name: "Korean", nativeName: "한국어",
            mixedPrompt: "오늘 meeting에서 project timeline 얘기했고, API 관련 bug는 다음 sprint에 fix 할게요.",
            practiceSentence: "안녕하세요, LocalFlow test 중이에요.",
            script: .hangul, verified: true
        ),
        SpokenLanguage(
            code: "ja", name: "Japanese", nativeName: "日本語",
            mixedPrompt: "今日のmeetingでproject timelineについて話して、APIのbugは次のsprintでfixします。",
            practiceSentence: "こんにちは、LocalFlowのtest中です。",
            script: .japanese, verified: false
        ),
        SpokenLanguage(
            code: "zh", name: "Chinese", nativeName: "中文",
            mixedPrompt: "今天的meeting我们讨论了project timeline，API的bug下个sprint再fix。",
            practiceSentence: "你好，我正在test LocalFlow。",
            script: .han, verified: false
        ),
        SpokenLanguage(
            code: "es", name: "Spanish", nativeName: "Español",
            mixedPrompt: "Hoy en el meeting hablamos del project timeline, y el bug de la API lo arreglo en el próximo sprint.",
            practiceSentence: "Hola, estoy haciendo un test de LocalFlow.",
            script: nil, verified: false
        ),
        SpokenLanguage(
            code: "fr", name: "French", nativeName: "Français",
            mixedPrompt: "Aujourd'hui en meeting on a parlé de la project timeline, et je fixe le bug de l'API au prochain sprint.",
            practiceSentence: "Bonjour, je fais un test de LocalFlow.",
            script: nil, verified: false
        ),
        SpokenLanguage(
            code: "de", name: "German", nativeName: "Deutsch",
            mixedPrompt: "Heute im Meeting haben wir über die Project Timeline gesprochen, den API-Bug fixe ich im nächsten Sprint.",
            practiceSentence: "Hallo, ich mache gerade einen Test mit LocalFlow.",
            script: nil, verified: false
        ),
        SpokenLanguage(
            code: "pt", name: "Portuguese", nativeName: "Português",
            mixedPrompt: "Hoje no meeting falamos da project timeline, e o bug da API eu corrijo no próximo sprint.",
            practiceSentence: "Olá, estou fazendo um test do LocalFlow.",
            script: nil, verified: false
        ),
        SpokenLanguage(
            code: "vi", name: "Vietnamese", nativeName: "Tiếng Việt",
            mixedPrompt: "Hôm nay trong meeting mình đã nói về project timeline, còn bug của API thì sprint sau mình fix.",
            practiceSentence: "Xin chào, mình đang test LocalFlow.",
            script: nil, verified: false
        ),
        SpokenLanguage(
            code: "hi", name: "Hindi", nativeName: "हिन्दी",
            mixedPrompt: "आज की meeting में हमने project timeline पर बात की, API का bug अगले sprint में fix करेंगे।",
            practiceSentence: "नमस्ते, अभी LocalFlow का test चल रहा है।",
            script: .devanagari, verified: false
        ),
    ]

    /// Whether a language puts spaces between words. Takes any Whisper code, including English.
    public static func usesSpaces(_ code: String) -> Bool {
        !["ja", "zh"].contains(code)
    }

    public static func find(_ code: String?) -> SpokenLanguage? {
        all.first { $0.code == code }
    }
}
