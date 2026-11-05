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
    /// Rows where Allow was pressed. If one still isn't allowed, the app may need to reopen to see it.
    @State private var requested: Set<PermissionKind> = []
    /// The hotkey still hasn't started some seconds after Microphone and Accessibility were allowed.
    @State private var hotkeyIsStuck = false
    /// Setup is done and a permission was taken away: only ask for that again.
    private let repairingPermissions: Bool

    typealias Step = SetupStep

    private static let hotkeyGraceSeconds = 5

    private enum PermissionKind {
        case microphone, inputMonitoring, accessibility
    }

    init(controller: DictationController) {
        self.controller = controller
        let repairing = AppSettings.shared.hasCompletedOnboarding && !controller.permissionsReady
        repairingPermissions = repairing
        _step = State(initialValue: repairing ? .permissions : SetupStep.resume(
            saved: AppSettings.shared.setupStep,
            permissionsGranted: controller.permissionsReady,
            modelReady: controller.isModelReady
        ))
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
        .onChange(of: controller.permissionsReady) { _, ready in
            if repairingPermissions && ready { dismissWindow(id: WindowID.onboarding) }
        }
        .task(id: permissions.coreGranted && !controller.hotkeyActive) {
            hotkeyIsStuck = false
            guard permissions.coreGranted && !controller.hotkeyActive else { return }
            // The hotkey retries every 2 s and permissions refresh every 2 s, so give both a turn before asking for more.
            try? await Task.sleep(for: .seconds(Self.hotkeyGraceSeconds))
            if !Task.isCancelled { hotkeyIsStuck = true }
        }
        .onAppear(perform: saveStep)
        .onChange(of: step) { _, _ in saveStep() }
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
                title("Permissions", "Allow each one. macOS may offer Later or Quit & Reopen: choose Later, and setup continues here.")
            }
            VStack(spacing: 0) {
                permissionRow(.microphone, "Microphone", "To hear you while you hold the shortcut.", permissions.microphone) {
                    permissions.requestMicrophone()
                }
                Divider()
                permissionRow(.accessibility, "Accessibility", "To notice the shortcut, and paste where your cursor is.", permissions.accessibility) {
                    permissions.requestAccessibility()
                }
                if hotkeyIsStuck {
                    Divider()
                    permissionRow(.inputMonitoring, "Input Monitoring", "This Mac also needs this one, to notice the shortcut in any app.", false) {
                        permissions.requestInputMonitoring()
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
            if mayNeedReopen {
                HStack(spacing: 12) {
                    Text(reopenAdvice)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit & Reopen") { permissions.quitAndReopen() }
                }
            }
        }
    }

    private var reopenAdvice: String {
        hotkeyIsStuck
            ? "After allowing Input Monitoring, reopen LocalFlow so it can see it."
            : "Allowed it, but it still says Allow? LocalFlow may need to reopen to see it."
    }

    private var mayNeedReopen: Bool {
        (requested.contains(.microphone) && !permissions.microphone)
            || (requested.contains(.accessibility) && !permissions.accessibility)
            || hotkeyIsStuck
    }

    private func permissionRow(
        _ kind: PermissionKind, _ name: String, _ why: String, _ granted: Bool, request: @escaping () -> Void
    ) -> some View {
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
                Button("Allow…") {
                    requested.insert(kind)
                    request()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
    }

    private var model: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Getting the speech model", "This only happens once. After this, LocalFlow works without internet.")
            VStack(alignment: .leading, spacing: 14) {
                Text(Transcriber.modelDisplayName).fontWeight(.semibold)
                if case .failed(let problem) = controller.modelStatus {
                    Text(problem.message).foregroundStyle(.secondary)
                    HStack {
                        Text(problem.advice)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(problem.actionTitle) { controller.retryModel() }
                    }
                } else {
                    downloadStage
                    prepareStage
                    Text("This Mac: \(MemoryInfo.macDescription)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
        }
    }

    private var downloadStage: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .downloading(let progress) = controller.modelStatus {
                modelStageLabel("1. Download", done: false) {
                    Text("\(Int(progress * Double(Transcriber.modelSizeMB))) of \(Transcriber.modelSizeMB) MB")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ProgressView(value: progress)
            } else {
                modelStageLabel("1. Download", done: true) { EmptyView() }
            }
        }
    }

    private var prepareStage: some View {
        VStack(alignment: .leading, spacing: 6) {
            modelStageLabel("2. Prepare for this Mac's Neural Engine", done: controller.modelStatus == .ready) { EmptyView() }
            if controller.modelStatus == .loading {
                ProgressView()
                    .progressViewStyle(.linear)
                Text("This can take a few minutes the first time. macOS doesn't report a percentage for this step.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func modelStageLabel<Trailing: View>(
        _ name: String, done: Bool, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 6) {
            Text(name)
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Done")
            }
            Spacer()
            trailing()
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

    private var canContinue: Bool {
        switch step {
        case .permissions: controller.permissionsReady
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

    private func saveStep() {
        if !repairingPermissions { settings.setupStep = step.rawValue }
    }

    private func move(_ delta: Int) {
        step = Step(rawValue: step.rawValue + delta) ?? step
    }
}
