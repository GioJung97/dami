import AppKit
import SwiftUI

/// The small floating indicator. Hidden until the shortcut is used; never takes keyboard focus
/// and ignores the mouse, so it can't get in the way of typing.
@MainActor
final class HUDController: ObservableObject {
    enum Phase: Equatable {
        case hidden
        case recording(handsFree: Bool)
        case transcribing
        case pasted
        case copiedOnly
    }

    static let barCount = 9

    @Published private(set) var phase: Phase = .hidden
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: barCount)
    @Published private(set) var recordingStartedAt = Date()

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ phase: Phase) {
        hideTask?.cancel()
        if case .recording = phase, !isRecording(self.phase) {
            levels = Array(repeating: 0, count: Self.barCount)
            recordingStartedAt = Date()
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { self.phase = phase }
        present()

        switch phase {
        case .pasted: scheduleHide(after: .milliseconds(700))
        case .copiedOnly: scheduleHide(after: .seconds(2.5))
        default: break
        }
    }

    func hide() {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { phase = .hidden }
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

    private func scheduleHide(after delay: Duration) {
        hideTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    private func scheduleOrderOut() {
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, phase == .hidden else { return }
            panel?.orderOut(nil)
        }
    }

    // MARK: Window

    private static let size = NSSize(width: 220, height: 44)

    private func present() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
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
        panel.contentView = NSHostingView(rootView: HUDView(controller: self))
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
