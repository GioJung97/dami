import Foundation

/// Counts failures the user may never see, by kind and day. The system log only reaches back so far, so these outlast it.
/// Holds a kind and a date only, never any text or key identity.
public enum HealthStats {
    public enum Event: String, CaseIterable, Sendable {
        case databaseUnavailable, historySaveFailed, tapTimedOut, tapDisabledByInput, micLost, recordingFailed, modelUnavailable
        /// Bluetooth mics (v1.0 M3): how often they're used, needed a restart before audio came, or gave none at all. Not failures
        /// in themselves, but kept here so a tester's file shows how much Bluetooth matters.
        case bluetoothMicStarted, bluetoothMicRestarted, bluetoothMicFailed
    }

    public static func key(_ event: Event, on date: Date, timeZone: TimeZone = .current) -> String {
        "\(event.rawValue).\(day(date, timeZone: timeZone))"
    }

    /// "2026-11-06", in the given time zone.
    public static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    public static func adding(_ event: Event, on date: Date, timeZone: TimeZone = .current, to counts: [String: Int]) -> [String: Int] {
        var counts = counts
        counts[key(event, on: date, timeZone: timeZone), default: 0] += 1
        return counts
    }
}
