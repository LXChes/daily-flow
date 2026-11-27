import DailyFlowCore
import Foundation

/// The app's source of "now". Injected so the belt, the clock and "today" are deterministic in demo
/// mode; in normal use it is the real time and the owner's current calendar.
struct DFClock: Sendable {
    private let provider: @Sendable () -> Date
    let calendar: Calendar

    init(calendar: Calendar, now: @escaping @Sendable () -> Date) {
        self.calendar = calendar
        self.provider = now
    }

    func now() -> Date {
        provider()
    }

    var today: CalendarDay {
        CalendarDay.today(now: now(), calendar: calendar)
    }

    /// Minutes after midnight including the seconds as a fraction, so the playhead glides.
    func fractionalMinute(of date: Date) -> Double {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let whole = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return Double(whole) + Double(parts.second ?? 0) / 60
    }

    static var live: DFClock {
        DFClock(calendar: .autoupdatingCurrent) { Date() }
    }

    static func fixed(_ date: Date, calendar: Calendar) -> DFClock {
        DFClock(calendar: calendar) { date }
    }
}
