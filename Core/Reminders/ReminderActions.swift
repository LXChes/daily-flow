import Foundation

/// The Lock Screen buttons on an urgent reminder. All run in the background, with the app closed.
public enum ReminderAction: String, CaseIterable, Sendable {
    case complete = "df.action.complete"
    case snooze = "df.action.snooze"
    case tomorrow = "df.action.tomorrow"

    public var title: String {
        switch self {
        case .complete: "Complete"
        case .snooze: "Snooze 30m"
        case .tomorrow: "Move to Tomorrow"
        }
    }
}

/// Notification categories and the payload key that carries a task's id.
public enum ReminderRoute {
    public static let urgentCategory = "df.category.urgent"
    public static let briefCategory = "df.category.brief"
    public static let taskIDKey = "taskID"

    public static func userInfo(for task: UUID?) -> [String: String] {
        guard let task else { return [:] }
        return [taskIDKey: task.uuidString]
    }

    /// The task a notification is about, or nil for a brief or a damaged payload.
    public static func taskID(from userInfo: [AnyHashable: Any]) -> UUID? {
        guard let text = userInfo[taskIDKey] as? String else { return nil }
        return UUID(uuidString: text)
    }
}

/// One snoozed reminder.
public struct Snooze: Codable, Equatable, Sendable {
    public let taskID: UUID
    public let until: Date

    public init(taskID: UUID, until: Date) {
        self.taskID = taskID
        self.until = until
    }
}

/// Snoozed reminders, kept on the device so a snooze survives the app being closed and relaunched.
public struct SnoozeBook: Codable, Equatable, Sendable {
    public static let snoozeMinutes = 30

    public private(set) var entries: [Snooze]

    public init(entries: [Snooze] = []) {
        self.entries = entries
    }

    /// Snoozes a task's reminder for 30 minutes from `now`, replacing any earlier snooze. Returns when it fires.
    @discardableResult
    public mutating func snooze(_ task: UUID, now: Date) -> Date {
        let until = now.addingTimeInterval(Double(Self.snoozeMinutes) * 60)
        entries.removeAll { $0.taskID == task }
        entries.append(Snooze(taskID: task, until: until))
        return until
    }

    public mutating func clear(_ task: UUID) {
        entries.removeAll { $0.taskID == task }
    }

    /// Drops snoozes that have already fired.
    public mutating func prune(now: Date) {
        entries.removeAll { $0.until <= now }
    }

    public func until(for task: UUID) -> Date? {
        entries.first { $0.taskID == task }?.until
    }

    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try? encoder.encode(self)
    }

    /// An empty book for missing or damaged data. Never throws.
    public static func decode(_ data: Data?) -> SnoozeBook {
        guard let data else { return SnoozeBook() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode(SnoozeBook.self, from: data)) ?? SnoozeBook()
    }
}
