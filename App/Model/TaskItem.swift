import DailyFlowCore
import Foundation

/// An immutable copy of a stored task. Views read these, never the live SwiftData objects, so a row that
/// is animating out after a delete can never touch a model that no longer exists.
struct TaskItem: Identifiable, Equatable, Sendable, ScheduledItem {
    let id: UUID
    let title: String
    let day: CalendarDay
    let category: TaskCategory
    let startMinute: Int?
    let durationMinutes: Int?
    let isUrgent: Bool
    let isDone: Bool
    let sortIndex: Int
    let createdAt: Date

    init(_ task: FlowTask) {
        id = task.id
        title = task.title
        day = task.day
        category = task.category
        startMinute = task.startMinute
        durationMinutes = task.durationMinutes
        isUrgent = task.isUrgent
        isDone = task.isDone
        sortIndex = task.sortIndex
        createdAt = task.createdAt
    }

    /// "Anytime", "07:30" or "07:30-08:30".
    var spanText: String {
        guard let startMinute else { return "Anytime" }
        return Fmt.span(start: startMinute, duration: durationMinutes)
    }
}

/// The watch reads tasks through the same pure rules as the widgets.
extension TaskItem: WatchItem {}
