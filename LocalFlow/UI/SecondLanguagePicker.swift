import SwiftUI

/// Picks the language spoken next to English (or none). Used in onboarding and Settings.
struct SecondLanguagePicker: View {
    @ObservedObject private var settings = AppSettings.shared
    /// Radio list for onboarding, pop-up menu for Settings.
    var asList = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if asList {
                picker.pickerStyle(.radioGroup).labelsHidden()
            } else {
                picker.pickerStyle(.menu)
            }
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var picker: some View {
        Picker("Language next to English", selection: $settings.secondLanguage) {
            Text("None, English only").tag(SpokenLanguage?.none)
            ForEach(SpokenLanguage.all) { language in
                Text(rowTitle(language)).tag(SpokenLanguage?.some(language))
            }
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
