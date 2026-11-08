import AVFoundation
import DamiCore
import SwiftUI

struct HistoryView: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var navigation = Navigation.shared
    /// Opened from the menu's pencil: show this dictation's fix box.
    @State private var fixing: Dictation.ID?
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
            TabKeys(label: "Language", options: filters.map { ($0.0, $0.1) }, selection: $filter, width: 64)

            if settings.retentionDays < 0 {
                Text("History is off (Settings › Privacy).").foregroundStyle(Theme.ink2)
            }

            HSplitView {
                List(selection: $selection) {
                    ForEach(groupedByDay, id: \.day) { group in
                        Section {
                            ForEach(group.items) { item in
                                HistoryRow(dictation: item)
                                    .tag(item.id)
                                    .onAppear { if item.id == items.last?.id { loadMore() } }
                            }
                        } header: {
                            Text(group.day).font(Theme.Font.dayHeader).foregroundStyle(Theme.ink2)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .frame(minWidth: 300, idealWidth: 360)

                Group {
                    if let selected {
                        HistoryDetail(dictation: selected, startFixing: fixing == selected.id)
                            .id(selected.id)
                    } else {
                        Text(items.isEmpty ? "No dictations" : "Select a dictation")
                            .foregroundStyle(Theme.ink2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 52)
        .padding(.top, 26)
        .padding(.bottom, 22)
        .onAppear {
            reload()
            if selection == nil { selection = items.first?.id }
            openRequestedFix()
        }
        .onChange(of: navigation.requestedFix) { openRequestedFix() }
        .onChange(of: selection) { if selection != fixing { fixing = nil } }
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

    /// Shows everything so the requested dictation is in the list, then selects it with the fix box open.
    private func openRequestedFix() {
        guard let id = navigation.requestedFix else { return }
        navigation.requestedFix = nil
        search = ""
        filter = "ALL"
        reload()
        fixing = id
        selection = id
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
                Text(dictation.createdAt.formatted(date: .omitted, time: .shortened)).font(Theme.Font.mono)
                Text("·")
                Text(dictation.appName ?? "Unknown app")
                Spacer()
                LanguageTag(label: dictation.languageLabel)
            }
            .font(Theme.Font.caption)
            .opacity(0.85)
            Text(dictation.displayText).font(Theme.Font.callout).lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

private struct HistoryDetail: View {
    let dictation: Dictation
    @State private var newTerm = ""
    @State private var addingTerm = false
    @State private var fixing: Bool
    @State private var draft: String
    /// Offered after a fix, until answered.
    @State private var suggestion: Suggestion?
    @ObservedObject private var store = Store.shared
    @Environment(\.palette) private var palette
    @FocusState private var draftFocused: Bool
    @StateObject private var playback = AudioPlayback()

    init(dictation: Dictation, startFixing: Bool) {
        self.dictation = dictation
        _fixing = State(initialValue: startFixing)
        _draft = State(initialValue: dictation.displayText)
    }

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
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.ink2)

                if fixing {
                    fixBox
                } else if let fixed = dictation.fixedText {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("FIXED TEXT")
                        Text(fixed).font(.system(size: 16)).textSelection(.enabled)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        sectionLabel("PASTED TEXT")
                        Text(dictation.finalText).font(Theme.Font.footnote).foregroundStyle(Theme.ink2).textSelection(.enabled)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("PASTED TEXT")
                        Text(dictation.finalText).font(.system(size: 16)).textSelection(.enabled)
                    }
                }

                if let suggestion, store.suggestions.contains(where: { $0.id == suggestion.id && $0.status == .pending }) {
                    SuggestionBox(suggestion: suggestion)
                }

                if dictation.rawText != dictation.finalText {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("WHAT WHISPER HEARD")
                        Text(dictation.rawText).font(Theme.Font.callout).textSelection(.enabled)
                        if let note = dictation.note {
                            Text(note).font(Theme.Font.footnote).foregroundStyle(Theme.ink2)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.keyFace))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.keyEdge))
                }

                HStack(spacing: 8) {
                    Button("Copy") { TextInserter.copy(dictation.displayText) }
                        .buttonStyle(.secondaryKey)
                    Button("Fix…") { startFixing() }
                        .buttonStyle(.primaryKey)
                        .disabled(fixing)
                    Button("Add a word to Dictionary…") { addingTerm = true }
                        .buttonStyle(.secondaryKey)
                    if let url = audioURL {
                        Button(playback.isPlaying ? "Stop" : "Play audio") { playback.toggle(url) }
                            .buttonStyle(.secondaryKey)
                    }
                    Spacer()
                    Button("Delete", role: .destructive) { Store.shared.delete(dictation) }
                        .buttonStyle(.destructiveKey)
                }
                if audioURL != nil {
                    confirmRow
                }
                Text(String(format: "Transcribed in %.2f s", dictation.latencySeconds))
                    .font(Theme.Font.mono)
                    .foregroundStyle(Theme.ink2)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.keyEdge))
        .sheet(isPresented: $addingTerm) {
            AddTermSheet(term: $newTerm) { Store.shared.addTerm(newTerm); newTerm = "" }
        }
        .onAppear { if fixing { draftFocused = true } }
    }

    private var fixBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("FIX THE TEXT")
            TextEditor(text: $draft)
                .font(.system(size: 15))
                .frame(minHeight: 80, maxHeight: 200)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.key).fill(Theme.keyFace))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.key).strokeBorder(palette.key, lineWidth: 1.5))
                .focused($draftFocused)
            HStack {
                Text("What was pasted stays as it was. Dami keeps this fix to learn from.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.ink2)
                Spacer()
                Button("Cancel") { fixing = false }
                    .buttonStyle(.secondaryKey)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let before = dictation.displayText
                    if Store.shared.fix(dictation, to: draft) {
                        suggestion = Store.shared.suggestion(fromFix: before, to: draft.trimmingCharacters(in: .whitespacesAndNewlines), dictation: dictation)
                    }
                    fixing = false
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.primaryKey)
                .disabled(FixText.normalized(draft, replacing: dictation.displayText) == nil)
            }
        }
    }

    /// "This is what I said": only with saved audio, since the mark exists to keep that pair.
    private var confirmRow: some View {
        HStack(spacing: 8) {
            if dictation.isConfirmed {
                Label("Marked as what you said", systemImage: "checkmark.seal.fill")
                    .font(Theme.Font.footnote.weight(.semibold))
                    .highlighted()
                Text("Kept with its audio until you unmark or delete it.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.ink2)
                Spacer()
                Button("Unmark") { Store.shared.setConfirmed(dictation, false) }
                    .buttonStyle(.secondaryKey)
            } else {
                Button("This is what I said") { Store.shared.setConfirmed(dictation, true) }
                    .buttonStyle(.secondaryKey)
                    .help("Marks this text as exactly what you said, and keeps the audio with it until you unmark it.")
                Text("Fix the text first if it's wrong.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.ink2)
                Spacer()
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(Theme.Font.keyLabel).tracking(Theme.keyLabelTracking).foregroundStyle(Theme.ink2)
    }

    private func startFixing() {
        draft = dictation.displayText
        fixing = true
        draftFocused = true
    }

    private var audioURL: URL? {
        guard let id = dictation.id else { return nil }
        let url = Store.shared.audioURL(for: id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

}

/// Plays one saved recording and says when it's over, so the button can follow.
@MainActor
private final class AudioPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    private var player: AVAudioPlayer?

    func toggle(_ url: URL) {
        if isPlaying {
            finish()
        } else {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            isPlaying = player?.play() ?? false
        }
    }

    private func finish() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.finish() }
    }
}

struct AddTermSheet: View {
    @Binding var term: String
    let onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add to Dictionary").font(Theme.Font.sectionTitle)
            Text("A name or term Dami should always spell this way.")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.ink2)
            TextField("e.g. Supabase, Tailwind", text: $term)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            SecondScriptTermHint(term: term)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.secondaryKey)
                Button("Add", action: add)
                    .buttonStyle(.primaryKey)
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
