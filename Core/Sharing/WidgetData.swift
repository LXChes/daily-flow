import Foundation

/// Where a widget's data came from, best first.
public enum WidgetDataSource: String, Sendable {
    /// Read from the shared folder just now: real tasks, and ticking works.
    case shared
    /// The shared folder could not be read this time; the widget's own last good copy (real tasks,
    /// read-only).
    case cached
    /// No usable data for today (no shared folder, or the app has not run yet today). The widget shows
    /// what it can work out itself: the date, the time and the built-in notice days.
    case basic
}

/// What one widget timeline draws.
public struct WidgetDay: Equatable, Sendable {
    public let snapshot: DaySnapshot
    public let source: WidgetDataSource

    public init(snapshot: DaySnapshot, source: WidgetDataSource) {
        self.snapshot = snapshot
        self.source = source
    }

    public var hasTasks: Bool { source != .basic }
    /// Tick buttons only appear when a tick can reach the app.
    public var canTick: Bool { source == .shared }
}

/// Picks what a widget shows. Pure, so the fallback order is unit-tested.
public enum WidgetDataResolver {
    public static func resolve(
        shared: DaySnapshot?,
        cached: DaySnapshot?,
        now: Date,
        calendar: Calendar
    ) -> WidgetDay {
        let today = CalendarDay.today(now: now, calendar: calendar)
        if let shared, shared.day == today {
            return WidgetDay(snapshot: shared, source: .shared)
        }
        if let cached, cached.day == today {
            return WidgetDay(snapshot: cached, source: .cached)
        }
        // An older snapshot still tells us the owner's chosen look.
        let known = shared ?? cached
        let basic = DaySnapshot(
            generatedAt: now,
            day: today,
            tasks: [],
            noticeTitles: NoticeCalendar.notices(on: today, rules: NoticeCalendar.builtInRules).map(\.title),
            widgetStyle: known?.widgetStyle ?? .matchApp,
            theme: known?.theme ?? .dark
        )
        return WidgetDay(snapshot: basic, source: .basic)
    }
}

extension WidgetStyle {
    /// The theme a widget draws in. A widget's own style wins; "Match app" defers to the style chosen in
    /// Settings, and if that is also "Match app", to the app's theme.
    public static func resolvedTheme(widget: WidgetStyle, global: WidgetStyle, appTheme: ThemeMode) -> ThemeMode {
        switch widget {
        case .darkChrome: return .dark
        case .lightVintage: return .light
        case .matchApp:
            switch global {
            case .darkChrome: return .dark
            case .lightVintage: return .light
            case .matchApp: return appTheme
            }
        }
    }
}

extension DaySnapshot {
    /// True when two snapshots would draw the same widgets (ignores when they were made).
    public func hasSameContent(as other: DaySnapshot) -> Bool {
        day == other.day && tasks == other.tasks && noticeTitles == other.noticeTitles
            && widgetStyle == other.widgetStyle && theme == other.theme
    }

    /// A copy with one task ticked or unticked, for showing a widget tick straight away.
    public func settingTask(_ id: UUID, done: Bool, now: Date) -> DaySnapshot {
        let updated = tasks.map { task -> TaskSnapshot in
            guard task.id == id else { return task }
            return TaskSnapshot(
                id: task.id,
                title: task.title,
                category: task.category,
                startMinute: task.startMinute,
                durationMinutes: task.durationMinutes,
                isUrgent: task.isUrgent,
                isDone: done,
                sortIndex: task.sortIndex,
                createdAt: task.createdAt
            )
        }
        return DaySnapshot(
            generatedAt: now,
            day: day,
            tasks: updated,
            noticeTitles: noticeTitles,
            widgetStyle: widgetStyle,
            theme: theme
        )
    }

    /// The next unfinished tasks at `minute`, for "Up next": timed tasks still running or ahead, in time
    /// order, then untimed ones in display order.
    public func upNext(atMinute minute: Int, limit: Int) -> [TaskSnapshot] {
        let open = tasks.filter { !$0.isDone }
        let timed = DaySchedule.timed(open).filter { ($0.endMinute ?? 0) > minute }
        let anytime = open.filter { !$0.isTimed }
        return Array((timed + anytime).prefix(max(0, limit)))
    }
}

/// A tick made on a widget, waiting for the app to apply it to the store.
public struct WidgetTick: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let taskID: UUID
    public let isDone: Bool
    public let at: Date

    public init(id: UUID = UUID(), taskID: UUID, isDone: Bool, at: Date) {
        self.id = id
        self.taskID = taskID
        self.isDone = isDone
        self.at = at
    }
}

/// Widget ticks in the order they were made. Widgets cannot open the app's database, so they leave
/// ticks here; the app applies them the next time it runs and removes exactly the ones it applied.
public struct WidgetTickQueue: Codable, Equatable, Sendable {
    public private(set) var ticks: [WidgetTick]

    public init(ticks: [WidgetTick] = []) {
        self.ticks = ticks
    }

    public mutating func append(_ tick: WidgetTick) {
        ticks.append(tick)
    }

    /// The final state per task: ticking then unticking the same task leaves only "not done".
    public var latestPerTask: [WidgetTick] {
        var latest: [UUID: WidgetTick] = [:]
        for tick in ticks {
            latest[tick.taskID] = tick
        }
        return latest.values.sorted { $0.at < $1.at }
    }

    public func removing(_ ids: Set<UUID>) -> WidgetTickQueue {
        WidgetTickQueue(ticks: ticks.filter { !ids.contains($0.id) })
    }

    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try? encoder.encode(self)
    }

    public static func decode(_ data: Data?) -> WidgetTickQueue {
        guard let data else { return WidgetTickQueue() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode(WidgetTickQueue.self, from: data)) ?? WidgetTickQueue()
    }
}
