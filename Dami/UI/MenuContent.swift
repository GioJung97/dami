import DamiCore
import SwiftUI

/// The panel that drops down from the menu bar icon.
struct MenuContent: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var store = Store.shared
    @State private var showingStoreReason = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if settings.hasCompletedOnboarding {
                fullMenu
            } else {
                setupPanel
            }
        }
        .foregroundStyle(Theme.ink)
        .font(Theme.Font.callout)
        .background(Theme.paper)
        .environment(\.palette, settings.keyColor.palette)
        .environment(\.appTheme, settings.theme)
        .onAppear { TourController.shared.menuOpened() }
    }

    /// Until setup is finished, only what's left and the two ways out, so nobody takes a half-set-up app for a broken one.
    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dami").font(Theme.Font.menuWordmark)
                Text("Setup isn't finished yet").font(Theme.Font.caption).foregroundStyle(Theme.ink2)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            menuRule

            setupRow("Language", detail: settings.setupStep > SetupStep.language.rawValue ? nil : "To do")
            setupRow("Permissions", detail: controller.permissionsReady ? nil : "To do")
            setupRow("Speech model", detail: setupModelDetail)

            menuRule
            Button { open(WindowID.onboarding) } label: {
                Text("Continue setup").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(MenuRowStyle())
            Button { NSApplication.shared.terminate(nil) } label: { row("Quit Dami", shortcut: "⌘Q") }
                .buttonStyle(MenuRowStyle())
                .keyboardShortcut("q")
        }
        .padding(6)
        .frame(width: 300)
    }

    /// Nil means done.
    private var setupModelDetail: String? {
        switch controller.modelStatus {
        case .downloading(let progress): "\(Int(progress * 100))%"
        case .loading: "Preparing…"
        case .ready: nil
        case .failed: "Needs attention"
        }
    }

    private func setupRow(_ name: String, detail: String?) -> some View {
        HStack {
            Text(name)
            Spacer()
            if let detail {
                Text(detail).foregroundStyle(Theme.ink2).monospacedDigit()
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .highlighted()
                    .accessibilityLabel("Done")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var fullMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let reason = store.unavailableReason {
                storeWarning(reason)
            }
            menuRule

            if !controller.permissionsReady {
                Button {
                    open(WindowID.onboarding)
                } label: {
                    Label("Finish setup: permissions needed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.danger)
                        .font(Theme.Font.callout.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(MenuRowStyle())
                menuRule
            }

            ForEach(controller.failedDictations) { failed in
                HStack(spacing: 2) {
                    Button { controller.retry(failed) } label: {
                        Group {
                            switch failed.kind {
                            case .failed: Label("Failed dictation · Retry", systemImage: "arrow.clockwise")
                            case .empty: Label("No speech recognized · Retry", systemImage: "arrow.clockwise")
                            case .filtered: Label("\(failed.message) · Paste anyway", systemImage: "text.insert")
                            }
                        }
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(MenuRowStyle())
                    .help(failed.message)
                    Button { controller.dismiss(failed) } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.ink2)
                    }
                    .buttonStyle(MenuRowStyle())
                    .frame(width: 28)
                    .accessibilityLabel("Dismiss")
                }
            }
            if !controller.failedDictations.isEmpty {
                menuRule
            }

            if settings.secondLanguage != nil {
                HStack {
                    Text("Language").foregroundStyle(Theme.ink2).font(Theme.Font.footnote)
                    Spacer()
                    TabKeys(
                        label: "Language",
                        options: AppSettings.LanguageMode.allCases.map { ($0, settings.label(for: $0)) },
                        selection: $settings.language,
                        width: 44
                    )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }

            HStack {
                Text("Cleanup").foregroundStyle(Theme.ink2).font(Theme.Font.footnote)
                Spacer()
                TabKeys(
                    label: "Cleanup",
                    options: [(CleanupMode.light, "Light"), (CleanupMode.raw, "Raw")],
                    selection: $settings.cleanupMode,
                    width: 54
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .help(settings.cleanupMode.explanation)

            HStack {
                Text("Microphone").foregroundStyle(Theme.ink2).font(Theme.Font.footnote)
                Spacer()
                MicrophonePicker(label: "Microphone")
                    .labelsHidden()
                    .frame(width: 180)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if !controller.recent.isEmpty {
                menuRule
                Text("Recent · click to paste again")
                    .font(Theme.Font.label)
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                ForEach(controller.recent) { item in
                    RecentRow(dictation: item.dictation) {
                        dismiss()
                        controller.pasteAgain(item.dictation)
                    } fix: {
                        guard let id = item.dictation.id else { return }
                        dismiss()
                        Navigation.shared.openHistory(fixing: id)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }

            menuRule
            Button { open(WindowID.main, section: .home) } label: { row("Open Dami…", shortcut: "⌘O") }
                .buttonStyle(MenuRowStyle())
                .keyboardShortcut("o")
            Button { open(WindowID.main, section: .settings) } label: { row("Settings…", shortcut: "⌘,") }
                .buttonStyle(MenuRowStyle())
                .keyboardShortcut(",")
            Toggle(isOn: $settings.paused) { Text("Pause dictation") }
                .toggleStyle(InkCheckboxStyle())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            menuRule
            Button { NSApplication.shared.terminate(nil) } label: { row("Quit Dami", shortcut: "⌘Q") }
                .buttonStyle(MenuRowStyle())
                .keyboardShortcut("q")
        }
        .padding(6)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dami").font(Theme.Font.menuWordmark)
                Text("On-device · nothing leaves this Mac").font(Theme.Font.caption).foregroundStyle(Theme.ink2)
            }
            Spacer()
            StatusBadge(controller: controller)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .help(controller.statusText)
    }

    private func row(_ title: String, shortcut: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Keycap(label: shortcut, size: 10)
        }
    }

    private var menuRule: some View {
        Rule().padding(.horizontal, 4).padding(.vertical, 5)
    }

    /// History lives only in memory this session. Says so, with the reason on click.
    private func storeWarning(_ reason: String) -> some View {
        Button { showingStoreReason.toggle() } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label("History isn't being saved", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
                    .font(Theme.Font.footnote.weight(.semibold))
                if showingStoreReason {
                    Text("Dami couldn't open its history database, so dictations from now until it quits won't be kept. Dictation still works. Reason: \(reason)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MenuRowStyle())
    }

    private func open(_ id: String, section: Navigation.Section? = nil) {
        if let section { Navigation.shared.section = section }
        dismiss()
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// One Recent dictation: click to paste it again, or the pencil to fix it in History.
private struct RecentRow: View {
    let dictation: Dictation
    let paste: () -> Void
    let fix: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: paste) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dictation.displayText).lineLimit(1).truncationMode(.tail)
                    Text("\(dictation.appName ?? "Unknown app") · \(dictation.createdAt.formatted(date: .omitted, time: .shortened))")
                        .font(Theme.Font.monoSmall)
                        .opacity(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, hovering ? 26 : 0)
            }
            .buttonStyle(MenuRowStyle())
            if hovering {
                Button(action: fix) {
                    Image(systemName: "pencil")
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Fix in History")
                .padding(.trailing, 8)
            }
        }
        .onHover { hovering = $0 }
    }
}

/// A full-width row that highlights on hover, like a native menu item.
struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRow(configuration: configuration)
    }

    private struct MenuRow: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.palette) private var palette

        var body: some View {
            configuration.label
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .foregroundStyle(hovering ? AnyShapeStyle(Theme.onHighlight) : AnyShapeStyle(Theme.ink))
                .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? palette.highlight : .clear))
                .onHover { hovering = $0 }
        }
    }
}
