import SwiftUI

@main
struct DamiApp: App {
    @StateObject private var controller = DictationController()
    @StateObject private var navigation = Navigation.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            MenuBarLabel(controller: controller)
        }
        .menuBarExtraStyle(.window)

        Window("Dami", id: WindowID.main) {
            MainView(controller: controller)
                .environmentObject(navigation)
                .showsDockIconWhileOpen()
        }
        .defaultSize(width: 1000, height: 680)

        Window("Welcome to Dami", id: WindowID.onboarding) {
            OnboardingView(controller: controller)
                .showsDockIconWhileOpen()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

enum WindowID {
    static let main = "main"
    static let onboarding = "onboarding"
}

/// Which section of the main window is showing. Shared so the menu can open a specific one.
@MainActor
final class Navigation: ObservableObject {
    static let shared = Navigation()

    enum Section: String, CaseIterable, Identifiable {
        case home, history, dictionary, settings
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .home: "house"
            case .history: "clock"
            case .dictionary: "character.book.closed"
            case .settings: "gearshape"
            }
        }
    }

    @Published var section: Section = .home
    /// Settings tab to show next, by name.
    @Published var requestedSettingsTab: String?
    /// A dictation to open in History with its fix box showing.
    @Published var requestedFix: Int64?
    /// Bumped to open the main window from code that can't reach SwiftUI's `openWindow`.
    @Published private(set) var windowRequests = 0
    /// The same, for the setup window.
    @Published private(set) var setupWindowRequests = 0

    func openSettings(tab: String) {
        section = .settings
        requestedSettingsTab = tab
        windowRequests += 1
    }

    func openHistory(fixing id: Int64) {
        section = .history
        requestedFix = id
        windowRequests += 1
    }

    func openSetup() {
        setupWindowRequests += 1
    }
}

/// The menu bar icon. Also opens onboarding on first launch, since it's the one view that
/// always exists.
private struct MenuBarLabel: View {
    @ObservedObject var controller: DictationController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: controller.state.symbolName)
            .onReceive(Navigation.shared.$windowRequests.dropFirst()) { _ in
                openWindow(id: WindowID.main)
                NSApp.activate(ignoringOtherApps: true)
            }
            .onReceive(Navigation.shared.$setupWindowRequests.dropFirst()) { _ in
                openWindow(id: WindowID.onboarding)
                NSApp.activate(ignoringOtherApps: true)
            }
            .onAppear {
                DispatchQueue.main.async(execute: Self.openOnRightClick)
                if !AppSettings.shared.hasCompletedOnboarding || !controller.permissionsReady {
                    openWindow(id: WindowID.onboarding)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }

    /// MenuBarExtra only opens its panel on a left click. Make the status bar button send its
    /// action on the matching right-click event too.
    private static func openOnRightClick() {
        let buttons = NSApp.windows
            .filter { $0.className.contains("NSStatusBarWindow") }
            .compactMap { $0.contentView.flatMap(statusButton) }
        for button in buttons {
            var mask = NSEvent.EventTypeMask(rawValue: UInt64(button.sendAction(on: [])))
            if mask.contains(.leftMouseDown) { mask.insert(.rightMouseDown) }
            if mask.contains(.leftMouseUp) { mask.insert(.rightMouseUp) }
            button.sendAction(on: mask)
        }
    }

    private static func statusButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        return view.subviews.lazy.compactMap(statusButton).first
    }
}

/// Dami is a menu bar app (no Dock icon), but while one of its windows is open it shows in
/// the Dock and ⌘-Tab like a normal app, so the window is easy to get back to.
private struct DockIconWhileOpen: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                DockIcon.openWindows += 1
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
            .onDisappear {
                DockIcon.openWindows -= 1
                if DockIcon.openWindows <= 0 {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
    }
}

@MainActor
private enum DockIcon {
    static var openWindows = 0
}

extension View {
    func showsDockIconWhileOpen() -> some View { modifier(DockIconWhileOpen()) }
}
