import Foundation

/// Counts dictations that produced no pasted text, so daily use can show whether speech may have been lost.
/// Holds a reason, a length range and a day only, never any text.
public enum DropStats {
    public enum Reason: String, CaseIterable, Sendable {
        /// Whisper returned nothing, even after its own retry.
        case empty
        /// Only a stock phrase Whisper makes up on silence, such as "Thanks for watching".
        case hallucination
        case silent, promptEcho, onlyFillers, failed
    }

    /// How a retry of a drop ended, to tell whether retrying is worth keeping.
    public enum RetryResult: String, CaseIterable, Sendable {
        case text, stillEmpty, filtered, failed
        /// A filtered stock phrase pasted with "Paste anyway": the filter was wrong that time.
        case pastedAnyway
    }

    /// "empty.1to3s.2026-11-06". Until v0.3.1 keys had no day and empty results counted as hallucination; those stay as they were.
    public static func key(_ reason: Reason, audioSeconds: Double, on date: Date, timeZone: TimeZone = .current) -> String {
        let range = switch audioSeconds {
        case ..<1: "under1s"
        case ..<3: "1to3s"
        case ..<10: "3to10s"
        default: "over10s"
        }
        return "\(reason.rawValue).\(range).\(HealthStats.day(date, timeZone: timeZone))"
    }

    public static func retryKey(_ result: RetryResult, on date: Date, timeZone: TimeZone = .current) -> String {
        "retry.\(result.rawValue).\(HealthStats.day(date, timeZone: timeZone))"
    }

    public static func adding(_ key: String, to counts: [String: Int]) -> [String: Int] {
        var counts = counts
        counts[key, default: 0] += 1
        return counts
    }
}

/// Trying a dropped dictation again in a way that can give a different result (v0.3.1 M4).
public enum DropRetry {
    /// Shorter drops are rarely speech, and a retry offer there would mostly follow stray presses.
    public static let minimumSeconds = 1.0

    /// The other of the two languages: a wrong detection is the likeliest reason a short clip came back empty. Without a second
    /// language, English again.
    public static func language(after detected: String, second: String?) -> String {
        guard let second, second != "en" else { return "en" }
        return detected == "en" ? second : "en"
    }
}
