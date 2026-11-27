import DailyFlowCore
import SwiftUI

/// Runs `content` with the minute the belt and the clock should show, refreshing every frame while the
/// day is playing and gently otherwise. Only the views inside it re-draw per frame.
struct PlayheadReader<Content: View>: View {
    @Environment(AppModel.self) private var model
    private let content: (Double) -> Content

    init(@ViewBuilder content: @escaping (Double) -> Content) {
        self.content = content
    }

    var body: some View {
        let mode = model.playhead.mode
        let range = model.beltRange
        TimelineView(.animation(minimumInterval: mode.isPlaying ? nil : 2)) { context in
            content(Playhead.minute(mode: mode, at: context.date, live: { model.liveMinute }, range: range))
        }
    }
}

/// Clock, "now" card, the tilted belt, playback controls and the Anytime pills.
struct PlayTheDaySection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlayheadReader { minute in
                VStack(alignment: .leading, spacing: 0) {
                    NowHeader(minute: minute)
                        .padding(.horizontal, Metrics.gutter)
                    ConveyorBelt(minute: minute)
                        .padding(.top, 12)
                    PlaybackControls(minute: minute)
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, 8)
                }
                .sensoryFeedback(trigger: model.playhead.isHeld ? Int(minute / 30) : -1) { old, new in
                    (old >= 0 && new >= 0 && model.settings.hapticTickEnabled) ? .selection : nil
                }
            }
            AnytimeSection()
                .padding(.horizontal, Metrics.gutter)
        }
        .task(id: model.playhead.playToken) {
            // Stops the playhead cleanly at the end of the belt.
            guard case .playing(let start, _) = model.playhead.mode else { return }
            let remaining = max(0, model.beltRange.upperBound - start) / Playhead.playSpeed
            try? await Task.sleep(for: .seconds(remaining))
            if !Task.isCancelled {
                model.playhead.finishPlaying(at: model.beltRange.upperBound)
            }
        }
    }
}

// MARK: Clock and "now"

private struct NowHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    let minute: Double

    var body: some View {
        let running = model.runningItem(atMinute: minute)
        let next = running == nil ? model.nextTimedItem(afterMinute: minute) : nil

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom) {
                ClockText(text: Fmt.clock(fractional: minute))
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                Spacer(minLength: 8)
                if let running {
                    TickButton(
                        isDone: running.isDone,
                        label: "Tick off \(running.title)",
                        size: 46
                    ) {
                        model.toggleDone(running.id)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(model.animated(Motion.settle), value: running?.id)

            Text(title(running: running, next: next))
                .dfStyle(.heading)
                .foregroundStyle(palette.ink)
                .lineLimit(2)
                .contentTransition(.opacity)
                .animation(model.animated(Motion.settle), value: running?.id)

            HStack(alignment: .firstTextBaseline) {
                Text(subtitle(running: running, next: next))
                    .dfStyle(.label)
                    .foregroundStyle(palette.inkSecondary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if !model.playhead.isLive {
                    Button {
                        withAnimation(model.animated(Motion.settle)) {
                            model.playhead.goLive()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(palette.accent).frame(width: 6, height: 6)
                            Text("Now").dfStyle(.captionStrong)
                        }
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: Metrics.hit)
                        .background(palette.accentSoft, in: Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("Back to the current time")
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    private func title(running: TaskItem?, next: TaskItem?) -> String {
        if let running { return running.title }
        if let next, let start = next.startMinute { return "Free until \(Fmt.clock(start))" }
        return model.timedItems.isEmpty ? "A free day" : "Free for the evening"
    }

    private func subtitle(running: TaskItem?, next: TaskItem?) -> String {
        if let running {
            return "Now \u{00B7} \(running.spanText)" + (running.isDone ? " \u{00B7} done" : "")
        }
        if let next {
            return "Next: \(next.title) \u{00B7} \(next.spanText)"
        }
        return "Nothing else timed today"
    }
}

// MARK: The belt

private struct ConveyorBelt: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    let minute: Double

    @State private var dragStart: Double?
    @State private var detent = 0

    private let pointsPerMinute = BeltLayout.pointsPerMinute

    var body: some View {
        let range = model.beltRange
        let trackWidth = CGFloat(range.upperBound - range.lowerBound) * pointsPerMinute

        GeometryReader { proxy in
            let width = proxy.size.width
            let offset = width / 2 - CGFloat(minute - range.lowerBound) * pointsPerMinute

            ZStack(alignment: .topLeading) {
                BeltTrack(
                    items: model.timedItems,
                    range: range,
                    runningID: model.runningItem(atMinute: minute)?.id,
                    isSorted: model.isSorted
                )
                .frame(width: trackWidth, height: BeltLayout.trackHeight, alignment: .topLeading)
                .offset(x: offset)
                .frame(width: width, height: BeltLayout.trackHeight, alignment: .topLeading)
                .rotation3DEffect(.degrees(34), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.4)
                .padding(.top, 18)

                Rectangle()
                    .fill(LinearGradient(colors: [.clear, palette.ink, .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: 2, height: 142)
                    .position(x: width / 2, y: 77)
                    .allowsHitTesting(false)

                Text("Drag the belt or press play. Blocks are as long as the task.")
                    .dfStyle(.micro)
                    .foregroundStyle(palette.inkSecondary)
                    .frame(width: width)
                    .multilineTextAlignment(.center)
                    .position(x: width / 2, y: 160)
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: 170, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        let start = dragStart ?? minute
                        if dragStart == nil { dragStart = minute }
                        let proposed = start - Double(value.translation.width / pointsPerMinute)
                        let clamped = min(max(proposed, range.lowerBound), range.upperBound)
                        model.playhead.hold(at: clamped)
                        detent = Int(clamped / 30)
                    }
                    .onEnded { _ in
                        dragStart = nil
                    }
            )
        }
        .frame(height: 170)
        .sensoryFeedback(trigger: detent) { _, _ in
            model.settings.hapticTickEnabled ? .selection : nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline of today")
    }
}

private enum BeltLayout {
    static let pointsPerMinute: CGFloat = 110.0 / 60.0
    static let trackHeight: CGFloat = 120
}

/// The belt itself: rule, hour marks and the task blocks. It does not read the playhead, so it is not
/// rebuilt while the belt glides; only its offset changes.
private struct BeltTrack: View {
    @Environment(\.palette) private var palette

    let items: [TaskItem]
    let range: ClosedRange<Double>
    let runningID: UUID?
    let isSorted: Bool

    var body: some View {
        let ppm = BeltLayout.pointsPerMinute
        let hours = Array(stride(from: Int(range.lowerBound), through: Int(range.upperBound), by: 60))

        ZStack(alignment: .topLeading) {
            // The belt's polished rail.
            Rectangle()
                .fill(palette.chrome)
                .frame(height: 3)
                .offset(y: 99)

            ForEach(hours, id: \.self) { minute in
                let x = CGFloat(Double(minute) - range.lowerBound) * ppm
                Rectangle()
                    .fill(palette.tickLine)
                    .frame(width: 1, height: 14)
                    .offset(x: x, y: 92)
                Text(Fmt.clock(minute))
                    .dfStyle(.micro)
                    .foregroundStyle(palette.inkSecondary)
                    .fixedSize()
                    .offset(x: x + 4, y: 106)
            }

            ForEach(items) { item in
                let start = Double(item.startMinute ?? 0)
                BeltBlock(
                    item: item,
                    isNow: item.id == runningID,
                    isSorted: isSorted,
                    width: max(96, CGFloat(item.effectiveDurationMinutes) * ppm - 6)
                )
                .offset(x: CGFloat(start - range.lowerBound) * ppm + 3, y: 8)
            }
        }
    }
}

private struct BeltBlock: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    let item: TaskItem
    let isNow: Bool
    let isSorted: Bool
    let width: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .dfStyle(.cardTitle)
                    .strikethrough(item.isDone)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                    .padding(.trailing, 28)
                Spacer(minLength: 0)
                Text(item.spanText)
                    .dfStyle(.micro)
                    .opacity(0.75)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 10))
            .foregroundStyle(isNow ? palette.slabInk : palette.ink)
            .opacity(item.isDone && !isNow ? 0.65 : 1)

            TickButton(
                isDone: item.isDone,
                label: "Tick off \(item.title)",
                size: 26,
                restingRing: isNow ? palette.slabInk : nil
            ) {
                model.toggleDone(item.id)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(width: width, height: 78)
        .background(fill, in: shape)
        .overlay(shape.strokeBorder(border, lineWidth: 1.5))
        .shadow(color: isNow ? palette.nowGlow : .clear, radius: isNow ? 17 : 0, x: 0, y: isNow ? 7 : 0)
        .animation(model.animated(Motion.settle), value: isNow)
    }

    private var fill: AnyShapeStyle {
        if isNow { return AnyShapeStyle(palette.slab) }
        return AnyShapeStyle(item.isDone ? palette.blockDone : palette.block)
    }

    private var border: Color {
        if item.isUrgent && !item.isDone { return palette.urgent }
        if isNow { return .clear }
        return isSorted ? palette.category(item.category) : palette.blockBorder
    }
}

// MARK: Playback

private struct PlaybackControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    let minute: Double

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(model.animated(Motion.settle)) {
                    model.playhead.togglePlay(from: minute, range: model.beltRange)
                }
            } label: {
                Image(systemName: model.playhead.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.background)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 46, height: 46)
                    .background(palette.ink, in: Circle())
                    .overlay(Circle().strokeBorder(palette.bevel, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.92))
            .accessibilityLabel(model.playhead.isPlaying ? "Pause" : "Play the day")

            ScrubSlider(minute: minute, range: model.beltRange) { value in
                model.playhead.hold(at: value)
            }

            Text(Fmt.clock(fractional: minute))
                .dfStyle(.bodyStrong)
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .frame(minWidth: 50, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}

/// A thin scrubber with a polished knob. Dragging anywhere on it moves the playhead.
private struct ScrubSlider: View {
    @Environment(\.palette) private var palette

    let minute: Double
    let range: ClosedRange<Double>
    let onScrub: (Double) -> Void

    private let knob: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.width - knob, 1)
            let span = max(range.upperBound - range.lowerBound, 1)
            let fraction = min(max((minute - range.lowerBound) / span, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.tickLine)
                    .frame(height: 4)
                Capsule()
                    .fill(palette.accent)
                    .frame(width: knob / 2 + travel * fraction, height: 4)
                Circle()
                    .fill(palette.slab)
                    .overlay(Circle().strokeBorder(palette.bevel, lineWidth: 1))
                    .frame(width: knob, height: knob)
                    .shadow(color: palette.scrim, radius: 3, y: 1)
                    .offset(x: travel * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let position = min(max((value.location.x - knob / 2) / travel, 0), 1)
                        onScrub(range.lowerBound + position * span)
                    }
            )
        }
        .frame(height: Metrics.hit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time of day")
        .accessibilityValue(Fmt.clock(fractional: minute))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onScrub(min(minute + 15, range.upperBound))
            case .decrement: onScrub(max(minute - 15, range.lowerBound))
            @unknown default: break
            }
        }
    }
}

// MARK: Anytime

private struct AnytimeSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        if !model.anytimeItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Overline(text: "ANYTIME")
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(model.anytimeItems) { item in
                        pill(item)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .animation(model.animated(Motion.settle), value: model.anytimeItems)
            }
            .padding(.top, 14)
        }
    }

    private func pill(_ item: TaskItem) -> some View {
        Button {
            model.toggleDone(item.id)
        } label: {
            HStack(spacing: 8) {
                TickGlyph(isDone: item.isDone, size: 30)
                Text(item.title)
                    .dfStyle(.control)
                    .strikethrough(item.isDone)
                    .foregroundStyle(palette.ink)
                    .opacity(item.isDone ? 0.55 : 1)
                    .lineLimit(1)
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .frame(minHeight: Metrics.hit)
            .background(palette.card, in: Capsule())
            .overlay(
                Capsule().strokeBorder(item.isUrgent && !item.isDone ? palette.urgent : palette.line, lineWidth: 1.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title + (item.isUrgent ? ", urgent" : ""))
        .accessibilityValue(item.isDone ? "Done" : "Not done")
        .accessibilityAddTraits(.isToggle)
    }
}
