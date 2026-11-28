import DailyFlowCore
import SwiftUI
import WidgetKit

// Shared building blocks for the widget faces. Compiled into the widget and the app (the DEBUG gallery).
// Everything here is static: widgets cannot animate, so there is no TimelineView and no animated fill.

// MARK: Look

/// Colour decisions for one render. Home Screen faces use the theme's palette; Lock Screen faces always
/// draw light-on-dark (the system re-tints them) and never rely on colour to carry meaning.
struct WidgetLook {
    let palette: Palette
    let family: WidgetFamily
    let renderingMode: WidgetRenderingMode

    var isAccessory: Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: true
        default: false
        }
    }

    /// Full colour on the Home Screen. Tinted and Lock Screen renders get flat marks, because gradients
    /// wash out once the system recolours them.
    var isFull: Bool { renderingMode == .fullColor && !isAccessory }

    var ink: Color { isAccessory ? Palette.dark.ink : palette.ink }
    var secondary: Color { isAccessory ? Palette.dark.ink.opacity(0.66) : palette.inkSecondary }
    /// Empty part of a ring, idle bars.
    var track: Color { isAccessory ? Palette.dark.ink.opacity(0.26) : palette.waveDim }
    /// Hairlines and bezel ticks.
    var hairline: Color { isAccessory ? Palette.dark.ink.opacity(0.4) : palette.tickLine }
    /// Marks for work still to do.
    var steel: Color { isFull ? palette.waveLit : ink.opacity(0.55) }
    var accent: Color { isFull ? palette.accent : ink }
    var onAccent: Color { isFull ? palette.onAccent : ink }

    /// Polished steel for numerals and tick rings; a flat ink when the system recolours the widget.
    var metal: AnyShapeStyle { isFull ? AnyShapeStyle(palette.chrome) : AnyShapeStyle(ink) }
    /// The iridescent sweep for progress arcs.
    var arc: AnyShapeStyle {
        isFull ? AnyShapeStyle(AngularGradient(colors: Palette.iridescentLoop, center: .center)) : AnyShapeStyle(ink)
    }
    /// Colours for lit (done) marks across the day.
    var litColors: [Color] { isFull ? Palette.iridescentStatic : [ink, ink] }
}

// MARK: Text

extension Text {
    /// A fixed-size font from the app's type hierarchy. Widgets use fixed sizes so layouts never overflow;
    /// tracking scales with the size it was designed for.
    func widgetFont(_ style: DFTextStyle, _ size: CGFloat) -> Text {
        font(style.font(fixedSize: size)).tracking(style.tracking * size / style.size)
    }
}

/// Plain-text helpers. Kept separate from the app's own formatters, which are not in the widget target.
enum WidgetText {
    static let openHint = "Open Daily Flow"

    static func clock(_ minute: Int) -> String {
        let value = MinuteOfDay.clamp(minute)
        let hours = value / 60
        let minutes = value % 60
        return "\(hours < 10 ? "0" : "")\(hours):\(minutes < 10 ? "0" : "")\(minutes)"
    }

    static func timeLabel(_ task: TaskSnapshot) -> String {
        guard let start = task.startMinute else { return "Anytime" }
        return task.isUrgent ? "\(clock(start)) \u{00B7} Urgent" : clock(start)
    }

    private static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        return calendar
    }

    static func weekday(_ day: CalendarDay) -> String {
        let names = gregorian.shortWeekdaySymbols
        return names.indices.contains(day.weekday - 1) ? names[day.weekday - 1].uppercased() : ""
    }

    static func month(_ day: CalendarDay) -> String {
        let names = gregorian.shortMonthSymbols
        return names.indices.contains(day.month - 1) ? names[day.month - 1].uppercased() : ""
    }

    /// "TUE 17".
    static func weekdayAndDay(_ day: CalendarDay) -> String { "\(weekday(day)) \(day.day)" }

    /// "TUE 17 NOV".
    static func dateLine(_ day: CalendarDay) -> String { "\(weekday(day)) \(day.day) \(month(day))" }

    static func progressSpoken(_ progress: DayProgress) -> String {
        progress.total == 0
            ? "Nothing planned today"
            : "\(progress.done) of \(progress.total) done, \(progress.percent) percent"
    }
}

// MARK: Marks

/// The check mark, as a stroke.
struct WidgetCheck: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.53))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// The tick: a chrome ring, filled with the accent and carrying a check once done. Static.
struct WidgetTickMark: View {
    let isDone: Bool
    let size: CGFloat
    let look: WidgetLook

    var body: some View {
        ZStack {
            if isDone {
                Circle().fill(look.isFull ? look.accent : look.ink.opacity(0.28))
                Circle().strokeBorder(look.accent, lineWidth: 2)
                WidgetCheck()
                    .stroke(
                        look.onAccent,
                        style: StrokeStyle(lineWidth: max(2, size * 0.1), lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: size * 0.48, height: size * 0.34)
            } else {
                Circle().strokeBorder(look.metal, lineWidth: 2)
            }
        }
        .frame(width: size, height: size)
        .widgetAccentable(isDone)
    }
}

/// A tick that really ticks, but only when the tick can reach the app. Otherwise the same mark is shown
/// as plain status, dimmed so it does not look pressable.
struct WidgetTickButton: View {
    let task: TaskSnapshot
    let canTick: Bool
    let size: CGFloat
    let look: WidgetLook

    var body: some View {
        if canTick {
            Button(intent: ToggleTaskIntent(task: task.id, done: !task.isDone)) {
                WidgetTickMark(isDone: task.isDone, size: size, look: look)
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(-5)
            .accessibilityLabel(task.isDone ? "Untick \(task.title)" : "Tick off \(task.title)")
        } else {
            WidgetTickMark(isDone: task.isDone, size: size, look: look)
                .opacity(0.6)
                .accessibilityHidden(true)
        }
    }
}

/// A progress ring with a 60-step bezel and an iridescent arc.
struct WidgetRing: View {
    let fraction: Double
    let diameter: CGFloat
    let lineWidth: CGFloat
    let look: WidgetLook
    var showsBezel = true

    var body: some View {
        let inset: CGFloat = showsBezel ? 8 : 0
        let ringDiameter = diameter - inset * 2 - lineWidth
        let clamped = min(max(fraction, 0), 1)
        ZStack {
            if showsBezel {
                let bezelDiameter = diameter - 3
                let step = Double.pi * Double(bezelDiameter) / 60
                Circle()
                    .stroke(look.hairline, style: StrokeStyle(lineWidth: 3, dash: [1.1, CGFloat(step) - 1.1]))
                    .frame(width: bezelDiameter, height: bezelDiameter)
            }
            Circle()
                .stroke(look.track, lineWidth: lineWidth)
                .frame(width: ringDiameter, height: ringDiameter)
            if clamped > 0 {
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(look.arc, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: ringDiameter, height: ringDiameter)
                    .widgetAccentable()
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// One segment per task, lit as each is done. Falls back to a plain ring for big days.
struct WidgetSegmentedRing: View {
    let done: Int
    let total: Int
    let diameter: CGFloat
    let lineWidth: CGFloat
    let look: WidgetLook

    static let maxSegments = 16

    var body: some View {
        if total < 1 || total > Self.maxSegments {
            WidgetRing(fraction: total == 0 ? 0 : Double(done) / Double(total), diameter: diameter, lineWidth: lineWidth, look: look)
        } else {
            let inset: CGFloat = 8
            let ringDiameter = diameter - inset * 2 - lineWidth
            let gap = 0.014
            let slice = 1 / Double(total)
            let lit = look.arc
            let off = AnyShapeStyle(look.track)
            ZStack {
                ForEach(0..<total, id: \.self) { index in
                    let from = Double(index) * slice + gap / 2
                    let to = Double(index + 1) * slice - gap / 2
                    Circle()
                        .trim(from: from, to: to)
                        .stroke(index < done ? lit : off, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .frame(width: ringDiameter, height: ringDiameter)
                }
            }
            .frame(width: diameter, height: diameter)
            .widgetAccentable()
        }
    }
}

// MARK: Header and capsules

/// The small overline row on the Home Screen faces.
struct WidgetHeader: View {
    let leading: String
    let trailing: String
    let highlightsLeading: Bool
    let look: WidgetLook

    var body: some View {
        HStack(spacing: 6) {
            Text(leading.uppercased())
                .widgetFont(.overline, 10)
                .foregroundStyle(highlightsLeading ? look.accent : look.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            Text(trailing)
                .widgetFont(.overline, 10)
                .foregroundStyle(look.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

/// The notice-day marker: an iridescent capsule, like the banner in the app. Outlined when tinted.
struct WidgetNoticeCapsule: View {
    let title: String
    let look: WidgetLook

    var body: some View {
        Text(title.uppercased())
            .widgetFont(.badge, 10)
            .foregroundStyle(look.isFull ? Palette.onIridescent : look.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                if look.isFull {
                    IridescentFill(animated: false).clipShape(Capsule())
                } else {
                    Capsule().strokeBorder(look.ink, lineWidth: 1)
                }
            }
            .accessibilityLabel("Notice day: \(title)")
    }
}

/// A tickable (or status-only) task row for the medium faces.
struct WidgetTaskRow: View {
    let task: TaskSnapshot
    let canTick: Bool
    let look: WidgetLook

    var body: some View {
        HStack(spacing: 10) {
            WidgetTickButton(task: task, canTick: canTick, size: 26, look: look)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .widgetFont(.rowTitle, 14)
                    .foregroundStyle(look.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(WidgetText.timeLabel(task))
                    .widgetFont(.captionStrong, 11)
                    .foregroundStyle(look.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}
