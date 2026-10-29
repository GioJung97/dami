import SwiftUI

/// The panel that drops down from the menu bar icon.
struct MenuContent: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var permissions = Permissions.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 4)

            if !permissions.allGranted {
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

            HStack {
                Text("Language").foregroundStyle(.secondary).font(.system(size: 12))
                Spacer()
                Picker("Language", selection: $settings.language) {
                    ForEach(AppSettings.LanguageMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
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
                ForEach(controller.recent) { dictation in
                    Button {
                        dismiss()
                        controller.pasteAgain(dictation)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dictation.finalText).lineLimit(1).truncationMode(.tail)
                            Text("\(dictation.appName ?? "Unknown app") · \(dictation.createdAt.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(MenuRowStyle())
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

    private func open(_ id: String, section: Navigation.Section? = nil) {
        if let section { Navigation.shared.section = section }
        dismiss()
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
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
