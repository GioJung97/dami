/// The steps of first-launch setup, in order. The raw value is what's saved between launches.
public enum SetupStep: Int, CaseIterable, Sendable {
    case welcome, language, permissions, model, practice, done

    /// "Try it once" needs the real shortcut. Before that, pressing it explains that setup isn't finished.
    public var allowsShortcut: Bool { rawValue >= SetupStep.practice.rawValue }

    /// Where to pick up after setup was left. macOS can quit the app in the middle of Permissions, so this can be any step. Never lands
    /// past something that's still missing.
    public static func resume(saved: Int, permissionsGranted: Bool, modelReady: Bool) -> SetupStep {
        let step = SetupStep(rawValue: saved) ?? .welcome
        if step.rawValue > SetupStep.permissions.rawValue, !permissionsGranted { return .permissions }
        if step.rawValue > SetupStep.model.rawValue, !modelReady { return .model }
        return step
    }
}
