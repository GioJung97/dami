import AVFoundation
import LocalFlowCore
import SwiftUI

struct HistoryView: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var search = ""
    @State private var filter = "ALL"
    @State private var selection: Dictation.ID?
    /// What the current search and filter found so far. More loads while scrolling.
    @State private var items: [Dictation] = []
    @State private var hasMore = false

    private static let pageSize = 200


    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                PageHeader(title: "History")
                Spacer()
                TextField("Search dictations", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
            Picker("Language", selection: $filter) {
                ForEach(filters, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)

            if settings.retentionDays < 0 {
                Text("History is off (Settings › Privacy).").foregroundStyle(.secondary)
            }

            HSplitView {
                List(selection: $selection) {
                    ForEach(groupedByDay, id: \.day) { group in
                        Section(group.day) {
                            ForEach(group.items) { item in
                                HistoryRow(dictation: item)
                                    .tag(item.id)
                                    .onAppear { if item.id == items.last?.id { loadMore() } }
                            }
                        }
                    }
                }
                .frame(minWidth: 300, idealWidth: 360)

                Group {
                    if let selected {
                        HistoryDetail(dictation: selected)
                    } else {
                        Text(items.isEmpty ? "No dictations" : "Select a dictation")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(28)
        .onAppear {
            reload()
            if selection == nil { selection = items.first?.id }
        }
        .onChange(of: search) { reload() }
        .onChange(of: filter) { reload() }
        .onChange(of: store.revision) { reload() }
    }

    private var filters: [(String, String)] {
        var filters = [("ALL", "All"), ("EN", "English")]
        if let second = settings.secondLanguage {
            filters.append((second.label, second.name))
            if second.script != nil { filters.append(("MIXED", "Mixed")) }
        }
        return filters
    }

    private var query: Store.HistoryQuery {
        let language: Store.LanguageFilter
        if let second = settings.secondLanguage, filter == second.label {
            language = .language(second.code, excludingMixed: second.script != nil)
        } else if let second = settings.secondLanguage, filter == "MIXED" {
            language = .mixed(second.code)
        } else {
            language = filter == "EN" ? .english : .all
        }
        return Store.HistoryQuery(search: search, language: language)
    }

    /// Queries again, keeping as many rows as are showing so the list doesn't jump.
    private func reload() {
        let limit = max(Self.pageSize, items.count)
        items = store.history(query, limit: limit)
        hasMore = items.count == limit
    }

    private func loadMore() {
        guard hasMore else { return }
        let page = store.history(query, limit: Self.pageSize, offset: items.count)
        items += page
        hasMore = page.count == Self.pageSize
    }

    private var selected: Dictation? {
        items.first { $0.id == selection }
    }

    private var groupedByDay: [(day: String, items: [Dictation])] {
        let calendar = Calendar.current
        var groups: [(day: String, items: [Dictation])] = []
        for item in items {
            let day: String
            if calendar.isDateInToday(item.createdAt) {
                day = "Today"
            } else if calendar.isDateInYesterday(item.createdAt) {
                day = "Yesterday"
            } else {
                day = item.createdAt.formatted(date: .abbreviated, time: .omitted)
            }
            if groups.last?.day == day {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append((day, [item]))
            }
        }
        return groups
    }
}

private struct HistoryRow: View {
    let dictation: Dictation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(dictation.createdAt.formatted(date: .omitted, time: .shortened))
                Text("·")
                Text(dictation.appName ?? "Unknown app")
                Spacer()
                LanguageTag(label: dictation.languageLabel)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            Text(dictation.finalText).font(.system(size: 13)).lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

private struct HistoryDetail: View {
    let dictation: Dictation
    @State private var newTerm = ""
    @State private var addingTerm = false
    @State private var player: AVAudioPlayer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 6) {
                    Text(dictation.appName ?? "Unknown app").fontWeight(.semibold)
                    Text("·")
                    Text(dictation.createdAt.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(String(format: "%.1f s of speech", dictation.audioSeconds))
                    LanguageTag(label: dictation.languageLabel)
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("PASTED TEXT").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    Text(dictation.finalText).font(.system(size: 16)).textSelection(.enabled)
                }

                if dictation.rawText != dictation.finalText {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("WHAT WHISPER HEARD").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        Text(dictation.rawText).font(.system(size: 13)).textSelection(.enabled)
                        if let note = dictation.note {
                            Text(note).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                }

                HStack {
                    Button("Copy") { TextInserter.copy(dictation.finalText) }
                        .buttonStyle(.borderedProminent)
                    Button("Add a word to Dictionary…") { addingTerm = true }
                    if let url = audioURL {
                        Button(player?.isPlaying == true ? "Stop" : "Play audio") { togglePlayback(url) }
                    }
                    Spacer()
                    Button("Delete", role: .destructive) { Store.shared.delete(dictation) }
                }
                Text(String(format: "Transcribed in %.2f s", dictation.latencySeconds))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
        .sheet(isPresented: $addingTerm) {
            AddTermSheet(term: $newTerm) { Store.shared.addTerm(newTerm); newTerm = "" }
        }
    }

    private var audioURL: URL? {
        guard let id = dictation.id else { return nil }
        let url = Store.shared.audioURL(for: id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func togglePlayback(_ url: URL) {
        if player?.isPlaying == true {
            player?.stop()
            player = nil
        } else {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.play()
        }
    }
}

struct AddTermSheet: View {
    @Binding var term: String
    let onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add to Dictionary").font(.headline)
            Text("A name or term LocalFlow should always spell this way.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("e.g. Supabase, Tailwind", text: $term)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            SecondScriptTermHint(term: term)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add", action: add)
                    .buttonStyle(.borderedProminent)
                    .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func add() {
        onAdd()
        dismiss()
    }
}
