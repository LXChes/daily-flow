import Foundation

/// Lets the tick intent reach the running app directly when iOS runs it inside the app's process.
///
/// The app sets `appHandler` at launch. Inside the widget extension it stays nil, and the intent falls back
/// to `WidgetDataStore.recordTick`, which the app applies on its next run. Either way the tick lands.
@MainActor
public enum WidgetTickRouter {
    public static var appHandler: ((UUID, Bool) -> Void)?

    /// Returns true when the app handled the tick itself.
    public static func handle(_ task: UUID, done: Bool) -> Bool {
        guard let appHandler else { return false }
        appHandler(task, done)
        return true
    }
}
