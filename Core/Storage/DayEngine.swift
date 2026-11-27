import Foundation
import SwiftData

/// What the app needs to know after the day may have changed.
public struct DayStatus: Equatable, Sendable {
    public let today: CalendarDay
    /// Leftovers waiting in the morning brief (always 0 when triage is off).
    public let leftoverCount: Int
    /// Leftovers moved onto today automatically because triage is off.
    public let rolledOverCount: Int
    public let notices: [NoticeOccurrence]
}

/// Ties the stores together for day-level work. Call `refresh` on launch, when the app becomes active
/// and when the day changes.
@MainActor
public final class DayEngine {
    public let tasks: TaskStore
    public let notices: NoticeStore
    public let settings: SettingsStore

    public init(context: ModelContext) {
        tasks = TaskStore(context: context)
        notices = NoticeStore(context: context)
        settings = SettingsStore(context: context)
    }

    public func refresh(now: Date, calendar: Calendar) throws -> DayStatus {
        let today = CalendarDay.today(now: now, calendar: calendar)
        let current = try settings.current()
        try notices.ensureBuiltIns()

        let rolledOver = try current.leftoversTriageEnabled ? 0 : tasks.rollLeftoversOntoToday(today)
        let waiting = try tasks.leftovers(today: today).count
        let rules = try notices.activeRules(noticesEnabled: current.noticesEnabled)
        return DayStatus(
            today: today,
            leftoverCount: waiting,
            rolledOverCount: rolledOver,
            notices: NoticeCalendar.notices(on: today, rules: rules)
        )
    }

    /// A compact copy of today for widgets and notifications.
    public func snapshot(now: Date, calendar: Calendar) throws -> DaySnapshot {
        let today = CalendarDay.today(now: now, calendar: calendar)
        let current = try settings.current()
        let todaysTasks = try tasks.tasks(on: today, autoSort: current.autoSortEnabled)
        let rules = try notices.activeRules(noticesEnabled: current.noticesEnabled)
        return DaySnapshot(
            generatedAt: now,
            day: today,
            tasks: todaysTasks.map { TaskSnapshot($0) },
            noticeTitles: NoticeCalendar.notices(on: today, rules: rules).map(\.title),
            widgetStyle: current.widgetStyle,
            theme: current.theme
        )
    }
}
