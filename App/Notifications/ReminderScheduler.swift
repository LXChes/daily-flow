import DailyFlowCore
import Foundation
import OSLog
import UserNotifications

private let logger = Logger(subsystem: "com.example.dailyflow", category: "reminders")

/// Whether the app may post notifications, in the app's own words.
enum ReminderAccess: Equatable, Sendable {
    case unknown, notAsked, allowed, denied

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notAsked
        case .denied: self = .denied
        case .authorized, .provisional, .ephemeral: self = .allowed
        @unknown default: self = .allowed
        }
    }
}

/// Hands the reminder plan to `UNUserNotificationCenter`. Local only: no push, no entitlement.
///
/// Every app change re-plans, but the centre is only touched when the plan really differs, and one
/// application at a time runs, always with the newest plan.
@MainActor
final class ReminderScheduler {
    private var applied: [PlannedReminder]?
    private var running: Task<Void, Never>?

    /// Registers the Lock Screen buttons. Call once at launch, before any notification can arrive.
    nonisolated static func registerCategories() {
        // No `.foreground` option: each button runs in the background without opening the app.
        let actions = ReminderAction.allCases.map { action in
            UNNotificationAction(identifier: action.rawValue, title: action.title, options: [])
        }
        let urgent = UNNotificationCategory(identifier: ReminderRoute.urgentCategory, actions: actions, intentIdentifiers: [])
        let brief = UNNotificationCategory(identifier: ReminderRoute.briefCategory, actions: [], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([urgent, brief])
    }

    nonisolated static func currentAccess() async -> ReminderAccess {
        ReminderAccess(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }

    /// Shows the system prompt once. Returns the access afterwards.
    nonisolated static func requestAccess() async -> ReminderAccess {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("Permission request failed: \(error.localizedDescription, privacy: .public)")
        }
        return await currentAccess()
    }

    /// Queues `plan` if it differs from what was last applied.
    func update(_ plan: [PlannedReminder]) {
        guard plan != applied else { return }
        applied = plan
        let previous = running
        running = Task {
            await previous?.value
            await Self.apply(plan)
        }
    }

    /// Forgets the last plan, so the next `update` re-applies it (after permission changes).
    func invalidate() {
        applied = nil
    }

    /// Waits for pending work. Notification actions call this before reporting back to the system.
    func flush() async {
        await running?.value
    }

    nonisolated private static func apply(_ plan: [PlannedReminder]) async {
        let center = UNUserNotificationCenter.current()
        guard ReminderAccess(await center.notificationSettings().authorizationStatus) == .allowed else { return }

        let wanted = Set(plan.map(\.id))
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(ReminderID.prefix) && !wanted.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        let calendar = Calendar.current
        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.threadIdentifier = reminder.kind == .morningBrief ? "df.brief" : "df.urgent"
            content.categoryIdentifier = reminder.kind == .morningBrief ? ReminderRoute.briefCategory : ReminderRoute.urgentCategory
            content.userInfo = ReminderRoute.userInfo(for: reminder.taskID)
            if reminder.kind != .morningBrief {
                content.relevanceScore = 1
            }

            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            do {
                // Same identifier replaces the pending one, so re-applying never duplicates.
                try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
            } catch {
                logger.error("Could not schedule \(reminder.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Clears one task's pending and delivered reminders (after it is ticked off or moved).
    nonisolated static func clear(task: UUID) {
        let ids = ReminderID.all(for: task)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}
