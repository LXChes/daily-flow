import Foundation
import SwiftData
import Testing
@testable import DailyFlowCore

@Suite("Reminder planning")
struct ReminderPlannerTests {
    let calendar = Fixture.london
    let today = Fixture.day(20300304)
    let defaults = ReminderPreferences(morningBriefEnabled: true, morningBriefMinute: 8 * 60, urgentLeadMinutes: 30, untimedMinute: 9 * 60)

    func task(
        _ title: String,
        day: CalendarDay? = nil,
        start: Int? = nil,
        urgent: Bool = true,
        done: Bool = false,
        id: UUID = UUID()
    ) -> ReminderTask {
        ReminderTask(id: id, title: title, day: day ?? today, startMinute: start, isUrgent: urgent, isDone: done)
    }

    func fire(_ task: ReminderTask, at now: Date, _ preferences: ReminderPreferences? = nil) -> Date? {
        ReminderPlanner.urgentFireDate(for: task, preferences: preferences ?? defaults, now: now, calendar: calendar)
    }

    // MARK: Urgent fire times

    @Test func timedUrgentFiresTheLeadTimeBefore() {
        let lecture = task("Lecture", start: 14 * 60)
        #expect(fire(lecture, at: Fixture.moment(20300304, 9)) == Fixture.moment(20300304, 13, 30))
    }

    @Test(arguments: [15, 30, 60])
    func leadTimeFollowsSettings(lead: Int) {
        var preferences = defaults
        preferences.urgentLeadMinutes = lead
        let seminar = task("Seminar", start: 14 * 60)
        let expected = Fixture.moment(20300304, 14).addingTimeInterval(-Double(lead) * 60)
        #expect(fire(seminar, at: Fixture.moment(20300304, 9), preferences) == expected)
    }

    @Test func addedTooLateForTheLeadFiresAtTheStart() {
        let gym = task("Gym", start: 10 * 60)
        #expect(fire(gym, at: Fixture.moment(20300304, 9, 50)) == Fixture.moment(20300304, 10))
    }

    @Test func alreadyStartedNeverFires() {
        let gym = task("Gym", start: 10 * 60)
        #expect(fire(gym, at: Fixture.moment(20300304, 10, 1)) == nil)
    }

    @Test func untimedUrgentFiresAtTheUntimedTime() {
        let essay = task("Essay draft")
        #expect(fire(essay, at: Fixture.moment(20300304, 7)) == Fixture.moment(20300304, 9))
        #expect(fire(essay, at: Fixture.moment(20300304, 9, 1)) == nil)
    }

    @Test func notUrgentOrDoneNeverFires() {
        let now = Fixture.moment(20300304, 7)
        #expect(fire(task("Gym", start: 12 * 60, urgent: false), at: now) == nil)
        #expect(fire(task("Gym", start: 12 * 60, done: true), at: now) == nil)
    }

    @Test func futureDayUsesThatDay() {
        let later = task("Lecture", day: today.adding(days: 3), start: 11 * 60)
        #expect(fire(later, at: Fixture.moment(20300304, 23)) == Fixture.moment(20300307, 10, 30))
    }

    @Test func survivesTheClocksGoingForward() {
        // 31 March 2030 is the UK spring-forward Sunday: 01:00 jumps to 02:00.
        let task = ReminderTask(id: UUID(), title: "Gym", day: Fixture.day(20300331), startMinute: 10 * 60, isUrgent: true, isDone: false)
        let fired = fire(task, at: Fixture.moment(20300330, 20))
        #expect(fired == Fixture.moment(20300331, 9, 30))
        #expect(fired.map { calendar.component(.hour, from: $0) } == 9)
    }

    // MARK: Whole plan

    @Test func planHasAWeekOfBriefsSkippingOnesThatPassed() {
        let plan = ReminderPlanner.plan(
            tasks: [], notices: [:], snoozes: SnoozeBook(), preferences: defaults,
            now: Fixture.moment(20300304, 8, 30), calendar: calendar
        )
        let briefs = plan.filter { $0.kind == .morningBrief }
        #expect(briefs.count == ReminderPlanner.briefDays - 1) // today's 08:00 has passed
        #expect(briefs.first?.id == ReminderID.brief(today.adding(days: 1)))
        #expect(briefs.first?.fireDate == Fixture.moment(20300305, 8))
    }

    @Test func briefOffMeansNoBriefs() {
        var preferences = defaults
        preferences.morningBriefEnabled = false
        let plan = ReminderPlanner.plan(
            tasks: [], notices: [:], snoozes: SnoozeBook(), preferences: preferences,
            now: Fixture.moment(20300304, 6), calendar: calendar
        )
        #expect(plan.isEmpty)
    }

    @Test func briefWordingSummarisesTheDay() {
        let text = ReminderPlanner.briefText(
            tasks: [
                task("Seminar", start: 14 * 60, urgent: false),
                task("Lecture", start: 10 * 60, urgent: false),
                task("Essay draft"),
                task("Gym", urgent: false, done: true)
            ],
            notices: []
        )
        #expect(text.title == "Good morning")
        #expect(text.body == "3 tasks today \u{00B7} first up Lecture at 10:00 \u{00B7} 1 urgent")
    }

    @Test func briefOnANoticeDayLeadsWithIt() {
        let text = ReminderPlanner.briefText(tasks: [], notices: ["Christmas Day"])
        #expect(text.title == "It\u{2019}s Christmas Day")
        #expect(text.body.hasPrefix("Nothing planned yet"))
    }

    @Test func planIsSortedCappedAndStable() {
        let tasks = (0..<80).map { index in
            task("Task \(index)", day: today.adding(days: 1 + index / 10), start: 9 * 60 + (index % 10) * 30)
        }
        let now = Fixture.moment(20300304, 12)
        let first = ReminderPlanner.plan(tasks: tasks, notices: [:], snoozes: SnoozeBook(), preferences: defaults, now: now, calendar: calendar)
        let second = ReminderPlanner.plan(tasks: tasks, notices: [:], snoozes: SnoozeBook(), preferences: defaults, now: now, calendar: calendar)
        #expect(first.count == ReminderPlanner.maxPending)
        #expect(first == second)
        #expect(first.map(\.fireDate) == first.map(\.fireDate).sorted())
        #expect(Set(first.map(\.id)).count == first.count)
    }

    @Test func aReminderThatFiredIsNotPlannedAgain() {
        let lecture = task("Lecture", start: 14 * 60)
        let before = ReminderPlanner.plan(tasks: [lecture], notices: [:], snoozes: SnoozeBook(), preferences: defaults, now: Fixture.moment(20300304, 13), calendar: calendar)
        let after = ReminderPlanner.plan(tasks: [lecture], notices: [:], snoozes: SnoozeBook(), preferences: defaults, now: Fixture.moment(20300304, 14, 5), calendar: calendar)
        #expect(before.contains { $0.id == ReminderID.urgent(lecture.id) })
        #expect(!after.contains { $0.taskID == lecture.id })
    }

    // MARK: Snooze

    @Test func snoozeReplacesTheUrgentReminder() {
        let lecture = task("Lecture", start: 14 * 60)
        let now = Fixture.moment(20300304, 13, 30)
        var book = SnoozeBook()
        let until = book.snooze(lecture.id, now: now)
        #expect(until == Fixture.moment(20300304, 14))

        let plan = ReminderPlanner.plan(tasks: [lecture], notices: [:], snoozes: book, preferences: defaults, now: now, calendar: calendar)
        let reminders = plan.filter { $0.taskID == lecture.id }
        #expect(reminders.count == 1)
        #expect(reminders.first?.kind == .snoozed)
        #expect(reminders.first?.id == ReminderID.snoozed(lecture.id))
        #expect(reminders.first?.fireDate == until)
    }

    @Test func snoozeOnAFinishedTaskIsDropped() {
        let lecture = task("Lecture", start: 14 * 60, done: true)
        let now = Fixture.moment(20300304, 13, 30)
        var book = SnoozeBook()
        book.snooze(lecture.id, now: now)
        let plan = ReminderPlanner.plan(tasks: [lecture], notices: [:], snoozes: book, preferences: defaults, now: now, calendar: calendar)
        #expect(plan.allSatisfy { $0.taskID != lecture.id })
    }

    @Test func snoozeAgainReplacesAndPruneDropsFired() {
        let id = UUID()
        var book = SnoozeBook()
        book.snooze(id, now: Fixture.moment(20300304, 10))
        book.snooze(id, now: Fixture.moment(20300304, 10, 30))
        #expect(book.entries.count == 1)
        #expect(book.until(for: id) == Fixture.moment(20300304, 11))

        book.prune(now: Fixture.moment(20300304, 11))
        #expect(book.entries.isEmpty)
    }

    @Test func snoozeBookRoundTripsAndToleratesDamage() {
        var book = SnoozeBook()
        book.snooze(UUID(), now: Fixture.moment(20300304, 10))
        #expect(SnoozeBook.decode(book.encoded()) == book)
        #expect(SnoozeBook.decode(Data("not json".utf8)) == SnoozeBook())
        #expect(SnoozeBook.decode(nil) == SnoozeBook())
    }

    // MARK: Routing

    @Test func payloadCarriesTheTask() {
        let id = UUID()
        #expect(ReminderRoute.taskID(from: ReminderRoute.userInfo(for: id)) == id)
        #expect(ReminderRoute.taskID(from: [:]) == nil)
        #expect(ReminderRoute.taskID(from: [ReminderRoute.taskIDKey: "nope"]) == nil)
        #expect(ReminderAction(rawValue: ReminderAction.snooze.rawValue) == .snooze)
        #expect(ReminderID.all(for: id) == [ReminderID.urgent(id), ReminderID.snoozed(id)])
    }
}

/// The plan built from the real store.
@MainActor
@Suite("Reminder plan from the store")
struct ReminderStoreTests {
    let engine: DayEngine
    let today = Fixture.day(20300304)
    let now = Fixture.moment(20300304, 9, 15)

    init() throws {
        let container = try DailyFlowStore.makeContainer(inMemory: true)
        engine = DayEngine(context: ModelContext(container))
    }

    @Test func urgentTasksAndSettingsFeedThePlan() throws {
        let lecture = try engine.tasks.add(title: "Lecture", day: today, startMinute: 14 * 60, isUrgent: true, now: now)
        try engine.tasks.add(title: "Gym", day: today, startMinute: 18 * 60, now: now)
        let settings = try engine.settings.current()
        settings.urgentLeadMinutes = 60

        var plan = try engine.reminderPlan(snoozes: SnoozeBook(), now: now, calendar: Fixture.london)
        let urgent = plan.filter { $0.kind == .urgent }
        #expect(urgent.map(\.taskID) == [lecture.id])
        #expect(urgent.first?.fireDate == Fixture.moment(20300304, 13))
        #expect(urgent.first?.body == "Urgent \u{00B7} starts at 14:00, in 60 min")

        try engine.tasks.setDone(lecture, true, at: now)
        plan = try engine.reminderPlan(snoozes: SnoozeBook(), now: now, calendar: Fixture.london)
        #expect(plan.allSatisfy { $0.kind == .morningBrief })
    }

    @Test func movingToTomorrowMovesTheReminder() throws {
        let essay = try engine.tasks.add(title: "Essay draft", day: today, isUrgent: true, now: now)
        try engine.tasks.move(essay, to: today.adding(days: 1))
        let plan = try engine.reminderPlan(snoozes: SnoozeBook(), now: now, calendar: Fixture.london)
        #expect(plan.first { $0.taskID == essay.id }?.fireDate == Fixture.moment(20300305, 9))
        #expect(try engine.tasks.task(id: essay.id)?.day == today.adding(days: 1))
    }

    @Test func pastDaysAreIgnored() throws {
        try engine.tasks.add(title: "Essay plan", day: today.adding(days: -1), isUrgent: true, now: now)
        let plan = try engine.reminderPlan(snoozes: SnoozeBook(), now: now, calendar: Fixture.london)
        #expect(plan.allSatisfy { $0.kind == .morningBrief })
    }
}
