import Foundation

// Pure maths for the skeleton watch, shared by the app's watch view and the widget watch faces.
// Angles are degrees clockwise from 12 o'clock, always in 0..<360. Inputs are minutes after midnight
// (fractional where a hand should glide), so the rules are testable without a clock.

/// A task the watch can show: the scheduling fields plus identity and category.
public protocol WatchItem: ScheduledItem {
    var id: UUID { get }
    var category: TaskCategory { get }
}

extension TaskSnapshot: WatchItem {}

/// Hand positions for one moment.
public struct WatchHands: Equatable, Sendable {
    /// 12-hour hand.
    public let hour: Double
    /// Minute hand.
    public let minute: Double
    /// Seconds hand (zero when the moment has no seconds, as in a widget entry).
    public let second: Double
    /// The arrow hand: one turn per day, pointing at "now" on the 24-hour bezel.
    public let day: Double
}

/// One timed task as an arc on the 24-hour bezel.
public struct WatchArc: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let category: TaskCategory
    public let startDegrees: Double
    public let endDegrees: Double
    public let isDone: Bool
    public let isUrgent: Bool
    /// Unfinished and running at the moment the arcs were made.
    public let isLive: Bool

    public var sweepDegrees: Double { endDegrees - startDegrees }
}

/// What a task gear is doing.
public enum WatchGearState: Equatable, Sendable {
    /// Waiting: turns slowly with the movement.
    case idle
    /// Running now: spins fast.
    case live
    /// Ticked off: polished, turning slowly.
    case done
}

/// A task bound to one of the movement's task-gear slots.
public struct WatchGear: Equatable, Sendable, Identifiable {
    /// The slot in the movement, 0 being the largest wheel.
    public let slot: Int
    public let taskID: UUID
    public let title: String
    public let category: TaskCategory
    public let state: WatchGearState
    /// An unfinished urgent task: its jewel pulses.
    public let pulsesJewel: Bool

    public var id: UUID { taskID }
    /// Multiplier on the movement's base rotation rate for this gear.
    public var spinRate: Double { WatchGeometry.spinRate(state) }
}

public enum WatchGeometry {
    /// Task-gear slots in the movement. Days with more tasks show the rest as plain cogs.
    public static let taskGearSlots = 8
    /// Gap left at each end of an arc so neighbouring tasks read as separate marks.
    public static let arcInsetMinutes = 5.0
    /// Shortest arc block, so a 15-minute task is still visible.
    public static let minimumArcBlockMinutes = 21.0

    public static let liveSpinRate = 7.0

    // MARK: Hands

    public static func hands(atMinute minute: Double) -> WatchHands {
        let day = wrap(minute, 1_440)
        let seconds = (day - day.rounded(.down)) * 60
        return WatchHands(
            hour: wrap(day, 720) / 720 * 360,
            minute: wrap(day, 60) / 60 * 360,
            second: seconds / 60 * 360,
            day: dayDegrees(atMinute: day)
        )
    }

    /// Position of a minute of the day on the 24-hour bezel (midnight at the top).
    public static func dayDegrees(atMinute minute: Double) -> Double {
        wrap(minute, 1_440) / 1_440 * 360
    }

    // MARK: Bezel arcs

    /// Every timed task as a bezel arc, in start order. Untimed tasks have no arc.
    public static func arcs<Item: WatchItem>(_ items: [Item], atMinute minute: Double) -> [WatchArc] {
        DaySchedule.timed(items).compactMap { item in
            guard let start = item.startMinute else { return nil }
            let block = max(Double(item.effectiveDurationMinutes), minimumArcBlockMinutes)
            let from = Double(start) + arcInsetMinutes
            let to = min(Double(start) + block - arcInsetMinutes, Double(DaySchedule.minutesPerDay))
            guard to > from else { return nil }
            return WatchArc(
                id: item.id,
                category: item.category,
                startDegrees: from / 1_440 * 360,
                endDegrees: to / 1_440 * 360,
                isDone: item.isDone,
                isUrgent: item.isUrgent,
                isLive: isLive(item, atMinute: minute)
            )
        }
    }

    // MARK: Task gears

    /// Binds up to `taskGearSlots` tasks to gear slots, keeping the given display order.
    ///
    /// The choice ignores done and time, so ticking a task never moves the gears around. On a busy
    /// day urgent tasks win a gear first, then timed ones, then anytime ones.
    public static func gears<Item: WatchItem>(
        _ items: [Item],
        titles: (Item) -> String,
        atMinute minute: Double
    ) -> [WatchGear] {
        let chosen: [Item]
        if items.count <= taskGearSlots {
            chosen = items
        } else {
            func rank(_ item: Item) -> Int { item.isUrgent ? 0 : (item.isTimed ? 1 : 2) }
            let picked = Set(
                items.indices
                    .sorted { lhs, rhs in
                        let left = rank(items[lhs])
                        let right = rank(items[rhs])
                        return left == right ? lhs < rhs : left < right
                    }
                    .prefix(taskGearSlots)
            )
            chosen = items.indices.filter(picked.contains).map { items[$0] }
        }
        return chosen.enumerated().map { slot, item in
            WatchGear(
                slot: slot,
                taskID: item.id,
                title: titles(item),
                category: item.category,
                state: item.isDone ? .done : (isLive(item, atMinute: minute) ? .live : .idle),
                pulsesJewel: item.isUrgent && !item.isDone
            )
        }
    }

    public static func spinRate(_ state: WatchGearState) -> Double {
        switch state {
        case .idle, .done: 1
        case .live: liveSpinRate
        }
    }

    /// Angle of a wheel turning at `degreesPerSecond`, `seconds` into its motion. Wrapped, so long
    /// sessions never lose precision in the drawing.
    public static func rotation(degreesPerSecond: Double, seconds: Double) -> Double {
        wrap(degreesPerSecond * wrap(seconds, 86_400), 360)
    }

    // MARK: Progress

    /// Progress arc sweep in degrees for a bezel progress track of `trackDegrees`.
    public static func progressSweep(_ progress: DayProgress, trackDegrees: Double) -> Double {
        min(max(progress.fraction, 0), 1) * trackDegrees
    }

    // MARK: Accessibility

    /// "Now 10:15. On now: Lecture, until 12:00. Next: Seminar at 14:00. 1 of 6 done."
    public static func spokenSummary<Item: WatchItem>(
        _ items: [Item],
        titles: (Item) -> String,
        atMinute minute: Double
    ) -> String {
        let whole = MinuteOfDay.clamp(Int(minute.rounded(.down)))
        var parts = ["Now \(clock(whole))."]
        if let running = DaySchedule.current(items, atMinute: whole), let end = running.endMinute {
            parts.append("On now: \(titles(running)), until \(clock(end)).")
        }
        if let next = DaySchedule.upcoming(items, afterMinute: whole).first, let start = next.startMinute {
            parts.append("Next: \(titles(next)) at \(clock(start)).")
        }
        let progress = DaySchedule.progress(items)
        if progress.total == 0 {
            parts.append("Nothing planned.")
        } else if progress.done == progress.total {
            parts.append("All \(progress.total) done.")
        } else {
            parts.append("\(progress.done) of \(progress.total) done.")
        }
        return parts.joined(separator: " ")
    }

    /// 24-hour "HH:mm". Midnight at the end of the day reads 24:00.
    public static func clock(_ minute: Int) -> String {
        let value = min(max(minute, 0), DaySchedule.minutesPerDay)
        let hours = value / 60
        let minutes = value % 60
        return (hours < 10 ? "0" : "") + "\(hours):" + (minutes < 10 ? "0" : "") + "\(minutes)"
    }

    // MARK: Helpers

    private static func isLive<Item: ScheduledItem>(_ item: Item, atMinute minute: Double) -> Bool {
        guard !item.isDone, let start = item.startMinute, let end = item.endMinute else { return false }
        return Double(start) <= minute && minute < Double(end)
    }

    /// `value` modulo `period`, in 0..<period, for negative values too.
    static func wrap(_ value: Double, _ period: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: period)
        return result < 0 ? result + period : result
    }
}
