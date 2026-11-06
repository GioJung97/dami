import LocalFlowCore
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
        if settings.hasCompletedOnboarding {
            fullMenu
        } else {
            setupPanel
        }
    }

    /// Until setup is finished, only what's left and the two ways out, so nobody takes a half-set-up app for a broken one.
    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LocalFlow").font(.system(size: 13, weight: .bold))
                Text("Setup isn't finished yet").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            Divider().padding(.vertical, 6)

            setupRow("Language", detail: settings.setupStep > SetupStep.language.rawValue ? nil : "To do")
            setupRow("Permissions", detail: controller.permissionsReady ? nil : "To do")
            setupRow("Speech model", detail: setupModelDetail)

            Divider().padding(.vertical, 6)
            Button { open(WindowID.onboarding) } label: {
                Text("Continue setup").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(MenuRowStyle())
            Button { NSApplication.shared.terminate(nil) } label: { row("Quit LocalFlow", shortcut: "⌘Q") }
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
                Text(detail).foregroundStyle(.secondary).monospacedDigit()
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
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
            Divider().padding(.vertical, 4)

            if !controller.permissionsReady {
                Button {
                    open(WindowID.onboarding)
                } label: {
                    Label("Finish setup: permissions needed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(MenuRowStyle())
                Divider().padding(.vertical, 4)
            }

            ForEach(controller.failedDictations) { failed in
                HStack(spacing: 2) {
                    Button { controller.retry(failed) } label: {
                        Label("Failed dictation · Retry", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(MenuRowStyle())
                    .help(failed.message)
                    Button { controller.dismiss(failed) } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(MenuRowStyle())
                    .frame(width: 28)
                    .accessibilityLabel("Dismiss failed dictation")
                }
            }
            if !controller.failedDictations.isEmpty {
                Divider().padding(.vertical, 4)
            }

            if settings.secondLanguage != nil {
                HStack {
                    Text("Language").foregroundStyle(.secondary).font(.system(size: 12))
                    Spacer()
                    Picker("Language", selection: $settings.language) {
                        ForEach(AppSettings.LanguageMode.allCases) { Text(settings.label(for: $0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }

            HStack {
                Text("Cleanup").foregroundStyle(.secondary).font(.system(size: 12))
                Spacer()
                CleanupModePicker(label: "Cleanup")
                    .labelsHidden()
                    .frame(width: 120)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .help(settings.cleanupMode.explanation)

            HStack {
                Text("Microphone").foregroundStyle(.secondary).font(.system(size: 12))
                Spacer()
                MicrophonePicker(label: "Microphone")
                    .labelsHidden()
                    .frame(width: 180)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if !controller.recent.isEmpty {
                Divider().padding(.vertical, 4)
                Text("RECENT · CLICK TO PASTE AGAIN")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
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

            Divider().padding(.vertical, 4)
            Button { open(WindowID.main, section: .home) } label: { row("Open LocalFlow…", shortcut: "⌘O") }
                .buttonStyle(MenuRowStyle())
                .keyboardShortcut("o")
            Button { open(WindowID.main, section: .settings) } label: { row("Settings…", shortcut: "⌘,") }
                .buttonStyle(MenuRowStyle())
                .keyboardShortcut(",")
            Toggle(isOn: $settings.paused) { Text("Pause dictation") }
                .toggleStyle(.checkbox)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            Divider().padding(.vertical, 4)
            Button { NSApplication.shared.terminate(nil) } label: { row("Quit LocalFlow", shortcut: "⌘Q") }
                .buttonStyle(MenuRowStyle())
                .keyboardShortcut("q")
        }
        .padding(6)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LocalFlow").font(.system(size: 13, weight: .bold))
                Text("On-device · nothing leaves this Mac").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(shortStatus).font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .help(controller.statusText)
    }

    private var shortStatus: String {
        switch controller.state {
        case .loadingModel: "Loading"
        case .idle: settings.paused ? "Paused" : (controller.hotkeyActive ? "Ready" : "Setup needed")
        case .recording: "Listening"
        case .transcribing: "Working"
        case .failed: "Error"
        }
    }

    private var statusColor: Color {
        switch controller.state {
        case .idle where !settings.paused && controller.hotkeyActive: .green
        case .recording: .red
        case .failed: .orange
        default: .gray
        }
    }

    private func row(_ title: String, shortcut: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(shortcut).foregroundStyle(.secondary)
        }
    }

    /// History lives only in memory this session. Says so, with the reason on click.
    private func storeWarning(_ reason: String) -> some View {
        Button { showingStoreReason.toggle() } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label("History isn't being saved", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 12, weight: .semibold))
                if showingStoreReason {
                    Text("LocalFlow couldn't open its history database, so dictations from now until it quits won't be kept. Dictation still works. Reason: \(reason)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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

        var body: some View {
            configuration.label
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .foregroundStyle(hovering ? Color.white : Color.primary)
                .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Color.accentColor : .clear))
                .onHover { hovering = $0 }
        }
    }
}
