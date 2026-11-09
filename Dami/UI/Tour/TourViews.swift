import SwiftUI

// MARK: The tour you do (B)

/// The tour window: a real dictation into its own text box, then finding Dami in the menu bar.
struct TourLiveView: View {
    @ObservedObject private var tour = TourController.shared
    @ObservedObject private var spotlight = TourController.shared.spotlight
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var practice = ""
    @FocusState private var boxFocused: Bool

    var body: some View {
        let step = tour.step ?? .hold
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Quick tour · \(step.stop) of \(TourController.Step.stops)")
                        .font(Theme.Font.keyLabelSmall)
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.ink2)
                    Spacer()
                    Button("Skip tour") { tour.end() }
                        .buttonStyle(.plain)
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.ink2)
                }
                Text(title(step)).font(Theme.Font.stepTitle)
                Text(message(step))
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if step == .menu {
                    menuHelp
                } else {
                    dictationArea(step)
                }
                Spacer(minLength: 0)
            }
            .padding(26)
            Rule()
            HStack(spacing: 10) {
                Spacer()
                if step != .hold {
                    Button("Back") { tour.back() }
                        .buttonStyle(KeyButtonStyle(kind: .secondary, height: 28))
                }
                Button(step.rawValue < TourController.Step.pasted.rawValue ? "Skip this step" : "Next") { tour.next() }
                    .buttonStyle(KeyButtonStyle(kind: step.rawValue < TourController.Step.pasted.rawValue ? .secondary : .primary, height: 28))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 520, height: 420)
        .foregroundStyle(Theme.ink)
        .background(Theme.paper)
        .environment(\.palette, settings.keyColor.palette)
        .environment(\.appTheme, settings.theme)
        .tint(settings.keyColor.palette.key)
        .onAppear {
            boxFocused = true
            centerWindow()
        }
        .onChange(of: tour.step) { _, newStep in
            if newStep == nil || newStep?.isInWindow == true { dismissWindow(id: WindowID.liveTour) }
            if newStep == .hold { boxFocused = true }
        }
    }

    /// Opens in the middle of the screen each time, not wherever it was last left.
    private func centerWindow() {
        DispatchQueue.main.async {
            NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(WindowID.liveTour) == true }?.center()
        }
    }

    private func title(_ step: TourController.Step) -> String {
        switch step {
        case .hold: "Hold the keys"
        case .speak: "Now say something"
        case .writing: "Let go… writing it down"
        case .pasted: "It's in"
        default: "Find Dami in the menu bar"
        }
    }

    private func message(_ step: TourController.Step) -> String {
        switch step {
        case .hold:
            switch tour.retry {
            case .tooShort: "That was a quick tap, so nothing was recorded. Click in the box and hold the keys a little longer."
            case .nothingHeard: "Nothing was recognized. Hold the keys, say a whole sentence, then let go."
            case nil: "Click in the box below, then press and keep holding these keys:"
            }
        case .speak:
            "Keep holding and say a sentence, like “Let's meet on Thursday.” The small note at the \(hudSide) of your screen shows Dami is listening. Let go when you're done."
        case .writing:
            "Dami is turning what you said into text. The note shows three dots while it works."
        case .pasted:
            "The text went where your cursor was: here, in the box. The check on the note means it was sent. Hold the keys the same way in any app."
        default:
            spotlight.iconVisible
                ? "Click the speech bubble that's lit up at the top of your screen. Recent lists your last dictations: click one to paste it again where your cursor is."
                : "Dami's speech bubble isn't showing right now: the menu bar may be too full on this screen. Quit an app with many menus, or use a wider screen, then look again at the top right."
        }
    }

    private var hudSide: String { settings.hudPosition == .bottomCenter ? "bottom" : "top" }

    private func dictationArea(_ step: TourController.Step) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                KeycapRow(keys: settings.shortcut.keycaps, size: 15)
                    .opacity(step == .hold || step == .speak ? 1 : 0.5)
                if step == .speak {
                    Label("Listening", systemImage: settings.hudPosition == .bottomCenter ? "arrow.down" : "arrow.up")
                        .font(Theme.Font.keyLabelSmall)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.ink2)
                }
            }
            TextEditor(text: $practice)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .frame(height: 64)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.keyFace))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(settings.keyColor.palette.key, lineWidth: 2))
                .focused($boxFocused)
                .accessibilityLabel("Practice box: your words appear here")
        }
    }

    private var menuHelp: some View {
        HStack(spacing: 14) {
            HStack(spacing: 14) {
                Image("glyph-ready").renderingMode(.template)
                Text("9:41").font(Theme.Font.callout)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.keyFace))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.keyEdge))
            .accessibilityHidden(true)
            if tour.menuFound {
                Text("Found it").font(Theme.Font.callout.weight(.semibold)).highlighted()
            }
        }
    }
}

/// The note shown in the main window, under the section key it's about (or centred at the end).
struct TourWindowNote: View {
    @ObservedObject var tour: TourController

    var body: some View {
        if let step = tour.step, step.isInWindow {
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick tour · \(step.stop) of \(TourController.Step.stops)")
                    .font(Theme.Font.keyLabelSmall)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.ink2)
                Text(title(step)).font(Theme.Font.sectionTitle)
                Text(message(step))
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if step != .done {
                        Button("Skip tour") { tour.end() }
                            .buttonStyle(.plain)
                            .font(Theme.Font.footnote)
                            .foregroundStyle(Theme.ink2)
                    }
                    Spacer()
                    if step != .done {
                        Button("Back") { tour.back() }
                            .buttonStyle(KeyButtonStyle(kind: .secondary, height: 24))
                    }
                    Button(step == .done ? "Done" : "Next") { tour.next() }
                        .buttonStyle(KeyButtonStyle(kind: .primary, height: 24))
                }
                .padding(.top, 2)
            }
            .padding(14)
            .frame(width: 310, alignment: .leading)
            .foregroundStyle(Theme.ink)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.slip))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.slipEdge))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .accessibilityElement(children: .contain)
        }
    }

    private func title(_ step: TourController.Step) -> String {
        switch step {
        case .history: "History"
        case .dictionary: "Dictionary"
        case .settings: "Settings"
        default: "That's the tour"
        }
    }

    private func message(_ step: TourController.Step) -> String {
        switch step {
        case .history: "Every dictation is kept here. Select one to copy it, fix a word, or add a name to your Dictionary."
        case .dictionary: "Names and terms Dami should always spell your way. Suggestions from your fixes wait here too."
        case .settings: "Change the shortcut, your languages, and how Dami looks."
        default: "Dami stays in the menu bar. Hold the keys in any app to dictate. You can take this tour again in Settings › General."
        }
    }
}
