import Foundation

/// The fields the scheduling rules need. Adopted by the stored `FlowTask` and the widget `TaskSnapshot`,
/// so the same rules run in the app, in tests and (from M4) in the widget.
public protocol ScheduledItem {
    var startMinute: Int? { get }
    var durationMinutes: Int? { get }
    var isDone: Bool { get }
    var isUrgent: Bool { get }
    var sortIndex: Int { get }
    var createdAt: Date { get }
}

extension ScheduledItem {
    public var isTimed: Bool { startMinute != nil }

    /// Length used for "now" and busy-time maths. A timed task with no duration counts as a short block.
    public var effectiveDurationMinutes: Int {
        max(durationMinutes ?? DaySchedule.defaultBlockMinutes, 1)
    }

    /// Minute after midnight when the block ends, capped at midnight.
    public var endMinute: Int? {
        startMinute.map { min($0 + effectiveDurationMinutes, DaySchedule.minutesPerDay) }
    }
}

public struct DayProgress: Equatable, Sendable {
    public let done: Int
    public let total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }

    /// 0...1. An empty day reads as 0, not complete.
    public var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    public var percent: Int { Int((fraction * 100).rounded()) }
}

/// Pure ordering and "what's on now" rules for one day's tasks.
public enum DaySchedule {
    public static let minutesPerDay = 1_440
    public static let defaultBlockMinutes = 15

    /// Display order. With auto-sort, timed tasks run by start time, then anytime tasks with urgent first.
    /// Without it, the owner's manual order is kept.
    public static func ordered<Item: ScheduledItem>(_ items: [Item], autoSort: Bool) -> [Item] {
        guard autoSort else {
            return items.sorted { lhs, rhs in
                lhs.sortIndex == rhs.sortIndex ? lhs.createdAt < rhs.createdAt : lhs.sortIndex < rhs.sortIndex
            }
        }
        return timed(items) + items.filter { !$0.isTimed }.sorted { lhs, rhs in
            if lhs.isUrgent != rhs.isUrgent { return lhs.isUrgent }
            return lhs.createdAt < rhs.createdAt
        }
    }

    /// Timed tasks by start time (ties by creation).
    public static func timed<Item: ScheduledItem>(_ items: [Item]) -> [Item] {
        items.filter(\.isTimed).sorted { lhs, rhs in
            let left = lhs.startMinute ?? 0
            let right = rhs.startMinute ?? 0
            return left == right ? lhs.createdAt < rhs.createdAt : left < right
        }
    }

    /// The unfinished timed task running at `minute`, if any. With overlaps, the latest to start wins.
    public static func current<Item: ScheduledItem>(_ items: [Item], atMinute minute: Int) -> Item? {
        timed(items).last { item in
            guard !item.isDone, let start = item.startMinute, let end = item.endMinute else { return false }
            return start <= minute && minute < end
        }
    }

    /// Unfinished timed tasks starting after `minute`, soonest first.
    public static func upcoming<Item: ScheduledItem>(_ items: [Item], afterMinute minute: Int) -> [Item] {
        timed(items).filter { item in
            guard !item.isDone, let start = item.startMinute else { return false }
            return start > minute
        }
    }

    /// The task the "now" card features: the one running at `minute`, else the next one to start.
    public static func nowOrNext<Item: ScheduledItem>(_ items: [Item], atMinute minute: Int) -> Item? {
        current(items, atMinute: minute) ?? upcoming(items, afterMinute: minute).first
    }

    public static func progress<Item: ScheduledItem>(_ items: [Item]) -> DayProgress {
        DayProgress(done: items.filter(\.isDone).count, total: items.count)
    }

    /// Busy minutes in each hour of the day (24 values, each 0...60), for the Wave progress view.
    public static func busyMinutesByHour<Item: ScheduledItem>(_ items: [Item]) -> [Int] {
        var busy = Array(repeating: Set<Int>(), count: 24)
        for item in items {
            guard let start = item.startMinute, let end = item.endMinute, start < end else { continue }
            for minute in max(start, 0)..<end {
                busy[minute / 60].insert(minute)
            }
        }
        return busy.map(\.count)
    }
}

/// Duration choices on the add sheet: quick picks from 15 minutes to 3 hours, nudged in 15-minute steps.
public enum DurationRules {
    public static let quickPicks = [15, 30, 45, 60, 90, 120, 180]
    public static let step = 15
    public static let range = 15...720

    /// Applies `steps` nudges of 15 minutes. Starting from no duration, a plus gives 15 minutes;
    /// going below 15 minutes clears the duration.
    public static func adjust(_ minutes: Int?, bySteps steps: Int) -> Int? {
        guard steps != 0 else { return minutes }
        let base = minutes ?? (steps > 0 ? range.lowerBound - step : range.lowerBound)
        let proposed = base + steps * step
        if proposed < range.lowerBound { return nil }
        return min(proposed, range.upperBound)
    }
}
