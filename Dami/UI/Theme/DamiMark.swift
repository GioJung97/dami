import SwiftUI

/// The Dami mark (spec §7 "App icon"): a quote mark in ink, a highlighter stroke and an orange key on a cream squircle.
/// Drawn in a 1024 × 1024 space, the same as the app icon, so the icon can be made from this one drawing.
struct DamiMark: View {
    var size: CGFloat = 96
    /// Leave out the drop shadow, e.g. when rendering the icon's own image.
    var shadow = true

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 1024
            context.scaleBy(x: scale, y: scale)
            let squircle = Path(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerRadius: 185, style: .continuous)
            if shadow {
                context.fill(squircle.offsetBy(dx: 0, dy: 10), with: .color(.black.opacity(0.16)))
            }
            context.fill(squircle, with: .color(Color(hex: 0xF6F1E7)))
            context.stroke(squircle, with: .color(Color(hex: 0x1F1B16, alpha: 0.10)), lineWidth: 2)

            let ink = GraphicsContext.Shading.color(Color(hex: 0x1F1B16))
            for dx in [CGFloat(0), 184] {
                context.fill(Path(ellipseIn: CGRect(x: 324 + dx, y: 324, width: 132, height: 132)), with: ink)
                var tail = Path()
                tail.move(to: CGPoint(x: 456 + dx, y: 390))
                tail.addCurve(to: CGPoint(x: 344 + dx, y: 544), control1: CGPoint(x: 456 + dx, y: 472), control2: CGPoint(x: 410 + dx, y: 524))
                tail.addLine(to: CGPoint(x: 337 + dx, y: 509))
                tail.addCurve(to: CGPoint(x: 399 + dx, y: 429), control1: CGPoint(x: 377 + dx, y: 491), control2: CGPoint(x: 399 + dx, y: 462))
                tail.closeSubpath()
                context.fill(tail, with: ink)
            }

            var stroke = context
            stroke.translateBy(x: 415, y: 664)
            stroke.rotate(by: .degrees(-2))
            stroke.fill(
                Path(roundedRect: CGRect(x: -165, y: -24, width: 330, height: 48), cornerRadius: 8),
                with: .color(Color(hex: 0xF2D74E))
            )

            context.fill(Path(ellipseIn: CGRect(x: 630, y: 608, width: 164, height: 164)), with: .color(Color(hex: 0xB83A0E)))
            context.fill(Path(ellipseIn: CGRect(x: 630, y: 600, width: 164, height: 164)), with: .color(Color(hex: 0xFF5A1F)))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Dami")
    }
}
