import Foundation

/// The notice days that ship with the app. Their dates are computed, never stored.
public enum BuiltInNotice: String, CaseIterable, Codable, Sendable {
    case newYearsDay = "new-years-day"
    case mothersDayUK = "mothers-day-uk"
    case easterSunday = "easter-sunday"
    case fathersDayUK = "fathers-day-uk"
    case halloween = "halloween"
    case christmasDay = "christmas-day"
    case newYearsEve = "new-years-eve"

    public var title: String {
        switch self {
        case .newYearsDay: "New Year's Day"
        case .mothersDayUK: "Mother's Day"
        case .easterSunday: "Easter Sunday"
        case .fathersDayUK: "Father's Day"
        case .halloween: "Halloween"
        case .christmasDay: "Christmas Day"
        case .newYearsEve: "New Year's Eve"
        }
    }

    /// The date this notice falls on in `year`.
    public func day(in year: Int) -> CalendarDay {
        switch self {
        case .newYearsDay: NoticeMath.fixed(year, 1, 1)
        case .mothersDayUK: NoticeMath.easterSunday(year: year).adding(days: -21) // Mothering Sunday
        case .easterSunday: NoticeMath.easterSunday(year: year)
        case .fathersDayUK: NoticeMath.nthWeekday(3, weekday: 1, month: 6, year: year) // 3rd Sunday of June
        case .halloween: NoticeMath.fixed(year, 10, 31)
        case .christmasDay: NoticeMath.fixed(year, 12, 25)
        case .newYearsEve: NoticeMath.fixed(year, 12, 31)
        }
    }
}

/// How a notice repeats.
public enum NoticeSchedule: Hashable, Codable, Sendable {
    case builtIn(BuiltInNotice)
    /// Every year on this month and day. 29 February falls on 28 February in non-leap years.
    case everyYear(month: Int, day: Int)
    /// A single date.
    case once(CalendarDay)

    /// The occurrence in `year`, or `nil` if there is none that year.
    public func occurrence(in year: Int) -> CalendarDay? {
        switch self {
        case .builtIn(let notice):
            return notice.day(in: year)
        case .everyYear(let month, let day):
            guard (1...12).contains(month), day >= 1 else { return nil }
            let lastDay = CalendarDay.numberOfDays(inMonth: month, year: year)
            return CalendarDay(year: year, month: month, day: min(day, lastDay))
        case .once(let date):
            return date.year == year ? date : nil
        }
    }
}

/// A notice the engine can place on the calendar: a built-in or an owner-added custom notice.
public struct NoticeRule: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let schedule: NoticeSchedule

    public init(id: String, title: String, schedule: NoticeSchedule) {
        self.id = id
        self.title = title
        self.schedule = schedule
    }

    public init(_ builtIn: BuiltInNotice) {
        self.init(id: NoticeRule.key(for: builtIn), title: builtIn.title, schedule: .builtIn(builtIn))
    }

    public static func key(for builtIn: BuiltInNotice) -> String {
        "builtin.\(builtIn.rawValue)"
    }
}

/// One rule landing on one day.
public struct NoticeOccurrence: Hashable, Sendable, Identifiable {
    public let rule: NoticeRule
    public let day: CalendarDay

    public var id: String { "\(rule.id)@\(day.key)" }
    public var title: String { rule.title }
}

/// Pure notice-day lookups. Pass the rules that are switched on; the engine never reads storage.
public enum NoticeCalendar {
    /// Every built-in notice, in calendar order.
    public static var builtInRules: [NoticeRule] {
        BuiltInNotice.allCases.map(NoticeRule.init)
    }

    /// Notices on `day`, in the order the rules were given.
    public static func notices(on day: CalendarDay, rules: [NoticeRule]) -> [NoticeOccurrence] {
        rules.compactMap { rule in
            rule.schedule.occurrence(in: day.year) == day ? NoticeOccurrence(rule: rule, day: day) : nil
        }
    }

    /// Notices from `start` up to and including `start + days`, soonest first.
    public static func upcoming(from start: CalendarDay, days: Int, rules: [NoticeRule]) -> [NoticeOccurrence] {
        guard days >= 0 else { return [] }
        let end = start.adding(days: days)
        var found: [NoticeOccurrence] = []
        for year in start.year...end.year {
            for rule in rules {
                if let day = rule.schedule.occurrence(in: year), day >= start, day <= end {
                    found.append(NoticeOccurrence(rule: rule, day: day))
                }
            }
        }
        return found.sorted { lhs, rhs in
            lhs.day == rhs.day ? lhs.title < rhs.title : lhs.day < rhs.day
        }
    }
}

/// Date arithmetic for the built-in notices.
public enum NoticeMath {
    /// Western (Gregorian) Easter Sunday, by the anonymous Gregorian algorithm (Meeus/Jones/Butcher).
    public static func easterSunday(year: Int) -> CalendarDay {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return fixed(year, month, day)
    }

    /// The `n`th given weekday (1 = Sunday ... 7 = Saturday) of a month, for n in 1...4.
    public static func nthWeekday(_ n: Int, weekday: Int, month: Int, year: Int) -> CalendarDay {
        let first = fixed(year, month, 1)
        let toFirstMatch = ((weekday - first.weekday) % 7 + 7) % 7
        return first.adding(days: toFirstMatch + 7 * (max(n, 1) - 1))
    }

    /// A date known to exist. Falls back to 1 January rather than trapping on bad input.
    static func fixed(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day) ?? CalendarDay(january1Of: year)
    }
}
