import DailyFlowCore
import Foundation
import OSLog
import WidgetKit

/// Everything the app sends outside itself: the widget snapshot, the pending notifications and the
/// snoozes behind them. `AppModel` calls `sync` after every reload; each output is only touched when it
/// actually changed. Demo builds have no `DeviceOutputs`, so screenshots never schedule anything.
@MainActor
final class DeviceOutputs {
    private static let logger = Logger(subsystem: "com.example.dailyflow", category: "outputs")
    private static let snoozeKey = "df.snoozes"

    let scheduler = ReminderScheduler()
    private(set) var snoozes: SnoozeBook
    private var published: DaySnapshot?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snoozes = SnoozeBook.decode(defaults.data(forKey: Self.snoozeKey))
    }

    // MARK: Snoozes

    func snooze(_ task: UUID, now: Date) {
        snoozes.snooze(task, now: now)
        saveSnoozes()
    }

    func clearSnooze(_ task: UUID) {
        guard snoozes.until(for: task) != nil else { return }
        snoozes.clear(task)
        saveSnoozes()
    }

    private func saveSnoozes() {
        defaults.set(snoozes.encoded(), forKey: Self.snoozeKey)
    }

    // MARK: Widget ticks

    /// Applies ticks made on widgets since the app last ran. Returns true if anything changed.
    @discardableResult
    func applyWidgetTicks(to tasks: TaskStore) -> Bool {
        let queue = WidgetDataStore.pendingTicks()
        guard !queue.ticks.isEmpty else { return false }
        var changed = false
        for tick in queue.latestPerTask {
            do {
                guard let task = try tasks.task(id: tick.taskID), task.isDone != tick.isDone else { continue }
                try tasks.setDone(task, tick.isDone, at: tick.at)
                changed = true
                if tick.isDone {
                    clearSnooze(task.id)
                }
            } catch {
                Self.logger.error("Widget tick not applied: \(error.localizedDescription, privacy: .public)")
            }
        }
        // Remove exactly what was read, so a tick a widget adds meanwhile is kept for next time.
        WidgetDataStore.removeTicks(Set(queue.ticks.map(\.id)))
        return changed
    }

    // MARK: Sync

    func sync(engine: DayEngine, now: Date, calendar: Calendar) {
        do {
            let snapshot = try engine.snapshot(now: now, calendar: calendar)
            if published.map({ !$0.hasSameContent(as: snapshot) }) ?? true {
                if WidgetDataStore.publish(snapshot) {
                    WidgetCenter.shared.reloadAllTimelines()
                }
                published = snapshot
            }

            let before = snoozes
            snoozes.prune(now: now)
            if snoozes != before {
                saveSnoozes()
            }
            scheduler.update(try engine.reminderPlan(snoozes: snoozes, now: now, calendar: calendar))
        } catch {
            Self.logger.error("Sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Makes the next `sync` re-apply the reminder plan (after notification permission changes).
    func invalidateReminders() {
        scheduler.invalidate()
    }
}
