import DamiCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var navigation = Navigation.shared
    @State private var tab = Tab.shortcut

    enum Tab: String, CaseIterable, Identifiable {
        case general = "General", shortcut = "Shortcut", language = "Language", models = "Models"
        case privacy = "Privacy", sync = "Sync"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Settings")
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Tab.allCases) { item in
                        Button {
                            tab = item
                        } label: {
                            Text(item.rawValue)
                                .fontWeight(tab == item ? .semibold : .regular)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(RoundedRectangle(cornerRadius: 6).fill(tab == item ? Color.accentColor.opacity(0.15) : .clear))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 150)

                Form {
                    switch tab {
                    case .general: general
                    case .shortcut: shortcut
                    case .language: language
                    case .models: ModelsSection(controller: controller)
                    case .privacy: PrivacySection()
                    case .sync: sync
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: showRequestedTab)
        .onChange(of: navigation.requestedSettingsTab) { showRequestedTab() }
    }

    private func showRequestedTab() {
        guard let requested = navigation.requestedSettingsTab.flatMap(Tab.init(rawValue:)) else { return }
        tab = requested
        navigation.requestedSettingsTab = nil
    }

    @ViewBuilder private var general: some View {
        Section {
            Toggle("Open at login", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
            MicrophonePicker(label: "Microphone")
            VStack(alignment: .leading, spacing: 6) {
                CleanupModePicker(label: "Cleanup")
                Text(settings.cleanupMode.explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Toggle("Play sounds when recording starts and stops", isOn: $settings.playSounds)
            Picker("Recording indicator position", selection: $settings.hudPosition) {
                ForEach(AppSettings.HUDPosition.allCases) { Text($0.label).tag($0) }
            }
        }
    }

    @ViewBuilder private var shortcut: some View {
        Section("Dictation shortcut") {
            ShortcutRecorder(controller: controller)
        }
        Section("How the shortcut works") {
            Picker("Mode", selection: $settings.shortcutMode) {
                Text("Hold to talk").tag(AppSettings.ShortcutMode.hold)
                Text("Hold, or double-tap for hands-free").tag(AppSettings.ShortcutMode.holdOrDoubleTap)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Text(settings.shortcutMode == .hold
                 ? "Record while held, paste when you let go."
                 : "Hold to talk as usual. Double-tap to keep recording without holding; tap once more to stop.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Press Esc while recording to cancel.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var language: some View {
        Section("Your languages") {
            SecondLanguagePicker()
        }
        if let second = settings.secondLanguage {
            Section("Listen for") {
                Picker("Listen for", selection: $settings.language) {
                    Text("Automatic (English + \(second.name))").tag(AppSettings.LanguageMode.auto)
                    Text("English only").tag(AppSettings.LanguageMode.english)
                    Text("\(second.name) only").tag(AppSettings.LanguageMode.second)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text("Automatic detects each dictation, and mixed sentences work.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(isOn: $settings.keepEnglishTerms) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep English words in English")
                        Text("Words like \"meeting\" or \"API\" stay in English inside \(second.name) sentences.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var sync: some View {
        Section {
            LabeledContent("Sync across your Macs") {
                Text("Coming later").foregroundStyle(.orange)
            }
            Text("Share your Dictionary, Replacements and Settings with Dami on your other Macs. History and audio stay on each Mac.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shortcut recorder

/// Shows the current shortcut and lets the user record a new one by pressing it.
/// Accepts modifier-only combos (released after pressing, e.g. Right ⌘ + Right ⌥) or a key with
/// modifiers (e.g. ⌃ Space). Esc cancels.
private struct ShortcutRecorder: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var settings = AppSettings.shared
    @State private var recording = false
    @State private var peak: Shortcut.Modifiers = []
    @State private var held: Shortcut.Modifiers = []
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Group {
                    if recording {
                        Text(held.isEmpty ? "Press the keys…" : Shortcut(modifiers: held, keyCode: nil).displayName)
                            .foregroundStyle(.secondary)
                    } else {
                        KeycapRow(keys: settings.shortcut.keycaps)
                    }
                }
                .frame(minWidth: 200, minHeight: 32, alignment: .leading)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(recording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: recording ? 2 : 1))

                if recording {
                    Button("Cancel") { stop() }
                } else {
                    Button("Record new shortcut…") { start() }
                    if settings.shortcut != .defaultDictation {
                        Button("Reset") { settings.shortcut = .defaultDictation }
                    }
                }
            }
            Text(message ?? "Press any key combination, or hold modifier keys and let go. Left and right modifier keys are told apart.")
                .font(.system(size: 12))
                .foregroundStyle(message == nil ? Color.secondary : Color.orange)
        }
        .onDisappear { stop() }
    }

    private func start() {
        message = nil
        peak = []
        held = []
        recording = true
        controller.suspendHotkey(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        controller.suspendHotkey(false)
    }

    private func handle(_ event: NSEvent) {
        let current = Shortcut.Modifiers(eventFlags: UInt64(event.modifierFlags.rawValue))
        switch event.type {
        case .flagsChanged:
            held = current
            peak.formUnion(current)
            if current.isEmpty && !peak.isEmpty {
                save(Shortcut(modifiers: peak, keyCode: nil))
            }
        case .keyDown:
            if event.keyCode == 53 && current.isEmpty && peak.isEmpty {
                stop()
                return
            }
            save(Shortcut(modifiers: current, keyCode: event.keyCode))
        default:
            break
        }
    }

    private func save(_ shortcut: Shortcut) {
        if shortcut.isUnsafe {
            message = "\(shortcut.displayName) would fire while typing. Add ⌃, ⌥ or ⌘, or use an F-key."
            peak = []
            held = []
            return
        }
        settings.shortcut = shortcut
        let leftOnly: Shortcut.Modifiers = [.leftCommand, .leftOption, .leftControl, .leftShift]
        if shortcut.isModifierOnly && shortcut.modifiers.isSubset(of: leftOnly) && shortcut.modifiers.rawValue.nonzeroBitCount == 1 {
            message = "Saved. Tip: a single left-side modifier is used by many shortcuts; right-side keys clash less."
        }
        stop()
    }
}

// MARK: - Models

private struct ModelsSection: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var store = Store.shared

    var body: some View {
        Section("Speech model") {
            LabeledContent(Transcriber.modelDisplayName) {
                Text(modelStatus).foregroundStyle(controller.isModelReady ? .green : .secondary)
            }
            if case .failed(let problem) = controller.modelStatus {
                HStack {
                    Text(problem.message).foregroundStyle(.orange)
                    Spacer()
                    Button(problem.actionTitle) { controller.retryModel() }
                }
            }
            LabeledContent("Size", value: "\(Transcriber.modelSizeMB) MB")
            LabeledContent("Dami memory in use", value: MemoryInfo.footprintText)
            LabeledContent("Typical speed", value: typicalSpeed)
            LabeledContent("This Mac", value: MemoryInfo.macDescription)
        }
        Section("Cleanup model") {
            LabeledContent("Rewrites sentences") {
                Text("Not installed").foregroundStyle(.secondary)
            }
            Text("Comes with Smart mode in a later update. It will load only while you dictate. Light mode doesn't need it.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var modelStatus: String {
        switch controller.modelStatus {
        case .downloading(let progress): "Downloading \(Int(progress * 100))%"
        case .loading: "Loading…"
        case .ready: "Installed"
        case .failed: "Not available"
        }
    }

    private var typicalSpeed: String {
        let recent = store.dictations.prefix(20)
        guard !recent.isEmpty else { return "–" }
        let average = recent.reduce(0) { $0 + $1.latencySeconds } / Double(recent.count)
        return String(format: "%.1f s per dictation", average)
    }
}

enum MemoryInfo {
    /// The same "Memory" number Activity Monitor shows for this app.
    static var footprintText: String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return "–" }
        return ByteCountFormatter.string(fromByteCount: Int64(info.phys_footprint), countStyle: .memory)
    }

    static var macDescription: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var chip = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &chip, &size, nil, 0)
        let name = String(cString: chip).replacingOccurrences(of: "Apple ", with: "")
        let gigabytes = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
        return "\(name) · \(gigabytes) GB"
    }
}

// MARK: - Privacy

private struct PrivacySection: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var confirmingDelete = false
    @State private var audioBytes: Int64 = 0

    private func prune() {
        Store.shared.prune(retentionDays: settings.retentionDays, audioRetentionDays: settings.audioRetentionDays)
        audioBytes = Store.shared.audioBytesUsed()
    }

    var body: some View {
        Section {
            Label("Everything runs on this Mac. Your voice and text are never uploaded.", systemImage: "lock.fill")
                .foregroundStyle(.blue)
            Text("Text history is stored unencrypted on this Mac until you delete it. Audio is only saved if you turn that on below.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        Section {
            Picker("Keep history for", selection: $settings.retentionDays) {
                ForEach(AppSettings.retentionChoices, id: \.days) { Text($0.label).tag($0.days) }
            }
            .onChange(of: settings.retentionDays) { prune() }
            Toggle(isOn: $settings.saveAudio) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save audio recordings")
                    Text("Off by default. Lets Dami learn your voice later. About 2 MB per minute.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(settings.retentionDays < 0)
            if settings.saveAudio {
                Picker("Keep recordings for", selection: $settings.audioRetentionDays) {
                    ForEach(AppSettings.audioRetentionChoices, id: \.self) { Text("\($0) days").tag($0) }
                }
                .onChange(of: settings.audioRetentionDays) { prune() }
            }
            Toggle(isOn: $settings.learnFromFixes) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Learn from fixes you make after pasting")
                    Text("For up to 2 minutes after a paste, Dami notices if you fix that text where you pasted it, and saves the fix in History. Only the pasted text is kept, never what's around it.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(settings.retentionDays < 0)
            .onChange(of: settings.learnFromFixes) { if !settings.learnFromFixes { PasteWatcher.shared.finish(.off) } }
            if settings.saveAudio || audioBytes > 0 {
                LabeledContent("Space used by recordings", value: ByteCountFormatter.string(fromByteCount: audioBytes, countStyle: .file))
            }
        }
        Section {
            Button("Delete all history…", role: .destructive) { confirmingDelete = true }
                .confirmationDialog("Delete all history and saved audio?", isPresented: $confirmingDelete) {
                    Button("Delete all", role: .destructive) { Store.shared.deleteAllHistory() }
                } message: {
                    Text("This deletes every dictation, saved recording and fix, and the copy kept from the last update. Your Dictionary is kept. This can't be undone.")
                }
        }
        .onAppear { audioBytes = Store.shared.audioBytesUsed() }
        .onChange(of: settings.saveAudio) { audioBytes = Store.shared.audioBytesUsed() }
    }
}
