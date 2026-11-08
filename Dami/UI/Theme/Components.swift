import SwiftUI

/// A raised key (spec §6). Primary is the key colour with white text; secondary is paper with an edge; destructive is red text.
struct KeyButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .secondary
    var height: CGFloat = 26
    /// Smaller label and padding, for a key inside the HUD.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        KeyBody(configuration: configuration, kind: kind, height: height, compact: compact)
    }

    private struct KeyBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        let height: CGFloat
        let compact: Bool
        @Environment(\.palette) private var palette
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let pressed = configuration.isPressed && isEnabled
            let raised = kind != .destructive && isEnabled
            let depth = compact ? Theme.Depth.keycap : Theme.Depth.key
            configuration.label
                .font(compact ? Theme.Font.keyLabelSmall : Theme.Font.keyLabel)
                .tracking(Theme.keyLabelTracking)
                .textCase(.uppercase)
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, kind == .destructive ? 6 : (compact ? 7 : 12))
                .frame(height: height)
                .background {
                    if kind != .destructive {
                        RoundedRectangle(cornerRadius: Theme.Radius.key)
                            .fill(fill)
                            .overlay {
                                if kind == .secondary {
                                    RoundedRectangle(cornerRadius: Theme.Radius.key).strokeBorder(Theme.keyEdge)
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.key)
                                    .fill(depthColor)
                                    .offset(y: raised ? (pressed ? Theme.Depth.pressed : depth) : 0)
                            )
                    }
                }
                .offset(y: pressed ? depth - Theme.Depth.pressed : 0)
                .padding(.bottom, raised ? depth : 0)
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.08), value: pressed)
        }

        private var foreground: Color {
            guard isEnabled else { return Theme.onDisabled }
            switch kind {
            case .primary: return Theme.onKey
            case .secondary: return Theme.ink
            case .destructive: return Theme.danger
            }
        }

        private var fill: Color {
            guard isEnabled else { return Theme.disabled }
            return kind == .primary ? palette.key : Theme.keyFace
        }

        private var depthColor: Color {
            kind == .primary ? palette.keyDepth : Theme.keyDepthNeutral
        }
    }
}

extension ButtonStyle where Self == KeyButtonStyle {
    static var primaryKey: KeyButtonStyle { KeyButtonStyle(kind: .primary) }
    static var secondaryKey: KeyButtonStyle { KeyButtonStyle(kind: .secondary) }
    static var destructiveKey: KeyButtonStyle { KeyButtonStyle(kind: .destructive) }
}

/// A key drawn inside text, such as ⌘V or Right ⌥. Not a button.
struct Keycap: View {
    let label: String
    var size: CGFloat = 11

    var body: some View {
        Text(label)
            .font(.system(size: size, design: .monospaced))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, size * 0.45)
            .padding(.vertical, size * 0.12)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.keycap)
                    .fill(Theme.keyFace)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.keycap).strokeBorder(Theme.keyEdge))
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.keycap).fill(Theme.keyDepthNeutral).offset(y: Theme.Depth.keycap)
                    )
            )
            .padding(.bottom, Theme.Depth.keycap)
    }
}

/// Text with known key names (⌘V, Esc) drawn as keycaps, for one-line messages. The wording stays exactly as given.
struct TextWithKeycaps: View {
    let text: String
    var font: Font = Theme.Font.captionMedium
    var color: Color = Theme.ink
    static let keys = ["⌘V", "Esc"]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(Self.segments(text).enumerated()), id: \.offset) { _, segment in
                if segment.isKey {
                    Keycap(label: segment.text, size: 9.5)
                } else {
                    Text(segment.text).font(font).foregroundStyle(color)
                }
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    static func segments(_ text: String) -> [(text: String, isKey: Bool)] {
        var result: [(String, Bool)] = []
        var rest = Substring(text)
        while !rest.isEmpty {
            let hit = keys.compactMap { key -> (Range<Substring.Index>, String)? in
                guard let range = rest.range(of: key), isWholeWord(range, in: rest) else { return nil }
                return (range, key)
            }.min { $0.0.lowerBound < $1.0.lowerBound }
            guard let (range, key) = hit else {
                result.append((String(rest), false))
                break
            }
            let before = rest[rest.startIndex..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            if !before.isEmpty { result.append((before, false)) }
            result.append((key, true))
            rest = rest[range.upperBound...]
            if rest.first == " " { rest = rest.dropFirst() }
        }
        return result
    }

    private static func isWholeWord(_ range: Range<Substring.Index>, in text: Substring) -> Bool {
        let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
        let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
        return !(before?.isLetter ?? false) && !(after?.isLetter ?? false)
    }
}

/// The yellow highlighter behind text.
struct HighlightMark: ViewModifier {
    @Environment(\.palette) private var palette
    var isOn = true

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isOn ? Theme.onHighlight : Theme.ink)
            .padding(.horizontal, isOn ? 2 : 0)
            .background(isOn ? RoundedRectangle(cornerRadius: Theme.Radius.mark).fill(palette.highlight) : nil)
    }
}

extension View {
    func highlighted(_ isOn: Bool = true) -> some View { modifier(HighlightMark(isOn: isOn)) }
}
