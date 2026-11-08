import AppKit
import SwiftUI

/// On the tour's menu step: a ring that breathes around the real menu bar icon and an arrow that bobs under it, saying "Click".
/// Clicks pass through to the icon. It follows the icon, which macOS can move or hide (a full menu bar, the notch).
@MainActor
final class MenuBarSpotlight: ObservableObject {
    /// The icon was found and is on screen.
    @Published private(set) var iconVisible = true

    private var panel: NSPanel?
    private var timer: Timer?
    private static let margin: CGFloat = 14
    private static let below: CGFloat = 64

    func show() {
        guard timer == nil else { return }
        follow()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.follow() }
        }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        iconVisible = true
    }

    private func follow() {
        guard let item = Self.statusItemFrame(), let screen = NSScreen.screens.first(where: { $0.frame.intersects(item) }),
              screen.frame.contains(NSPoint(x: item.midX, y: item.midY)) else {
            iconVisible = false
            panel?.orderOut(nil)
            return
        }
        iconVisible = true
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let frame = NSRect(
            x: item.minX - Self.margin,
            y: item.minY - Self.below,
            width: item.width + Self.margin * 2,
            height: item.height + Self.below + 4
        )
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        (panel.contentView as? NSHostingView<SpotlightView>)?.rootView = SpotlightView(itemSize: item.size, margin: Self.margin)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        // Above the menu bar and its status items, so the ring can sit around the icon.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: SpotlightView(itemSize: .zero, margin: Self.margin))
        return panel
    }

    /// Where Dami's menu bar icon is, in screen coordinates. Nil when macOS isn't showing it.
    static func statusItemFrame() -> NSRect? {
        NSApp.windows.first { $0.className.contains("NSStatusBarWindow") && $0.isVisible && $0.occlusionState.contains(.visible) }?.frame
    }
}

struct SpotlightView: View {
    let itemSize: CGSize
    let margin: CGFloat
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        let key = settings.keyColor.palette.key
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(key, lineWidth: 2.5)
                .frame(width: itemSize.width + 10, height: itemSize.height + 2)
                .scaleEffect(pulse ? 1.12 : 0.96)
                .opacity(pulse ? 0.55 : 1)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(key.opacity(0.18))
                        .frame(width: itemSize.width + 10, height: itemSize.height + 2)
                )
            VStack(spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(key)
                Text("Click")
                    .font(Theme.Font.keyLabelSmall)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.onKey)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(key))
            }
            .offset(y: pulse ? 4 : -2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}
