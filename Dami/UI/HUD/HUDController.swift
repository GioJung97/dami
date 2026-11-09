import AppKit
import SwiftUI

/// The small floating indicator. Hidden until the shortcut is used; never takes keyboard focus,
/// and ignores the mouse unless it's offering an action, so it can't get in the way of typing.
@MainActor
final class HUDController: ObservableObject {
    enum Phase: Equatable {
        case hidden
        case recording(handsFree: Bool)
        case transcribing(waiting: Int)
        case pasted
        case copied(String)
        /// Text with an optional button. Stays until replaced if `isSticky`.
        case message(Message)
    }

    struct Message: Equatable {
        var text: String
        var actionTitle: String?
        var isSticky = false
    }

    static let barCount = 9

    @Published private(set) var phase: Phase = .hidden
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: barCount)
    @Published private(set) var recordingStartedAt = Date()
    /// A short message above the pill. Independent of the phase, so a recording keeps its meter.
    @Published private(set) var note: String?

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var noteTask: Task<Void, Never>?
    private var messageAction: (() -> Void)?
    /// What to show once a timed phase is over: the recording or pending work, or nothing.
    var restingPhase: (() -> Phase)?

    func show(_ phase: Phase) {
        hideTask?.cancel()
        if case .recording = phase, !isRecording(self.phase) {
            levels = Array(repeating: 0, count: Self.barCount)
            recordingStartedAt = Date()
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { self.phase = phase }
        present()

        panel?.ignoresMouseEvents = !hasAction

        switch phase {
        case .pasted: scheduleRest(after: .milliseconds(700))
        case .copied: scheduleRest(after: Self.messageDuration)
        case .message(let message) where !message.isSticky:
            scheduleRest(after: message.actionTitle == nil ? Self.messageDuration : Self.actionMessageDuration)
        default: break
        }
    }

    /// Shows a message, with a button if `action` is given.
    func show(message text: String, actionTitle: String? = nil, isSticky: Bool = false, action: (() -> Void)? = nil) {
        messageAction = action
        show(.message(Message(text: text, actionTitle: actionTitle, isSticky: isSticky)))
    }

    func performMessageAction() {
        let action = messageAction
        rest()
        action?()
    }

    private var hasAction: Bool {
        if case .message(let message) = phase { return message.actionTitle != nil }
        return false
    }

    func hide() {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { phase = .hidden }
        panel?.ignoresMouseEvents = true
        scheduleOrderOut()
    }

    func show(note: String) {
        noteTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { self.note = note }
        present()
        noteTask = Task {
            try? await Task.sleep(for: Self.noteDuration)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) { self.note = nil }
            scheduleOrderOut()
        }
    }

    /// Takes a note away early, when what it said is over.
    func hideNote(_ text: String) {
        guard note == text else { return }
        noteTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { note = nil }
        scheduleOrderOut()
    }

    func push(level: Float) {
        guard isRecording(phase) else { return }
        levels.removeFirst()
        levels.append(level)
    }

    private func isRecording(_ phase: Phase) -> Bool {
        if case .recording = phase { return true }
        return false
    }

    private func scheduleRest(after delay: Duration) {
        hideTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            rest()
        }
    }

    private func rest() {
        if let next = restingPhase?(), next != .hidden {
            show(next)
        } else {
            hide()
        }
    }

    private func scheduleOrderOut() {
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, phase == .hidden, note == nil else { return }
            panel?.orderOut(nil)
        }
    }

    // MARK: Window

    static let noteDuration: Duration = .seconds(4)
    static let messageDuration: Duration = .seconds(3)
    static let actionMessageDuration: Duration = .seconds(7)
    /// Room for the pill and a note above or below it. The panel itself is invisible.
    private static let size = NSSize(width: 360, height: 76)

    private func present() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.ignoresMouseEvents = !hasAction
        position(panel)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = HUDHostingView(rootView: HUDView(controller: self))
        return panel
    }

    /// Bottom (or top) center of the screen the mouse is on, clear of the Dock and menu bar.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let x = frame.midX - Self.size.width / 2
        let y = AppSettings.shared.hudPosition == .bottomCenter
            ? frame.minY + 18
            : frame.maxY - Self.size.height - 12
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: Self.size), display: false)
    }
}

/// The panel is never key, so without this a button's first click would be lost.
private final class HUDHostingView: NSHostingView<HUDView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
