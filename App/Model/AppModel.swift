import DailyFlowCore
import Foundation
import Observation
import OSLog
import SwiftData
import SwiftUI
import UIKit

enum AppSheet: String, Identifiable {
    case add, settings, triage

    var id: String { rawValue }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

/// A row in the Settings notice list, already worded for display.
struct NoticeRowItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let isEnabled: Bool
    let isCustom: Bool
}

/// Everything the screens show, and every action they can take. All rules live in `DailyFlowCore`; this
/// type only fetches, turns results into immutable display values and forwards taps to the engine.
@MainActor
@Observable
final class AppModel {
    private static let logger = Logger(subsystem: "com.example.dailyflow", category: "model")

    let clock: DFClock
    let isTemporaryStore: Bool
    let playhead = Playhead()

    // Stored settings, read live by the views.
    private(set) var settings: AppSettings

    // Today
    private(set) var today: CalendarDay
    private(set) var items: [TaskItem] = []
    private(set) var timedItems: [TaskItem] = []
    private(set) var anytimeItems: [TaskItem] = []
    private(set) var progress = DayProgress(done: 0, total: 0)
    private(set) var nextOpenLine = ""
    private(set) var beltRange: ClosedRange<Double> = 420...1380
    private(set) var waveBars: [WaveBar] = []

    // Leftovers and notices
    private(set) var leftovers: [TaskItem] = []
    private(set) var noticeRows: [NoticeRowItem] = []
    private(set) var todaysNotices: [NoticeOccurrence] = []
    private(set) var preview: PreviewMode = .normal
    private(set) var previewOccurrence: NoticeOccurrence?
    private(set) var previewLabels: [PreviewMode: String] = [:]

    // Presentation
    var sheet: AppSheet?
    var showsViewSwitcher = false
    private(set) var toast: ToastMessage?
    /// Bumps each time something is ticked off, to drive the haptic.
    private(set) var tickPulse = 0

    // Reminders and widgets
    private(set) var reminderAccess: ReminderAccess = .unknown
    /// False in demo builds, which never touch notifications.
    private(set) var remindersAvailable: Bool
    private(set) var reminderPromptDismissed: Bool

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let engine: DayEngine
    @ObservationIgnored private var storedByID: [UUID: FlowTask] = [:]
    @ObservationIgnored private var rules: [NoticeRule] = []
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private let outputs: DeviceOutputs?

    private static let promptDismissedKey = "df.reminderPromptDismissed"

    /// `outputs` is nil in demo builds: no notifications, no widget files.
    init(container: ModelContainer, isTemporaryStore: Bool, clock: DFClock, outputs: DeviceOutputs? = nil) {
        self.container = container
        self.isTemporaryStore = isTemporaryStore
        self.clock = clock
        self.outputs = outputs
        self.remindersAvailable = outputs != nil
        self.reminderPromptDismissed = UserDefaults.standard.bool(forKey: Self.promptDismissedKey)
        let engine = DayEngine(context: container.mainContext)
        self.engine = engine
        self.settings = (try? engine.settings.current()) ?? AppSettings()
        self.today = clock.today
        if outputs != nil {
            WidgetTickRouter.appHandler = { [weak self] id, done in
                self?.applyWidgetTick(id, done: done)
            }
        }
        reload()
    }

    // MARK: Derived display values

    var theme: ThemeMode { settings.theme }
    var palette: Palette { Palette.for(settings.theme) }

    /// Watch arrives in M5; until then a stored `.watch` behaves as Play the day.
    var layout: LayoutMode { settings.layout == .list ? .list : .playTheDay }
    var isSorted: Bool { settings.categoryMode == .sorted }

    var activeNotices: [NoticeOccurrence] {
        if let previewOccurrence { return [previewOccurrence] }
        return todaysNotices
    }

    var showsBanner: Bool { settings.noticesEnabled && !activeNotices.isEmpty }
    var bannerTitle: String {
        "It\u{2019}s " + activeNotices.map(\.title).joined(separator: " \u{00B7} ")
    }

    /// The one-off "Let Daily Flow remind you" card.
    var showsReminderPrompt: Bool {
        remindersAvailable && reminderAccess == .notAsked && !reminderPromptDismissed && preview == .normal
    }

    /// True when the widgets can see real tasks (the shared folder was granted).
    var widgetsShareData: Bool { WidgetDataStore.isShared }

    var showsLeftoversCard: Bool {
        settings.leftoversTriageEnabled && !leftovers.isEmpty && preview == .normal
    }

    var dateLine: String {
        DateText.long(previewOccurrence?.day ?? today, calendar: clock.calendar)
    }

    var greeting: String {
        let hour = Int(clock.fractionalMinute(of: clock.now()) / 60)
        if hour < 12 { return "Good morning." }
        if hour < 18 { return "Good afternoon." }
        return "Good evening."
    }

    var liveMinute: Double {
        clock.fractionalMinute(of: clock.now())
    }

    /// The timed task whose block covers `minute`, ticked or not.
    func runningItem(atMinute minute: Double) -> TaskItem? {
        timedItems.last { item in
            guard let start = item.startMinute, let end = item.endMinute else { return false }
            return Double(start) <= minute && minute < Double(end)
        }
    }

    /// The next unfinished timed task after `minute`.
    func nextTimedItem(afterMinute minute: Double) -> TaskItem? {
        DaySchedule.upcoming(items, afterMinute: Int(minute.rounded(.down))).first
    }

    func displayedMinute(at date: Date) -> Double {
        Playhead.minute(mode: playhead.mode, at: date, live: { liveMinute }, range: beltRange)
    }

    func previewLabel(_ mode: PreviewMode) -> String {
        previewLabels[mode] ?? "Normal"
    }

    func fromLabel(for item: TaskItem) -> String {
        let away = today.days(since: item.day)
        let when: String
        if away == 1 {
            when = "yesterday"
        } else if away <= 6 {
            when = DateText.weekday(item.day, calendar: clock.calendar)
        } else {
            when = DateText.medium(item.day, calendar: clock.calendar)
        }
        return "From \(when) \u{00B7} \(item.category.title)"
    }

    /// Chooses a spring, or the calm alternative when Reduce Motion is on.
    func animated(_ animation: Animation) -> Animation {
        Motion.resolve(animation, reduceMotion: UIAccessibility.isReduceMotionEnabled)
    }

    // MARK: Loading

    /// Re-reads everything from the engine. Cheap: a day holds a handful of tasks.
    func reload() {
        let now = clock.now()
        do {
            outputs?.applyWidgetTicks(to: engine.tasks)
            let status = try engine.refresh(now: now, calendar: clock.calendar)
            let current = try engine.settings.current()
            if current !== settings {
                settings = current
            }
            if status.today != today {
                playhead.goLive()
            }
            today = status.today

            let stored = try engine.tasks.tasks(on: status.today, autoSort: current.autoSortEnabled)
            let pending = try current.leftoversTriageEnabled ? engine.tasks.leftovers(today: status.today) : []
            storedByID = Dictionary((stored + pending).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            let all = stored.map(TaskItem.init)
            // Open tasks first, finished ones sink: the list reads as what is left to do.
            items = all.filter { !$0.isDone } + all.filter(\.isDone)
            timedItems = DaySchedule.timed(all)
            anytimeItems = items.filter { !$0.isTimed }
            progress = DaySchedule.progress(all)
            leftovers = pending.map(TaskItem.init)
            nextOpenLine = Self.nextLine(from: all)
            beltRange = Self.range(for: timedItems, liveMinute: liveMinute)
            waveBars = WaveModel.bars(items: all, range: beltRange)

            let noticeStored = try engine.notices.all()
            rules = try engine.notices.activeRules(noticesEnabled: current.noticesEnabled)
            todaysNotices = status.notices
            noticeRows = noticeStored.map { noticeRow($0, today: status.today) }
            refreshPreview()
            outputs?.sync(engine: engine, now: now, calendar: clock.calendar)
        } catch {
            Self.logger.error("Reload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func nextLine(from tasks: [TaskItem]) -> String {
        if tasks.isEmpty { return "Nothing planned" }
        let open = tasks.filter { !$0.isDone }
        let timed = DaySchedule.timed(open)
        guard let next = timed.first ?? open.first else { return "All done" }
        if let start = next.startMinute {
            return "\(next.title) \u{00B7} \(Fmt.clock(start))"
        }
        return next.title
    }

    /// The belt always shows 07:00 to 23:00, widened to hold every timed task and the real time.
    private static func range(for timed: [TaskItem], liveMinute: Double) -> ClosedRange<Double> {
        let earliest = timed.compactMap(\.startMinute).min() ?? 420
        let latest = timed.compactMap(\.endMinute).max() ?? 1380
        let live = Int(liveMinute)
        let low = max(0, min(420, earliest / 60 * 60, live / 60 * 60))
        let high = min(1440, max(1380, (latest + 59) / 60 * 60, (live + 59) / 60 * 60))
        return Double(low)...Double(max(high, low + 60))
    }

    private func refreshPreview() {
        previewOccurrence = NoticeCalendar.preview(preview, after: today, rules: rules)
        func label(_ prefix: String, _ mode: PreviewMode) -> String {
            guard let found = NoticeCalendar.preview(mode, after: today, rules: rules) else { return "\(prefix): none" }
            return "\(prefix): \(found.title)"
        }
        previewLabels = [
            .normal: "Normal",
            .nextNotice: label("Next", .nextNotice),
            .noticeAfter: label("After", .noticeAfter)
        ]
    }

    private func noticeRow(_ notice: NoticeDay, today: CalendarDay) -> NoticeRowItem {
        let repeatText: String
        if let builtIn = notice.builtIn {
            switch builtIn {
            case .mothersDayUK: repeatText = "UK \u{00B7} 3 weeks before Easter"
            case .easterSunday: repeatText = "moves each year"
            case .fathersDayUK: repeatText = "UK \u{00B7} 3rd Sunday of June"
            default: repeatText = "every year"
            }
        } else {
            repeatText = notice.repeatsEveryYear ? "every year" : "once"
        }

        var parts: [String] = []
        if let rule = notice.rule {
            if let next = NoticeCalendar.upcoming(from: today, days: 366, rules: [rule]).first {
                let away = next.day.days(since: today)
                parts.append(DateText.medium(next.day, calendar: clock.calendar))
                parts.append(repeatText)
                parts.append(away == 0 ? "today" : (away == 1 ? "tomorrow" : "in \(away) days"))
            } else if case .once(let date) = rule.schedule {
                parts.append(DateText.medium(date, calendar: clock.calendar))
                parts.append("once \u{00B7} passed")
            } else {
                parts.append(repeatText)
            }
        } else {
            parts.append("Date not valid")
        }
        return NoticeRowItem(
            id: notice.key,
            title: notice.title,
            detail: parts.joined(separator: " \u{00B7} "),
            isEnabled: notice.isEnabled,
            isCustom: !notice.isBuiltIn
        )
    }

    // MARK: Settings

    /// Applies a change to the settings record, saves it and refreshes everything that depends on it.
    func updateSettings(_ change: (AppSettings) -> Void) {
        change(settings)
        do {
            try engine.settings.save()
        } catch {
            fail(error)
        }
        reload()
    }

    func setPreview(_ mode: PreviewMode) {
        preview = mode
        refreshPreview()
    }

    // MARK: Task actions

    func toggleDone(_ id: UUID) {
        guard let task = storedByID[id] else { return }
        let makeDone = !task.isDone
        guard commit({ try engine.tasks.setDone(task, makeDone, at: clock.now()) }) else { return }
        if makeDone {
            clearReminders(for: id)
            tickPulse &+= 1
            if settings.tickSoundEnabled {
                TickSound.play()
            }
        }
    }

    func toggleUrgent(_ id: UUID) {
        guard let task = storedByID[id] else { return }
        let makeUrgent = !task.isUrgent
        guard commit({ try engine.tasks.setUrgent(task, makeUrgent) }) else { return }
        guard makeUrgent else {
            say("No longer urgent")
            return
        }
        askForRemindersIfNeeded()
        if reminderAccess == .denied {
            say("Urgent \u{00B7} notifications are off in iOS Settings")
            return
        }
        let fires = ReminderPlanner.urgentFireDate(
            for: ReminderTask(task),
            preferences: ReminderPreferences(settings),
            now: clock.now(),
            calendar: clock.calendar
        )
        if fires == nil {
            say("Urgent \u{00B7} its reminder time has passed")
        } else if task.startMinute != nil {
            say("Urgent \u{00B7} reminder \(settings.urgentLead) minutes before")
        } else {
            say("Urgent \u{00B7} reminder at \(Fmt.clock(settings.untimedReminderTime))")
        }
    }

    func moveToTomorrow(_ id: UUID) {
        guard let task = storedByID[id] else { return }
        let tomorrow = today.adding(days: 1)
        if commit({ try engine.tasks.move(task, to: tomorrow) }) {
            say("Moved to tomorrow")
        }
    }

    func delete(_ id: UUID) {
        guard let task = storedByID[id] else { return }
        _ = commit({ try engine.tasks.delete(task) })
    }

    func triage(_ id: UUID, _ choice: LeftoverChoice) {
        guard let task = storedByID[id] else { return }
        _ = commit({ try engine.tasks.triage(task, choice, today: today) })
    }

    /// Returns true when the task was added.
    @discardableResult
    func addTask(
        title: String,
        day: CalendarDay,
        startMinute: Int?,
        durationMinutes: Int?,
        isUrgent: Bool,
        category: TaskCategory?
    ) -> Bool {
        let added: Bool = commit {
            try engine.tasks.add(
                title: title,
                day: day,
                startMinute: startMinute,
                durationMinutes: durationMinutes,
                isUrgent: isUrgent,
                category: category,
                now: clock.now()
            )
        }
        guard added else { return false }
        if isUrgent {
            askForRemindersIfNeeded()
        }

        var parts = ["Added to " + dayWord(day)]
        if let startMinute {
            parts.append(Fmt.span(start: startMinute, duration: durationMinutes))
        } else if let durationMinutes {
            parts.append(Fmt.duration(durationMinutes))
        }
        parts.append(category?.title ?? TaskCategoriser.category(for: title).title)
        say(parts.joined(separator: " \u{00B7} "))
        return true
    }

    private func dayWord(_ day: CalendarDay) -> String {
        let away = day.days(since: today)
        if away == 0 { return "today" }
        if away == 1 { return "tomorrow" }
        return DateText.medium(day, calendar: clock.calendar)
    }

    // MARK: Reminders

    /// Reads the current permission. Called whenever the app comes to the front.
    func refreshReminderAccess() async {
        guard remindersAvailable else { return }
        let access = await ReminderScheduler.currentAccess()
        guard access != reminderAccess else { return }
        let becameAllowed = access == .allowed
        reminderAccess = access
        if becameAllowed {
            // Plans made before permission was granted were never applied.
            outputs?.invalidateReminders()
            reload()
        }
    }

    /// Shows the system prompt, from the reminder card or the first urgent task.
    func requestReminders() async {
        guard remindersAvailable else { return }
        let access = await ReminderScheduler.requestAccess()
        reminderAccess = access
        dismissReminderPrompt()
        outputs?.invalidateReminders()
        reload()
        if access == .denied {
            say("Reminders are off \u{00B7} you can turn them on in iOS Settings")
        }
    }

    func dismissReminderPrompt() {
        reminderPromptDismissed = true
        UserDefaults.standard.set(true, forKey: Self.promptDismissedKey)
    }

    func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// A Lock Screen button: Complete, Snooze 30m or Move to Tomorrow. Finishes saving and rescheduling
    /// before returning, because iOS may suspend the app straight after.
    func handleReminder(_ action: ReminderAction, taskID: UUID) async {
        let now = clock.now()
        do {
            guard let task = try engine.tasks.task(id: taskID) else { return }
            switch action {
            case .complete:
                try engine.tasks.setDone(task, true, at: now)
                clearReminders(for: taskID)
            case .snooze:
                outputs?.snooze(taskID, now: now)
            case .tomorrow:
                let tomorrow = CalendarDay.today(now: now, calendar: clock.calendar).adding(days: 1)
                try engine.tasks.move(task, to: tomorrow)
                outputs?.clearSnooze(taskID)
            }
        } catch {
            Self.logger.error("Reminder action failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        reload()
        await outputs?.scheduler.flush()
    }

    private func askForRemindersIfNeeded() {
        guard remindersAvailable, reminderAccess == .notAsked else { return }
        Task { await requestReminders() }
    }

    /// A tick made on a widget, when iOS runs the intent inside the app.
    private func applyWidgetTick(_ id: UUID, done: Bool) {
        guard let task = try? engine.tasks.task(id: id), task.isDone != done else { return }
        if commit({ try engine.tasks.setDone(task, done, at: clock.now()) }), done {
            clearReminders(for: id)
        }
    }

    private func clearReminders(for id: UUID) {
        guard let outputs else { return }
        outputs.clearSnooze(id)
        ReminderScheduler.clear(task: id)
    }

    #if DEBUG
    /// Demo scenes only: today's snapshot exactly as the widgets would receive it, and the demo clock.
    func demoWidgetSnapshot() -> (snapshot: DaySnapshot, now: Date, calendar: Calendar)? {
        let now = clock.now()
        guard let snapshot = try? engine.snapshot(now: now, calendar: clock.calendar) else { return nil }
        return (snapshot, now, clock.calendar)
    }

    /// Demo scenes only: pretend notifications exist, to show the reminder card and Settings rows.
    func showDemoReminders(_ access: ReminderAccess) {
        remindersAvailable = true
        reminderAccess = access
        reminderPromptDismissed = false
    }
    #endif

    // MARK: Notice actions

    func setNotice(_ id: String, enabled: Bool) {
        guard let notice = (try? engine.notices.all())?.first(where: { $0.key == id }) else { return }
        _ = commit({ try engine.notices.setEnabled(notice, enabled) })
    }

    func removeNotice(_ id: String) {
        guard let notice = (try? engine.notices.all())?.first(where: { $0.key == id }) else { return }
        _ = commit({ try engine.notices.delete(notice) })
    }

    func addNotice(title: String, day: CalendarDay, repeatsEveryYear: Bool) {
        let added: Bool = commit {
            try engine.notices.addCustom(
                title: title,
                month: day.month,
                day: day.day,
                year: day.year,
                repeatsEveryYear: repeatsEveryYear,
                now: clock.now()
            )
        }
        if added {
            say("Notice added \u{00B7} \(title)")
        }
    }

    // MARK: Toast

    func say(_ text: String) {
        let message = ToastMessage(text: text)
        withAnimation(animated(Motion.sheet)) {
            toast = message
        }
        AccessibilityNotification.Announcement(text).post()
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            self?.dismissToast(message.id)
        }
    }

    private func dismissToast(_ id: UUID) {
        guard toast?.id == id else { return }
        withAnimation(animated(Motion.sheet)) {
            toast = nil
        }
    }

    // MARK: Helpers

    /// Runs one engine change, then reloads with a spring so rows move rather than jump.
    private func commit<Output>(_ work: () throws -> Output) -> Bool {
        do {
            _ = try work()
        } catch {
            fail(error)
            return false
        }
        withAnimation(animated(Motion.settle)) {
            reload()
        }
        return true
    }

    private func fail(_ error: Error) {
        Self.logger.error("Change failed: \(error.localizedDescription, privacy: .public)")
        say("Couldn\u{2019}t save that. Try again.")
    }
}
