import DailyFlowCore
import OSLog
import SwiftData
import SwiftUI

@main
struct DailyFlowApp: App {
    private static let logger = Logger(subsystem: "com.example.dailyflow", category: "app")

    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer
    private let isTemporaryStore: Bool

    init() {
        let store = DailyFlowStore.makeContainerWithFallback()
        container = store.container
        isTemporaryStore = store.isTemporary
    }

    var body: some Scene {
        WindowGroup {
            ContentView(isTemporaryStore: isTemporaryStore)
        }
        .modelContainer(container)
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            refreshDay()
        }
    }

    /// Rolls the day forward (leftovers, notices) whenever the app comes to the front.
    private func refreshDay() {
        do {
            _ = try DayEngine(context: container.mainContext).refresh(now: .now, calendar: .current)
        } catch {
            Self.logger.error("Day refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
