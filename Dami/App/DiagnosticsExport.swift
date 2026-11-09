import AppKit
import DamiCore
import Foundation

/// Gathers what goes in the diagnostics file (v1.0 M3). `Diagnostics` in DamiCore decides what's safe to write.
@MainActor
enum DiagnosticsExport {
    static func report(modelReady: Bool) -> String {
        let settings = AppSettings.shared
        let defaults = UserDefaults.standard
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let database = Store.shared.diagnostics()
        let devices = InputDevices.shared
        let chosen = settings.inputDeviceUID.flatMap { uid in CoreAudioDevices.inputDevices().first { $0.id == uid } }
        let values: [(String, String)] = [
            ("setupDone", String(settings.hasCompletedOnboarding)),
            ("modelReady", String(modelReady)),
            ("language", settings.language.rawValue),
            ("secondLanguage", settings.secondLanguage?.code ?? "none"),
            ("keepEnglishTerms", String(settings.keepEnglishTerms)),
            ("cleanupMode", settings.cleanupMode.rawValue),
            ("shortcut", settings.shortcut == .defaultDictation ? "default" : "custom"),
            ("shortcutMode", settings.shortcutMode.rawValue),
            ("microphone", settings.inputDeviceUID == nil ? "systemDefault" : (chosen == nil ? "chosenMissing" : "chosen")),
            ("microphoneTransport", (chosen ?? devices.systemDefault)?.transportName ?? "none"),
            ("playSounds", String(settings.playSounds)),
            ("hudPosition", settings.hudPosition.rawValue),
            ("appearance", settings.appearanceMode.rawValue),
            ("theme", settings.theme.rawValue),
            ("keyColor", settings.keyColor.rawValue),
            ("retentionDays", String(settings.retentionDays)),
            ("saveAudio", String(settings.saveAudio)),
            ("learnFromFixes", String(settings.learnFromFixes)),
            ("tourShown", String(settings.tourShown)),
        ]
        let input = Diagnostics.Input(
            appVersion: version,
            macOS: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            mac: MemoryInfo.macDescription,
            settings: values,
            healthCounts: defaults.dictionary(forKey: "healthCounts") as? [String: Int] ?? [:],
            dropCounts: defaults.dictionary(forKey: "dropCountsByDay") as? [String: Int] ?? [:],
            latencySamples: defaults.stringArray(forKey: "latencySamples") ?? [],
            pasteWatches: database.pasteWatches,
            database: database.check,
            dictations: database.dictations,
            crashReports: crashReports()
        )
        return Diagnostics.report(input)
    }

    /// Only the file names, which hold the app's name and a time.
    private static func crashReports() -> [String] {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/DiagnosticReports")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix("Dami") }.sorted()
    }

    static func save(_ report: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Dami-diagnostics-\(HealthStats.day(Date())).txt"
        panel.allowedContentTypes = [.plainText]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }
}
