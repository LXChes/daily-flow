import DailyFlowCore
import UIKit
import UserNotifications

/// Receives notification taps and Lock Screen button presses. iOS launches the app in the background
/// for a button press (no `.foreground` option), so Complete / Snooze 30m / Move to Tomorrow work with
/// the app closed.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // The delegate must be set before launch finishes, or a background button press is lost.
        UNUserNotificationCenter.current().delegate = self
        ReminderScheduler.registerCategories()
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let action = ReminderAction(rawValue: response.actionIdentifier),
              let taskID = ReminderRoute.taskID(from: response.notification.request.content.userInfo) else {
            return // A plain tap just opens the app.
        }
        // Returning tells iOS the work is done, so finish saving and rescheduling first.
        await Self.route(action, taskID: taskID)
    }

    private static func route(_ action: ReminderAction, taskID: UUID) async {
        await AppBootstrap.shared.handleReminder(action, taskID: taskID)
    }
}
