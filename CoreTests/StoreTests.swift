import Foundation
import SwiftData
import Testing
@testable import DailyFlowCore

/// Storage behaviour against a fresh in-memory store per test.
@MainActor
@Suite("Storage and day engine")
struct StoreTests {
    let container: ModelContainer
    let engine: DayEngine
    let today = Fixture.day(20300304)
    let now = Fixture.moment(20300304, 9, 15)

    init() throws {
        container = try DailyFlowStore.makeContainer(inMemory: true)
        engine = DayEngine(context: ModelContext(container))
    }

    // MARK: Tasks

    @Test func addingGuessesTheCategoryAndTrimsTheTitle() throws {
        let task = try engine.tasks.add(title: "  Lecture notes ", day: today, now: now)
        #expect(task.title == "Lecture notes")
        #expect(task.category == .uni)
        #expect(!task.isCategoryManual)
    }

    @Test func emptyTitlesAreRejected() {
        #expect(throws: CoreError.emptyTitle) {
            try engine.tasks.add(title: "   ", day: today)
        }
    }

    @Test func manualCategorySurvivesRename() throws {
        let task = try engine.tasks.add(title: "Gym", day: today, now: now)
        try engine.tasks.rename(task, to: "Lecture notes")
        #expect(task.category == .uni) // re-guessed

        try engine.tasks.setCategory(task, to: .social)
        try engine.tasks.rename(task, to: "Gym")
        #expect(task.category == .social) // owner's choice kept
    }

    @Test func futureTasksAppearOnlyOnTheirDay() throws {
        let friday = today.adding(days: 4)
        try engine.tasks.add(title: "Gym", day: today, now: now)
        try engine.tasks.add(title: "Seminar prep", day: friday, now: now)

        #expect(try engine.tasks.tasks(on: today, autoSort: true).map(\.title) == ["Gym"])
        #expect(try engine.tasks.tasks(on: friday, autoSort: true).map(\.title) == ["Seminar prep"])
    }

    @Test func manualOrderAndMovingKeepSortIndexesTidy() throws {
        let first = try engine.tasks.add(title: "First", day: today, now: now)
        let second = try engine.tasks.add(title: "Second", day: today, now: now)
        #expect(first.sortIndex == 0 && second.sortIndex == 1)

        try engine.tasks.reorder([second, first])
        #expect(try engine.tasks.tasks(on: today, autoSort: false).map(\.title) == ["Second", "First"])

        let tomorrow = today.adding(days: 1)
        try engine.tasks.add(title: "Already there", day: tomorrow, now: now)
        try engine.tasks.move(first, to: tomorrow)
        #expect(try engine.tasks.tasks(on: tomorrow, autoSort: false).map(\.title) == ["Already there", "First"])
    }

    @Test func timesAndDurationsAreClamped() throws {
        let task = try engine.tasks.add(title: "Long study", day: today, startMinute: 5_000, durationMinutes: 2, now: now)
        #expect(task.startMinute == 1_439)
        #expect(task.durationMinutes == 15)
        try engine.tasks.setTime(task, startMinute: nil, durationMinutes: 10_000)
        #expect(task.startMinute == nil)
        #expect(task.durationMinutes == 720)
    }

    // MARK: Leftovers

    @Test func leftoversAreUnfinishedTasksFromEarlierDays() throws {
        let yesterday = today.adding(days: -1)
        try engine.tasks.add(title: "Old essay", day: today.adding(days: -3), now: now)
        try engine.tasks.add(title: "Laundry", day: yesterday, now: now)
        let done = try engine.tasks.add(title: "Gym", day: yesterday, now: now)
        try engine.tasks.setDone(done, true, at: now)
        try engine.tasks.add(title: "Lecture", day: today, now: now)

        #expect(try engine.tasks.leftovers(today: today).map(\.title) == ["Old essay", "Laundry"])
    }

    @Test func triageChoicesMoveOrBin() throws {
        let yesterday = today.adding(days: -1)
        let keep = try engine.tasks.add(title: "Keep me", day: yesterday, now: now)
        let later = try engine.tasks.add(title: "Later", day: yesterday, now: now)
        let bin = try engine.tasks.add(title: "Bin me", day: yesterday, now: now)

        try engine.tasks.triage(keep, .keepToday, today: today)
        try engine.tasks.triage(later, .tomorrow, today: today)
        try engine.tasks.triage(bin, .bin, today: today)

        #expect(try engine.tasks.leftovers(today: today).isEmpty)
        #expect(try engine.tasks.tasks(on: today, autoSort: true).map(\.title) == ["Keep me"])
        #expect(try engine.tasks.tasks(on: today.adding(days: 1), autoSort: true).map(\.title) == ["Later"])
        #expect(try engine.tasks.context.fetch(FetchDescriptor<FlowTask>()).count == 2)
    }

    @Test func triageIgnoresTasksThatAreNotLeftovers() throws {
        let current = try engine.tasks.add(title: "Today's task", day: today, now: now)
        try engine.tasks.triage(current, .bin, today: today)
        #expect(try engine.tasks.tasks(on: today, autoSort: true).count == 1)
    }

    @Test func triageAllAppliesOneChoice() throws {
        try engine.tasks.add(title: "One", day: today.adding(days: -1), now: now)
        try engine.tasks.add(title: "Two", day: today.adding(days: -2), now: now)
        try engine.tasks.triageAll(.tomorrow, today: today)
        #expect(try engine.tasks.tasks(on: today.adding(days: 1), autoSort: true).count == 2)
    }

    @Test func refreshWaitsForTriageWhenItIsOn() throws {
        try engine.tasks.add(title: "Laundry", day: today.adding(days: -1), now: now)
        let status = try engine.refresh(now: now, calendar: Fixture.london)
        #expect(status.today == today)
        #expect(status.leftoverCount == 1)
        #expect(status.rolledOverCount == 0)
        #expect(try engine.tasks.tasks(on: today, autoSort: true).isEmpty)
    }

    @Test func refreshRollsLeftoversOverWhenTriageIsOff() throws {
        try engine.settings.current().leftoversTriageEnabled = false
        try engine.settings.save()
        try engine.tasks.add(title: "Laundry", day: today.adding(days: -2), now: now)

        let status = try engine.refresh(now: now, calendar: Fixture.london)
        #expect(status.leftoverCount == 0)
        #expect(status.rolledOverCount == 1)
        #expect(try engine.tasks.tasks(on: today, autoSort: true).map(\.title) == ["Laundry"])
    }

    // MARK: Settings

    @Test func settingsAreASingletonWithBriefDefaults() throws {
        let first = try engine.settings.current()
        let second = try engine.settings.current()
        #expect(first === second)
        #expect(try engine.settings.context.fetch(FetchDescriptor<AppSettings>()).count == 1)

        #expect(first.noticesEnabled && first.morningBriefEnabled && first.leftoversTriageEnabled)
        #expect(first.morningBriefTime == 480)
        #expect(first.urgentLead == 30)
        #expect(first.untimedReminderTime == 540)
        #expect(first.autoSortEnabled && first.hapticTickEnabled && first.tickSoundEnabled)
        #expect(first.widgetStyle == .matchApp)
        #expect(first.layout == .playTheDay && first.theme == .dark && first.progressStyle == .wave)
        #expect(first.categoryMode == .simple && first.previewMode == .normal)
    }

    @Test func settingsRejectOutOfRangeValues() throws {
        let settings = try engine.settings.current()
        settings.urgentLead = 45
        #expect(settings.urgentLead == 30)
        settings.urgentLead = 60
        #expect(settings.urgentLead == 60)
        settings.morningBriefTime = 2_000
        #expect(settings.morningBriefTime == 1_439)
        settings.themeRaw = "unknown"
        #expect(settings.theme == .dark)
    }

    // MARK: Notices

    @Test func builtInsAreSeededOnce() throws {
        try engine.notices.ensureBuiltIns()
        try engine.notices.ensureBuiltIns()
        let rows = try engine.notices.all()
        #expect(rows.count == BuiltInNotice.allCases.count)
        #expect(rows.compactMap(\.builtIn) == BuiltInNotice.allCases)
    }

    @Test func noticesFollowTheirSwitches() throws {
        let christmas = Fixture.moment(20301225, 8)
        #expect(try engine.refresh(now: christmas, calendar: Fixture.london).notices.map(\.title) == ["Christmas Day"])

        let row = try #require(try engine.notices.all().first { $0.builtIn == .christmasDay })
        try engine.notices.setEnabled(row, false)
        #expect(try engine.refresh(now: christmas, calendar: Fixture.london).notices.isEmpty)

        try engine.notices.setEnabled(row, true)
        try engine.settings.current().noticesEnabled = false
        #expect(try engine.refresh(now: christmas, calendar: Fixture.london).notices.isEmpty)
    }

    @Test func customNoticesAreValidatedAndListedAfterBuiltIns() throws {
        try engine.notices.ensureBuiltIns()
        #expect(throws: CoreError.emptyTitle) {
            try engine.notices.addCustom(title: " ", month: 5, day: 1, year: 2030, repeatsEveryYear: true)
        }
        #expect(throws: CoreError.invalidDate) {
            try engine.notices.addCustom(title: "Bad date", month: 2, day: 30, year: 2030, repeatsEveryYear: true)
        }
        #expect(throws: CoreError.invalidDate) {
            try engine.notices.addCustom(title: "Not a leap year", month: 2, day: 29, year: 2030, repeatsEveryYear: false)
        }

        let yearly = try engine.notices.addCustom(
            title: "Club anniversary", month: 2, day: 29, year: 2028, repeatsEveryYear: true, now: now
        )
        try engine.notices.addCustom(
            title: "Open day", month: 6, day: 14, year: 2030, repeatsEveryYear: false, now: now.addingTimeInterval(1)
        )
        #expect(try engine.notices.all().suffix(2).map(\.title) == ["Club anniversary", "Open day"])
        #expect(yearly.rule?.schedule.occurrence(in: 2031) == Fixture.day(20310228))

        let rules = try engine.notices.activeRules(noticesEnabled: true)
        #expect(NoticeCalendar.notices(on: Fixture.day(20300614), rules: rules).map(\.title) == ["Open day"])
        #expect(NoticeCalendar.notices(on: Fixture.day(20310614), rules: rules).isEmpty)
    }

    @Test func builtInsCannotBeDeletedButCustomCan() throws {
        try engine.notices.ensureBuiltIns()
        let builtIn = try #require(try engine.notices.all().first)
        #expect(throws: CoreError.cannotDeleteBuiltInNotice) {
            try engine.notices.delete(builtIn)
        }
        let custom = try engine.notices.addCustom(title: "Open day", month: 6, day: 14, year: 2030, repeatsEveryYear: false)
        try engine.notices.delete(custom)
        #expect(try engine.notices.all().count == BuiltInNotice.allCases.count)
    }

    // MARK: Snapshot

    @Test func snapshotCapturesTodayAndRoundTrips() throws {
        try engine.tasks.add(title: "Lecture", day: today, startMinute: 600, durationMinutes: 60, now: now)
        let gym = try engine.tasks.add(title: "Gym", day: today, startMinute: 480, durationMinutes: 45, now: now)
        try engine.tasks.setDone(gym, true, at: now)
        try engine.tasks.add(title: "Tomorrow's thing", day: today.adding(days: 1), now: now)

        let snapshot = try engine.snapshot(now: now, calendar: Fixture.london)
        #expect(snapshot.day == today)
        #expect(snapshot.tasks.map(\.title) == ["Gym", "Lecture"])
        #expect(snapshot.progress == DayProgress(done: 1, total: 2))
        #expect(snapshot.tasks.first?.category == .health)

        let decoded = DaySnapshot.decode(try snapshot.encoded())
        #expect(decoded == snapshot)
    }

    @Test func snapshotDecodingNeverThrows() throws {
        #expect(DaySnapshot.decode(nil) == nil)
        #expect(DaySnapshot.decode(Data("not json".utf8)) == nil)

        let placeholder = DaySnapshot.placeholder(now: now, calendar: Fixture.london)
        #expect(placeholder.tasks.isEmpty && placeholder.day == today)

        let json = try #require(String(data: try placeholder.encoded(), encoding: .utf8))
        let future = json.replacingOccurrences(of: "\"version\":1", with: "\"version\":99")
        #expect(future != json)
        #expect(DaySnapshot.decode(Data(future.utf8)) == nil)
    }
}
