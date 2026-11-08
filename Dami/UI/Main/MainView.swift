import SwiftUI

/// The main window: a top bar of section keys (Home, History, Dictionary, Settings) and the section below (spec §7, D2).
struct MainView: View {
    @ObservedObject var controller: DictationController
    @EnvironmentObject private var navigation: Navigation
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        let palette = settings.keyColor.palette
        VStack(spacing: 0) {
            TopBar(controller: controller)
            Rule()
            Group {
                switch navigation.section {
                case .home: HomeView(controller: controller)
                case .history: HistoryView()
                case .dictionary: DictionaryView()
                case .settings: SettingsView(controller: controller)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.paper)
        .environment(\.palette, palette)
        .environment(\.appTheme, settings.theme)
        .tint(palette.key)
        .frame(minWidth: 860, minHeight: 560)
        // Back to General for the next time the window opens. On close, so a tab asked for by the menu isn't overwritten.
        .onDisappear { navigation.settingsTab = SettingsView.Tab.general.rawValue }
        .overlayPreferenceValue(SectionKeyAnchors.self) { anchors in
            TourWindowLayer(anchors: anchors)
        }
    }
}

/// Traffic lights sit at the left of this bar (the window's title bar is hidden).
private struct TopBar: View {
    @ObservedObject var controller: DictationController
    @EnvironmentObject private var navigation: Navigation
    @ObservedObject private var tour = TourController.shared
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 22) {
            Text("Dami").font(Theme.Font.wordmark)
            HStack(spacing: 8) {
                ForEach(Navigation.Section.allCases) { section in
                    Button(section.title) { navigation.section = section }
                        .buttonStyle(TabKeyStyle(isOn: navigation.section == section, height: 26))
                        .accessibilityAddTraits(navigation.section == section ? .isSelected : [])
                        .overlay {
                            if tour.step?.section == section {
                                RoundedRectangle(cornerRadius: Theme.Radius.key)
                                    .strokeBorder(palette.key, lineWidth: 2)
                                    .padding(-4)
                                    .offset(y: -1)
                            }
                        }
                        .anchorPreference(key: SectionKeyAnchors.self, value: .bounds) { [section: $0] }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sections")
            Spacer()
            StatusBadge(controller: controller)
        }
        .padding(.leading, 84)
        .padding(.trailing, 22)
        .frame(height: 52)
    }
}

/// Where each section key is, so the tour can put its note under the one it's about.
struct SectionKeyAnchors: PreferenceKey {
    static let defaultValue: [Navigation.Section: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Navigation.Section: Anchor<CGRect>], nextValue: () -> [Navigation.Section: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The tour's note inside the main window: under the section key for History, Dictionary and Settings, and centred at the end.
private struct TourWindowLayer: View {
    let anchors: [Navigation.Section: Anchor<CGRect>]
    @ObservedObject private var tour = TourController.shared

    var body: some View {
        GeometryReader { proxy in
            if let step = tour.step, step.isInWindow {
                let key = step.section.flatMap { anchors[$0] }.map { proxy[$0] }
                let x = key.map { min(max(12, $0.minX - 20), proxy.size.width - 322) } ?? (proxy.size.width - 310) / 2
                let y = key.map { $0.maxY + 14 } ?? 90
                TourWindowNote(tour: tour)
                    .offset(x: x, y: y)
            }
        }
    }
}

/// Keys drawn as little keycaps, e.g. [Right ⌘] + [Right ⌥].
struct KeycapRow: View {
    let keys: [String]
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                if index > 0 { Text("+").font(.system(size: size)).foregroundStyle(Theme.ink2) }
                Keycap(label: key, size: size)
            }
        }
    }
}

/// Page title + subtitle used at the top of each section.
struct PageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.Font.pageTitle).tracking(-0.5)
            if let subtitle {
                Text(subtitle).font(Theme.Font.body).foregroundStyle(Theme.ink2)
            }
        }
    }
}

/// A rounded bordered box.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.keyFace))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.keyEdge))
    }
}

/// Small language label: EN, the other language's code, or MIXED. The word carries the meaning, so it's ink, not colour.
struct LanguageTag: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(Theme.ink2)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.keycap).strokeBorder(Theme.keyEdge))
    }
}
