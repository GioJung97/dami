// Draws the Dami app icon into Dami/Assets.xcassets/AppIcon.appiconset (design spec §7 "App icon").
// The shapes mirror Dami/UI/Theme/DamiMark.swift; change both together.
//
// Usage: swift scripts/make-icon.swift   (from the repo root)
import AppKit

let out = URL(fileURLWithPath: "Dami/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// One icon image, `pixels` wide. Small sizes get a slightly heavier quote mark so it stays readable.
func render(pixels: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(pixels) / 1024
    // Flip to the drawing's top-left coordinates.
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: s, y: -s)

    let squircle = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 22, color: color(0x000000, 0.28))
    ctx.addPath(squircle); ctx.setFillColor(color(0xF6F1E7)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(squircle); ctx.setStrokeColor(color(0x1F1B16, 0.10)); ctx.setLineWidth(2); ctx.strokePath()

    let heavy: CGFloat = pixels <= 64 ? 1.14 : 1
    ctx.setFillColor(color(0x1F1B16))
    for dx in [CGFloat(0), 184] {
        ctx.saveGState()
        ctx.translateBy(x: 390 + dx, y: 430)
        ctx.scaleBy(x: heavy, y: heavy)
        ctx.translateBy(x: -(390 + dx), y: -430)
        ctx.fillEllipse(in: CGRect(x: 324 + dx, y: 324, width: 132, height: 132))
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: 456 + dx, y: 390))
        tail.addCurve(to: CGPoint(x: 344 + dx, y: 544), control1: CGPoint(x: 456 + dx, y: 472), control2: CGPoint(x: 410 + dx, y: 524))
        tail.addLine(to: CGPoint(x: 337 + dx, y: 509))
        tail.addCurve(to: CGPoint(x: 399 + dx, y: 429), control1: CGPoint(x: 377 + dx, y: 491), control2: CGPoint(x: 399 + dx, y: 462))
        tail.closeSubpath()
        ctx.addPath(tail); ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.translateBy(x: 415, y: 664)
    ctx.rotate(by: -2 * .pi / 180)
    ctx.addPath(CGPath(roundedRect: CGRect(x: -165, y: -24, width: 330, height: 48), cornerWidth: 8, cornerHeight: 8, transform: nil))
    ctx.setFillColor(color(0xF2D74E)); ctx.fillPath()
    ctx.restoreGState()

    ctx.setFillColor(color(0xB83A0E)); ctx.fillEllipse(in: CGRect(x: 630, y: 608, width: 164, height: 164))
    ctx.setFillColor(color(0xFF5A1F)); ctx.fillEllipse(in: CGRect(x: 630, y: 600, width: 164, height: 164))

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

var images: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: points * scale).write(to: out.appendingPathComponent(name))
        images.append("""
            { "idiom" : "mac", "size" : "\(points)x\(points)", "scale" : "\(scale)x", "filename" : "\(name)" }
        """)
    }
}
let contents = "{\n  \"images\" : [\n" + images.joined(separator: ",\n") + "\n  ],\n  \"info\" : { \"version\" : 1, \"author\" : \"xcode\" }\n}\n"
try contents.write(to: out.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(images.count) icon images to \(out.path)")
