import SwiftUI

/// The pill itself. Kept small: 28 pt tall, about the size of a menu bar item.
struct HUDView: View {
    @ObservedObject var controller: HUDController

    var body: some View {
        let atBottom = AppSettings.shared.hudPosition == .bottomCenter
        VStack(spacing: 6) {
            if atBottom { noteLabel }
            phaseView
            if !atBottom { noteLabel }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: atBottom ? .bottom : .top)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var noteLabel: some View {
        if let note = controller.note {
            Text(note)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(Color(white: 0.11).opacity(0.92)))
                .transition(.opacity)
        }
    }

    private var phaseView: some View {
        ZStack {
            switch controller.phase {
            case .hidden:
                EmptyView()
            case .recording(let handsFree):
                pill {
                    Circle().fill(Color(red: 1, green: 0.27, blue: 0.23)).frame(width: 7, height: 7)
                    LevelBars(levels: controller.levels)
                    if handsFree {
                        Text("Tap to stop").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                    } else {
                        ElapsedTime(since: controller.recordingStartedAt)
                    }
                }
            case .transcribing(let waiting):
                pill {
                    ThinkingDots()
                    if waiting > 0 {
                        Text("Processing · \(waiting) waiting").font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                    }
                }
            case .pasted:
                pill {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0.19, green: 0.82, blue: 0.35))
                }
            case .copied(let text):
                pill {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.04))
                    Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                }
            case .message(let message):
                pill {
                    Text(message.text).font(.system(size: 11, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                    if let title = message.actionTitle {
                        Button(title) { controller.performMessageAction() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(red: 0.4, green: 0.72, blue: 1))
                    }
                }
            }
        }
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(Color(white: 0.11).opacity(0.92)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            .transition(.scale(scale: 0.7).combined(with: .opacity))
    }
}

private struct LevelBars: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(.white)
                    .frame(width: 2.5, height: 3 + CGFloat(levels[index]) * 13)
            }
        }
        .frame(height: 16)
        .animation(.linear(duration: 0.06), value: levels)
    }
}

private struct ElapsedTime: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(since)))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

private struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.25) % 3
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(.white.opacity(index == step ? 1 : 0.35))
                        .frame(width: 5, height: 5)
                }
            }
        }
    }
}
