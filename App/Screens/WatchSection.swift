import DailyFlowCore
import SwiftUI

/// Layout "Watch": the day as a skeleton watch. Every task is a gear that turns, timed tasks are arcs on
/// the 24 hour bezel, an arrow hand points at now. Tap a gear to see its task under the watch and tick it.
///
/// The watch is four stacked canvases so only what moves is redrawn each frame:
/// back (case, strap, plate: redrawn only on a theme or size change), movement (wheels, balance, bridges,
/// every frame), front (rings, arcs, hands: every couple of seconds) and glass (seconds hand, glint).
struct WatchSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The gear the owner tapped. Ignored once that task is no longer on the watch.
    @State private var tappedID: UUID?

    var body: some View {
        // The clock the static parts hang on: every couple of seconds, or once a minute with Reduce Motion.
        TimelineView(.periodic(from: .now, by: reduceMotion ? 60 : 2)) { _ in
            let minute = model.liveMinute
            let gears = WatchGeometry.gears(model.items, titles: { $0.title }, atMinute: minute)
            let selection = effectiveSelection(gears: gears, minute: minute)
            let frame = WatchFrame(
                hands: WatchGeometry.hands(atMinute: minute),
                arcs: WatchGeometry.arcs(model.items, atMinute: minute),
                gears: gears,
                progress: model.progress,
                seconds: 0,
                pulse: WatchSection.restingPulse,
                theme: model.theme,
                style: .fullColour,
                selected: selection,
                showsHardware: true
            )
            VStack(spacing: 14) {
                WatchStageView(
                    frame: frame,
                    summary: WatchGeometry.spokenSummary(model.items, titles: { $0.title }, atMinute: minute),
                    reduceMotion: reduceMotion,
                    label: { gear in spokenLabel(for: gear) },
                    isSelected: { id in id == selection },
                    select: { id in select(id) }
                )
                WatchNowLine(minute: minute)
                    .padding(.horizontal, Metrics.gutter)
                WatchTaskCard(item: model.items.first(where: { $0.id == selection }), minute: minute)
                    .padding(.horizontal, Metrics.gutter)
            }
            .sensoryFeedback(trigger: selection) { old, new in
                (old != nil && new != nil && model.settings.hapticTickEnabled) ? .selection : nil
            }
        }
    }

    /// The pulse of an urgent jewel when nothing animates.
    static let restingPulse = 0.85

    // MARK: Selection

    /// The tapped gear if it is still on the watch; else the live one, the next timed task, the first open
    /// one, or whatever is there.
    private func effectiveSelection(gears: [WatchGear], minute: Double) -> UUID? {
        if let tappedID, gears.contains(where: { $0.taskID == tappedID }) { return tappedID }
        if let live = gears.first(where: { $0.state == .live }) { return live.taskID }
        if let next = model.nextTimedItem(afterMinute: minute), gears.contains(where: { $0.taskID == next.id }) {
            return next.id
        }
        return gears.first(where: { $0.state != .done })?.taskID ?? gears.first?.taskID
    }

    private func select(_ id: UUID) {
        withAnimation(model.animated(Motion.settle)) {
            tappedID = id
        }
    }

    /// "Lecture, 10:00, not done"
    private func spokenLabel(for gear: WatchGear) -> String {
        let item = model.items.first { $0.id == gear.taskID }
        let time = item?.startMinute.map { Fmt.clock($0) } ?? "anytime"
        return "\(gear.title), \(time), \(item?.isDone == true ? "done" : "not done")"
    }
}

// MARK: The watch

/// The four layers plus tapping and VoiceOver.
private struct WatchStageView: View {
    let frame: WatchFrame
    let summary: String
    let reduceMotion: Bool
    let label: (WatchGear) -> String
    let isSelected: (UUID) -> Bool
    let select: (UUID) -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                WatchBackLayer(theme: frame.theme)
                WatchMovementLayer(frame: frame, reduceMotion: reduceMotion)
                WatchFrontLayer(frame: frame, drawsSeconds: reduceMotion)
                if !reduceMotion {
                    WatchGlassLayer(frame: frame)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    let stage = WatchStage.composition(in: geometry.size)
                    if let hit = WatchHitTest.gear(at: value.location, stage: stage, gears: frame.gears) {
                        select(hit.taskID)
                    }
                }
            )
            .accessibilityLabel(summary)
            .accessibilityChildren {
                VStack {
                    ForEach(frame.gears) { gear in
                        Button(label(gear)) { select(gear.taskID) }
                            .accessibilityAddTraits(isSelected(gear.taskID) ? .isSelected : [])
                    }
                }
            }
        }
        .aspectRatio(360.0 / 440.0, contentMode: .fit)
        // The strap runs off the top and bottom of the picture: fade it into the screen.
        .mask {
            LinearGradient(
                stops: [
                    .init(color: palette.background.opacity(0), location: 0),
                    .init(color: palette.background, location: 0.1),
                    .init(color: palette.background, location: 0.9),
                    .init(color: palette.background.opacity(0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

/// Which gear a touch lands on.
enum WatchHitTest {
    /// The task gear nearest to `point`, if it is within reach. Small gears get a generous 22 point reach.
    static func gear(at point: CGPoint, stage: WatchStage, gears: [WatchGear]) -> WatchGear? {
        var best: WatchGear?
        var bestDistance = CGFloat.infinity
        for gear in gears {
            guard let wheel = WatchMovement.taskWheels.first(where: { $0.taskSlot == gear.slot }) else { continue }
            let center = stage.point(wheel.center)
            let distance = hypot(point.x - center.x, point.y - center.y)
            let reach = max(CGFloat(wheel.tipRadius) * stage.unit + 6, 22)
            if distance <= reach, distance < bestDistance {
                best = gear
                bestDistance = distance
            }
        }
        return best
    }
}

/// Case, strap and plate. Depends only on the theme, so SwiftUI skips it when nothing about it changed.
private struct WatchBackLayer: View {
    let theme: ThemeMode

    var body: some View {
        Canvas { context, size in
            let frame = WatchFrame(
                hands: WatchGeometry.hands(atMinute: 0),
                arcs: [],
                gears: [],
                progress: DayProgress(done: 0, total: 0),
                seconds: 0,
                pulse: 0,
                theme: theme,
                style: .fullColour,
                showsHardware: true
            )
            let stage = WatchStage.composition(in: size)
            WatchPainter.backdrop(&context, frame, stage)
            WatchPainter.plate(&context, frame, stage)
        }
    }
}

/// Barrel, wheels, balance and fork, bridges: the layer that moves. Wheels turn, the balance swings,
/// urgent jewels pulse. With Reduce Motion it is drawn once, still.
private struct WatchMovementLayer: View {
    let frame: WatchFrame
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            Canvas { context, size in
                WatchMovementLayer.draw(&context, size, frame)
            }
        } else {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let moving = frame.moved(seconds: t, pulse: 0.55 + 0.45 * sin(5 * t))
                Canvas { context, size in
                    WatchMovementLayer.draw(&context, size, moving)
                }
            }
        }
    }

    private static func draw(_ context: inout GraphicsContext, _ size: CGSize, _ frame: WatchFrame) {
        let stage = WatchStage.composition(in: size)
        WatchPainter.barrel(&context, frame, stage)
        WatchPainter.wheels(&context, frame, stage)
        WatchPainter.escapement(&context, frame, stage)
        WatchPainter.bridges(&context, frame, stage)
        WatchPainter.selection(&context, frame, stage)
    }
}

/// Edge shadow, hour ring, bezel, task arcs, progress and the hour, minute and day hands.
private struct WatchFrontLayer: View {
    let frame: WatchFrame
    /// Draws the seconds hand, cap and glint too (when nothing animates above it).
    let drawsSeconds: Bool

    var body: some View {
        Canvas { context, size in
            let stage = WatchStage.composition(in: size)
            WatchPainter.dialEdge(&context, frame, stage)
            WatchPainter.hourRing(&context, frame, stage)
            WatchPainter.bezel(&context, frame, stage)
            WatchPainter.taskArcs(&context, frame, stage)
            WatchPainter.progressArc(&context, frame, stage)
            WatchPainter.hands(&context, frame, stage)
            if drawsSeconds {
                WatchPainter.secondsHand(&context, frame, stage)
                WatchPainter.glint(&context, frame, stage)
            }
        }
    }
}

/// The sweeping seconds hand, the centre cap and the crystal, redrawn every frame.
private struct WatchGlassLayer: View {
    @Environment(AppModel.self) private var model

    let frame: WatchFrame

    var body: some View {
        TimelineView(.animation) { timeline in
            // The live clock glides between whole seconds; the fixed demo clock stays put.
            let now = model.clock.now()
            let isLive = abs(now.timeIntervalSince(timeline.date)) < 2
            let fraction = isLive ? timeline.date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) : 0
            let minute = model.clock.fractionalMinute(of: now) + fraction / 60
            let moving = frame.with(hands: WatchGeometry.hands(atMinute: minute))
            Canvas { context, size in
                let stage = WatchStage.composition(in: size)
                WatchPainter.secondsHand(&context, moving, stage)
                WatchPainter.glint(&context, moving, stage)
            }
        }
    }
}

// MARK: Under the watch

/// "On now: Lecture until 12:00" or "Next: Seminar at 14:00".
private struct WatchNowLine: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    let minute: Double

    var body: some View {
        let running = model.runningItem(atMinute: minute)
        let next = running == nil ? model.nextTimedItem(afterMinute: minute) : nil
        HStack(spacing: 8) {
            Circle()
                .fill(running == nil ? palette.tickLine : palette.accent)
                .frame(width: 7, height: 7)
            Text(lead(running: running, next: next))
                .dfStyle(.overline)
                .foregroundStyle(palette.inkSecondary)
            Text(detail(running: running, next: next))
                .dfStyle(.label)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func lead(running: TaskItem?, next: TaskItem?) -> String {
        if running != nil { return "ON NOW" }
        return next != nil ? "NEXT" : "FREE"
    }

    private func detail(running: TaskItem?, next: TaskItem?) -> String {
        if let running, let end = running.endMinute { return "\(running.title) \u{00B7} until \(Fmt.clockEnd(end))" }
        if let next, let start = next.startMinute { return "\(next.title) \u{00B7} \(Fmt.clock(start))" }
        return "Nothing else timed today"
    }
}

/// The selected gear's task: category stripe, status, title, time and the tick.
private struct WatchTaskCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    let item: TaskItem?
    let minute: Double

    var body: some View {
        Group {
            if let item {
                taskCard(item)
                    .id(item.id)
                    .transition(.opacity)
            } else {
                emptyCard
                    .transition(.opacity)
            }
        }
        .animation(model.animated(Motion.settle), value: item?.id)
    }

    private func taskCard(_ item: TaskItem) -> some View {
        HStack(spacing: 14) {
            // A slice of the bezel arc: the same colour the task has on the watch.
            Capsule()
                .fill(item.isUrgent && !item.isDone ? palette.urgent : palette.category(item.category))
                .frame(width: 5, height: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(status(item))
                    .dfStyle(.overline)
                    .foregroundStyle(palette.inkSecondary)
                Text(item.title)
                    .dfStyle(.heading)
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
                    .contentTransition(.opacity)
                Text(item.spanText)
                    .dfStyle(.label)
                    .foregroundStyle(palette.inkSecondary)
            }
            Spacer(minLength: 8)
            TickButton(isDone: item.isDone, label: "Tick off \(item.title)", size: 46) {
                model.toggleDone(item.id)
            }
        }
        .padding(.vertical, 14)
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .cardSurface()
        .accessibilityElement(children: .contain)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NO GEARS YET")
                .dfStyle(.overline)
                .foregroundStyle(palette.inkSecondary)
            Text("Add a task and it becomes a gear.")
                .dfStyle(.body)
                .foregroundStyle(palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardSurface()
    }

    private func status(_ item: TaskItem) -> String {
        let kind: String
        if item.isDone {
            kind = "DONE"
        } else if let start = item.startMinute, let end = item.endMinute, Double(start) <= minute, minute < Double(end) {
            kind = "ON NOW"
        } else if model.nextTimedItem(afterMinute: minute)?.id == item.id {
            kind = "NEXT"
        } else {
            kind = item.isTimed ? "LATER" : "ANYTIME"
        }
        return kind + " \u{00B7} " + item.category.title.uppercased() + (item.isUrgent && !item.isDone ? " \u{00B7} URGENT" : "")
    }
}
