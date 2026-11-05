import LocalFlowCore
import SwiftUI

/// Vocabulary only reaches Whisper for English dictations, so a term in the second language's script
/// wouldn't do anything there. Says so while it's being typed.
struct SecondScriptTermHint: View {
    let term: String
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        if let second = settings.secondLanguage, second.script?.matches(term) == true {
            Text("\(second.name) terms don't help here, since Vocabulary only reaches English dictations. Use Replacements to fix how a \(second.name) word comes out.")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DictionaryView: View {
    @ObservedObject private var store = Store.shared
    @State private var tab = Tab.vocabulary
    @State private var newTerm = ""
    @State private var newFind = ""
    @State private var newReplace = ""

    enum Tab: String, CaseIterable, Identifiable {
        case vocabulary = "Vocabulary", replacements = "Replacements", suggestions = "Suggestions"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Dictionary", subtitle: "Names and terms LocalFlow should always spell your way.")
            Picker("Section", selection: $tab) {
                Text("Vocabulary · \(store.vocabulary.count)").tag(Tab.vocabulary)
                Text("Replacements · \(store.replacements.count)").tag(Tab.replacements)
                Text("Suggestions").tag(Tab.suggestions)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 420)

            switch tab {
            case .vocabulary: vocabulary
            case .replacements: replacements
            case .suggestions: suggestions
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var vocabulary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Add a word or name, e.g. Tailwind", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)
                    .onSubmit(addTerm)
                Button("Add", action: addTerm)
                    .buttonStyle(.borderedProminent)
                    .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            SecondScriptTermHint(term: newTerm)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(store.vocabulary) { term in
                        HStack(spacing: 6) {
                            Text(term.term).lineLimit(1)
                            Spacer(minLength: 0)
                            Button {
                                store.removeTerm(term)
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(term.term)")
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
                    }
                }
            }
            Text("These help English dictations only: Whisper gets them as a spelling hint. For your second language and mixed sentences, or terms it still mishears, use Replacements.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var replacements: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("When Whisper writes…", text: $newFind)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                TextField("Replace with…", text: $newReplace)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onSubmit(addReplacement)
                Button("Add", action: addReplacement)
                    .buttonStyle(.borderedProminent)
                    .disabled(newFind.trimmingCharacters(in: .whitespaces).isEmpty || newReplace.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Table(store.replacements) {
                TableColumn("When Whisper writes") { Text($0.find) }
                TableColumn("Replace with") { Text($0.replace).fontWeight(.semibold) }
                TableColumn("Used") { Text($0.uses == 1 ? "1 time" : "\($0.uses) times").foregroundStyle(.secondary) }
                    .width(80)
                TableColumn("") { rule in
                    Button {
                        store.removeReplacement(rule)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove rule for \(rule.find)")
                }
                .width(32)
            }
            .frame(minHeight: 240)
            Text("English words match as whole words, ignoring case. Korean matches exactly.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var suggestions: some View {
        Card {
            Text("Learned from your edits").font(.system(size: 15, weight: .semibold))
            Text("After LocalFlow pastes, it will notice words you fix right away and suggest them here. Coming in a later update.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 560)
    }

    private func addTerm() {
        store.addTerm(newTerm)
        newTerm = ""
    }

    private func addReplacement() {
        store.addReplacement(find: newFind, replace: newReplace)
        newFind = ""
        newReplace = ""
    }
}
