import Foundation

/// Counts dictations that produced no pasted text, so a week of use can show whether speech may have been lost.
/// Holds a reason and a length range only, never any text.
public enum DropStats {
    public enum Reason: String, CaseIterable, Sendable {
        case silent, hallucination, promptEcho, onlyFillers, failed
    }

    public static func key(_ reason: Reason, audioSeconds: Double) -> String {
        let range = switch audioSeconds {
        case ..<1: "under1s"
        case ..<3: "1to3s"
        case ..<10: "3to10s"
        default: "over10s"
        }
        return "\(reason.rawValue).\(range)"
    }

    public static func adding(_ reason: Reason, audioSeconds: Double, to counts: [String: Int]) -> [String: Int] {
        var counts = counts
        counts[key(reason, audioSeconds: audioSeconds), default: 0] += 1
        return counts
    }
}
