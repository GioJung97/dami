import LocalFlowCore
import SwiftUI

/// First-launch setup: welcome → languages → permissions → model → try it → done.
struct OnboardingView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var step: Step
    @State private var practiceText = ""
    /// Setup is done and a permission was taken away: only ask for that again.
    private let repairingPermissions: Bool

    enum Step: Int, CaseIterable {
        case welcome, language, permissions, model, practice, done
    }

    init(controller: DictationController) {
        self.controller = controller
        let repairing = AppSettings.shared.hasCompletedOnboarding && !Permissions.shared.allGranted
        repairingPermissions = repairing
        _step = State(initialValue: repairing ? .permissions : .welcome)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcome
                case .language: languageStep
                case .permissions: permissionsStep
                case .model: model
                case .practice: practice
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 48)
            .padding(.top, 40)

            if !repairingPermissions { footer }
        }
        .frame(width: 640, height: 480)
        .navigationTitle(repairingPermissions ? "LocalFlow Permissions" : "Welcome to LocalFlow")
        .onChange(of: permissions.allGranted) { _, granted in
            if repairingPermissions && granted { dismissWindow(id: WindowID.onboarding) }
        }
    }

    @ViewBuilder private var footer: some View {
        Divider()
        HStack {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { item in
                    Circle()
                        .fill(item == step ? Color.accentColor : Color(nsColor: .separatorColor))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
            Spacer()
            if step != .welcome && step != .done {
                Button("Back") { move(-1) }
            }
            Button(nextTitle) { next() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.accentColor))
            Text("Welcome to LocalFlow").font(.system(size: 28, weight: .bold))
            Text("Speak in English, another language, or both. Your words appear wherever you're typing. Everything runs on this Mac, so your voice never leaves it.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .padding(.top, 20)
    }

    private var languageStep: some View {
        LanguageSentencePicker()
            .padding(.top, 36)
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if repairingPermissions {
                title("Permission needed", "LocalFlow can't work without these. This window closes once they're all allowed.")
            } else {
                title("Three permissions", "macOS asks you to allow each one. This window updates on its own.")
            }
            VStack(spacing: 0) {
                permissionRow("Microphone", "To hear you while you hold the shortcut.", permissions.microphone) {
                    permissions.requestMicrophone()
                }
                Divider()
                permissionRow("Input Monitoring", "To notice the shortcut in any app.", permissions.inputMonitoring) {
                    permissions.requestInputMonitoring()
                }
                Divider()
                permissionRow("Accessibility", "To paste the text where your cursor is.", permissions.accessibility) {
                    permissions.requestAccessibility()
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
            if permissions.inputMonitoring && !controller.hotkeyActive {
                Text("If the shortcut doesn't work after allowing Input Monitoring, quit and reopen LocalFlow.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func permissionRow(_ name: String, _ why: String, _ granted: Bool, request: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 14, weight: .semibold))
                Text(why).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 13, weight: .semibold))
            } else {
                Button("Allow…", action: request).buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
    }

    private var model: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Getting the speech model", "A one-time download. After this, LocalFlow works without internet.")
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(Transcriber.modelDisplayName).fontWeight(.semibold)
                    Spacer()
                    Text(modelStatus).foregroundStyle(.secondary).monospacedDigit()
                }
                if case .failed(let problem) = controller.modelStatus {
                    HStack {
                        Text(problem.advice)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(problem.actionTitle) { controller.retryModel() }
                    }
                } else {
                    ProgressView(value: modelProgress)
                    Text("This Mac: \(MemoryInfo.macDescription)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
        }
    }

    private var practice: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Try it once", "Click the box, hold the keys, say the sentence, then let go.")
            HStack {
                Spacer()
                KeycapRow(keys: settings.shortcut.keycaps, size: 15)
                Spacer()
            }
            Text("\"\((settings.secondLanguage ?? .english).practiceSentence)\"")
                .font(.system(size: 15))
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            TextEditor(text: $practiceText)
                .font(.system(size: 15))
                .frame(height: 60)
                .padding(6)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2))
                .accessibilityLabel("Your words appear here")
        }
    }

    private var done: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("You're all set").font(.system(size: 26, weight: .bold))
            Text("LocalFlow lives in the menu bar. Hold \(settings.shortcut.displayName) in any app to dictate. Change the shortcut any time in Settings.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Toggle("Open LocalFlow at login", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
                .toggleStyle(.checkbox)
        }
        .padding(.top, 20)
    }

    private func title(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 24, weight: .bold))
            Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
        }
    }

    // MARK: Navigation

    private var modelProgress: Double {
        if case .downloading(let progress) = controller.modelStatus { return progress }
        return 1
    }

    private var modelStatus: String {
        switch controller.modelStatus {
        case .downloading(let progress): "\(Int(progress * Double(Transcriber.modelSizeMB))) of \(Transcriber.modelSizeMB) MB"
        case .loading: "Preparing…"
        case .ready: "Ready"
        case .failed(let problem): problem.message
        }
    }

    private var canContinue: Bool {
        switch step {
        case .permissions: permissions.allGranted
        case .model: controller.isModelReady
        default: true
        }
    }

    private var nextTitle: String {
        switch step {
        case .welcome: "Get started"
        case .practice: practiceText.isEmpty ? "Skip" : "Continue"
        case .done: "Start using LocalFlow"
        default: "Continue"
        }
    }

    private func next() {
        if step == .done {
            settings.hasCompletedOnboarding = true
            dismissWindow(id: WindowID.onboarding)
            return
        }
        move(1)
    }

    private func move(_ delta: Int) {
        step = Step(rawValue: step.rawValue + delta) ?? step
    }
}
