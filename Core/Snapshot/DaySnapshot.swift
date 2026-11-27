import Foundation

/// A plain, versioned copy of one task for widgets and notifications. No SwiftData types inside.
public struct TaskSnapshot: Codable, Equatable, Sendable, Identifiable, ScheduledItem {
    public let id: UUID
    public let title: String
    public let category: TaskCategory
    public let startMinute: Int?
    public let durationMinutes: Int?
    public let isUrgent: Bool
    public let isDone: Bool
    public let sortIndex: Int
    public let createdAt: Date

    public init(
        id: UUID,
        title: String,
        category: TaskCategory,
        startMinute: Int?,
        durationMinutes: Int?,
        isUrgent: Bool,
        isDone: Bool,
        sortIndex: Int,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
        self.isUrgent = isUrgent
        self.isDone = isDone
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }

    public init(_ task: FlowTask) {
        self.init(
            id: task.id,
            title: task.title,
            category: task.category,
            startMinute: task.startMinute,
            durationMinutes: task.durationMinutes,
            isUrgent: task.isUrgent,
            isDone: task.isDone,
            sortIndex: task.sortIndex,
            createdAt: task.createdAt
        )
    }
}

/// Everything a widget needs to draw one day, small enough to write to a file or `UserDefaults`.
///
/// M4 writes this after every change. Reading never throws: a missing, damaged or newer-format
/// snapshot decodes to `nil`, and the widget then shows `placeholder`.
public struct DaySnapshot: Codable, Equatable, Sendable {
    public static let formatVersion = 1

    public let version: Int
    public let generatedAt: Date
    public let day: CalendarDay
    /// In display order.
    public let tasks: [TaskSnapshot]
    public let noticeTitles: [String]
    public let widgetStyle: WidgetStyle
    public let theme: ThemeMode

    public init(
        generatedAt: Date,
        day: CalendarDay,
        tasks: [TaskSnapshot],
        noticeTitles: [String],
        widgetStyle: WidgetStyle,
        theme: ThemeMode
    ) {
        self.version = DaySnapshot.formatVersion
        self.generatedAt = generatedAt
        self.day = day
        self.tasks = tasks
        self.noticeTitles = noticeTitles
        self.widgetStyle = widgetStyle
        self.theme = theme
    }

    public var progress: DayProgress { DaySchedule.progress(tasks) }

    /// An empty day for when no snapshot can be read.
    public static func placeholder(now: Date, calendar: Calendar) -> DaySnapshot {
        DaySnapshot(
            generatedAt: now,
            day: CalendarDay.today(now: now, calendar: calendar),
            tasks: [],
            noticeTitles: [],
            widgetStyle: .matchApp,
            theme: .dark
        )
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(self)
    }

    /// `nil` for missing, damaged or unsupported data. Never throws.
    public static func decode(_ data: Data?) -> DaySnapshot? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(DaySnapshot.self, from: data),
              snapshot.version == formatVersion else { return nil }
        return snapshot
    }
}
