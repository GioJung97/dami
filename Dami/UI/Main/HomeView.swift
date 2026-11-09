import SwiftUI

struct HomeView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var store = Store.shared
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject private var navigation: Navigation

    @Environment(\.palette) private var palette

    var body: some View {
        let stats = store.todayStats()
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: greeting, subtitle: "Hold \(settings.shortcut.displayName) in any app, speak, and let go.")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Today").font(Theme.Font.label).foregroundStyle(Theme.ink2)
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 4) {
                        GridRow {
                            stat("Words dictated", stats.words.formatted())
                            stat("Time saved vs. typing", "\(Int(stats.minutesSaved.rounded())) min")
                            stat("Average speed", stats.averageLatency.map { String(format: "%.1f s", $0) } ?? "–")
                            stat("Day streak", "\(stats.streakDays)")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(palette.key.opacity(0.10)))
                    .accessibilityElement(children: .contain)
                }

                HStack(alignment: .top, spacing: 16) {
                    Card {
                        Text("Learned from your edits").font(Theme.Font.sectionTitle)
                        Text("Fix a dictation in History, or right where it was pasted, and Dami suggests a Replacement so it's right next time. Nothing changes until you approve it.")
                            .font(Theme.Font.footnote)
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        if pendingSuggestions > 0 {
                            Button {
                                navigation.requestedDictionaryTab = DictionaryView.Tab.suggestions.rawValue
                                navigation.section = .dictionary
                            } label: {
                                Text(pendingSuggestions == 1 ? "1 suggestion waiting" : "\(pendingSuggestions) suggestions waiting")
                                    .underline()
                                    .font(Theme.Font.footnote.weight(.medium))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("No suggestions waiting.")
                                .font(Theme.Font.footnote.weight(.medium))
                                .foregroundStyle(Theme.ink2)
                        }
                    }

                    Card {
                        HStack {
                            Text("Recent").font(Theme.Font.sectionTitle)
                            Spacer()
                            Button { navigation.section = .history } label: {
                                Text("View all").underline().font(Theme.Font.footnote)
                            }
                            .buttonStyle(.plain)
                        }
                        if store.dictations.isEmpty {
                            Text("Nothing yet. Hold the shortcut and say something.")
                                .font(Theme.Font.footnote)
                                .foregroundStyle(Theme.ink2)
                        }
                        ForEach(Array(store.dictations.prefix(4).enumerated()), id: \.element.id) { index, dictation in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(dictation.appName ?? "Unknown app")
                                    Text("·")
                                    Text(dictation.createdAt.formatted(date: .omitted, time: .shortened)).font(Theme.Font.mono)
                                    Spacer()
                                    LanguageTag(label: dictation.languageLabel)
                                }
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.ink2)
                                Text(dictation.displayText).font(Theme.Font.callout).lineLimit(1).highlighted(index == 0)
                            }
                            .padding(.top, 6)
                        }
                    }
                }
            }
            .padding(.horizontal, 52)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pendingSuggestions: Int { store.suggestions.filter { $0.status == .pending }.count }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    /// One number in today's panel.
    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.Font.statValue).foregroundStyle(Theme.ink)
            Text(label).font(Theme.Font.footnote).foregroundStyle(Theme.ink2)
        }
        .accessibilityElement(children: .combine)
    }
}
