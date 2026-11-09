import AppKit
import SwiftUI

/// On the tour's menu step: a ring that breathes around the real menu bar icon and an arrow that bobs under it, saying "Click".
/// The rest of that screen is dimmed, except the icon and the tour window, so the icon stands out.
/// Clicks pass through to the icon. It follows the icon, which macOS can move or hide (a full menu bar, the notch).
@MainActor
final class MenuBarSpotlight: ObservableObject {
    /// The icon was found and is on screen.
    @Published private(set) var iconVisible = true

    private var panel: NSPanel?
    private var dimmer: NSPanel?
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
        dimmer?.orderOut(nil)
        iconVisible = true
    }

    private func follow() {
        guard let item = Self.statusItemFrame(), let screen = NSScreen.screens.first(where: { $0.frame.intersects(item) }),
              screen.frame.contains(NSPoint(x: item.midX, y: item.midY)) else {
            iconVisible = false
            panel?.orderOut(nil)
            dimmer?.orderOut(nil)
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
        showDimmer(on: screen, icon: item)
        panel.orderFrontRegardless()
    }

    /// Dims the icon's screen, leaving a hole around the icon and one over the tour window.
    private func showDimmer(on screen: NSScreen, icon: NSRect) {
        let isNew = dimmer == nil || dimmer?.isVisible == false
        let dimmer = self.dimmer ?? makePanel(content: DimView(size: .zero, holes: []))
        self.dimmer = dimmer
        if dimmer.frame != screen.frame { dimmer.setFrame(screen.frame, display: true) }
        // Holes in the panel's own coordinates, which start at the top left.
        func local(_ rect: NSRect) -> CGRect {
            CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        var holes = [DimView.Hole(rect: local(icon).insetBy(dx: -5, dy: -1), radius: 7)]
        if let tour = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(WindowID.liveTour) == true && $0.isVisible }),
           tour.frame.intersects(screen.frame) {
            holes.append(DimView.Hole(rect: local(tour.frame), radius: 10))
        }
        (dimmer.contentView as? NSHostingView<DimView>)?.rootView = DimView(size: screen.frame.size, holes: holes)
        if isNew {
            let fade = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            dimmer.alphaValue = fade ? 0 : 1
            // Just under the ring, so the ring and arrow stay bright.
            dimmer.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            dimmer.orderFrontRegardless()
            if fade {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.35
                    dimmer.animator().alphaValue = 1
                }
            }
        }
    }

    private func makePanel() -> NSPanel {
        makePanel(content: SpotlightView(itemSize: .zero, margin: Self.margin))
    }

    private func makePanel<Content: View>(content: Content) -> NSPanel {
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
        panel.contentView = NSHostingView(rootView: content)
        return panel
    }

    /// Where Dami's menu bar icon is, in screen coordinates. Nil when macOS isn't showing it.
    static func statusItemFrame() -> NSRect? {
        NSApp.windows.first { $0.className.contains("NSStatusBarWindow") && $0.isVisible && $0.occlusionState.contains(.visible) }?.frame
    }
}

/// The dim layer: the whole screen, darker, with see-through holes.
struct DimView: View {
    struct Hole: Equatable {
        let rect: CGRect
        let radius: CGFloat
    }

    let size: CGSize
    let holes: [Hole]

    var body: some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            for hole in holes { path.addRoundedRect(in: hole.rect, cornerSize: CGSize(width: hole.radius, height: hole.radius)) }
        }
        .fill(Theme.scrim, style: FillStyle(eoFill: true))
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
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
