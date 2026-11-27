import Foundation
import SwiftData

@MainActor
public final class SettingsStore {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// The settings record, created with the brief's defaults on first use.
    public func current() throws -> AppSettings {
        let key = AppSettings.singletonKey
        var descriptor = FetchDescriptor<AppSettings>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let created = AppSettings()
        context.insert(created)
        try context.save()
        return created
    }

    /// Saves changes made to the settings record's properties.
    public func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }
}
