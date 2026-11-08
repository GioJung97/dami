import SwiftUI

/// The main window: sidebar with Home, History, Dictionary and Settings.
struct MainView: View {
    @ObservedObject var controller: DictationController
    @EnvironmentObject private var navigation: Navigation

    var body: some View {
        NavigationSplitView {
            List(Navigation.Section.allCases, selection: $navigation.section) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) { SidebarStatus(controller: controller) }
        } detail: {
            switch navigation.section {
            case .home: HomeView(controller: controller)
            case .history: HistoryView()
            case .dictionary: DictionaryView()
            case .settings: SettingsView(controller: controller)
            }
        }
        .frame(minWidth: 860, minHeight: 560)
    }
}

private struct SidebarStatus: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text(controller.statusText).font(.system(size: 12, weight: .semibold)).lineLimit(2)
            Text("On-device · nothing leaves this Mac").font(.system(size: 11)).foregroundStyle(.secondary)
            KeycapRow(keys: settings.shortcut.keycaps, size: 11)
        }
        .padding(12)
    }
}

/// Keys drawn as little keycaps, e.g. [Right ⌘] + [Right ⌥].
struct KeycapRow: View {
    let keys: [String]
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                if index > 0 { Text("+").font(.system(size: size)).foregroundStyle(.secondary) }
                Text(key)
                    .font(.system(size: size))
                    .padding(.horizontal, size * 0.55)
                    .padding(.vertical, size * 0.25)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: .separatorColor)))
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
            Text(title).font(.system(size: 26, weight: .bold))
            if let subtitle {
                Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
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
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

/// Small colored language label: EN (blue), the other language e.g. KO (orange), MIXED (gray).
struct LanguageTag: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.14)))
    }

    private var color: Color {
        switch label {
        case "EN": .blue
        case "MIXED": .secondary
        default: .orange
        }
    }
}
