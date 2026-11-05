import LocalFlowCore
import SwiftUI

/// Chooses how much LocalFlow changes what Whisper wrote. Used in the menu and Settings.
struct CleanupModePicker: View {
    let label: String
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Picker(label, selection: $settings.cleanupMode) {
            Text("Light").tag(CleanupMode.light)
            Text("Raw").tag(CleanupMode.raw)
        }
        .pickerStyle(.segmented)
    }
}

extension CleanupMode {
    var explanation: String {
        switch self {
        case .light: "Removes fillers like \"um\" and \"음\" and repeated words, keeps corrected numbers, and applies your Dictionary."
        case .raw: "Pastes exactly what Whisper wrote: no cleanup and no Dictionary replacements."
        }
    }
}
