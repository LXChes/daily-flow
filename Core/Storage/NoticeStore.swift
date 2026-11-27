import Foundation
import SwiftData

/// The Settings notice list: built-ins (switch only) plus custom notices added on the phone.
@MainActor
public final class NoticeStore {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Adds a row for any built-in notice that does not have one yet. Safe to call on every launch.
    public func ensureBuiltIns() throws {
        let existing = Set(try context.fetch(FetchDescriptor<NoticeDay>()).map(\.key))
        var inserted = false
        for builtIn in BuiltInNotice.allCases where !existing.contains(NoticeRule.key(for: builtIn)) {
            context.insert(NoticeDay(builtIn: builtIn))
            inserted = true
        }
        if inserted {
            try context.save()
        }
    }

    /// Built-ins in calendar order, then custom notices in the order they were added.
    public func all() throws -> [NoticeDay] {
        let rows = try context.fetch(FetchDescriptor<NoticeDay>())
        let order = Dictionary(uniqueKeysWithValues: BuiltInNotice.allCases.enumerated().map { ($0.element, $0.offset) })
        let builtIns = rows
            .filter(\.isBuiltIn)
            .sorted { (lhs, rhs) in
                (lhs.builtIn.flatMap { order[$0] } ?? 0) < (rhs.builtIn.flatMap { order[$0] } ?? 0)
            }
        let custom = rows.filter { !$0.isBuiltIn }.sorted { $0.createdAt < $1.createdAt }
        return builtIns + custom
    }

    /// Adds a custom notice. `year` is used only when it does not repeat; an every-year notice on
    /// 29 February shows on 28 February in other years.
    @discardableResult
    public func addCustom(
        title: String,
        month: Int,
        day: Int,
        year: Int,
        repeatsEveryYear: Bool,
        now: Date = .now
    ) throws -> NoticeDay {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw CoreError.emptyTitle }
        let checkYear = repeatsEveryYear ? 2000 : year // 2000 is a leap year, so 29 February is allowed
        guard CalendarDay(year: checkYear, month: month, day: day) != nil else { throw CoreError.invalidDate }

        let notice = NoticeDay(
            customTitle: cleanTitle,
            month: month,
            day: day,
            year: year,
            repeatsEveryYear: repeatsEveryYear,
            createdAt: now
        )
        context.insert(notice)
        try context.save()
        return notice
    }

    public func setEnabled(_ notice: NoticeDay, _ isEnabled: Bool) throws {
        notice.isEnabled = isEnabled
        try context.save()
    }

    /// Removes a custom notice. Built-ins can only be switched off.
    public func delete(_ notice: NoticeDay) throws {
        guard !notice.isBuiltIn else { throw CoreError.cannotDeleteBuiltInNotice }
        context.delete(notice)
        try context.save()
    }

    /// Rules for every switched-on notice, or none when notices are off.
    public func activeRules(noticesEnabled: Bool) throws -> [NoticeRule] {
        guard noticesEnabled else { return [] }
        return try all().filter(\.isEnabled).compactMap(\.rule)
    }
}
