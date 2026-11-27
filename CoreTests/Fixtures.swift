import Foundation
@testable import DailyFlowCore

/// Fixed, neutral test inputs. No real people or personal dates.
enum Fixture {
    static let london: Calendar = calendar("Europe/London")
    static let tokyo: Calendar = calendar("Asia/Tokyo")

    static func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? .gmt
        return calendar
    }

    /// A day from a `yyyymmdd` key. Test inputs are always valid dates.
    static func day(_ key: Int) -> CalendarDay {
        CalendarDay(key: key) ?? CalendarDay(dayNumber: 0)
    }

    /// A moment on `key` at `hour:minute`, London time.
    static func moment(_ key: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        day(key).date(atMinute: hour * 60 + minute, in: london)
    }
}

/// A minimal schedulable item for the pure scheduling rules.
struct Item: ScheduledItem, Equatable {
    var name: String
    var startMinute: Int?
    var durationMinutes: Int?
    var isDone = false
    var isUrgent = false
    var sortIndex = 0
    var createdAt = Date(timeIntervalSince1970: 0)
}
