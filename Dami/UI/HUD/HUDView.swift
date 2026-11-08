import SwiftUI

/// The HUD: a paper slip, 28 pt tall, about the size of a menu bar item (spec §7).
struct HUDView: View {
    @ObservedObject var controller: HUDController
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let atBottom = settings.hudPosition == .bottomCenter
        VStack(spacing: 6) {
            if atBottom { noteLabel }
            phaseView
            if !atBottom { noteLabel }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: atBottom ? .bottom : .top)
        .environment(\.palette, settings.keyColor.palette)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var noteLabel: some View {
        if let note = controller.note {
            Text(note)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(Theme.onTape)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.tape).fill(Theme.tape))
                .transition(.opacity)
        }
    }

    private var phaseView: some View {
        ZStack {
            switch controller.phase {
            case .hidden:
                EmptyView()
            case .recording(let handsFree):
                slip {
                    RecordingDot()
                    LevelBars(levels: controller.levels)
                    ElapsedTime(since: controller.recordingStartedAt)
                    if handsFree {
                        Text("Tap to stop").font(Theme.Font.captionMedium).foregroundStyle(Theme.ink2)
                    }
                }
            case .transcribing(let waiting):
                slip {
                    ThinkingDots(still: reduceMotion)
                    if waiting > 0 {
                        Text("Processing · \(waiting) waiting").font(Theme.Font.captionMedium).foregroundStyle(Theme.ink)
                    }
                }
            case .pasted:
                slip(horizontalPadding: 9) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.onHighlight)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 1)
                        .highlighted()
                }
            case .copied(let text):
                slip {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ink)
                    TextWithKeycaps(text: text)
                }
            case .message(let message):
                slip {
                    TextWithKeycaps(text: message.text)
                    if let title = message.actionTitle {
                        Button(title) { controller.performMessageAction() }
                            .buttonStyle(KeyButtonStyle(kind: .primary, height: 18, compact: true))
                    }
                }
            }
        }
    }

    private func slip<Content: View>(horizontalPadding: CGFloat = 12, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .padding(.horizontal, horizontalPadding)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.slip).fill(Theme.slip))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.slip).strokeBorder(Theme.slipEdge))
            .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.7).combined(with: .opacity))
    }
}

private struct RecordingDot: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Circle().fill(palette.key).frame(width: 8, height: 8)
    }
}

private struct LevelBars: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(Theme.ink)
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
                .font(Theme.Font.monoSmall)
                .foregroundStyle(Theme.ink2)
        }
    }
}

/// One dark dot at a time. With Reduce Motion, the middle one stays dark.
private struct ThinkingDots: View {
    let still: Bool

    var body: some View {
        if still {
            dots(step: 1)
        } else {
            TimelineView(.animation(minimumInterval: 0.12)) { context in
                dots(step: Int(context.date.timeIntervalSinceReferenceDate / 0.25) % 3)
            }
        }
    }

    private func dots(step: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(index == step ? Theme.ink : Theme.keyEdge)
                    .frame(width: 5, height: 5)
            }
        }
    }
}
