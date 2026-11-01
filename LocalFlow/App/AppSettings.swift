import Foundation
import LocalFlowCore
import ServiceManagement

/// User preferences, persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    enum ShortcutMode: String, CaseIterable, Identifiable {
        case hold
        case holdOrDoubleTap
        var id: String { rawValue }
    }

    /// Which of the user's languages to listen for. `second` is the language picked in
    /// `secondLanguage`; without one, only `english` applies.
    enum LanguageMode: String, CaseIterable, Identifiable {
        case auto, english, second
        var id: String { rawValue }
    }

    enum HUDPosition: String, CaseIterable, Identifiable {
        case bottomCenter, topCenter
        var id: String { rawValue }
        var label: String { self == .bottomCenter ? "Bottom center" : "Top center" }
    }

    /// Days to keep history. 0 = forever, -1 = don't keep.
    static let retentionChoices: [(days: Int, label: String)] = [(7, "7 days"), (30, "30 days"), (0, "Forever"), (-1, "Don't keep")]

    private let defaults = UserDefaults.standard

    @Published var shortcut: Shortcut { didSet { save(shortcut, "shortcut") } }
    @Published var shortcutMode: ShortcutMode { didSet { defaults.set(shortcutMode.rawValue, forKey: "shortcutMode") } }
    @Published var language: LanguageMode { didSet { defaults.set(language.rawValue, forKey: "language") } }
    /// The language spoken next to English, or nil for English only.
    @Published var secondLanguage: SpokenLanguage? {
        didSet {
            defaults.set(secondLanguage?.code ?? "", forKey: "secondLanguage")
            if secondLanguage == nil { language = .english } else if oldValue == nil { language = .auto }
        }
    }
    @Published var keepEnglishTerms: Bool { didSet { defaults.set(keepEnglishTerms, forKey: "keepEnglishInKorean") } }
    @Published var playSounds: Bool { didSet { defaults.set(playSounds, forKey: "playSounds") } }
    @Published var hudPosition: HUDPosition { didSet { defaults.set(hudPosition.rawValue, forKey: "hudPosition") } }
    @Published var retentionDays: Int { didSet { defaults.set(retentionDays, forKey: "retentionDays") } }
    @Published var saveAudio: Bool { didSet { defaults.set(saveAudio, forKey: "saveAudio") } }
    @Published var paused = false
    @Published var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") } }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("LocalFlow: launch at login change failed: \(error.localizedDescription)")
            }
        }
    }

    private init() {
        shortcut = Self.load("shortcut") ?? .defaultDictation
        shortcutMode = ShortcutMode(rawValue: defaults.string(forKey: "shortcutMode") ?? "") ?? .hold
        // Before language choice existed, the second language was always Korean ("korean" mode).
        let savedMode = defaults.string(forKey: "language")
        let isOlderInstall = savedMode != nil || defaults.bool(forKey: "hasCompletedOnboarding")
        let second = SpokenLanguage.find(defaults.string(forKey: "secondLanguage") ?? (isOlderInstall ? "ko" : nil))
        secondLanguage = second
        language = second == nil ? .english : savedMode == "korean" ? .second : LanguageMode(rawValue: savedMode ?? "") ?? .auto
        keepEnglishTerms = defaults.object(forKey: "keepEnglishInKorean") as? Bool ?? true
        playSounds = defaults.object(forKey: "playSounds") as? Bool ?? true
        hudPosition = HUDPosition(rawValue: defaults.string(forKey: "hudPosition") ?? "") ?? .bottomCenter
        retentionDays = defaults.object(forKey: "retentionDays") as? Int ?? 30
        saveAudio = defaults.bool(forKey: "saveAudio")
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
    }

    /// Display label for a mode: "Auto", "EN", or the second language's code.
    func label(for mode: LanguageMode) -> String {
        switch mode {
        case .auto: "Auto"
        case .english: "EN"
        case .second: secondLanguage?.label ?? "—"
        }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
