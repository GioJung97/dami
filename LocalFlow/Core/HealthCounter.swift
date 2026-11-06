import Foundation
import LocalFlowCore

/// Numbers only, read with `scripts/health-check.sh`. See `HealthStats`.
enum HealthCounter {
    private static let queue = DispatchQueue(label: "com.localflow.app.health")

    /// Callable from any thread, including the event tap's, which must not wait.
    static func count(_ event: HealthStats.Event) {
        let date = Date()
        queue.async {
            let defaults = UserDefaults.standard
            let counts = defaults.dictionary(forKey: "healthCounts") as? [String: Int] ?? [:]
            defaults.set(HealthStats.adding(event, on: date, to: counts), forKey: "healthCounts")
        }
    }
}
