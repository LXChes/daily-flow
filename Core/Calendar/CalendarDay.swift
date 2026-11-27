import Foundation

/// A date on the Gregorian calendar with no time of day and no time zone.
///
/// Tasks and notices are pinned to a `CalendarDay`, never to an absolute `Date`, so a task set for
/// "Friday" stays on Friday when the clocks change or the phone crosses a time zone. Converting to and
/// from `Date` always goes through an injected `Calendar`, so every rule can be tested with fixed dates.
public struct CalendarDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Returns `nil` for dates that do not exist, such as 30 February.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month),
              day >= 1,
              day <= CalendarDay.numberOfDays(inMonth: month, year: year) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// 1 January of `year`, which always exists.
    init(january1Of year: Int) {
        self.year = year
        self.month = 1
        self.day = 1
    }

    /// The day containing `date`, read in the time zone of `calendar`.
    public init(_ date: Date, calendar: Calendar) {
        let parts = CalendarDay.gregorian(matching: calendar).dateComponents([.year, .month, .day], from: date)
        if let year = parts.year, let month = parts.month, let day = parts.day,
           let value = CalendarDay(year: year, month: month, day: day) {
            self = value
        } else {
            // Unreachable for a Gregorian calendar; fall back to plain UTC arithmetic instead of trapping.
            self = CalendarDay(dayNumber: Int((date.timeIntervalSince1970 / 86_400).rounded(.down)))
        }
    }

    /// Days since 1970-01-01 (negative before it).
    public init(dayNumber: Int) {
        // Civil-from-days, H. Hinnant's public-domain algorithm (proleptic Gregorian).
        let z = dayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        self.year = yoe + era * 400 + (month <= 2 ? 1 : 0)
        self.month = month
        self.day = day
    }

    /// Restores a day from its storage `key` (`yyyymmdd`). Returns `nil` for malformed keys.
    public init?(key: Int) {
        self.init(year: key / 10_000, month: (key / 100) % 100, day: key % 100)
    }

    // MARK: Derived values

    /// Compact, sortable storage form, e.g. 2030-03-04 is `20300304`.
    public var key: Int { year * 10_000 + month * 100 + day }

    /// Days since 1970-01-01.
    public var dayNumber: Int {
        // Days-from-civil, H. Hinnant's public-domain algorithm.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// 1 = Sunday ... 7 = Saturday, matching `Calendar.component(.weekday, from:)`.
    public var weekday: Int {
        // 1970-01-01 was a Thursday (5).
        let offset = (dayNumber + 4) % 7
        return (offset < 0 ? offset + 7 : offset) + 1
    }

    public func adding(days: Int) -> CalendarDay {
        CalendarDay(dayNumber: dayNumber + days)
    }

    /// Whole days from `other` to `self` (positive when `self` is later).
    public func days(since other: CalendarDay) -> Int {
        dayNumber - other.dayNumber
    }

    /// Midnight at the start of this day in the time zone of `calendar`.
    public func startDate(in calendar: Calendar) -> Date {
        date(atMinute: 0, in: calendar)
    }

    /// The moment `minute` minutes after midnight on this day (0...1439), in the time zone of `calendar`.
    /// A time skipped by a daylight-saving jump resolves to the next valid moment.
    public func date(atMinute minute: Int, in calendar: Calendar) -> Date {
        let clamped = MinuteOfDay.clamp(minute)
        let parts = DateComponents(year: year, month: month, day: day, hour: clamped / 60, minute: clamped % 60)
        if let date = CalendarDay.gregorian(matching: calendar).date(from: parts) {
            return date
        }
        return Date(timeIntervalSince1970: TimeInterval(dayNumber * 86_400 + clamped * 60))
    }

    public var description: String {
        func pad(_ value: Int, _ width: Int) -> String {
            let digits = String(value)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        lhs.key < rhs.key
    }

    // MARK: Calendar helpers

    public static func today(now: Date, calendar: Calendar) -> CalendarDay {
        CalendarDay(now, calendar: calendar)
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func numberOfDays(inMonth month: Int, year: Int) -> Int {
        switch month {
        case 2: return isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// A Gregorian calendar sharing the injected calendar's time zone, so the owner's calendar setting
    /// (for example Buddhist or Japanese) never changes which day a task is on.
    static func gregorian(matching calendar: Calendar) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        gregorian.locale = calendar.locale
        return gregorian
    }
}

/// Minutes after midnight, 0...1439. Used for task times and reminder times.
public enum MinuteOfDay {
    public static let range = 0...1_439

    public static func clamp(_ minute: Int) -> Int {
        min(max(minute, range.lowerBound), range.upperBound)
    }

    /// Minutes after midnight for `date`, in the time zone of `calendar`.
    public static func of(_ date: Date, calendar: Calendar) -> Int {
        let parts = CalendarDay.gregorian(matching: calendar).dateComponents([.hour, .minute], from: date)
        return clamp((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }
}
