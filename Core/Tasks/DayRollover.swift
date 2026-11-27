import Foundation

/// The owner's choice for each leftover in the morning triage sheet.
public enum LeftoverChoice: String, CaseIterable, Codable, Sendable {
    case keepToday, tomorrow, bin

    public var title: String {
        switch self {
        case .keepToday: "Keep today"
        case .tomorrow: "Tomorrow"
        case .bin: "Bin"
        }
    }
}

/// Pure day-change rules.
///
/// - A task belongs to exactly one day and is shown only on that day, so tasks added for a future day
///   appear when that day arrives.
/// - An unfinished task from an earlier day is a leftover. With triage on it waits in the morning brief
///   until the owner chooses; with triage off it rolls onto today automatically.
/// - Finished tasks stay on the day they were done.
public enum DayRollover {
    public static func isLeftover(taskDay: CalendarDay, isDone: Bool, today: CalendarDay) -> Bool {
        !isDone && taskDay < today
    }

    public static func isShown(taskDay: CalendarDay, on day: CalendarDay) -> Bool {
        taskDay == day
    }

    /// The new day for a leftover, or `nil` when it should be deleted.
    public static func destination(for choice: LeftoverChoice, today: CalendarDay) -> CalendarDay? {
        switch choice {
        case .keepToday: today
        case .tomorrow: today.adding(days: 1)
        case .bin: nil
        }
    }

    /// Days offered on the add sheet: today, tomorrow and the next five days.
    public static func quickPickDays(from today: CalendarDay) -> [CalendarDay] {
        (0..<7).map { today.adding(days: $0) }
    }
}
