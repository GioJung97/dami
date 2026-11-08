import AppKit
import SwiftUI

/// Every colour, font, size and shadow the app draws with (docs/design/spec.md). Views use these, never literal values.
enum Theme {
    // MARK: Base colours (spec §3.1). Light, dark, and an optional Increase Contrast value for each.

    // `paper` follows the key colour, so it lives in `Palette`.
    static let ink = Color.dynamic(light: 0x1F1B16, dark: 0xEDE6D8)
    static let ink2 = Color.dynamic(light: 0x685F54, dark: 0xA69D8E, highContrastLight: 0x1F1B16, highContrastDark: 0xEDE6D8)
    static let rule = Color.dynamic(light: 0xDCD2C1, dark: 0x36322C, highContrastLight: 0x79736B, highContrastDark: 0x969089)
    static let keyFace = Color.dynamic(light: 0xFFFDF8, dark: 0x2A2723)
    static let keyEdge = Color.dynamic(light: 0xD6CCBA, dark: 0x3E3934, highContrastLight: 0x79736B, highContrastDark: 0x969089)
    static let keyDepthNeutral = Color.dynamic(light: 0xD6CCBA, dark: 0x0E0D0B)
    static let selected = Color.dynamic(light: 0x1F1B16, dark: 0xEDE6D8)
    static let onSelected = Color.dynamic(light: 0xF6F1E7, dark: 0x1C1A17)
    static let danger = Color.dynamic(light: 0xA3321F, dark: 0xE88A72)
    static let lcd = Color.dynamic(light: 0x262A24, dark: 0x10120E)
    static let lcdText = Color(hex: 0xDDE8B5)
    static let lcdLabel = Color(hex: 0x9FAE7A)
    static let slip = Color.dynamic(light: 0xFBF7EE, dark: 0x2A2723)
    static let slipEdge = Color.dynamic(light: 0x1F1B16, dark: 0xEDE6D8, lightAlpha: 0.24, darkAlpha: 0.18, highContrastAlpha: 0.6)
    static let tape = Color.dynamic(light: 0x1F1B16, dark: 0xEDE6D8)
    static let onTape = Color.dynamic(light: 0xF6F1E7, dark: 0x1C1A17)
    static let track = Color.dynamic(light: 0xE6DECF, dark: 0x10120E)
    static let disabled = Color.dynamic(light: 0xD6CCBA, dark: 0x3E3934)
    static let onDisabled = Color(hex: 0x857C70)
    /// Text on the highlighter, in light and dark mode alike.
    static let onHighlight = Color(hex: 0x1F1B16)
    /// Text on a key-colour fill.
    static let onKey = Color.white

    // MARK: Type (spec §4)

    enum Font {
        static let pageTitle = SwiftUI.Font.system(size: 36, weight: .semibold, design: .serif)
        static let stepTitle = SwiftUI.Font.system(size: 28, weight: .semibold, design: .serif)
        static let bigStepTitle = SwiftUI.Font.system(size: 32, weight: .semibold, design: .serif)
        static let sectionTitle = SwiftUI.Font.system(size: 18, weight: .semibold, design: .serif)
        static let dayHeader = SwiftUI.Font.system(size: 15, design: .serif).italic()
        static let wordmark = SwiftUI.Font.system(size: 19, weight: .bold, design: .serif)
        static let menuWordmark = SwiftUI.Font.system(size: 16, weight: .semibold, design: .serif)
        static let body = SwiftUI.Font.system(size: 14)
        static let callout = SwiftUI.Font.system(size: 13)
        static let footnote = SwiftUI.Font.system(size: 12)
        static let caption = SwiftUI.Font.system(size: 11)
        static let captionMedium = SwiftUI.Font.system(size: 11, weight: .medium)
        static let keyLabel = SwiftUI.Font.system(size: 10.5, weight: .bold, design: .monospaced)
        static let keyLabelSmall = SwiftUI.Font.system(size: 9.5, weight: .bold, design: .monospaced)
        static let mono = SwiftUI.Font.system(size: 11, design: .monospaced)
        static let monoSmall = SwiftUI.Font.system(size: 10.5, design: .monospaced)
        static let lcdValue = SwiftUI.Font.system(size: 18, weight: .bold, design: .monospaced)
        static let lcdLabel = SwiftUI.Font.system(size: 9, design: .monospaced)
    }
    /// Letter spacing for `Font.keyLabel` and other uppercase mono labels.
    static let keyLabelTracking: CGFloat = 1

    // MARK: Shape and depth (spec §5)

    enum Radius {
        static let window: CGFloat = 12
        static let menu: CGFloat = 10
        static let card: CGFloat = 8
        static let slip: CGFloat = 7
        static let key: CGFloat = 6
        static let keycap: CGFloat = 4
        static let tape: CGFloat = 4
        static let mark: CGFloat = 2
    }

    enum Depth {
        static let key: CGFloat = 3
        static let keycap: CGFloat = 2
        static let pressed: CGFloat = 1
    }
}

/// The user's key colour (spec §3.2). The icon and onboarding always use `.orange`.
enum KeyColor: String, CaseIterable, Identifiable {
    case orange, blue, green, teal, plum, graphite, rose, ochre
    var id: String { rawValue }

    var name: String {
        switch self {
        case .orange: "Orange"
        case .blue: "Ink blue"
        case .green: "Forest"
        case .teal: "Teal"
        case .plum: "Plum"
        case .graphite: "Graphite"
        case .rose: "Rose"
        case .ochre: "Ochre"
        }
    }

    var palette: Palette {
        switch self {
        case .orange: Palette(key: (0xCC4410, 0xCC4410), depth: 0x8A2C08, highlight: (0xF2D74E, 0xE3C53A), paper: 0xF6F1E7)
        case .blue: Palette(key: (0x2F5BD3, 0x426AD7), depth: 0x1E3E99, highlight: (0xF2D74E, 0xE3C53A), paper: 0xF5F2EA)
        case .green: Palette(key: (0x2F7D55, 0x2F7E56), depth: 0x1F5639, highlight: (0xF2D74E, 0xE3C53A), paper: 0xF3F1E8)
        case .teal: Palette(key: (0x12808A, 0x12808A), depth: 0x0B575E, highlight: (0xFFD966, 0xE8C24A), paper: 0xF4F2EB)
        case .plum: Palette(key: (0x7A3E8F, 0x9A52B4), depth: 0x55296A, highlight: (0xF6C1D6, 0xE5A3BF), paper: 0xF7F2EE)
        case .graphite: Palette(key: (0x2B2B2B, 0x707070), depth: 0x000000, highlight: (0xA8E6CF, 0x86D4B4), paper: 0xF3F3F0)
        case .rose: Palette(key: (0xB03A5B, 0xC14366), depth: 0x7A2540, highlight: (0xFFD3B0, 0xF0B98F), paper: 0xF8F1EE)
        case .ochre: Palette(key: (0x8A6100, 0x946800), depth: 0x5C4100, highlight: (0xF5E68A, 0xE0CF6C), paper: 0xF6F2E6)
        }
    }
}

/// The colours that follow the user's key colour.
struct Palette {
    let key: Color
    let keyDepth: Color
    let highlight: Color
    let paper: Color
    /// The key colour at 30%, for the ring around the dot while listening.
    let ring: Color

    init(key: (light: UInt32, dark: UInt32), depth: UInt32, highlight: (light: UInt32, dark: UInt32), paper: UInt32) {
        self.key = .dynamic(light: key.light, dark: key.dark)
        keyDepth = .dynamic(light: depth, dark: 0x000000)
        self.highlight = .dynamic(light: highlight.light, dark: highlight.dark)
        self.paper = .dynamic(light: paper, dark: 0x1C1A17)
        ring = .dynamic(light: key.light, dark: key.dark, lightAlpha: 0.3, darkAlpha: 0.3)
    }

    static let standard = KeyColor.orange.palette
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.standard
}

extension EnvironmentValues {
    /// Set once at the top of each window, panel and HUD from `AppSettings.keyColor`.
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(nsColor: NSColor(hex: hex, alpha: alpha))
    }

    /// Follows light and dark mode, and Increase Contrast when a value is given for it.
    static func dynamic(
        light: UInt32, dark: UInt32,
        highContrastLight: UInt32? = nil, highContrastDark: UInt32? = nil,
        lightAlpha: Double = 1, darkAlpha: Double = 1, highContrastAlpha: Double? = nil
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            switch match {
            case .accessibilityHighContrastDarkAqua:
                return NSColor(hex: highContrastDark ?? dark, alpha: highContrastAlpha ?? darkAlpha)
            case .accessibilityHighContrastAqua:
                return NSColor(hex: highContrastLight ?? light, alpha: highContrastAlpha ?? lightAlpha)
            case .darkAqua:
                return NSColor(hex: dark, alpha: darkAlpha)
            default:
                return NSColor(hex: light, alpha: lightAlpha)
            }
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
