import LocalFlowCore
import SwiftUI

/// Pop-up menu for the language spoken next to English (or none). Used in Settings.
struct SecondLanguagePicker: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Language next to English", selection: $settings.secondLanguage) {
                Text("None, English only").tag(SpokenLanguage?.none)
                ForEach(SpokenLanguage.all) { language in
                    Text(rowTitle(language)).tag(SpokenLanguage?.some(language))
                }
            }
            .pickerStyle(.menu)
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func rowTitle(_ language: SpokenLanguage) -> String {
        let title = "English + \(language.name) (\(language.nativeName))"
        return language.verified ? title : title + " · experimental"
    }

    private var caption: String {
        guard let second = settings.secondLanguage else {
            return "LocalFlow listens for English only."
        }
        let mixed = "Speak English, \(second.name), or both in one sentence."
        return second.verified ? mixed : mixed + " Experimental: not yet tested on real recordings."
    }
}

/// Onboarding's language step: "I speak English and ___", filled in by tapping a pill, with a
/// sample sentence showing that mixing works. Everything keeps its place when the selection
/// changes, so the pills never move under the pointer.
struct LanguageSentencePicker: View {
    @ObservedObject private var settings = AppSettings.shared

    private static let englishSample = "Let's move the meeting to Thursday and send the notes after."
    /// English words used in every language's mixed prompt, highlighted in the sample.
    private static let englishTerms: Set<String> = ["meeting", "project", "timeline", "api", "bug", "sprint", "fix", "fixe"]

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            sentence
            FlowLayout(spacing: 8) {
                ForEach(SpokenLanguage.all) { language in
                    pill(language.nativeName, help: language.name, selected: settings.secondLanguage == language) {
                        settings.secondLanguage = language
                    }
                }
                pill("Just English", help: "English only", selected: settings.secondLanguage == nil, dashed: true) {
                    settings.secondLanguage = nil
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                (Text("Try saying: “") + sample + Text("”"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let second = settings.secondLanguage, !second.verified {
                    Text("Beta: \(second.name) hasn't been tested on real voices yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 72, alignment: .topLeading)
        }
    }

    private var sentence: some View {
        Group {
            if let second = settings.secondLanguage {
                Text("I speak English and ") + Text(second.nativeName).foregroundColor(.accentColor).underline() + Text(".")
            } else {
                Text("I speak English ") + Text("only").foregroundColor(.accentColor).underline() + Text(".")
            }
        }
        .font(.system(size: 30, weight: .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// The sample with the English terms in the accent color (only when mixing).
    private var sample: Text {
        guard let second = settings.secondLanguage else { return Text(Self.englishSample) }
        var result = Text("")
        var word = ""
        func flush() {
            guard !word.isEmpty else { return }
            let isEnglish = Self.englishTerms.contains(word.lowercased())
            result = result + (isEnglish ? Text(word).foregroundColor(.accentColor).fontWeight(.semibold) : Text(word))
            word = ""
        }
        for character in second.mixedPrompt {
            if character.isASCII && character.isLetter {
                word.append(character)
            } else {
                flush()
                result = result + Text(String(character))
            }
        }
        flush()
        return result
    }

    private func pill(_ title: String, help: String, selected: Bool, dashed: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14))
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? Color.white : dashed ? Color.secondary : Color.primary)
                .background(Capsule().fill(selected ? Color.accentColor : Color.clear))
                .overlay(
                    Capsule().strokeBorder(
                        selected ? Color.accentColor : Color(nsColor: .separatorColor),
                        style: StrokeStyle(lineWidth: 1, dash: dashed && !selected ? [4, 3] : [])
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Lays out views left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
