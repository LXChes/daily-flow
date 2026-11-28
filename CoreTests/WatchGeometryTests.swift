import Foundation
import Testing
@testable import DailyFlowCore

/// A neutral watch task for the geometry rules.
struct WatchTask: WatchItem, Equatable {
    var id = UUID()
    var name: String
    var category: TaskCategory = .other
    var startMinute: Int?
    var durationMinutes: Int?
    var isDone = false
    var isUrgent = false
    var sortIndex = 0
    var createdAt = Date(timeIntervalSince1970: 0)
}

@Suite("Watch geometry")
struct WatchGeometryTests {
    private func near(_ value: Double, _ expected: Double, _ tolerance: Double = 1e-9) -> Bool {
        abs(value - expected) <= tolerance
    }

    // MARK: Hands

    @Test func handsAtMidnightAllPointUp() {
        let hands = WatchGeometry.hands(atMinute: 0)
        #expect(hands == WatchHands(hour: 0, minute: 0, second: 0, day: 0))
    }

    @Test func handsAtQuarterPastTen() {
        let hands = WatchGeometry.hands(atMinute: 10 * 60 + 15)
        #expect(near(hands.hour, 307.5))       // 10.25 of 12 hours
        #expect(near(hands.minute, 90))
        #expect(near(hands.day, 153.75))       // 10.25 of 24 hours
        #expect(near(hands.second, 0))
    }

    @Test func afternoonHourHandWrapsButDayHandDoesNot() {
        let hands = WatchGeometry.hands(atMinute: 18 * 60)
        #expect(near(hands.hour, 180))
        #expect(near(hands.day, 270))
    }

    @Test func secondsComeFromTheFractionalMinute() {
        let hands = WatchGeometry.hands(atMinute: 600.5)
        #expect(near(hands.second, 180, 1e-6))
        #expect(near(hands.minute, 3, 1e-6))
    }

    @Test func handsWrapOutOfRangeMinutes() {
        #expect(WatchGeometry.hands(atMinute: 1_440 + 60) == WatchGeometry.hands(atMinute: 60))
        #expect(near(WatchGeometry.dayDegrees(atMinute: -360), 270))
    }

    // MARK: Arcs

    @Test func arcsAreInsetAndInStartOrder() {
        let items = [
            WatchTask(name: "Seminar", category: .uni, startMinute: 840, durationMinutes: 60),
            WatchTask(name: "Anytime", startMinute: nil),
            WatchTask(name: "Gym", category: .health, startMinute: 450, durationMinutes: 60, isDone: true)
        ]
        let arcs = WatchGeometry.arcs(items, atMinute: 0)
        #expect(arcs.map(\.category) == [.health, .uni])
        #expect(near(arcs[0].startDegrees, 455.0 / 4))   // 07:35 = 113.75 deg
        #expect(near(arcs[0].endDegrees, 505.0 / 4))     // 08:25
        #expect(arcs[0].isDone)
        #expect(!arcs[1].isDone)
    }

    @Test func shortTasksStillGetAVisibleArc() {
        let quick = WatchTask(name: "Call", startMinute: 600, durationMinutes: 15)
        let untimedLength = WatchTask(name: "Reminder", startMinute: 700, durationMinutes: nil)
        let arcs = WatchGeometry.arcs([quick, untimedLength], atMinute: 0)
        #expect(arcs.count == 2)
        for arc in arcs {
            #expect(near(arc.sweepDegrees, 11.0 / 4)) // 21-minute block less two 5-minute insets
        }
    }

    @Test func arcsNeverRunPastMidnight() {
        let late = WatchTask(name: "Late study", startMinute: 1_410, durationMinutes: 120)
        let arc = WatchGeometry.arcs([late], atMinute: 0)
        #expect(arc.count == 1)
        #expect(arc[0].endDegrees <= 360)
    }

    @Test func liveArcIsTheUnfinishedRunningTask() {
        let lecture = WatchTask(name: "Lecture", startMinute: 600, durationMinutes: 120)
        var finished = lecture
        finished.isDone = true
        #expect(WatchGeometry.arcs([lecture], atMinute: 615)[0].isLive)
        #expect(!WatchGeometry.arcs([lecture], atMinute: 720)[0].isLive)
        #expect(!WatchGeometry.arcs([finished], atMinute: 615)[0].isLive)
    }

    // MARK: Gears

    @Test func gearsFollowDisplayOrderWithStates() {
        let items = [
            WatchTask(name: "Gym", startMinute: 450, durationMinutes: 60, isDone: true),
            WatchTask(name: "Lecture", startMinute: 600, durationMinutes: 120),
            WatchTask(name: "Essay", isUrgent: true),
            WatchTask(name: "Seminar", startMinute: 840, durationMinutes: 60)
        ]
        let gears = WatchGeometry.gears(items, titles: \.name, atMinute: 615)
        #expect(gears.map(\.title) == ["Gym", "Lecture", "Essay", "Seminar"])
        #expect(gears.map(\.slot) == [0, 1, 2, 3])
        #expect(gears.map(\.state) == [.done, .live, .idle, .idle])
        #expect(gears.map(\.pulsesJewel) == [false, false, true, false])
        #expect(gears[1].spinRate == WatchGeometry.liveSpinRate)
        #expect(gears[0].spinRate == 1)
    }

    @Test func doneUrgentTaskStopsPulsing() {
        let gears = WatchGeometry.gears([WatchTask(name: "Essay", isDone: true, isUrgent: true)], titles: \.name, atMinute: 0)
        #expect(gears[0].pulsesJewel == false)
        #expect(gears[0].state == .done)
    }

    @Test func busyDayKeepsUrgentThenTimedTasksInDisplayOrder() {
        var items = (0..<6).map { WatchTask(name: "Anytime \($0)") }
        items.insert(WatchTask(name: "Lecture", startMinute: 600), at: 2)
        items.append(WatchTask(name: "Urgent", isUrgent: true))
        items.append(WatchTask(name: "Seminar", startMinute: 840))
        items.append(WatchTask(name: "Anytime last"))
        let gears = WatchGeometry.gears(items, titles: \.name, atMinute: 0)
        #expect(gears.count == WatchGeometry.taskGearSlots)
        #expect(gears.map(\.title) == [
            "Anytime 0", "Anytime 1", "Lecture", "Anytime 2", "Anytime 3", "Anytime 4", "Urgent", "Seminar"
        ])
        #expect(gears.map(\.slot) == Array(0..<8))
    }

    @Test func tickingNeverReshufflesGears() {
        var items = (0..<10).map { WatchTask(name: "Task \($0)", startMinute: $0.isMultiple(of: 2) ? 600 + $0 * 30 : nil) }
        let before = WatchGeometry.gears(items, titles: \.name, atMinute: 0).map(\.taskID)
        for index in items.indices { items[index].isDone = true }
        let after = WatchGeometry.gears(items, titles: \.name, atMinute: 0).map(\.taskID)
        #expect(before == after)
    }

    @Test func rotationWrapsAndRunsBothWays() {
        #expect(near(WatchGeometry.rotation(degreesPerSecond: 90, seconds: 5), 90))
        #expect(near(WatchGeometry.rotation(degreesPerSecond: -90, seconds: 1), 270))
        let late = WatchGeometry.rotation(degreesPerSecond: 7.5, seconds: 86_400 * 3 + 12)
        #expect(late >= 0 && late < 360)
    }

    // MARK: Progress and speech

    @Test func progressSweepIsClamped() {
        #expect(near(WatchGeometry.progressSweep(DayProgress(done: 1, total: 4), trackDegrees: 100), 25))
        #expect(near(WatchGeometry.progressSweep(DayProgress(done: 0, total: 0), trackDegrees: 100), 0))
        #expect(near(WatchGeometry.progressSweep(DayProgress(done: 3, total: 3), trackDegrees: 100), 100))
    }

    @Test func spokenSummaryNamesNowNextAndProgress() {
        let items = [
            WatchTask(name: "Gym", startMinute: 450, durationMinutes: 60, isDone: true),
            WatchTask(name: "Lecture", startMinute: 600, durationMinutes: 120),
            WatchTask(name: "Seminar", startMinute: 840, durationMinutes: 60)
        ]
        #expect(WatchGeometry.spokenSummary(items, titles: \.name, atMinute: 615.4)
            == "Now 10:15. On now: Lecture, until 12:00. Next: Seminar at 14:00. 1 of 3 done.")
        #expect(WatchGeometry.spokenSummary([WatchTask](), titles: \.name, atMinute: 0)
            == "Now 00:00. Nothing planned.")
        let allDone = items.map { item -> WatchTask in var copy = item; copy.isDone = true; return copy }
        #expect(WatchGeometry.spokenSummary(allDone, titles: \.name, atMinute: 1_000) == "Now 16:40. All 3 done.")
    }

    @Test func clockPadsAndCapsAtMidnight() {
        #expect(WatchGeometry.clock(5) == "00:05")
        #expect(WatchGeometry.clock(1_440) == "24:00")
        #expect(WatchGeometry.clock(-3) == "00:00")
    }
}
