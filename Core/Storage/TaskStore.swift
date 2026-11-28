import Foundation
import SwiftData

/// Reads and changes tasks. Every change is saved straight away.
@MainActor
public final class TaskStore {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Reading

    /// Tasks on `day` in display order.
    public func tasks(on day: CalendarDay, autoSort: Bool) throws -> [FlowTask] {
        let key = day.key
        let found = try context.fetch(FetchDescriptor<FlowTask>(predicate: #Predicate { $0.dayKey == key }))
        return DaySchedule.ordered(found, autoSort: autoSort)
    }

    /// Unfinished tasks from before `today`, oldest day first.
    public func leftovers(today: CalendarDay) throws -> [FlowTask] {
        let key = today.key
        let descriptor = FetchDescriptor<FlowTask>(
            predicate: #Predicate { $0.completedAt == nil && $0.dayKey < key },
            sortBy: [SortDescriptor(\.dayKey), SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor)
    }

    /// One task by id, on any day.
    public func task(id: UUID) throws -> FlowTask? {
        var descriptor = FetchDescriptor<FlowTask>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Every task from `day` onwards, for planning reminders.
    public func tasks(from day: CalendarDay) throws -> [FlowTask] {
        let key = day.key
        let descriptor = FetchDescriptor<FlowTask>(
            predicate: #Predicate { $0.dayKey >= key },
            sortBy: [SortDescriptor(\.dayKey), SortDescriptor(\.sortIndex)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: Changing

    /// Adds a task. The category is guessed from the title unless one is given.
    @discardableResult
    public func add(
        title: String,
        day: CalendarDay,
        startMinute: Int? = nil,
        durationMinutes: Int? = nil,
        isUrgent: Bool = false,
        category: TaskCategory? = nil,
        now: Date = .now
    ) throws -> FlowTask {
        let cleanTitle = try Self.validated(title)
        let task = FlowTask(
            title: cleanTitle,
            day: day,
            startMinute: startMinute,
            durationMinutes: durationMinutes.map { Self.clampedDuration($0) },
            category: category ?? TaskCategoriser.category(for: cleanTitle),
            isCategoryManual: category != nil,
            isUrgent: isUrgent,
            sortIndex: try nextSortIndex(on: day),
            createdAt: now
        )
        context.insert(task)
        try context.save()
        return task
    }

    /// Renames a task, re-guessing its category unless the owner set one by hand.
    public func rename(_ task: FlowTask, to title: String) throws {
        task.title = try Self.validated(title)
        if !task.isCategoryManual {
            task.category = TaskCategoriser.category(for: task.title)
        }
        try context.save()
    }

    /// Owner override of the guessed category.
    public func setCategory(_ task: FlowTask, to category: TaskCategory) throws {
        task.category = category
        task.isCategoryManual = true
        try context.save()
    }

    public func setTime(_ task: FlowTask, startMinute: Int?, durationMinutes: Int?) throws {
        task.startMinute = startMinute.map(MinuteOfDay.clamp)
        task.durationMinutes = durationMinutes.map { Self.clampedDuration($0) }
        try context.save()
    }

    public func setUrgent(_ task: FlowTask, _ isUrgent: Bool) throws {
        task.isUrgent = isUrgent
        try context.save()
    }

    public func setDone(_ task: FlowTask, _ isDone: Bool, at now: Date = .now) throws {
        task.completedAt = isDone ? now : nil
        try context.save()
    }

    /// Moves a task to another day, placing it last in that day's manual order.
    public func move(_ task: FlowTask, to day: CalendarDay) throws {
        guard task.day != day else { return }
        task.sortIndex = try nextSortIndex(on: day)
        task.day = day
        try context.save()
    }

    /// Saves a new manual order for one day's tasks.
    public func reorder(_ tasks: [FlowTask]) throws {
        for (index, task) in tasks.enumerated() {
            task.sortIndex = index
        }
        try context.save()
    }

    public func delete(_ task: FlowTask) throws {
        context.delete(task)
        try context.save()
    }

    // MARK: Day change

    /// Applies the owner's triage choice to one leftover. Ignores tasks that are no longer leftovers.
    public func triage(_ task: FlowTask, _ choice: LeftoverChoice, today: CalendarDay) throws {
        guard DayRollover.isLeftover(taskDay: task.day, isDone: task.isDone, today: today) else { return }
        if let destination = DayRollover.destination(for: choice, today: today) {
            try move(task, to: destination)
        } else {
            try delete(task)
        }
    }

    /// Applies one choice to every leftover.
    public func triageAll(_ choice: LeftoverChoice, today: CalendarDay) throws {
        for task in try leftovers(today: today) {
            try triage(task, choice, today: today)
        }
    }

    /// Moves every leftover onto today (used when triage is switched off). Returns how many moved.
    @discardableResult
    public func rollLeftoversOntoToday(_ today: CalendarDay) throws -> Int {
        let moving = try leftovers(today: today)
        for task in moving {
            try move(task, to: today)
        }
        return moving.count
    }

    // MARK: Helpers

    private func nextSortIndex(on day: CalendarDay) throws -> Int {
        let key = day.key
        var descriptor = FetchDescriptor<FlowTask>(
            predicate: #Predicate { $0.dayKey == key },
            sortBy: [SortDescriptor(\.sortIndex, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try context.fetch(descriptor).first?.sortIndex ?? -1) + 1
    }

    nonisolated static func validated(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CoreError.emptyTitle }
        return trimmed
    }

    nonisolated static func clampedDuration(_ minutes: Int) -> Int {
        min(max(minutes, DurationRules.range.lowerBound), DurationRules.range.upperBound)
    }
}
