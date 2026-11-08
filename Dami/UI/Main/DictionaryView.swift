import DamiCore
import SwiftUI

/// Vocabulary only reaches Whisper for English dictations, so a term in the second language's script
/// wouldn't do anything there. Says so while it's being typed.
struct SecondScriptTermHint: View {
    let term: String
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        if let second = settings.secondLanguage, second.script?.matches(term) == true {
            Text("\(second.name) terms don't help here, since Vocabulary only reaches English dictations. Use Replacements to fix how a \(second.name) word comes out.")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DictionaryView: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var fit = VocabularyFit.shared
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
            PageHeader(title: "Dictionary", subtitle: "Names and terms Dami should always spell your way.")
            TabKeys(
                label: "Section",
                options: [
                    (Tab.vocabulary, "Vocabulary · \(store.vocabulary.count)"),
                    (Tab.replacements, "Replacements · \(store.replacements.count)"),
                    (Tab.suggestions, pendingCount > 0 ? "Suggestions · \(pendingCount)" : "Suggestions"),
                ],
                selection: $tab
            )

            switch tab {
            case .vocabulary: vocabulary
            case .replacements: replacements
            case .suggestions: suggestions
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 52)
        .padding(.top, 26)
        .padding(.bottom, 22)
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
                    .buttonStyle(.primaryKey)
                    .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            SecondScriptTermHint(term: newTerm)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(store.vocabulary) { term in
                        HStack(spacing: 6) {
                            Text(term.term).lineLimit(1)
                                .foregroundStyle(fit.leftOut.contains(term.term) ? Theme.ink2 : Theme.ink)
                            Spacer(minLength: 0)
                            if fit.leftOut.contains(term.term) {
                                Text("Not in the hint")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.danger)
                                    .help("Whisper's hint has room for a limited number of terms, newest first. This one doesn't fit.")
                            }
                            Button {
                                store.removeTerm(term)
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.ink2)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(term.term)")
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.key)
                                .fill(Theme.keyFace)
                                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.key).strokeBorder(Theme.keyEdge))
                                .background(RoundedRectangle(cornerRadius: Theme.Radius.key).fill(Theme.keyDepthNeutral).offset(y: Theme.Depth.keycap))
                        )
                        .padding(.bottom, Theme.Depth.keycap)
                    }
                }
            }
            if !fit.leftOut.isEmpty {
                Text("\(fit.leftOut.count) of these don't fit in Whisper's hint, which has room for a limited number. The newest terms are used. Remove ones you no longer need, or use Replacements for them.")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("These help English dictations only: Whisper gets them as a spelling hint. For your second language and mixed sentences, or terms it still mishears, use Replacements.")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.ink2)
        }
    }

    private var replacements: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("When Whisper writes…", text: $newFind)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Image(systemName: "arrow.right").foregroundStyle(Theme.ink2)
                TextField("Replace with…", text: $newReplace)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onSubmit(addReplacement)
                Button("Add", action: addReplacement)
                    .buttonStyle(.primaryKey)
                    .disabled(newFind.trimmingCharacters(in: .whitespaces).isEmpty || newReplace.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Table(store.replacements) {
                TableColumn("When Whisper writes") { Text($0.find) }
                TableColumn("Replace with") { Text($0.replace).fontWeight(.semibold).highlighted() }
                TableColumn("Used") { Text($0.uses == 1 ? "1 time" : "\($0.uses) times").font(Theme.Font.mono).foregroundStyle(Theme.ink2) }
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
            .scrollContentBackground(.hidden)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.keyFace))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.keyEdge))
            Text("Rules match whole words, ignoring case. Korean also matches with particles such as 을, 에서 or 에서도 after. Japanese, Chinese and Thai match anywhere in the text.")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.ink2)
        }
    }

    private var pendingCount: Int { store.suggestions.filter { $0.status == .pending }.count }

    private var suggestions: some View {
        let pending = store.suggestions.filter { $0.status == .pending }
        let declined = store.suggestions.filter { $0.status == .declined }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("When you fix a word in History, Dami offers to fix it every time. Nothing changes until you say so.")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.ink2)
                if pending.isEmpty && declined.isEmpty {
                    Card {
                        Text("No suggestions yet").font(Theme.Font.sectionTitle)
                        Text("Fix a dictation in History, and a word you changed shows up here if you haven't answered it there.")
                            .font(Theme.Font.footnote)
                            .foregroundStyle(Theme.ink2)
                    }
                    .frame(maxWidth: 560)
                }
                if !pending.isEmpty {
                    Text("WAITING FOR AN ANSWER").font(Theme.Font.keyLabel).tracking(Theme.keyLabelTracking).foregroundStyle(Theme.ink2)
                    ForEach(pending) { SuggestionBox(suggestion: $0) }
                }
                if !declined.isEmpty {
                    Text("DECLINED").font(Theme.Font.keyLabel).tracking(Theme.keyLabelTracking).foregroundStyle(Theme.ink2)
                    ForEach(declined) { suggestion in
                        HStack {
                            Text(suggestion.find)
                            Image(systemName: "arrow.right").foregroundStyle(Theme.ink2)
                            Text(suggestion.replace)
                            Spacer()
                            Button("Ask again") { store.askAgain(suggestion) }
                                .buttonStyle(.secondaryKey)
                        }
                        .frame(maxWidth: 560)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

/// "Always fix X → Y?", with how many past dictations have the word, so a rule that would also hit other words shows up first.
struct SuggestionBox: View {
    let suggestion: Suggestion
    @State private var preview: (dictations: Int, words: [String])?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Always fix")
                Text("\u{201C}\(suggestion.find)\u{201D}").fontWeight(.semibold)
                Image(systemName: "arrow.right").foregroundStyle(Theme.ink2)
                Text("\u{201C}\(suggestion.replace)\u{201D}").fontWeight(.bold).highlighted()
                Text("?")
            }
            .font(.system(size: 13))
            if let preview {
                Text(previewText(preview))
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Always fix") { Store.shared.answer(suggestion, accept: true) }
                    .buttonStyle(.primaryKey)
                Button("Not this") { Store.shared.answer(suggestion, accept: false) }
                    .buttonStyle(.secondaryKey)
                Spacer()
                Text("Only future dictations change.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.ink2)
            }
        }
        .padding(12)
        .frame(maxWidth: 560, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.keyFace))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.keyEdge))
        .onAppear { preview = Store.shared.preview(find: suggestion.find) }
    }

    private func previewText(_ preview: (dictations: Int, words: [String])) -> String {
        guard preview.dictations > 0 else { return "None of your past dictations has this word." }
        let count = preview.dictations == 1 ? "1 past dictation has" : "\(preview.dictations) past dictations have"
        let words = preview.words.map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", ")
        return "\(count) this, as in \(words). Check that these should change too."
    }
}
