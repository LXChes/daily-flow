import DailyFlowCore
import Foundation

/// Plain-text formatting for times and dates. 24-hour, as in the design.
enum Fmt {
    /// "07:05". Clamped to 00:00...23:59.
    static func clock(_ minute: Int) -> String {
        let value = MinuteOfDay.clamp(minute)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    /// Whole minutes of a gliding playhead value.
    static func clock(fractional minute: Double) -> String {
        clock(Int(minute.rounded(.down)))
    }

    /// An end time; 24:00 reads as midnight.
    static func clockEnd(_ minute: Int) -> String {
        minute >= DaySchedule.minutesPerDay ? "24:00" : clock(minute)
    }

    /// "45m", "1h", "1h 30m".
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        if rest == 0 { return "\(hours)h" }
        return "\(hours)h \(rest)m"
    }

    /// "07:30-08:30", or just the start when there is no duration.
    static func span(start: Int, duration: Int?) -> String {
        guard let duration else { return clock(start) }
        return "\(clock(start))\u{2013}\(clockEnd(start + duration))"
    }
}

/// Day names built from the injected calendar's locale, so they need no formatter objects.
enum DateText {
    private static func gregorian(_ calendar: Calendar) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = calendar.locale ?? .current
        value.timeZone = calendar.timeZone
        return value
    }

    private static func weekdayName(_ day: CalendarDay, _ calendar: Calendar, short: Bool) -> String {
        let source = gregorian(calendar)
        let names = short ? source.shortWeekdaySymbols : source.weekdaySymbols
        return names.indices.contains(day.weekday - 1) ? names[day.weekday - 1] : ""
    }

    private static func monthName(_ day: CalendarDay, _ calendar: Calendar, short: Bool) -> String {
        let source = gregorian(calendar)
        let names = short ? source.shortMonthSymbols : source.monthSymbols
        return names.indices.contains(day.month - 1) ? names[day.month - 1] : ""
    }

    /// "Tuesday 17 November".
    static func long(_ day: CalendarDay, calendar: Calendar) -> String {
        "\(weekdayName(day, calendar, short: false)) \(day.day) \(monthName(day, calendar, short: false))"
    }

    /// "Tue 17 Nov".
    static func medium(_ day: CalendarDay, calendar: Calendar) -> String {
        "\(weekdayName(day, calendar, short: true)) \(day.day) \(monthName(day, calendar, short: true))"
    }

    /// "Tue 17".
    static func chip(_ day: CalendarDay, calendar: Calendar) -> String {
        "\(weekdayName(day, calendar, short: true)) \(day.day)"
    }

    /// "Monday".
    static func weekday(_ day: CalendarDay, calendar: Calendar) -> String {
        weekdayName(day, calendar, short: false)
    }

    /// "17 Nov".
    static func dayMonth(_ day: CalendarDay, calendar: Calendar) -> String {
        "\(day.day) \(monthName(day, calendar, short: true))"
    }
}
