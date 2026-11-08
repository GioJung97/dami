import DamiCore
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
        .foregroundStyle(Theme.ink)
        .background(Theme.paper)
        .tint(Palette.standard.key)
        .navigationTitle(repairingPermissions ? "Dami Permissions" : "Welcome to Dami")
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
        Rule()
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(stepColor(item))
                        .frame(width: item == step ? 22 : 8, height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
            Spacer()
            if step != .welcome && step != .done {
                Button("Back") { move(-1) }
                    .buttonStyle(KeyButtonStyle(kind: .secondary, height: 28))
            }
            Button(nextTitle) { next() }
                .buttonStyle(KeyButtonStyle(kind: .primary, height: 28))
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    /// Current step: a key-colour bar. Done: ink2. Still to do: the edge colour.
    private func stepColor(_ item: Step) -> AnyShapeStyle {
        if item == step { return AnyShapeStyle(Palette.standard.key) }
        return item.rawValue < step.rawValue ? AnyShapeStyle(Theme.ink2) : AnyShapeStyle(Theme.keyEdge)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 16) {
            DamiMark(size: 96)
            Text("Welcome to Dami").font(Theme.Font.bigStepTitle).tracking(-0.4)
            Text("Speak in English, another language, or both. Your words appear wherever you're typing. Everything runs on this Mac, so your voice never leaves it.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink2)
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
                title("Permission needed", "Dami can't work without these. This window closes once they're all allowed.")
            } else {
                title("Permissions", "Allow each one. macOS may offer Later or Quit & Reopen: choose Later, and setup continues here.")
            }
            VStack(spacing: 0) {
                permissionRow(.microphone, "Microphone", "To hear you while you hold the shortcut.", permissions.microphone) {
                    permissions.requestMicrophone()
                }
                Rule()
                permissionRow(.accessibility, "Accessibility", "To notice the shortcut, and paste where your cursor is.", permissions.accessibility) {
                    permissions.requestAccessibility()
                }
                if hotkeyIsStuck {
                    Rule()
                    permissionRow(.inputMonitoring, "Input Monitoring", "This Mac also needs this one, to notice the shortcut in any app.", false) {
                        permissions.requestInputMonitoring()
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.keyFace))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.keyEdge))
            if mayNeedReopen {
                HStack(spacing: 12) {
                    Text(reopenAdvice)
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.ink2)
                    Spacer()
                    Button("Quit & Reopen") { permissions.quitAndReopen() }
                        .buttonStyle(.secondaryKey)
                }
            }
        }
    }

    private var reopenAdvice: String {
        hotkeyIsStuck
            ? "After allowing Input Monitoring, reopen Dami so it can see it."
            : "Allowed it, but it still says Allow? Dami may need to reopen to see it."
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
                Text(why).font(Theme.Font.footnote).foregroundStyle(Theme.ink2)
            }
            Spacer()
            if granted {
                HStack(spacing: 6) {
                    DoneCheck()
                    Text("Allowed").font(Theme.Font.keyLabel).tracking(Theme.keyLabelTracking).textCase(.uppercase)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Allowed")
            } else {
                Button("Allow…") {
                    requested.insert(kind)
                    request()
                }
                .buttonStyle(.primaryKey)
            }
        }
        .padding(14)
    }

    private var model: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Getting the speech model", "This only happens once. After this, Dami works without internet.")
            VStack(alignment: .leading, spacing: 14) {
                Text(Transcriber.modelDisplayName).fontWeight(.semibold)
                if case .failed(let problem) = controller.modelStatus {
                    Text(problem.message).foregroundStyle(Theme.danger)
                    HStack {
                        Text(problem.advice)
                            .font(Theme.Font.footnote)
                            .foregroundStyle(Theme.ink2)
                        Spacer()
                        Button(problem.actionTitle) { controller.retryModel() }
                            .buttonStyle(.primaryKey)
                    }
                } else {
                    downloadStage
                    prepareStage
                    Text("This Mac: \(MemoryInfo.macDescription)")
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.ink2)
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.keyFace))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.keyEdge))
        }
    }

    private var downloadStage: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .downloading(let progress) = controller.modelStatus {
                modelStageLabel("1. Download", done: false) {
                    Text("\(Int(progress * Double(Transcriber.modelSizeMB))) of \(Transcriber.modelSizeMB) MB")
                        .font(Theme.Font.mono)
                        .foregroundStyle(Theme.ink2)
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
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.ink2)
            }
        }
    }

    private func modelStageLabel<Trailing: View>(
        _ name: String, done: Bool, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 6) {
            Text(name)
            if done {
                DoneCheck()
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
                .font(.system(size: 17, design: .serif))
                .frame(maxWidth: .infinity)
                .padding(10)
            TextEditor(text: $practiceText)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .frame(height: 60)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.keyFace))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Palette.standard.key, lineWidth: 2))
                .accessibilityLabel("Your words appear here")
        }
    }

    private var done: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.onHighlight)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.standard.highlight))
                .rotationEffect(.degrees(-3))
                .accessibilityHidden(true)
            Text("You're all set").font(Theme.Font.bigStepTitle)
            Text("Dami lives in the menu bar. Hold \(settings.shortcut.displayName) in any app to dictate. Change the shortcut any time in Settings.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Toggle("Open Dami at login", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
                .toggleStyle(InkCheckboxStyle())
        }
        .padding(.top, 20)
    }

    private func title(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.Font.stepTitle)
            Text(subtitle).font(Theme.Font.body).foregroundStyle(Theme.ink2)
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
        case .done: "Start using Dami"
        default: "Continue"
        }
    }

    private func next() {
        if step == .done {
            settings.hasCompletedOnboarding = true
            dismissWindow(id: WindowID.onboarding)
            TourController.shared.startAfterSetup(controller: controller)
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

/// An ink check on the highlighter: "done" in setup.
private struct DoneCheck: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(Theme.onHighlight)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(Palette.standard.highlight))
            .accessibilityLabel("Done")
    }
}
