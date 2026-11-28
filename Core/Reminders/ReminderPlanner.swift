import Foundation

/// One task as the reminder planner sees it. Plain values, so planning is pure and testable.
public struct ReminderTask: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let day: CalendarDay
    public let startMinute: Int?
    public let isUrgent: Bool
    public let isDone: Bool

    public init(id: UUID, title: String, day: CalendarDay, startMinute: Int?, isUrgent: Bool, isDone: Bool) {
        self.id = id
        self.title = title
        self.day = day
        self.startMinute = startMinute
        self.isUrgent = isUrgent
        self.isDone = isDone
    }

    public init(_ task: FlowTask) {
        self.init(
            id: task.id,
            title: task.title,
            day: task.day,
            startMinute: task.startMinute,
            isUrgent: task.isUrgent,
            isDone: task.isDone
        )
    }
}

/// The reminder settings, already validated.
public struct ReminderPreferences: Equatable, Sendable {
    public var morningBriefEnabled: Bool
    public var morningBriefMinute: Int
    public var urgentLeadMinutes: Int
    public var untimedMinute: Int

    public init(morningBriefEnabled: Bool, morningBriefMinute: Int, urgentLeadMinutes: Int, untimedMinute: Int) {
        self.morningBriefEnabled = morningBriefEnabled
        self.morningBriefMinute = MinuteOfDay.clamp(morningBriefMinute)
        self.urgentLeadMinutes = max(0, urgentLeadMinutes)
        self.untimedMinute = MinuteOfDay.clamp(untimedMinute)
    }

    public init(_ settings: AppSettings) {
        self.init(
            morningBriefEnabled: settings.morningBriefEnabled,
            morningBriefMinute: settings.morningBriefTime,
            urgentLeadMinutes: settings.urgentLead,
            untimedMinute: settings.untimedReminderTime
        )
    }
}

public enum ReminderKind: String, Sendable {
    case morningBrief, urgent, snoozed
}

/// A local notification the app should have pending.
public struct PlannedReminder: Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: ReminderKind
    public let fireDate: Date
    public let title: String
    public let body: String
    /// The task the Lock Screen actions act on (urgent and snoozed reminders only).
    public let taskID: UUID?
}

/// Works out every pending notification from the tasks and settings. Pure: same input, same plan.
///
/// The app throws the whole plan at `UNUserNotificationCenter` each time it changes. Identifiers are
/// stable, so re-planning replaces a pending reminder rather than duplicating it, and a reminder whose
/// moment has passed is never planned again, so relaunching the app cannot make one fire twice.
public enum ReminderPlanner {
    /// iOS keeps at most 64 pending local notifications per app; stay safely under.
    public static let maxPending = 60
    /// How many mornings ahead the brief is scheduled.
    public static let briefDays = 7

    public static func plan(
        tasks: [ReminderTask],
        notices: [CalendarDay: [String]],
        snoozes: SnoozeBook,
        preferences: ReminderPreferences,
        now: Date,
        calendar: Calendar
    ) -> [PlannedReminder] {
        var planned: [PlannedReminder] = []

        if preferences.morningBriefEnabled {
            let today = CalendarDay.today(now: now, calendar: calendar)
            for offset in 0..<briefDays {
                let day = today.adding(days: offset)
                let fire = day.date(atMinute: preferences.morningBriefMinute, in: calendar)
                guard fire > now else { continue }
                let text = briefText(tasks: tasks.filter { $0.day == day }, notices: notices[day] ?? [])
                planned.append(PlannedReminder(
                    id: ReminderID.brief(day),
                    kind: .morningBrief,
                    fireDate: fire,
                    title: text.title,
                    body: text.body,
                    taskID: nil
                ))
            }
        }

        for task in tasks where task.isUrgent && !task.isDone {
            if let until = snoozes.until(for: task.id), until > now {
                planned.append(PlannedReminder(
                    id: ReminderID.snoozed(task.id),
                    kind: .snoozed,
                    fireDate: until,
                    title: task.title,
                    body: "Snoozed \u{00B7} " + dueText(task),
                    taskID: task.id
                ))
            } else if let fire = urgentFireDate(for: task, preferences: preferences, now: now, calendar: calendar) {
                planned.append(PlannedReminder(
                    id: ReminderID.urgent(task.id),
                    kind: .urgent,
                    fireDate: fire,
                    title: task.title,
                    body: urgentBody(task, fire: fire, calendar: calendar),
                    taskID: task.id
                ))
            }
        }

        planned.sort { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        return Array(planned.prefix(maxPending))
    }

    /// When an urgent task's reminder fires, or nil when it is not urgent, done or its moment has passed.
    ///
    /// Timed: the lead time before the start. If that has passed but the task has not started yet (it was
    /// added late), the reminder fires at the start instead. Untimed: the untimed reminder time that day.
    public static func urgentFireDate(
        for task: ReminderTask,
        preferences: ReminderPreferences,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard task.isUrgent, !task.isDone else { return nil }
        guard let startMinute = task.startMinute else {
            let fire = task.day.date(atMinute: preferences.untimedMinute, in: calendar)
            return fire > now ? fire : nil
        }
        let start = task.day.date(atMinute: startMinute, in: calendar)
        let lead = start.addingTimeInterval(-Double(preferences.urgentLeadMinutes) * 60)
        if lead > now { return lead }
        if start > now { return start }
        return nil
    }

    /// The morning brief's wording for one day.
    public static func briefText(tasks: [ReminderTask], notices: [String]) -> (title: String, body: String) {
        let title = notices.isEmpty
            ? "Good morning"
            : "It\u{2019}s " + notices.joined(separator: " \u{00B7} ")
        let open = tasks.filter { !$0.isDone }
        guard !open.isEmpty else {
            return (title, "Nothing planned yet. Open Daily Flow to shape the day.")
        }
        var parts = [open.count == 1 ? "1 task today" : "\(open.count) tasks today"]
        let firstTimed = open
            .filter { $0.startMinute != nil }
            .min { ($0.startMinute ?? 0, $0.title) < ($1.startMinute ?? 0, $1.title) }
        if let firstTimed, let start = firstTimed.startMinute {
            parts.append("first up \(firstTimed.title) at \(clock(start))")
        }
        let urgent = open.filter(\.isUrgent).count
        if urgent > 0 {
            parts.append("\(urgent) urgent")
        }
        return (title, parts.joined(separator: " \u{00B7} "))
    }

    static func urgentBody(_ task: ReminderTask, fire: Date, calendar: Calendar) -> String {
        guard let startMinute = task.startMinute else { return "Urgent \u{00B7} due today" }
        let start = task.day.date(atMinute: startMinute, in: calendar)
        let minutesAway = Int((start.timeIntervalSince(fire) / 60).rounded())
        if minutesAway <= 0 {
            return "Urgent \u{00B7} starting now, \(clock(startMinute))"
        }
        return "Urgent \u{00B7} starts at \(clock(startMinute)), in \(minutesAway) min"
    }

    static func dueText(_ task: ReminderTask) -> String {
        guard let startMinute = task.startMinute else { return "due today" }
        return "starts at \(clock(startMinute))"
    }

    /// "09:05". Matches the app's 24-hour clock.
    static func clock(_ minute: Int) -> String {
        let value = MinuteOfDay.clamp(minute)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

/// Stable notification identifiers. Everything the app schedules starts with `prefix`.
public enum ReminderID {
    public static let prefix = "df."

    public static func brief(_ day: CalendarDay) -> String { "df.brief.\(day.key)" }
    public static func urgent(_ task: UUID) -> String { "df.urgent.\(task.uuidString)" }
    public static func snoozed(_ task: UUID) -> String { "df.snooze.\(task.uuidString)" }

    /// Every identifier that can belong to one task, for clearing them when it is ticked off.
    public static func all(for task: UUID) -> [String] { [urgent(task), snoozed(task)] }
}
