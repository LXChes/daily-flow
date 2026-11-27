import Foundation
import Testing
@testable import DailyFlowCore

@Suite("Day schedule")
struct ScheduleTests {
    let items = [
        Item(name: "Anytime", startMinute: nil, durationMinutes: nil, createdAt: Date(timeIntervalSince1970: 1)),
        Item(name: "Lecture", startMinute: 600, durationMinutes: 60),
        Item(name: "Gym", startMinute: 480, durationMinutes: 45),
        Item(name: "Urgent anytime", startMinute: nil, durationMinutes: nil, isUrgent: true,
             createdAt: Date(timeIntervalSince1970: 2)),
        Item(name: "Seminar", startMinute: 840, durationMinutes: nil)
    ]

    @Test func autoSortPutsTimedFirstThenUrgentAnytime() {
        let names = DaySchedule.ordered(items, autoSort: true).map(\.name)
        #expect(names == ["Gym", "Lecture", "Seminar", "Urgent anytime", "Anytime"])
    }

    @Test func manualOrderFollowsSortIndex() {
        let manual = [
            Item(name: "B", startMinute: 60, durationMinutes: nil, sortIndex: 1),
            Item(name: "A", startMinute: 900, durationMinutes: nil, sortIndex: 0),
            Item(name: "C", startMinute: nil, durationMinutes: nil, sortIndex: 2)
        ]
        #expect(DaySchedule.ordered(manual, autoSort: false).map(\.name) == ["A", "B", "C"])
    }

    @Test func currentBlockAndUntimedDefaultLength() {
        #expect(DaySchedule.current(items, atMinute: 610)?.name == "Lecture")
        #expect(DaySchedule.current(items, atMinute: 660) == nil) // the lecture ends at 11:00
        #expect(DaySchedule.current(items, atMinute: 854)?.name == "Seminar") // 15-minute default block
        #expect(DaySchedule.current(items, atMinute: 855) == nil)
    }

    @Test func doneTasksAreNeverCurrentOrUpcoming() {
        var finished = items
        finished[1].isDone = true
        #expect(DaySchedule.current(finished, atMinute: 610) == nil)
        #expect(DaySchedule.upcoming(finished, afterMinute: 0).map(\.name) == ["Gym", "Seminar"])
    }

    @Test func nowOrNextFeaturesTheRunningTaskElseTheNextOne() {
        #expect(DaySchedule.nowOrNext(items, atMinute: 610)?.name == "Lecture")
        #expect(DaySchedule.nowOrNext(items, atMinute: 300)?.name == "Gym")
        #expect(DaySchedule.nowOrNext(items, atMinute: 700)?.name == "Seminar")
        #expect(DaySchedule.nowOrNext(items, atMinute: 900) == nil)
    }

    @Test func progressCountsDoneTasks() {
        var some = items
        some[0].isDone = true
        some[2].isDone = true
        let progress = DaySchedule.progress(some)
        #expect(progress == DayProgress(done: 2, total: 5))
        #expect(progress.percent == 40)
        #expect(DaySchedule.progress([Item]()).fraction == 0)
    }

    @Test func busyMinutesPerHour() {
        let busy = DaySchedule.busyMinutesByHour([
            Item(name: "A", startMinute: 570, durationMinutes: 75),  // 09:30 to 10:45
            Item(name: "B", startMinute: 600, durationMinutes: 30),  // overlaps A, not double counted
            Item(name: "C", startMinute: 1_410, durationMinutes: 90) // 23:30, capped at midnight
        ])
        #expect(busy.count == 24)
        #expect(busy[9] == 30)
        #expect(busy[10] == 45)
        #expect(busy[23] == 30)
        #expect(busy.reduce(0, +) == 105)
    }

    @Test func durationNudges() {
        #expect(DurationRules.adjust(nil, bySteps: 1) == 15)
        #expect(DurationRules.adjust(nil, bySteps: -1) == nil)
        #expect(DurationRules.adjust(nil, bySteps: 0) == nil)
        #expect(DurationRules.adjust(30, bySteps: 1) == 45)
        #expect(DurationRules.adjust(15, bySteps: -1) == nil)
        #expect(DurationRules.adjust(715, bySteps: 2) == 720)
        #expect(DurationRules.quickPicks.first == 15 && DurationRules.quickPicks.last == 180)
    }
}

@Suite("Day rollover rules")
struct RolloverRuleTests {
    let today = Fixture.day(20300304)

    @Test func leftoverMeansUnfinishedAndEarlier() {
        #expect(DayRollover.isLeftover(taskDay: today.adding(days: -1), isDone: false, today: today))
        #expect(!DayRollover.isLeftover(taskDay: today.adding(days: -1), isDone: true, today: today))
        #expect(!DayRollover.isLeftover(taskDay: today, isDone: false, today: today))
        #expect(!DayRollover.isLeftover(taskDay: today.adding(days: 3), isDone: false, today: today))
    }

    @Test func choicesMapToDays() {
        #expect(DayRollover.destination(for: .keepToday, today: today) == today)
        #expect(DayRollover.destination(for: .tomorrow, today: today) == Fixture.day(20300305))
        #expect(DayRollover.destination(for: .bin, today: today) == nil)
    }

    @Test func futureTasksShowOnlyOnTheirDay() {
        let friday = Fixture.day(20300308)
        #expect(!DayRollover.isShown(taskDay: friday, on: today))
        #expect(DayRollover.isShown(taskDay: friday, on: friday))
    }

    @Test func quickPickDaysAreTodayPlusSix() {
        let days = DayRollover.quickPickDays(from: today)
        #expect(days.count == 7)
        #expect(days.first == today)
        #expect(days.last == Fixture.day(20300310))
    }
}
