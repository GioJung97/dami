// Draws the background of the .dmg window: Dami and Applications side by side with an arrow, and how to open Dami the first time.
// scripts/release.sh runs this and places the icons on top to match; change the layout in both together.
//
// Usage: swift scripts/make-dmg-background.swift <output folder>
// Writes background.png (1×) and background@2x.png (2×) at 660 × 460 points.
import AppKit

let size = CGSize(width: 660, height: 460)
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".", isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let paper = color(0xF6F1E7), ink = color(0x1F1B16), ink2 = color(0x5C5348), rule = color(0x1F1B16, 0.12)
let key = color(0xFF5A1F), keyDepth = color(0xB83A0E), highlight = color(0xF2D74E)

func serif(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .semibold)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size) ?? base
}

/// Text with its top left at `point`, in a top-left coordinate space.
func draw(_ text: String, at point: CGPoint, width: CGFloat, font: NSFont, color: NSColor, center: Bool = false) {
    let style = NSMutableParagraphStyle()
    style.alignment = center ? .center : .left
    style.lineSpacing = 2
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    string.draw(with: CGRect(x: point.x, y: point.y, width: width, height: 200), options: [.usesLineFragmentOrigin])
}

/// A numbered key, like the app's keycaps.
func stepKey(_ number: Int, at point: CGPoint) {
    let face = CGRect(x: point.x, y: point.y, width: 22, height: 22)
    keyDepth.setFill(); NSBezierPath(roundedRect: face.offsetBy(dx: 0, dy: 2), xRadius: 5, yRadius: 5).fill()
    key.setFill(); NSBezierPath(roundedRect: face, xRadius: 5, yRadius: 5).fill()
    draw("\(number)", at: CGPoint(x: face.minX, y: face.minY + 3), width: face.width,
         font: .systemFont(ofSize: 12, weight: .bold), color: .white, center: true)
}

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    // Top-left coordinates, the same as Finder's icon positions.
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    context.cgContext.translateBy(x: 0, y: size.height)
    context.cgContext.scaleBy(x: 1, y: -1)

    paper.setFill(); CGRect(origin: .zero, size: size).fill()

    // Title, with the highlighter under "Applications".
    let titleFont = serif(22)
    let title = "Drag Dami into Applications"
    let titleWidth = (title as NSString).size(withAttributes: [.font: titleFont]).width
    let titleX = (size.width - titleWidth) / 2
    let lead = ("Drag Dami into " as NSString).size(withAttributes: [.font: titleFont]).width
    let mark = ("Applications" as NSString).size(withAttributes: [.font: titleFont]).width
    highlight.setFill()
    NSBezierPath(roundedRect: CGRect(x: titleX + lead - 3, y: 41, width: mark + 6, height: 14), xRadius: 3, yRadius: 3).fill()
    draw(title, at: CGPoint(x: titleX, y: 28), width: titleWidth + 4, font: titleFont, color: ink)

    // The arrow between the two icons (icons sit at x 170 and 490, y 160).
    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: 258, y: 150)); arrow.line(to: CGPoint(x: 392, y: 150))
    arrow.lineWidth = 4; arrow.lineCapStyle = .round
    key.setStroke(); arrow.stroke()
    let head = NSBezierPath()
    head.move(to: CGPoint(x: 404, y: 150)); head.line(to: CGPoint(x: 386, y: 139)); head.line(to: CGPoint(x: 386, y: 161)); head.close()
    key.setFill(); head.fill()

    // How to open it the first time, next to the Privacy & Security shortcut (icon at x 540, y 355).
    rule.setFill(); CGRect(x: 40, y: 262, width: size.width - 80, height: 1).fill()
    draw("THE FIRST TIME YOU OPEN IT", at: CGPoint(x: 48, y: 280), width: 400, font: .systemFont(ofSize: 10.5, weight: .bold), color: ink2)
    let steps = [
        "Open Dami. macOS stops it once, since it isn't notarized by Apple. Choose Done.",
        "Double-click Privacy & Security, then scroll to the bottom.",
        "Choose Open Anyway next to Dami, and confirm.",
    ]
    var y: CGFloat = 304
    for (index, step) in steps.enumerated() {
        stepKey(index + 1, at: CGPoint(x: 48, y: y))
        draw(step, at: CGPoint(x: 80, y: y + 2), width: 340, font: .systemFont(ofSize: 12.5), color: ink)
        y += index == 0 ? 50 : 36
    }
    let pointer = NSBezierPath()
    pointer.move(to: CGPoint(x: 432, y: 355)); pointer.line(to: CGPoint(x: 478, y: 355))
    pointer.lineWidth = 2; pointer.lineCapStyle = .round
    pointer.setLineDash([3, 5], count: 2, phase: 0)
    ink2.setStroke(); pointer.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try render(scale: 1).write(to: out.appendingPathComponent("background.png"))
try render(scale: 2).write(to: out.appendingPathComponent("background@2x.png"))
print("Wrote background.png and background@2x.png to \(out.path)")
