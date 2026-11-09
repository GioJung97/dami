import AppKit
import SwiftUI

/// Every colour, font, size and shadow the app draws with (docs/design/spec.md). Views use these, never literal values.
enum Theme {
    // MARK: Colours that follow the theme (spec §3.1 and §3.5). Resolved from the environment when drawn,
    // so a theme change, light/dark and Increase Contrast all apply without the views knowing.

    static let paper = ThemeColor(.paper)
    static let ink = ThemeColor(.ink)
    static let ink2 = ThemeColor(.ink2)
    static let rule = ThemeColor(.rule)
    static let keyFace = ThemeColor(.keyFace)
    static let keyEdge = ThemeColor(.keyEdge)
    static let keyDepthNeutral = ThemeColor(.keyDepth)
    static let selected = ThemeColor(.ink)
    static let onSelected = ThemeColor(.paper)
    static let slip = ThemeColor(.slip)
    static let slipEdge = ThemeColor(.slipEdge)
    static let tape = ThemeColor(.ink)
    static let onTape = ThemeColor(.paper)
    static let track = ThemeColor(.track)
    static let disabled = ThemeColor(.keyEdge)

    // MARK: Colours that are the same on every theme

    static let danger = Color.dynamic(light: 0xA3321F, dark: 0xE88A72)
    static let onDisabled = Color(hex: 0x857C70)
    /// Text on the highlighter, in light and dark mode alike.
    static let onHighlight = Color(hex: 0x1F1B16)
    /// Text on a key-colour fill.
    static let onKey = Color.white
    /// Dims the screen around the menu bar icon during the quick tour.
    static let scrim = Color.black.opacity(0.45)

    // MARK: Type (spec §4)

    enum Font {
        static let pageTitle = SwiftUI.Font.system(size: 36, weight: .semibold, design: .serif)
        static let stepTitle = SwiftUI.Font.system(size: 28, weight: .semibold, design: .serif)
        static let bigStepTitle = SwiftUI.Font.system(size: 32, weight: .semibold, design: .serif)
        static let sectionTitle = SwiftUI.Font.system(size: 18, weight: .semibold, design: .serif)
        static let dayHeader = SwiftUI.Font.system(size: 15, design: .serif).italic()
        static let wordmark = SwiftUI.Font.system(size: 23, weight: .bold, design: .serif)
        static let menuWordmark = SwiftUI.Font.system(size: 16, weight: .semibold, design: .serif)
        static let body = SwiftUI.Font.system(size: 14)
        static let callout = SwiftUI.Font.system(size: 13)
        static let footnote = SwiftUI.Font.system(size: 12)
        static let caption = SwiftUI.Font.system(size: 11)
        static let captionMedium = SwiftUI.Font.system(size: 11, weight: .medium)
        static let keyLabel = SwiftUI.Font.system(size: 10.5, weight: .bold, design: .monospaced)
        static let keyLabelSmall = SwiftUI.Font.system(size: 9.5, weight: .bold, design: .monospaced)
        /// Tabs and buttons: rounded and in sentence case, so the app reads soft rather than formal.
        static let sectionKey = SwiftUI.Font.system(size: 14, design: .rounded)
        static let tabLabel = SwiftUI.Font.system(size: 12.5, design: .rounded)
        static let buttonLabel = SwiftUI.Font.system(size: 12.5, weight: .semibold, design: .rounded)
        static let buttonLabelSmall = SwiftUI.Font.system(size: 11, weight: .semibold, design: .rounded)
        /// Small labels above content ("Quick tour · 1 of 6", "Today", the status).
        static let label = SwiftUI.Font.system(size: 11.5, weight: .semibold, design: .rounded)
        static let mono = SwiftUI.Font.system(size: 11, design: .monospaced)
        static let monoSmall = SwiftUI.Font.system(size: 10.5, design: .monospaced)
        /// The numbers in Home's "Today" panel.
        static let statValue = SwiftUI.Font.system(size: 22, weight: .semibold, design: .rounded)
    }
    /// Letter spacing for `Font.keyLabel` and other uppercase mono labels.
    static let keyLabelTracking: CGFloat = 1

    // MARK: Shape and depth (spec §5)

    enum Radius {
        static let window: CGFloat = 12
        static let menu: CGFloat = 12
        static let card: CGFloat = 12
        static let slip: CGFloat = 10
        static let key: CGFloat = 9
        static let keycap: CGFloat = 6
        static let tape: CGFloat = 4
        static let mark: CGFloat = 2
    }

    enum Depth {
        static let key: CGFloat = 2
        static let keycap: CGFloat = 2
        static let pressed: CGFloat = 1
    }
}

/// The user's key colour (spec §3.2). The icon and onboarding always use `.orange`. The paper comes from `AppTheme`.
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
        case .orange: Palette(key: (0xCC4410, 0xCC4410), depth: 0x8A2C08, highlight: (0xF2D74E, 0xE3C53A))
        case .blue: Palette(key: (0x2F5BD3, 0x426AD7), depth: 0x1E3E99, highlight: (0xF2D74E, 0xE3C53A))
        case .green: Palette(key: (0x2F7D55, 0x2F7E56), depth: 0x1F5639, highlight: (0xF2D74E, 0xE3C53A))
        case .teal: Palette(key: (0x12808A, 0x12808A), depth: 0x0B575E, highlight: (0xFFD966, 0xE8C24A))
        case .plum: Palette(key: (0x7A3E8F, 0x9A52B4), depth: 0x55296A, highlight: (0xF6C1D6, 0xE5A3BF))
        case .graphite: Palette(key: (0x2B2B2B, 0x707070), depth: 0x000000, highlight: (0xA8E6CF, 0x86D4B4))
        case .rose: Palette(key: (0xB03A5B, 0xC14366), depth: 0x7A2540, highlight: (0xFFD3B0, 0xF0B98F))
        case .ochre: Palette(key: (0x8A6100, 0x946800), depth: 0x5C4100, highlight: (0xF5E68A, 0xE0CF6C))
        }
    }
}

/// The colours that follow the user's key colour.
struct Palette {
    let key: Color
    let keyDepth: Color
    let highlight: Color
    /// The key colour at 30%, for the ring around the dot while listening.
    let ring: Color

    init(key: (light: UInt32, dark: UInt32), depth: UInt32, highlight: (light: UInt32, dark: UInt32)) {
        self.key = .dynamic(light: key.light, dark: key.dark)
        keyDepth = .dynamic(light: depth, dark: 0x000000)
        self.highlight = .dynamic(light: highlight.light, dark: highlight.dark)
        ring = .dynamic(light: key.light, dark: key.dark, lightAlpha: 0.3, darkAlpha: 0.3)
    }

    static let standard = KeyColor.orange.palette
}

/// The user's theme (spec §3.5, D6): paper, cards, ink and lines, in light and dark. Onboarding always uses `.cream`.
enum AppTheme: String, CaseIterable, Identifiable {
    case cream, white, stone, sepia, sage, mist, blush
    var id: String { rawValue }

    var name: String { rawValue.capitalized }

    struct Tokens {
        let paper, keyFace, ink, ink2, rule, keyEdge: UInt32
    }

    var light: Tokens {
        switch self {
        case .cream: Tokens(paper: 0xF6F1E7, keyFace: 0xFFFDF8, ink: 0x1F1B16, ink2: 0x685F54, rule: 0xDCD2C1, keyEdge: 0xD6CCBA)
        case .white: Tokens(paper: 0xFAFAF8, keyFace: 0xFFFFFF, ink: 0x1A1A1A, ink2: 0x5F5F63, rule: 0xE3E3E0, keyEdge: 0xD9D9D6)
        case .stone: Tokens(paper: 0xECEBE8, keyFace: 0xF8F7F5, ink: 0x1E1E1C, ink2: 0x5C5B57, rule: 0xD4D2CD, keyEdge: 0xC9C7C1)
        case .sepia: Tokens(paper: 0xEFE3CC, keyFace: 0xFAF3E4, ink: 0x2B1F12, ink2: 0x6B5843, rule: 0xD9C8A8, keyEdge: 0xCDB991)
        case .sage: Tokens(paper: 0xEEF1E8, keyFace: 0xFAFBF6, ink: 0x1C211B, ink2: 0x5A6356, rule: 0xD3DACB, keyEdge: 0xC8D0BF)
        case .mist: Tokens(paper: 0xEEF1F5, keyFace: 0xFBFCFE, ink: 0x1A1F27, ink2: 0x576070, rule: 0xD5DBE4, keyEdge: 0xC9D0DB)
        case .blush: Tokens(paper: 0xF6EEEC, keyFace: 0xFFFAF9, ink: 0x241A19, ink2: 0x6A5755, rule: 0xE2D3D0, keyEdge: 0xD8C6C2)
        }
    }

    var dark: Tokens {
        switch self {
        case .cream: Tokens(paper: 0x1C1A17, keyFace: 0x2A2723, ink: 0xEDE6D8, ink2: 0xA69D8E, rule: 0x36322C, keyEdge: 0x3E3934)
        case .white: Tokens(paper: 0x161617, keyFace: 0x242426, ink: 0xEDEDED, ink2: 0xA1A1A6, rule: 0x323234, keyEdge: 0x3A3A3D)
        case .stone: Tokens(paper: 0x19191B, keyFace: 0x252629, ink: 0xE6E6E3, ink2: 0xA0A09B, rule: 0x37383B, keyEdge: 0x434447)
        case .sepia: Tokens(paper: 0x1F1912, keyFace: 0x2C241A, ink: 0xEFE2CB, ink2: 0xB09D80, rule: 0x3B3125, keyEdge: 0x4A3E2F)
        case .sage: Tokens(paper: 0x171B17, keyFace: 0x232823, ink: 0xE3E9DF, ink2: 0x9DA898, rule: 0x303730, keyEdge: 0x3B433B)
        case .mist: Tokens(paper: 0x141820, keyFace: 0x1F2430, ink: 0xE4E8EF, ink2: 0x9AA3B2, rule: 0x2C3240, keyEdge: 0x39404F)
        case .blush: Tokens(paper: 0x1D1717, keyFace: 0x2A2222, ink: 0xEEE2E0, ink2: 0xA99896, rule: 0x3A3030, keyEdge: 0x473B3A)
        }
    }
}

/// A colour that follows the theme in the environment, light/dark and Increase Contrast.
struct ThemeColor: ShapeStyle {
    enum Role { case paper, keyFace, ink, ink2, rule, keyEdge, keyDepth, slip, slipEdge, track }
    let role: Role
    init(_ role: Role) { self.role = role }

    func resolve(in environment: EnvironmentValues) -> Color {
        let dark = environment.colorScheme == .dark
        let highContrast = environment.colorSchemeContrast == .increased
        return Self.color(role, theme: environment.appTheme, dark: dark, highContrast: highContrast)
    }

    static func color(_ role: Role, theme: AppTheme, dark: Bool, highContrast: Bool) -> Color {
        let t = dark ? theme.dark : theme.light
        switch role {
        case .paper: return Color(hex: t.paper)
        case .keyFace: return Color(hex: t.keyFace)
        case .ink: return Color(hex: t.ink)
        case .ink2: return Color(hex: highContrast ? t.ink : t.ink2)
        case .rule: return highContrast ? Color(hex: t.ink, alpha: 0.6) : Color(hex: t.rule)
        case .keyEdge: return highContrast ? Color(hex: t.ink, alpha: 0.6) : Color(hex: t.keyEdge)
        case .keyDepth: return dark ? Color(hex: 0x0E0D0B) : Color(hex: t.keyEdge)
        case .slip:
            if theme == .cream && !dark { return Color(hex: 0xFBF7EE) }
            return Color(hex: t.keyFace)
        case .slipEdge: return Color(hex: t.ink, alpha: highContrast ? 0.6 : (dark ? 0.18 : 0.24))
        case .track:
            if dark { return Color(hex: 0x10120E) }
            return theme == .cream ? Color(hex: 0xE6DECF) : Color(hex: t.rule)
        }
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.cream
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

    /// Set next to `palette` from `AppSettings.theme`.
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
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
