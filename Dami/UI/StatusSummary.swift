import SwiftUI

/// The one-word status and its dot, shared by the menu panel and the main window's top bar.
extension DictationController {
    func shortStatus(paused: Bool) -> String {
        switch state {
        case .loadingModel: "Loading"
        case .idle: paused ? "Paused" : (hotkeyActive ? "Ready" : "Setup needed")
        case .recording: "Listening"
        case .transcribing: "Working"
        case .failed: "Error"
        }
    }

    func statusKind(paused: Bool) -> StatusDot.Kind {
        switch state {
        case .idle where !paused && hotkeyActive: .ready
        case .recording: .listening
        case .failed: .error
        default: .idle
        }
    }
}

/// Dot + uppercase word, with the full status text on hover.
struct StatusBadge: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 4) {
            StatusDot(kind: controller.statusKind(paused: settings.paused))
            Text(controller.shortStatus(paused: settings.paused))
                .font(Theme.Font.keyLabelSmall)
                .tracking(0.6)
                .textCase(.uppercase)
        }
        .help(controller.statusText)
        .accessibilityElement(children: .combine)
    }
}
