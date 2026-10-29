import SwiftUI

@main
struct LocalFlowApp: App {
    @StateObject private var controller = DictationController()
    @StateObject private var navigation = Navigation.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            MenuBarLabel(controller: controller)
        }
        .menuBarExtraStyle(.window)

        Window("LocalFlow", id: WindowID.main) {
            MainView(controller: controller)
                .environmentObject(navigation)
                .showsDockIconWhileOpen()
        }
        .defaultSize(width: 1000, height: 680)

        Window("Welcome to LocalFlow", id: WindowID.onboarding) {
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
}

/// The menu bar icon. Also opens onboarding on first launch, since it's the one view that
/// always exists.
private struct MenuBarLabel: View {
    @ObservedObject var controller: DictationController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: controller.state.symbolName)
            .onAppear {
                if !AppSettings.shared.hasCompletedOnboarding || !Permissions.shared.allGranted {
                    openWindow(id: WindowID.onboarding)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }
}

/// LocalFlow is a menu bar app (no Dock icon), but while one of its windows is open it shows in
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
