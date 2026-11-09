import Foundation

/// The diagnostics file a user can send when something goes wrong (v1.0 M3). Numbers, versions and setting names only: never
/// dictated text, Dictionary entries, device names or which key was pressed. Everything taken from storage passes a filter that
/// only lets through what this app writes there, so text that got in by mistake can't leave in the file.
public enum Diagnostics {
    public struct Input: Sendable {
        public var appVersion: String
        public var macOS: String
        public var mac: String
        /// Setting names and values, such as ("cleanupMode", "light").
        public var settings: [(String, String)]
        public var healthCounts: [String: Int]
        public var dropCounts: [String: Int]
        public var latencySamples: [String]
        /// "outcome.endedBy" for each paste watched by Learn from fixes.
        public var pasteWatches: [String: Int]
        public var database: String
        public var dictations: Int
        public var crashReports: [String]

        public init(
            appVersion: String, macOS: String, mac: String, settings: [(String, String)], healthCounts: [String: Int],
            dropCounts: [String: Int], latencySamples: [String], pasteWatches: [String: Int], database: String, dictations: Int,
            crashReports: [String]
        ) {
            self.appVersion = appVersion
            self.macOS = macOS
            self.mac = mac
            self.settings = settings
            self.healthCounts = healthCounts
            self.dropCounts = dropCounts
            self.latencySamples = latencySamples
            self.pasteWatches = pasteWatches
            self.database = database
            self.dictations = dictations
            self.crashReports = crashReports
        }
    }

    /// How many of the latest latency samples go in.
    public static let latencyLimit = 100

    public static func report(_ input: Input, generated: Date = Date()) -> String {
        var lines = [
            "Dami diagnostics",
            "Numbers, versions and setting names only. No dictated text, Dictionary entries, device names or keys pressed.",
            "",
            "generated: \(ISO8601DateFormatter().string(from: generated))",
            "app: \(word(input.appVersion))",
            "macOS: \(word(input.macOS))",
            "mac: \(word(input.mac))",
            "",
            "== Settings",
        ]
        lines += input.settings.map { "\(code($0.0)): \(code($0.1))" }
        lines += ["", "== Failures by kind and day"] + counts(input.healthCounts)
        lines += ["", "== Dictations that pasted nothing, by reason, length and day"] + counts(input.dropCounts)
        lines += ["", "== Learn from fixes: how each watch ended"] + counts(input.pasteWatches)
        let latency = input.latencySamples.compactMap(safeLatencyLine).suffix(latencyLimit)
        lines += ["", "== Stage times of the last \(latency.count) dictations (seconds)"] + latency
        lines += ["", "== Database", "check: \(word(input.database))", "dictations: \(input.dictations)"]
        lines += ["", "== Crash reports"] + (input.crashReports.isEmpty ? ["none"] : input.crashReports.compactMap(safeCrashName))
        return lines.joined(separator: "\n") + "\n"
    }

    /// A latency line exactly as `DictationProcessor` writes it: a timestamp, then `key=value` pairs with known keys and
    /// number or code values. Anything else is dropped.
    public static func safeLatencyLine(_ line: String) -> String? {
        let parts = line.split(separator: " ").map(String.init)
        guard let first = parts.first, first.range(of: #"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$"#, options: .regularExpression) != nil else {
            return nil
        }
        for pair in parts.dropFirst() {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2, latencyKeys.contains(kv[0]) else { return nil }
            let pattern = kv[0] == "lang" || kv[0] == "mode" ? #"^[a-z]{2,8}$"# : #"^\d+(\.\d+)?$"#
            guard kv[1].range(of: pattern, options: .regularExpression) != nil else { return nil }
        }
        return line
    }

    private static let latencyKeys: Set<String> = [
        "audio", "lang", "mode", "firstAfterIdle", "wait", "detect", "transcribe", "runs", "reused", "cleanup", "paste", "total",
    ]

    /// Counter keys are made of names, ranges and dates: "empty.1to3s.2026-11-06".
    static func counts(_ counts: [String: Int]) -> [String] {
        let safe = counts.filter { $0.key.range(of: #"^[A-Za-z0-9.\-]{1,80}$"#, options: .regularExpression) != nil }
        return safe.isEmpty ? ["none"] : safe.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
    }

    /// "Dami-2026-11-08-153412.ips": the app's name and a time, nothing else.
    static func safeCrashName(_ name: String) -> String? {
        name.range(of: #"^Dami[A-Za-z0-9_.\-]{0,60}$"#, options: .regularExpression) != nil ? name : nil
    }

    /// Setting names and values are single codes, such as "light" or "systemDefault". Anything else becomes "?".
    static func code(_ value: String) -> String {
        value.range(of: #"^[A-Za-z0-9.\-_]{1,40}$"#, options: .regularExpression) != nil ? value : "?"
    }

    /// Versions and the Mac's description are short phrases: "1.0.0 (4)", "M3 · 16 GB". Anything else becomes "?".
    static func word(_ value: String) -> String {
        value.range(of: #"^[A-Za-z0-9 .,()·+\-_/]{1,60}$"#, options: .regularExpression) != nil ? value : "?"
    }
}
