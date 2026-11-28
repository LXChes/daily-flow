#if DEBUG
import DailyFlowCore
import Foundation
import OSLog
import SwiftData

/// Screenshot support, compiled out of Release builds.
///
/// `-DFDemo YES` opens an in-memory store seeded with neutral demo tasks and a fixed clock of 10:15 on a
/// fixed day. `-DFScene <name>` then opens a particular state straight away:
/// day, day-light, list, list-light, sorted, triage, add, view, settings, notice, ring, bar, number.
@MainActor
enum DemoSupport {
    private static let logger = Logger(subsystem: "com.example.dailyflow", category: "demo")

    private struct Seed {
        let title: String
        var start: Int?
        var duration: Int?
        var isUrgent = false
        var isDone = false
    }

    static func makeModel() -> AppModel? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "DFDemo") else { return nil }
        let scene = defaults.string(forKey: "DFScene") ?? ""

        do {
            let container = try DailyFlowStore.makeContainer(inMemory: true)
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "en_GB")
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current

            let today = CalendarDay(year: 2026, month: 11, day: 17) ?? CalendarDay(dayNumber: 0)
            let now = today.date(atMinute: 10 * 60 + 15, in: calendar)

            let engine = DayEngine(context: container.mainContext)
            try seed(engine, today: today, now: now)
            try configure(engine, scene: scene)

            let model = AppModel(container: container, isTemporaryStore: false, clock: .fixed(now, calendar: calendar))
            present(scene, on: model)
            return model
        } catch {
            logger.error("Demo setup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func seed(_ engine: DayEngine, today: CalendarDay, now: Date) throws {
        let todays: [Seed] = [
            Seed(title: "Gym", start: 7 * 60 + 30, duration: 60, isDone: true),
            Seed(title: "Take vitamins", isDone: true),
            Seed(title: "Lecture", start: 10 * 60, duration: 120),
            Seed(title: "Coffee with a friend", start: 12 * 60 + 30, duration: 60),
            Seed(title: "Seminar", start: 14 * 60, duration: 60),
            Seed(title: "Buy bus tickets"),
            Seed(title: "Essay draft", isUrgent: true),
            Seed(title: "Food shopping", start: 17 * 60 + 30, duration: 45),
            Seed(title: "Cook dinner", start: 19 * 60, duration: 45)
        ]
        for (index, item) in todays.enumerated() {
            let task = try engine.tasks.add(
                title: item.title,
                day: today,
                startMinute: item.start,
                durationMinutes: item.duration,
                isUrgent: item.isUrgent,
                now: now.addingTimeInterval(Double(index))
            )
            if item.isDone {
                try engine.tasks.setDone(task, true, at: now)
            }
        }
        // Two leftovers from yesterday.
        let yesterday = today.adding(days: -1)
        for (index, title) in ["Essay plan", "Laundry"].enumerated() {
            try engine.tasks.add(title: title, day: yesterday, now: now.addingTimeInterval(Double(100 + index)))
        }
    }

    private static func configure(_ engine: DayEngine, scene: String) throws {
        let settings = try engine.settings.current()
        switch scene {
        case "day-light": settings.theme = .light
        case "list": settings.layout = .list
        case "list-light":
            settings.layout = .list
            settings.theme = .light
        case "sorted": settings.categoryMode = .sorted
        case "ring": settings.progressStyle = .ring
        case "bar": settings.progressStyle = .bar
        case "number": settings.progressStyle = .number
        default: break
        }
        try engine.settings.save()
    }

    private static func present(_ scene: String, on model: AppModel) {
        switch scene {
        case "triage": model.sheet = .triage
        case "add": model.sheet = .add
        case "settings": model.sheet = .settings
        case "view": model.showsViewSwitcher = true
        case "notice": model.setPreview(.nextNotice)
        case "remind": model.showDemoReminders(.notAsked)
        case "settings-off":
            model.showDemoReminders(.denied)
            model.sheet = .settings
        default: break
        }
    }
}
#endif
