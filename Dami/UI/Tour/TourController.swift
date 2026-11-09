import AppKit
import Combine
import SwiftUI

/// The quick tour you do, not read: a small window with its own text box walks through a real dictation, following what the app is
/// doing (keys held, listening, writing, pasted), then the menu, then the main window's sections.
/// It only watches the app's state and Recent list; it never changes what dictation does.
@MainActor
final class TourController: ObservableObject {
    static let shared = TourController()

    enum Step: Int, CaseIterable {
        case hold, speak, writing, pasted, menu, history, dictionary, settings, done

        /// Shown in the main window, as a note under a section key, instead of in the tour window.
        var isInWindow: Bool { rawValue >= Step.history.rawValue }

        var section: Navigation.Section? {
            switch self {
            case .history: .history
            case .dictionary: .dictionary
            case .settings: .settings
            default: nil
            }
        }

        /// The numbered stops shown to the user: the dictation is one stop (hold → pasted).
        var stop: Int {
            switch self {
            case .hold, .speak, .writing, .pasted: 1
            case .menu: 2
            case .history: 3
            case .dictionary: 4
            case .settings: 5
            case .done: 6
            }
        }
        static let stops = 6
    }

    /// Nil when the tour isn't running.
    @Published private(set) var step: Step?
    /// Why the dictation step started over, shown on the "hold" step.
    enum Retry { case tooShort, nothingHeard }
    @Published private(set) var retry: Retry?
    /// The menu was opened on the "menu" step.
    @Published private(set) var menuFound = false

    /// The ring and arrow on the real menu bar icon, during the menu step until the menu is opened.
    let spotlight = MenuBarSpotlight()

    private var watchers: Set<AnyCancellable> = []
    private var spotlightWatcher: AnyCancellable?
    private var sawRecording = false

    private init() {
        spotlightWatcher = $step.combineLatest($menuFound)
            .sink { [weak self] step, found in
                Task { @MainActor in
                    if step == .menu && !found { self?.spotlight.show() } else { self?.spotlight.hide() }
                }
            }
    }

    /// Once, right after setup.
    func startAfterSetup(controller: DictationController) {
        guard !AppSettings.shared.tourShown else { return }
        start(controller: controller)
    }

    func start(controller: DictationController) {
        AppSettings.shared.tourShown = true
        watchers = []
        retry = nil
        menuFound = false
        sawRecording = false

        controller.$state
            .removeDuplicates()
            .sink { [weak self] state in Task { @MainActor in self?.follow(state) } }
            .store(in: &watchers)

        var lastFirst = controller.recent.first?.id
        controller.$recent
            .sink { [weak self] recent in
                Task { @MainActor in
                    guard let self, let first = recent.first?.id, first != lastFirst else { return }
                    lastFirst = first
                    if let step = self.step, step.rawValue <= Step.writing.rawValue { self.step = .pasted }
                }
            }
            .store(in: &watchers)

        go(to: .hold)
    }

    /// Moves through the dictation steps as the app moves through its states.
    private func follow(_ state: DictationController.State) {
        guard let step, step.rawValue <= Step.writing.rawValue else { return }
        switch state {
        case .recording:
            sawRecording = true
            retry = nil
            self.step = .speak
        case .transcribing:
            if sawRecording { self.step = .writing }
        case .idle, .failed:
            // Back to idle straight from listening: a quick tap, dropped without writing anything.
            if step == .speak {
                retry = .tooShort
                self.step = .hold
            }
            // Done writing but nothing reached Recent shortly after: nothing was recognized.
            if step == .writing {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    if self.step == .writing {
                        self.retry = .nothingHeard
                        self.step = .hold
                    }
                }
            }
            sawRecording = false
        case .loadingModel:
            break
        }
    }

    func next() {
        guard let step, let following = Step(rawValue: step.rawValue + 1) else { return end() }
        go(to: following)
    }

    func back() {
        guard let step else { return }
        // Back from a section goes to the previous stop; back from the menu redoes the dictation.
        let previous: Step = switch step {
        case .menu: .hold
        case .history: .menu
        default: Step(rawValue: step.rawValue - 1) ?? .hold
        }
        go(to: previous)
    }

    func end() {
        step = nil
        watchers = []
    }

    /// Called by the menu panel when it opens.
    func menuOpened() {
        if step == .menu { menuFound = true }
    }

    private func go(to newStep: Step) {
        step = newStep
        if newStep == .hold { retry = nil }
        if newStep == .menu { menuFound = false }
        // The tour window closes itself when the step moves into the main window.
        if newStep.isInWindow {
            Navigation.shared.openMain(section: newStep.section ?? .home)
        } else {
            Navigation.shared.openTourWindow()
        }
    }
}
