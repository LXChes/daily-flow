import Foundation
import OSLog
import SwiftData

/// Builds the on-device SwiftData store.
///
/// Free-sideload safe: no App Group and no CloudKit, both switched off explicitly so a stray entitlement
/// can never change where data lives. The store sits in the app's own Application Support folder.
/// M4 shares data with the widget through `DaySnapshot`, not through this store.
public enum DailyFlowStore {
    static let logger = Logger(subsystem: "com.example.dailyflow", category: "storage")

    public static var schema: Schema {
        Schema([FlowTask.self, NoticeDay.self, AppSettings.self])
    }

    /// The persistent store, or an in-memory one for tests and previews.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            inMemory ? nil : "DailyFlow",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// The persistent store, falling back to a temporary in-memory one if the file cannot be opened,
    /// so the app still launches. `isTemporary` tells the UI to warn that changes will not be kept.
    public static func makeContainerWithFallback() -> (container: ModelContainer, isTemporary: Bool) {
        do {
            return (try makeContainer(), false)
        } catch {
            logger.error("Persistent store failed to open: \(error.localizedDescription, privacy: .public)")
        }
        do {
            return (try makeContainer(inMemory: true), true)
        } catch {
            // An in-memory store with this fixed schema cannot fail short of memory exhaustion.
            fatalError("Could not create an in-memory store: \(error)")
        }
    }
}

public enum CoreError: Error, Equatable, Sendable {
    case emptyTitle
    case invalidDate
    case cannotDeleteBuiltInNotice
}
