import AppIntents
import DailyFlowCore
import SwiftUI
import UserNotifications
import WidgetKit

// Compiled into BOTH the widget extension and the app: the app's DEBUG widget gallery draws the same
// views for CI screenshots, and the tick intent can run in either process.

/// Every widget Daily Flow offers. Each is its own `Widget` kind, so it appears separately in the picker.
enum DFWidgetKind: String, CaseIterable, Sendable {
    /// Lock Screen rectangular: the next task with a tick.
    case upNext = "df.upnext"
    /// Lock Screen circular and Home small: percentage ring.
    case progressRing = "df.ring"
    /// Home small: "3/8" done ring.
    case doneRing = "df.done"
    /// Home medium: busy-time bars with done tasks lit and a now line.
    case wave = "df.wave"
    /// Lock Screen circular: the skeleton watch, simplified. Home medium: the watch head + two tickable tasks.
    case dayDial = "df.dial"
    /// Lock Screen inline: notice day or progress line.
    case todayLine = "df.line"

    var displayName: String {
        switch self {
        case .upNext: "Up next"
        case .progressRing: "Progress ring"
        case .doneRing: "Done count"
        case .wave: "Wave"
        case .dayDial: "Day dial"
        case .todayLine: "Today line"
        }
    }

    var summary: String {
        switch self {
        case .upNext: "Your next task. Tick it off from the Lock Screen."
        case .progressRing: "How much of today is done."
        case .doneRing: "Tasks done out of today\u{2019}s total."
        case .wave: "Busy times across the day, with done tasks lit."
        case .dayDial: "Your day as a skeleton watch: tasks are gears and arcs."
        case .todayLine: "A notice day or today\u{2019}s progress, above the clock."
        }
    }

    var families: [WidgetFamily] {
        switch self {
        case .upNext: [.accessoryRectangular]
        case .progressRing: [.accessoryCircular, .systemSmall]
        case .doneRing: [.systemSmall]
        case .wave: [.systemMedium]
        case .dayDial: [.accessoryCircular, .systemMedium]
        case .todayLine: [.accessoryInline]
        }
    }
}

/// One moment of a widget timeline.
struct DFWidgetEntry: TimelineEntry, Sendable {
    let date: Date
    let day: WidgetDay
    /// The resolved theme (per-widget style, then Settings, then the app's theme).
    let theme: ThemeMode
    /// Minutes after midnight at `date`, in the owner's calendar.
    let minute: Int

    var snapshot: DaySnapshot { day.snapshot }
    var palette: Palette { Palette.for(theme) }
}

/// Neutral sample data for the widget picker, placeholders and the demo gallery. No personal data.
enum WidgetSamples {
    static func day(now: Date, calendar: Calendar) -> DaySnapshot {
        let today = CalendarDay.today(now: now, calendar: calendar)
        let items: [(String, TaskCategory, Int?, Int?, Bool, Bool)] = [
            ("Gym", .health, 7 * 60 + 30, 60, false, true),
            ("Lecture", .uni, 10 * 60, 120, false, false),
            ("Seminar", .uni, 14 * 60, 60, false, false),
            ("Food shopping", .errands, 17 * 60 + 30, 45, false, false),
            ("Essay draft", .uni, nil, nil, true, false),
            ("Laundry", .home, nil, nil, false, false)
        ]
        let tasks = items.enumerated().map { index, item in
            TaskSnapshot(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1)) ?? UUID(),
                title: item.0,
                category: item.1,
                startMinute: item.2,
                durationMinutes: item.3,
                isUrgent: item.4,
                isDone: item.5,
                sortIndex: index,
                createdAt: Date(timeIntervalSince1970: 0)
            )
        }
        return DaySnapshot(generatedAt: now, day: today, tasks: tasks, noticeTitles: [], widgetStyle: .matchApp, theme: .dark)
    }

    static func entry(now: Date, calendar: Calendar, theme: ThemeMode = .dark) -> DFWidgetEntry {
        DFWidgetEntry(
            date: now,
            day: WidgetDay(snapshot: day(now: now, calendar: calendar), source: .shared),
            theme: theme,
            minute: MinuteOfDay.of(now, calendar: calendar)
        )
    }
}

/// Ticks or unticks a task from a widget, with the app closed.
///
/// In the widget extension (the usual case) the tick is queued in the shared folder and the shared
/// snapshot is updated so every widget shows it at once; the app applies the queue the next time it
/// runs. If iOS runs the intent in the app's own process, the app applies it directly.
struct ToggleTaskIntent: AppIntent {
    static var title: LocalizedStringResource { "Tick task" }
    static var description: IntentDescription { IntentDescription("Marks a Daily Flow task done or not done.") }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Task") var taskID: String
    @Parameter(title: "Done") var done: Bool

    init() {}

    init(task: UUID, done: Bool) {
        self.taskID = task.uuidString
        self.done = done
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        let target = done
        let handledByApp = await MainActor.run { WidgetTickRouter.handle(id, done: target) }
        if !handledByApp {
            WidgetDataStore.recordTick(taskID: id, done: target, now: .now)
            if target {
                // The reminder is no longer needed. Removing it here means it cannot fire before the app
                // next runs and applies the tick.
                let ids = ReminderID.all(for: id)
                let center = UNUserNotificationCenter.current()
                center.removePendingNotificationRequests(withIdentifiers: ids)
                center.removeDeliveredNotifications(withIdentifiers: ids)
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
