// Draws the README's dictation demo (docs/assets/dami-demo.gif) and copies the icon (docs/assets/dami-icon.png).
// Made-up text only, drawn from scratch: no screenshots of the real app or its data (design brief, "The owner's data").
// Colours, HUD and glyph follow docs/design/spec.md (Cream, Orange).
//
// Usage: swift scripts/make-readme-demo.swift   (from the repo root, after scripts/make-icon.swift)
import AppKit
import ImageIO
import UniformTypeIdentifiers

let width: CGFloat = 800, height: CGFloat = 450
let assets = URL(fileURLWithPath: "docs/assets", isDirectory: true)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
}
let ink = hex(0x1F1B16), ink2 = hex(0x685F54), paper = hex(0xF6F1E7), slip = hex(0xFBF7EE), keyFace = hex(0xFFFDF8)
let edge = hex(0xD6CCBA), orange = hex(0xCC4410), highlight = hex(0xF2D74E)

enum HUD { case none, recording(seconds: Int, levels: [CGFloat]), working(step: Int), sent }
enum Glyph { case ready, recording, working }

struct Frame {
    var lines: [String]
    var showCursor = true
    var hud: HUD = .none
    var glyph: Glyph = .ready
    var caption: String
    var delay: Double
}

// MARK: Drawing (top-left origin)

func rounded(_ rect: CGRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius) }

func text(_ string: String, at point: CGPoint, font: NSFont, color: NSColor, centeredIn width: CGFloat? = nil) -> CGSize {
    let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
    let size = attributed.size()
    var origin = point
    if let width { origin.x += (width - size.width) / 2 }
    attributed.draw(at: origin)
    return size
}

func bubble(in rect: CGRect) -> NSBezierPath {
    // The Speech key glyph, scaled from its 18 × 18 design.
    let s = rect.width / 18
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
    let path = NSBezierPath()
    path.move(to: p(5, 2.8)); path.line(to: p(13, 2.8))
    path.curve(to: p(15.5, 5.3), controlPoint1: p(14.4, 2.8), controlPoint2: p(15.5, 3.9))
    path.line(to: p(15.5, 10.3))
    path.curve(to: p(13, 12.8), controlPoint1: p(15.5, 11.7), controlPoint2: p(14.4, 12.8))
    path.line(to: p(8.6, 12.8)); path.line(to: p(5.4, 15.4)); path.line(to: p(5.4, 12.8)); path.line(to: p(5, 12.8))
    path.curve(to: p(2.5, 10.3), controlPoint1: p(3.6, 12.8), controlPoint2: p(2.5, 11.7))
    path.line(to: p(2.5, 5.3))
    path.curve(to: p(5, 2.8), controlPoint1: p(2.5, 3.9), controlPoint2: p(3.6, 2.8))
    path.close()
    path.lineWidth = 1.5 * s
    path.lineJoinStyle = .round
    return path
}

func drawGlyph(_ glyph: Glyph, in rect: CGRect) {
    let s = rect.width / 18
    let path = bubble(in: rect)
    NSColor.black.setStroke(); NSColor.black.setFill()
    path.stroke()
    switch glyph {
    case .ready, .recording:
        if case .recording = glyph { path.fill() }
        let lineColor: NSColor = { if case .recording = glyph { return hex(0xECE8E1) } else { return .black } }()
        lineColor.setFill()
        rounded(CGRect(x: rect.minX + 4.85 * s, y: rect.minY + 5.65 * s, width: 8.3 * s, height: 1.5 * s), 0.75 * s).fill()
        rounded(CGRect(x: rect.minX + 4.85 * s, y: rect.minY + 8.45 * s, width: 5.9 * s, height: 1.5 * s), 0.75 * s).fill()
    case .working:
        for x in [6.0, 9.0, 12.0] {
            NSBezierPath(ovalIn: CGRect(x: rect.minX + (x - 1.15) * s, y: rect.minY + 6.65 * s, width: 2.3 * s, height: 2.3 * s)).fill()
        }
    }
}

func keycap(_ label: String, at point: CGPoint) -> CGFloat {
    let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let size = NSAttributedString(string: label, attributes: [.font: font]).size()
    let rect = CGRect(x: point.x, y: point.y, width: size.width + 12, height: 20)
    edge.setFill(); rounded(rect.offsetBy(dx: 0, dy: 2), 4).fill()
    keyFace.setFill(); rounded(rect, 4).fill()
    edge.setStroke(); rounded(rect.insetBy(dx: 0.5, dy: 0.5), 4).stroke()
    _ = text(label, at: CGPoint(x: point.x + 6, y: point.y + 2), font: font, color: ink)
    return rect.width
}

func drawHUD(_ hud: HUD) {
    let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    var items: CGFloat = 0
    switch hud {
    case .none: return
    case .recording: items = 128
    case .working: items = 46
    case .sent: items = 34
    }
    let rect = CGRect(x: (width - items) / 2, y: height - 62, width: items, height: 32)
    NSGraphicsContext.saveGraphicsState()
    hex(0xCFC5B3).setFill(); rounded(rect.offsetBy(dx: 0, dy: 3), 8).fill()
    slip.setFill(); rounded(rect, 8).fill()
    NSGraphicsContext.restoreGraphicsState()
    ink.withAlphaComponent(0.24).setStroke(); rounded(rect.insetBy(dx: 0.5, dy: 0.5), 8).stroke()
    let midY = rect.midY
    switch hud {
    case .recording(let seconds, let levels):
        orange.setFill(); NSBezierPath(ovalIn: CGRect(x: rect.minX + 14, y: midY - 4.5, width: 9, height: 9)).fill()
        ink.setFill()
        for (index, level) in levels.enumerated() {
            let h = 4 + level * 14
            rounded(CGRect(x: rect.minX + 33 + CGFloat(index) * 5, y: midY - h / 2, width: 3, height: h), 1.5).fill()
        }
        _ = text(String(format: "0:%02d", seconds), at: CGPoint(x: rect.minX + 84, y: midY - 8),
                 font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), color: ink2)
    case .working(let step):
        for index in 0..<3 {
            (index == step ? ink : edge).setFill()
            NSBezierPath(ovalIn: CGRect(x: rect.minX + 11 + CGFloat(index) * 9, y: midY - 3, width: 6, height: 6)).fill()
        }
    case .sent:
        highlight.setFill(); rounded(CGRect(x: rect.minX + 8, y: midY - 9, width: 18, height: 18), 3).fill()
        let check = NSBezierPath()
        check.move(to: CGPoint(x: rect.minX + 12, y: midY)); check.line(to: CGPoint(x: rect.minX + 15.5, y: midY + 3.5)); check.line(to: CGPoint(x: rect.minX + 22, y: midY - 4))
        check.lineWidth = 2.2; check.lineCapStyle = .round; check.lineJoinStyle = .round
        ink.setStroke(); check.stroke()
    case .none: break
    }
    _ = font
}

func render(_ frame: Frame) -> CGImage {
    let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
        // Desk
        // Flat colours only: a GIF has 256 colours, and gradients or soft shadows band.
        hex(0xE4DCCD).setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        // Menu bar with the Dami glyph and a clock
        hex(0xF4F1EC, 0.92).setFill(); NSRect(x: 0, y: 0, width: width, height: 26).fill()
        drawGlyph(frame.glyph, in: CGRect(x: width - 92, y: 4, width: 18, height: 18))
        _ = text("9:41", at: CGPoint(x: width - 54, y: 5), font: .systemFont(ofSize: 13, weight: .medium), color: .black)

        // A plain writing window (any app)
        let window = CGRect(x: 90, y: 64, width: 620, height: 280)
        NSGraphicsContext.saveGraphicsState()
        hex(0xCFC5B3).setFill(); rounded(window.offsetBy(dx: 0, dy: 4), 10).fill()
        NSColor.white.setFill(); rounded(window, 10).fill()
        NSGraphicsContext.restoreGraphicsState()
        for (index, color) in [hex(0xFF5F57), hex(0xFEBC2E), hex(0x28C840)].enumerated() {
            color.setFill(); NSBezierPath(ovalIn: CGRect(x: window.minX + 14 + CGFloat(index) * 20, y: window.minY + 13, width: 12, height: 12)).fill()
        }
        _ = text("Meeting notes", at: CGPoint(x: window.minX, y: window.minY + 10), font: .systemFont(ofSize: 13, weight: .semibold), color: hex(0x4A4A4A), centeredIn: window.width)
        hex(0xE6E6E6).setFill(); NSRect(x: window.minX, y: window.minY + 38, width: window.width, height: 1).fill()

        let body = NSFont.systemFont(ofSize: 16)
        var y = window.minY + 58
        var lastEnd = CGPoint(x: window.minX + 28, y: y)
        for line in frame.lines {
            let size = text(line, at: CGPoint(x: window.minX + 28, y: y), font: body, color: hex(0x1D1D1F))
            lastEnd = CGPoint(x: window.minX + 28 + size.width + 2, y: y)
            y += 30
        }
        if frame.showCursor {
            hex(0x1D1D1F).setFill()
            NSRect(x: frame.lines.isEmpty ? window.minX + 28 : lastEnd.x, y: lastEnd.y + 2, width: 1.5, height: 20).fill()
        }

        // Caption above the window
        let captionFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        if frame.caption == "hold" {
            let parts = ["Hold", "Right ⌘", "+", "Right ⌥", "and speak"]
            var x: CGFloat = 0
            let widths = parts.map { part -> CGFloat in
                part.hasPrefix("Right") ? NSAttributedString(string: part, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]).size().width + 12
                    : NSAttributedString(string: part, attributes: [.font: captionFont]).size().width
            }
            x = (width - widths.reduce(0, +) - CGFloat(parts.count - 1) * 6) / 2
            for (index, part) in parts.enumerated() {
                if part.hasPrefix("Right") { _ = keycap(part, at: CGPoint(x: x, y: 33)) } else { _ = text(part, at: CGPoint(x: x, y: 35), font: captionFont, color: ink) }
                x += widths[index] + 6
            }
        } else {
            _ = text(frame.caption, at: CGPoint(x: 0, y: 35), font: captionFont, color: ink, centeredIn: width)
        }

        drawHUD(frame.hud)
        return true
    }
    var rect = CGRect(x: 0, y: 0, width: width, height: height)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
}

// MARK: The story: an English sentence, then a mixed Korean–English one.

let first = "Let's move the design review to Thursday and keep the agenda short."
let second = "오늘 standup에서 release checklist 같이 봐요."
var frames: [Frame] = []
func dictate(before: [String], after: [String], seed: Int) {
    frames.append(Frame(lines: before, caption: "hold", delay: 0.9))
    var rng = seed
    for tick in 0..<14 {
        let levels = (0..<9).map { _ -> CGFloat in rng = (rng &* 1103515245 &+ 12345) & 0x7FFFFFFF; return CGFloat(rng % 100) / 100 }
        frames.append(Frame(lines: before, hud: .recording(seconds: 1 + tick / 7, levels: levels), glyph: .recording, caption: "hold", delay: 0.1))
    }
    for step in 0..<6 {
        frames.append(Frame(lines: before, showCursor: false, hud: .working(step: step % 3), glyph: .working, caption: "Let go", delay: 0.12))
    }
    frames.append(Frame(lines: after, hud: .sent, caption: "Pasted at your cursor", delay: 0.9))
    frames.append(Frame(lines: after, caption: "Pasted at your cursor", delay: 1.2))
}
dictate(before: [], after: [first], seed: 7)
dictate(before: [first], after: [first, second], seed: 42)
frames[frames.count - 1].delay = 2.4

let gif = assets.appendingPathComponent("dami-demo.gif")
let destination = CGImageDestinationCreateWithURL(gif as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for frame in frames {
    CGImageDestinationAddImage(destination, render(frame), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frame.delay]] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write \(gif.path)") }

// A still of the paste moment, for checking and for places that don't play GIFs.
let still = NSBitmapImageRep(cgImage: render(Frame(lines: [first, second], hud: .sent, caption: "Pasted at your cursor", delay: 0)))
try still.representation(using: .png, properties: [:])!.write(to: assets.appendingPathComponent("dami-demo-still.png"))

try? FileManager.default.removeItem(at: assets.appendingPathComponent("dami-icon.png"))
try FileManager.default.copyItem(at: URL(fileURLWithPath: "Dami/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png"),
                                 to: assets.appendingPathComponent("dami-icon.png"))
print("Wrote \(frames.count) frames to \(gif.path), a still, and the icon")
