import SwiftUI

struct HomeView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var store = Store.shared
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject private var navigation: Navigation

    var body: some View {
        let stats = store.todayStats()
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: greeting, subtitle: "Hold \(settings.shortcut.displayName) in any app, speak, and let go.")

                VStack(alignment: .leading, spacing: 10) {
                    Text("Today").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    Grid(horizontalSpacing: 12) {
                        GridRow {
                            stat("Words dictated", stats.words.formatted())
                            stat("Time saved vs. typing", "\(Int(stats.minutesSaved.rounded())) min")
                            stat("Average speed", stats.averageLatency.map { String(format: "%.1f s", $0) } ?? "–")
                            stat("Day streak", "\(stats.streakDays)")
                        }
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    Card {
                        Text("Learned from your edits").font(.system(size: 15, weight: .semibold))
                        Text("When you fix a word right after LocalFlow pastes it, it will suggest adding it to your Dictionary here, so it's right next time.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Coming in a later update.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Card {
                        HStack {
                            Text("Recent").font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Button("View all") { navigation.section = .history }
                                .buttonStyle(.link)
                        }
                        if store.dictations.isEmpty {
                            Text("Nothing yet. Hold the shortcut and say something.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(store.dictations.prefix(4)) { dictation in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(dictation.appName ?? "Unknown app")
                                    Text("·")
                                    Text(dictation.createdAt.formatted(date: .omitted, time: .shortened))
                                    Spacer()
                                    LanguageTag(label: dictation.languageLabel)
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                Text(dictation.finalText).font(.system(size: 13)).lineLimit(1)
                            }
                            .padding(.top, 6)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        Card {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .bold))
        }
    }
}
