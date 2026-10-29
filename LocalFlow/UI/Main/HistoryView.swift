import AVFoundation
import SwiftUI

struct HistoryView: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var search = ""
    @State private var filter = "ALL"
    @State private var selection: Dictation.ID?

    private static let filters = [("ALL", "All"), ("EN", "English"), ("KO", "Korean"), ("MIXED", "Mixed")]

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
                ForEach(Self.filters, id: \.0) { Text($0.1).tag($0.0) }
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
                                HistoryRow(dictation: item).tag(item.id)
                            }
                        }
                    }
                }
                .frame(minWidth: 300, idealWidth: 360)

                Group {
                    if let selected {
                        HistoryDetail(dictation: selected)
                    } else {
                        Text(filtered.isEmpty ? "No dictations" : "Select a dictation")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(28)
        .onAppear { if selection == nil { selection = filtered.first?.id } }
    }

    private var filtered: [Dictation] {
        store.dictations.filter { item in
            (filter == "ALL" || item.languageLabel == filter)
                && (search.isEmpty || item.finalText.localizedCaseInsensitiveContains(search)
                    || item.rawText.localizedCaseInsensitiveContains(search))
        }
    }

    private var selected: Dictation? {
        filtered.first { $0.id == selection }
    }

    private var groupedByDay: [(day: String, items: [Dictation])] {
        let calendar = Calendar.current
        var groups: [(day: String, items: [Dictation])] = []
        for item in filtered {
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
        let url = Store.audioURL(for: id)
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
            TextField("e.g. Supabase, 김지수", text: $term)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
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
