import Foundation
import SwiftData

/// A task on one day. Times are minutes after midnight so they survive clock and time zone changes.
@Model
public final class FlowTask {
    @Attribute(.unique) public var id: UUID = UUID()
    public var title: String = ""
    /// `CalendarDay.key` of the day the task is on (yyyymmdd).
    public var dayKey: Int = 0
    public var startMinute: Int? = nil
    public var durationMinutes: Int? = nil
    public var categoryRaw: String = TaskCategory.other.rawValue
    /// True once the owner picks a category by hand, so renaming no longer re-guesses it.
    public var isCategoryManual: Bool = false
    public var isUrgent: Bool = false
    public var completedAt: Date? = nil
    public var createdAt: Date = Date.now
    /// Manual order within a day, used when auto-sort is off.
    public var sortIndex: Int = 0

    public init(
        title: String,
        day: CalendarDay,
        startMinute: Int? = nil,
        durationMinutes: Int? = nil,
        category: TaskCategory,
        isCategoryManual: Bool = false,
        isUrgent: Bool = false,
        sortIndex: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.title = title
        self.dayKey = day.key
        self.startMinute = startMinute.map(MinuteOfDay.clamp)
        self.durationMinutes = durationMinutes
        self.categoryRaw = category.rawValue
        self.isCategoryManual = isCategoryManual
        self.isUrgent = isUrgent
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.completedAt = nil
    }

    public var day: CalendarDay {
        get { CalendarDay(key: dayKey) ?? CalendarDay(dayNumber: 0) }
        set { dayKey = newValue.key }
    }

    public var category: TaskCategory {
        get { TaskCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

extension FlowTask: ScheduledItem {
    public var isDone: Bool { completedAt != nil }
}

/// A row in the Settings notice list: either a built-in (date computed in code, only its switch is
/// stored) or a custom notice the owner added on the phone.
@Model
public final class NoticeDay {
    /// `builtin.<id>` for built-ins, `custom.<uuid>` for custom notices.
    @Attribute(.unique) public var key: String = ""
    public var title: String = ""
    public var builtInRaw: String? = nil
    /// Custom notices only.
    public var month: Int = 1
    public var day: Int = 1
    public var year: Int = 2000
    public var repeatsEveryYear: Bool = true
    public var isEnabled: Bool = true
    public var createdAt: Date = Date.now

    public init(builtIn: BuiltInNotice) {
        self.key = NoticeRule.key(for: builtIn)
        self.title = builtIn.title
        self.builtInRaw = builtIn.rawValue
        self.isEnabled = true
        self.createdAt = .now
    }

    public init(customTitle: String, month: Int, day: Int, year: Int, repeatsEveryYear: Bool, createdAt: Date = .now) {
        self.key = "custom.\(UUID().uuidString)"
        self.title = customTitle
        self.builtInRaw = nil
        self.month = month
        self.day = day
        self.year = year
        self.repeatsEveryYear = repeatsEveryYear
        self.isEnabled = true
        self.createdAt = createdAt
    }

    public var builtIn: BuiltInNotice? { builtInRaw.flatMap(BuiltInNotice.init(rawValue:)) }
    public var isBuiltIn: Bool { builtInRaw != nil }

    /// The rule the notice engine uses, or `nil` if the stored date is unusable.
    public var rule: NoticeRule? {
        if let builtIn {
            return NoticeRule(builtIn)
        }
        if repeatsEveryYear {
            guard CalendarDay(year: 2000, month: month, day: day) != nil else { return nil } // 2000 is a leap year
            return NoticeRule(id: key, title: title, schedule: .everyYear(month: month, day: day))
        }
        guard let date = CalendarDay(year: year, month: month, day: day) else { return nil }
        return NoticeRule(id: key, title: title, schedule: .once(date))
    }
}

/// The single settings record. Defaults match the design brief.
@Model
public final class AppSettings {
    public static let singletonKey = "app-settings"

    @Attribute(.unique) public var key: String = AppSettings.singletonKey

    // Notices
    public var noticesEnabled: Bool = true
    // Morning brief and leftovers
    public var morningBriefEnabled: Bool = true
    public var morningBriefMinute: Int = ReminderTiming.defaultMorningBriefMinute
    public var leftoversTriageEnabled: Bool = true
    // Urgent reminders
    public var urgentLeadMinutes: Int = ReminderTiming.defaultLeadMinutes
    public var untimedReminderMinute: Int = ReminderTiming.defaultUntimedMinute
    // Behaviour and feel
    public var autoSortEnabled: Bool = true
    public var widgetStyleRaw: String = WidgetStyle.matchApp.rawValue
    public var hapticTickEnabled: Bool = true
    public var tickSoundEnabled: Bool = true
    // View switcher
    public var layoutRaw: String = LayoutMode.playTheDay.rawValue
    public var categoryModeRaw: String = CategoryMode.simple.rawValue
    public var themeRaw: String = ThemeMode.dark.rawValue
    public var progressStyleRaw: String = ProgressStyle.wave.rawValue
    public var previewModeRaw: String = PreviewMode.normal.rawValue

    public init() {
        self.key = AppSettings.singletonKey
    }

    public var widgetStyle: WidgetStyle {
        get { WidgetStyle(rawValue: widgetStyleRaw) ?? .matchApp }
        set { widgetStyleRaw = newValue.rawValue }
    }

    public var layout: LayoutMode {
        get { LayoutMode(rawValue: layoutRaw) ?? .playTheDay }
        set { layoutRaw = newValue.rawValue }
    }

    public var categoryMode: CategoryMode {
        get { CategoryMode(rawValue: categoryModeRaw) ?? .simple }
        set { categoryModeRaw = newValue.rawValue }
    }

    public var theme: ThemeMode {
        get { ThemeMode(rawValue: themeRaw) ?? .dark }
        set { themeRaw = newValue.rawValue }
    }

    public var progressStyle: ProgressStyle {
        get { ProgressStyle(rawValue: progressStyleRaw) ?? .wave }
        set { progressStyleRaw = newValue.rawValue }
    }

    public var previewMode: PreviewMode {
        get { PreviewMode(rawValue: previewModeRaw) ?? .normal }
        set { previewModeRaw = newValue.rawValue }
    }

    /// Lead time for timed urgent reminders, always one of `ReminderTiming.leadTimeChoices`.
    public var urgentLead: Int {
        get {
            ReminderTiming.leadTimeChoices.contains(urgentLeadMinutes) ? urgentLeadMinutes : ReminderTiming.defaultLeadMinutes
        }
        set {
            urgentLeadMinutes = ReminderTiming.leadTimeChoices.contains(newValue) ? newValue : ReminderTiming.defaultLeadMinutes
        }
    }

    public var morningBriefTime: Int {
        get { MinuteOfDay.clamp(morningBriefMinute) }
        set { morningBriefMinute = MinuteOfDay.clamp(newValue) }
    }

    public var untimedReminderTime: Int {
        get { MinuteOfDay.clamp(untimedReminderMinute) }
        set { untimedReminderMinute = MinuteOfDay.clamp(newValue) }
    }
}
