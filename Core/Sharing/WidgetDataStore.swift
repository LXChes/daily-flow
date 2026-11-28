import Foundation
import OSLog

/// Reads and writes the files the app and widgets share. Every call is safe without a shared folder:
/// writes quietly do nothing and reads fall back as `WidgetDataResolver` describes.
public enum WidgetDataStore {
    private static let logger = Logger(subsystem: "com.example.dailyflow", category: "sharing")
    private static let snapshotFile = "day-snapshot.json"
    private static let ticksFile = "widget-ticks.json"
    /// The widget's own last good copy, in the widget's standard `UserDefaults` (no App Group needed).
    static let cacheKey = "df.widget.lastSnapshot"

    public static var isShared: Bool { SharedContainer.isAvailable }

    // MARK: App side

    /// Publishes today's snapshot for the widgets. Returns false in basic mode.
    @discardableResult
    public static func publish(_ snapshot: DaySnapshot) -> Bool {
        guard let url = url(snapshotFile) else { return false }
        do {
            try snapshot.encoded().write(to: url, options: .atomic)
            return true
        } catch {
            logger.error("Snapshot write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Ticks made on widgets that the app has not applied yet.
    public static func pendingTicks() -> WidgetTickQueue {
        WidgetTickQueue.decode(read(ticksFile))
    }

    /// Removes ticks the app has applied, keeping any a widget added in the meantime.
    public static func removeTicks(_ ids: Set<UUID>) {
        guard !ids.isEmpty, let url = url(ticksFile) else { return }
        let remaining = pendingTicks().removing(ids)
        if remaining.ticks.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else if let data = remaining.encoded() {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: Widget side

    /// The shared snapshot (if the folder exists and holds a valid one) and the widget's own cached copy.
    /// A good shared snapshot refreshes the cache, so the widget has something if the folder later fails.
    public static func loadSources(defaults: UserDefaults = .standard) -> (shared: DaySnapshot?, cached: DaySnapshot?) {
        let shared = DaySnapshot.decode(read(snapshotFile))
        if let shared, let data = try? shared.encoded() {
            defaults.set(data, forKey: cacheKey)
        }
        return (shared, DaySnapshot.decode(defaults.data(forKey: cacheKey)))
    }

    /// What a widget should draw now. Never fails.
    public static func loadForWidget(now: Date, calendar: Calendar, defaults: UserDefaults = .standard) -> WidgetDay {
        let sources = loadSources(defaults: defaults)
        return WidgetDataResolver.resolve(shared: sources.shared, cached: sources.cached, now: now, calendar: calendar)
    }

    /// Records a tick made on a widget: queues it for the app and updates the shared snapshot so every
    /// widget shows it straight away. Returns false in basic mode (no tick buttons are shown then).
    @discardableResult
    public static func recordTick(taskID: UUID, done: Bool, now: Date) -> Bool {
        guard let ticksURL = url(ticksFile), let snapshotURL = url(snapshotFile) else { return false }
        var queue = pendingTicks()
        queue.append(WidgetTick(taskID: taskID, isDone: done, at: now))
        do {
            if let data = queue.encoded() {
                try data.write(to: ticksURL, options: .atomic)
            }
            if let snapshot = DaySnapshot.decode(read(snapshotFile)) {
                try snapshot.settingTask(taskID, done: done, now: now).encoded().write(to: snapshotURL, options: .atomic)
            }
            return true
        } catch {
            logger.error("Widget tick write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: Files

    private static func url(_ name: String) -> URL? {
        SharedContainer.directory?.appendingPathComponent(name)
    }

    private static func read(_ name: String) -> Data? {
        guard let url = url(name) else { return nil }
        return try? Data(contentsOf: url)
    }
}
