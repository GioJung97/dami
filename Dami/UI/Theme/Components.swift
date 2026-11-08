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

        private var foreground: AnyShapeStyle {
            guard isEnabled else { return AnyShapeStyle(Theme.onDisabled) }
            switch kind {
            case .primary: return AnyShapeStyle(Theme.onKey)
            case .secondary: return AnyShapeStyle(Theme.ink)
            case .destructive: return AnyShapeStyle(Theme.danger)
            }
        }

        private var fill: AnyShapeStyle {
            guard isEnabled else { return AnyShapeStyle(Theme.disabled) }
            return kind == .primary ? AnyShapeStyle(palette.key) : AnyShapeStyle(Theme.keyFace)
        }

        private var depthColor: AnyShapeStyle {
            kind == .primary ? AnyShapeStyle(palette.keyDepth) : AnyShapeStyle(Theme.keyDepthNeutral)
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
    var color: ThemeColor = Theme.ink
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
            .foregroundStyle(isOn ? AnyShapeStyle(Theme.onHighlight) : AnyShapeStyle(Theme.ink))
            .padding(.horizontal, isOn ? 2 : 0)
            .background(isOn ? RoundedRectangle(cornerRadius: Theme.Radius.mark).fill(palette.highlight) : nil)
    }
}

extension View {
    func highlighted(_ isOn: Bool = true) -> some View { modifier(HighlightMark(isOn: isOn)) }
}

/// A row of keys where one is chosen, in place of a segmented control (spec §6 "Tab keys").
struct TabKeys<Value: Hashable>: View {
    let label: String
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var width: CGFloat? = nil

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button(option.title) { selection = option.value }
                    .buttonStyle(TabKeyStyle(isOn: option.value == selection, width: width))
                    .accessibilityAddTraits(option.value == selection ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// One tab key. The chosen one is dark and pressed in.
struct TabKeyStyle: ButtonStyle {
    let isOn: Bool
    var width: CGFloat? = nil
    var height: CGFloat = 20

    func makeBody(configuration: Configuration) -> some View {
        let down = isOn || configuration.isPressed
        configuration.label
            .font(Theme.Font.keyLabelSmall)
            .tracking(0.6)
            .textCase(.uppercase)
            .lineLimit(1)
            .foregroundStyle(isOn ? Theme.onSelected : Theme.ink)
            .padding(.horizontal, 8)
            .frame(minWidth: width, minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.keycap)
                    .fill(isOn ? Theme.selected : Theme.keyFace)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.keycap).strokeBorder(isOn ? Theme.selected : Theme.keyEdge))
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.keycap)
                            .fill(Theme.keyDepthNeutral)
                            .offset(y: down ? Theme.Depth.pressed : Theme.Depth.keycap)
                    )
            )
            .offset(y: down ? Theme.Depth.keycap - Theme.Depth.pressed : 0)
            .padding(.bottom, Theme.Depth.keycap)
            .contentShape(Rectangle())
    }
}

/// A square checkbox in ink; filled with the key colour when on.
struct InkCheckboxStyle: ToggleStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(configuration.isOn ? palette.key : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(configuration.isOn ? AnyShapeStyle(palette.key) : AnyShapeStyle(Theme.ink), lineWidth: 1.5))
                    .overlay {
                        if configuration.isOn {
                            Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(Theme.onKey)
                        }
                    }
                    .frame(width: 14, height: 14)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "on" : "off")
    }
}

/// A status dot. Ready and listening use the key colour (listening adds a ring), errors are red, the rest grey. Always shown with a word.
struct StatusDot: View {
    enum Kind { case ready, listening, error, idle }
    let kind: Kind
    @Environment(\.palette) private var palette

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .background(Circle().fill(kind == .listening ? palette.ring : .clear).frame(width: 14, height: 14))
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
    }

    private var color: AnyShapeStyle {
        switch kind {
        case .ready, .listening: AnyShapeStyle(palette.key)
        case .error: AnyShapeStyle(Theme.danger)
        case .idle: AnyShapeStyle(Theme.ink2)
        }
    }
}

/// A 1 pt line in the rule colour.
struct Rule: View {
    var body: some View {
        Rectangle().fill(Theme.rule).frame(height: 1)
    }
}
