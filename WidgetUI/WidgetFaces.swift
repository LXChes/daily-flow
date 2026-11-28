import DailyFlowCore
import SwiftUI
import WidgetKit

// The crafted faces. Each reads only from `DFWidgetEntry` and the resolved `WidgetLook`.
// Basic mode (no task data) is designed, not degraded: date, time of day, notice, and a short hint.

// MARK: Progress ring (Home small, Lock circular)

/// Today as a ring with the percentage in chrome numerals. Basic mode: the ring is how far through the
/// day we are, and the day number sits in the middle.
struct ProgressRingSmallFace: View {
    let entry: DFWidgetEntry
    let look: WidgetLook

    var body: some View {
        let progress = entry.snapshot.progress
        let day = entry.snapshot.day
        let live = entry.day.hasTasks && progress.total > 0
        let notice = entry.snapshot.noticeTitles.first
        VStack(spacing: live ? 10 : 6) {
            WidgetHeader(
                leading: notice ?? "Today",
                trailing: WidgetText.weekdayAndDay(day),
                highlightsLeading: notice != nil,
                look: look
            )
            ZStack {
                WidgetRing(
                    fraction: live ? progress.fraction : Double(entry.minute) / 1_440,
                    diameter: live ? 108 : 92,
                    lineWidth: 9,
                    look: look
                )
                if live {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(progress.percent)")
                            .widgetFont(.numeral, 34)
                            .foregroundStyle(look.metal)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("%")
                            .widgetFont(.ringValue, 13)
                            .foregroundStyle(look.secondary)
                    }
                    .frame(maxWidth: 62)
                } else {
                    RingDayLabel(day: day, look: look)
                }
            }
            if !live {
                Text(entry.day.hasTasks ? "Nothing planned" : WidgetText.openHint)
                    .widgetFont(.captionStrong, 10)
                    .foregroundStyle(look.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            live
                ? WidgetText.progressSpoken(progress)
                : "\(WidgetText.dateLine(day)). \(entry.day.hasTasks ? "Nothing planned today" : WidgetText.openHint)"
        )
    }
}

/// The day number with its weekday underneath, for rings with no task data.
struct RingDayLabel: View {
    let day: CalendarDay
    let look: WidgetLook

    var body: some View {
        VStack(spacing: -1) {
            Text("\(day.day)")
                .widgetFont(.numeral, 34)
                .foregroundStyle(look.metal)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(WidgetText.weekday(day))
                .widgetFont(.overline, 9)
                .foregroundStyle(look.secondary)
        }
        .frame(maxWidth: 62)
    }
}

/// Lock Screen circular: percentage ring. Basic mode: time through the day, with the day number inside.
struct ProgressRingCircularFace: View {
    let entry: DFWidgetEntry
    let look: WidgetLook

    var body: some View {
        let progress = entry.snapshot.progress
        let day = entry.snapshot.day
        let live = entry.day.hasTasks && progress.total > 0
        ZStack {
            WidgetRing(
                fraction: live ? progress.fraction : Double(entry.minute) / 1_440,
                diameter: 62,
                lineWidth: 6,
                look: look,
                showsBezel: false
            )
            if live {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(progress.percent)")
                        .widgetFont(.numeral, 18)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("%")
                        .widgetFont(.ringValue, 8)
                }
                .foregroundStyle(look.ink)
                .frame(maxWidth: 38)
                .widgetAccentable()
            } else {
                VStack(spacing: -1) {
                    Text("\(day.day)")
                        .widgetFont(.numeral, 19)
                        .lineLimit(1)
                    Text(WidgetText.weekday(day))
                        .widgetFont(.overline, 7)
                }
                .foregroundStyle(look.ink)
                .widgetAccentable()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            live
                ? WidgetText.progressSpoken(progress)
                : "\(WidgetText.dateLine(day)). \(WidgetText.openHint)"
        )
    }
}

// MARK: Done ring (Home small)

/// "3 of 8 done": one segment per task, lit as each is ticked, with the count (not a percentage) inside.
struct DoneRingSmallFace: View {
    let entry: DFWidgetEntry
    let look: WidgetLook

    var body: some View {
        let progress = entry.snapshot.progress
        let day = entry.snapshot.day
        let live = entry.day.hasTasks && progress.total > 0
        let notice = entry.snapshot.noticeTitles.first
        VStack(spacing: live ? 10 : 6) {
            WidgetHeader(
                leading: notice ?? (live ? "Done" : "Daily"),
                trailing: live ? WidgetText.weekdayAndDay(day) : WidgetText.month(day),
                highlightsLeading: notice != nil,
                look: look
            )
            ZStack {
                if live {
                    WidgetSegmentedRing(done: progress.done, total: progress.total, diameter: 108, lineWidth: 10, look: look)
                    VStack(spacing: -1) {
                        Text("\(progress.done)")
                            .widgetFont(.numeral, 38)
                            .foregroundStyle(look.metal)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("of \(progress.total)")
                            .widgetFont(.captionStrong, 11)
                            .foregroundStyle(look.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 62)
                } else {
                    WidgetRing(fraction: Double(entry.minute) / 1_440, diameter: 92, lineWidth: 9, look: look)
                    RingDayLabel(day: day, look: look)
                }
            }
            if !live {
                Text(entry.day.hasTasks ? "Nothing planned" : WidgetText.openHint)
                    .widgetFont(.captionStrong, 10)
                    .foregroundStyle(look.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            live
                ? "\(progress.done) of \(progress.total) done"
                : "\(WidgetText.dateLine(day)). \(entry.day.hasTasks ? "Nothing planned today" : WidgetText.openHint)"
        )
    }
}

// MARK: Wave (Home medium)

/// Busy-time bars across the day: raised where tasks sit, lit where they are done, with a now line.
struct WaveMediumFace: View {
    let entry: DFWidgetEntry
    let look: WidgetLook

    var body: some View {
        let snapshot = entry.snapshot
        let progress = snapshot.progress
        let day = snapshot.day
        let live = entry.day.hasTasks && progress.total > 0
        let notice = snapshot.noticeTitles.first
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                headline(progress: progress, day: day, live: live)
                Spacer(minLength: 6)
                trailing(notice: notice, day: day, live: live)
            }
            WidgetWaveChart(slices: WidgetWave.slices(snapshot.tasks), minute: entry.minute, look: look)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            live
                ? "\(progress.done) of \(progress.total) done. Busy times across the day."
                : "\(WidgetText.dateLine(day)). \(entry.day.hasTasks ? "Nothing planned today" : WidgetText.openHint)"
        )
    }

    @ViewBuilder
    private func trailing(notice: String?, day: CalendarDay, live: Bool) -> some View {
        let hint = entry.day.hasTasks ? "Nothing planned" : WidgetText.openHint
        if let notice {
            VStack(alignment: .trailing, spacing: 3) {
                WidgetNoticeCapsule(title: notice, look: look)
                if !live {
                    Text(hint)
                        .widgetFont(.captionStrong, 10)
                        .foregroundStyle(look.secondary)
                        .lineLimit(1)
                }
            }
        } else if live {
            Text(WidgetText.dateLine(day))
                .widgetFont(.overline, 10)
                .foregroundStyle(look.secondary)
                .lineLimit(1)
        } else {
            Text(hint)
                .widgetFont(.captionStrong, 11)
                .foregroundStyle(look.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func headline(progress: DayProgress, day: CalendarDay, live: Bool) -> some View {
        if live {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(progress.done)")
                    .widgetFont(.numeral, 36)
                    .foregroundStyle(look.metal)
                Text("of \(progress.total) done")
                    .widgetFont(.bodyStrong, 15)
                    .foregroundStyle(look.secondary)
                    .lineLimit(1)
            }
        } else {
            Text(WidgetText.weekdayAndDay(day))
                .widgetFont(.numeral, 30)
                .foregroundStyle(look.metal)
                .lineLimit(1)
        }
    }
}

/// One slice of the day (half an hour) on the wave.
struct WaveSlice: Equatable, Sendable {
    enum State: Sendable { case idle, open, done }

    let height: Double
    let state: State
}

enum WidgetWave {
    static let count = 48
    private static let reachMinutes = 36.0

    /// Computed once per render. A gentle ripple that rises where timed tasks sit.
    static func slices(_ tasks: [TaskSnapshot]) -> [WaveSlice] {
        let step = Double(DaySchedule.minutesPerDay) / Double(count)
        return (0..<count).map { index -> WaveSlice in
            let from = Double(index) * step
            let to = from + step
            let mid = from + step / 2
            var height = 0.14 + 0.07 * abs(sin(Double(index) * 1.7)) + 0.04 * abs(sin(Double(index) * 0.41))
            var insideOpen = false
            var insideDone = false
            for task in tasks {
                guard let startMinute = task.startMinute, let endMinute = task.endMinute, endMinute > startMinute else {
                    continue
                }
                let start = Double(startMinute)
                let end = Double(endMinute)
                if from < end && to > start {
                    if task.isDone { insideDone = true } else { insideOpen = true }
                    let along = min(max((mid - start) / (end - start), 0), 1)
                    height += 0.55 + 0.18 * sin(along * Double.pi)
                } else {
                    let distance = min(abs(mid - start), abs(mid - end))
                    if distance < reachMinutes {
                        height += (reachMinutes - distance) / reachMinutes * 0.2
                    }
                }
            }
            let state: WaveSlice.State = insideOpen ? .open : (insideDone ? .done : .idle)
            return WaveSlice(height: min(height, 1), state: state)
        }
    }
}

struct WaveChartStyle: Sendable {
    let idle: Color
    let open: Color
    let ink: Color
    let label: Color
    let lit: [Color]
}

struct WidgetWaveChart: View {
    let slices: [WaveSlice]
    let minute: Int
    let look: WidgetLook

    var body: some View {
        let style = WaveChartStyle(idle: look.track, open: look.steel, ink: look.ink, label: look.secondary, lit: look.litColors)
        let bars = slices
        let now = minute
        ZStack {
            Canvas { context, size in
                WaveChartPainter.drawBase(&context, size: size, slices: bars, style: style)
            }
            // The lit layer is its own canvas so a tinted Home Screen can accent just the done bars and now line.
            Canvas { context, size in
                WaveChartPainter.drawLit(&context, size: size, slices: bars, minute: now, style: style)
            }
            .widgetAccentable()
        }
    }
}

enum WaveChartPainter {
    private static let labelBand: CGFloat = 14

    private static func barRect(_ index: Int, slice: CGFloat, plotHeight: CGFloat, height: Double) -> CGRect {
        let barWidth = slice * 0.58
        let barHeight = max(3, plotHeight * CGFloat(height))
        return CGRect(
            x: CGFloat(index) * slice + (slice - barWidth) / 2,
            y: plotHeight - barHeight,
            width: barWidth,
            height: barHeight
        )
    }

    /// Idle and open bars, plus the hour labels.
    static func drawBase(_ context: inout GraphicsContext, size: CGSize, slices: [WaveSlice], style: WaveChartStyle) {
        guard !slices.isEmpty else { return }
        let plotHeight = size.height - labelBand
        let slice = size.width / CGFloat(slices.count)
        for (index, item) in slices.enumerated() {
            let rect = barRect(index, slice: slice, plotHeight: plotHeight, height: item.height)
            let path = Path(roundedRect: rect, cornerRadius: rect.width / 2)
            context.fill(path, with: .color(item.state == .idle ? style.idle : style.open))
        }
        let labels: [(Int, String, UnitPoint)] = [
            (0, "00", .topLeading), (6, "06", .top), (12, "12", .top), (18, "18", .top), (24, "24", .topTrailing)
        ]
        for (hour, text, anchor) in labels {
            let label = Text(text)
                .font(DFTextStyle.badge.font(fixedSize: 9))
                .foregroundStyle(style.label)
            context.draw(label, at: CGPoint(x: size.width * CGFloat(hour) / 24, y: plotHeight + 4), anchor: anchor)
        }
    }

    /// Done bars (iridescent when in full colour) and the now line.
    static func drawLit(_ context: inout GraphicsContext, size: CGSize, slices: [WaveSlice], minute: Int, style: WaveChartStyle) {
        guard !slices.isEmpty else { return }
        let plotHeight = size.height - labelBand
        let slice = size.width / CGFloat(slices.count)
        var lit = Path()
        for (index, item) in slices.enumerated() where item.state == .done {
            let rect = barRect(index, slice: slice, plotHeight: plotHeight, height: item.height)
            lit.addRoundedRect(in: rect, cornerSize: CGSize(width: rect.width / 2, height: rect.width / 2))
        }
        context.fill(
            lit,
            with: .linearGradient(
                Gradient(colors: style.lit),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: size.width, y: 0)
            )
        )

        let x = size.width * CGFloat(minute) / CGFloat(DaySchedule.minutesPerDay)
        var line = Path()
        line.move(to: CGPoint(x: x, y: 5))
        line.addLine(to: CGPoint(x: x, y: plotHeight + 2))
        context.stroke(line, with: .color(style.ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        let head = Path(ellipseIn: CGRect(x: x - 3, y: 0, width: 6, height: 6))
        context.fill(head, with: .color(style.ink))
    }
}

// MARK: Day dial: the skeleton watch (Home medium, Lock circular)

/// Lock Screen circular: the skeleton watch, simplified (bezel ring, task arcs, wheel outlines, hands and the
/// "now" arrow). Basic mode still works: the hands and arrow read the time.
struct DayDialCircularFace: View {
    let entry: DFWidgetEntry
    let look: WidgetLook

    var body: some View {
        WatchFaceView(tasks: entry.snapshot.tasks, minute: entry.minute, diameter: 64, look: look)
    }
}

/// Home medium: the skeleton watch head on the left, "Up next" with two tickable tasks and the count on the right.
struct DayDialMediumFace: View {
    let entry: DFWidgetEntry
    let look: WidgetLook

    var body: some View {
        let snapshot = entry.snapshot
        let progress = snapshot.progress
        let live = entry.day.hasTasks && progress.total > 0
        HStack(spacing: 16) {
            WatchFaceView(tasks: snapshot.tasks, minute: entry.minute, diameter: 134, look: look)
            if live {
                liveColumn(snapshot: snapshot, progress: progress)
            } else {
                quietColumn(snapshot: snapshot)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func liveColumn(snapshot: DaySnapshot, progress: DayProgress) -> some View {
        let upcoming = snapshot.upNext(atMinute: entry.minute, limit: 2)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("UP NEXT")
                    .widgetFont(.overline, 10)
                    .foregroundStyle(look.secondary)
                Spacer(minLength: 4)
                if let notice = snapshot.noticeTitles.first {
                    WidgetNoticeCapsule(title: notice, look: look)
                }
            }
            if upcoming.isEmpty {
                HStack(spacing: 10) {
                    WidgetTickMark(isDone: true, size: 26, look: look)
                    Text("All done")
                        .widgetFont(.rowTitle, 14)
                        .foregroundStyle(look.ink)
                }
            } else {
                ForEach(upcoming) { task in
                    WidgetTaskRow(task: task, canTick: entry.day.canTick, look: look)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(progress.done)/\(progress.total)")
                    .widgetFont(.cardTitle, 15)
                    .foregroundStyle(look.metal)
                Text("done")
                    .widgetFont(.captionStrong, 11)
                    .foregroundStyle(look.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(progress.done) of \(progress.total) done")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// No task data, or nothing planned: the date, any notice, and a hint. Never a broken-looking empty list.
    private func quietColumn(snapshot: DaySnapshot) -> some View {
        let day = snapshot.day
        return VStack(alignment: .leading, spacing: 6) {
            Text(WidgetText.weekday(day))
                .widgetFont(.overline, 10)
                .foregroundStyle(look.secondary)
            Text("\(day.day) \(WidgetText.month(day).capitalized)")
                .widgetFont(.numeral, 30)
                .foregroundStyle(look.metal)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let notice = snapshot.noticeTitles.first {
                WidgetNoticeCapsule(title: notice, look: look)
            }
            Spacer(minLength: 0)
            Text(entry.day.hasTasks ? "Nothing planned" : WidgetText.openHint)
                .widgetFont(.captionStrong, 11)
                .foregroundStyle(look.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: Up next (Lock rectangular)

/// The next task with a tick, a small count, and its time (or "Anytime").
struct UpNextRectangularFace: View {
    let entry: DFWidgetEntry
    let look: WidgetLook

    var body: some View {
        let snapshot = entry.snapshot
        let progress = snapshot.progress
        let hasPlan = entry.day.hasTasks && progress.total > 0
        let next = snapshot.upNext(atMinute: entry.minute, limit: 1).first
        let running = next.map { ($0.startMinute ?? Int.max) <= entry.minute } ?? false
        let copy = Self.copy(entry: entry, next: next, hasPlan: hasPlan)
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(running ? "NOW" : (next == nil && hasPlan ? "DONE" : "UP NEXT"))
                        .widgetFont(.overline, 9)
                        .foregroundStyle(look.secondary)
                    Spacer(minLength: 2)
                    if hasPlan {
                        Text("\(progress.done)/\(progress.total)")
                            .widgetFont(.captionStrong, 10)
                            .foregroundStyle(look.secondary)
                    }
                }
                Text(copy.title)
                    .widgetFont(.rowTitle, 14)
                    .foregroundStyle(look.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(copy.subtitle)
                    .widgetFont(.captionStrong, 11)
                    .foregroundStyle(look.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let next {
                WidgetTickButton(task: next, canTick: entry.day.canTick, size: 28, look: look)
            } else if hasPlan {
                WidgetTickMark(isDone: true, size: 28, look: look)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private static func copy(entry: DFWidgetEntry, next: TaskSnapshot?, hasPlan: Bool) -> (title: String, subtitle: String) {
        if let next {
            return (next.title, WidgetText.timeLabel(next))
        }
        if hasPlan {
            return ("All done", "Day complete")
        }
        if entry.day.hasTasks {
            return ("Nothing planned", WidgetText.dateLine(entry.snapshot.day))
        }
        return (entry.snapshot.noticeTitles.first ?? WidgetText.openHint, WidgetText.dateLine(entry.snapshot.day))
    }
}

// MARK: Today line (Lock inline)

/// One line above the clock: the notice on a notice day, else progress and the next timed task.
struct TodayLineFace: View {
    let entry: DFWidgetEntry
    let look: WidgetLook

    var body: some View {
        Text(line)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .widgetAccentable()
    }

    private var line: String {
        let snapshot = entry.snapshot
        if let notice = snapshot.noticeTitles.first {
            return "It\u{2019}s \(notice)"
        }
        let progress = snapshot.progress
        guard entry.day.hasTasks else { return WidgetText.openHint }
        guard progress.total > 0 else { return "Nothing planned today" }
        guard let next = snapshot.upNext(atMinute: entry.minute, limit: 1).first else {
            return "All \(progress.total) done"
        }
        let when = next.startMinute.map { " \(WidgetText.clock($0))" } ?? ""
        return "\(progress.done) of \(progress.total) done \u{00B7} \(next.title)\(when)"
    }
}
