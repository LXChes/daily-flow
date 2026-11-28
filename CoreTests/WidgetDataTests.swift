import Foundation
import Testing
@testable import DailyFlowCore

@Suite("Widget data and fallbacks")
struct WidgetDataTests {
    let calendar = Fixture.london
    let today = Fixture.day(20301225)
    let now = Fixture.moment(20301225, 10)

    func snapshot(day: CalendarDay, tasks: [TaskSnapshot] = [], theme: ThemeMode = .dark, style: WidgetStyle = .matchApp) -> DaySnapshot {
        DaySnapshot(generatedAt: now, day: day, tasks: tasks, noticeTitles: [], widgetStyle: style, theme: theme)
    }

    func item(_ title: String, start: Int? = nil, duration: Int? = nil, done: Bool = false, index: Int = 0) -> TaskSnapshot {
        TaskSnapshot(
            id: UUID(), title: title, category: .other, startMinute: start, durationMinutes: duration,
            isUrgent: false, isDone: done, sortIndex: index, createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: Fallback order

    @Test func sharedTodayWins() {
        let shared = snapshot(day: today, tasks: [item("Lecture")])
        let resolved = WidgetDataResolver.resolve(shared: shared, cached: nil, now: now, calendar: calendar)
        #expect(resolved.source == .shared)
        #expect(resolved.canTick)
        #expect(resolved.snapshot == shared)
    }

    @Test func cachedCopyWhenSharedIsMissingOrOld() {
        let cached = snapshot(day: today, tasks: [item("Gym")])
        let old = snapshot(day: today.adding(days: -1))
        for shared in [nil, old] {
            let resolved = WidgetDataResolver.resolve(shared: shared, cached: cached, now: now, calendar: calendar)
            #expect(resolved.source == .cached)
            #expect(resolved.hasTasks)
            #expect(!resolved.canTick)
        }
    }

    @Test func basicModeComputesTheDayItself() {
        let resolved = WidgetDataResolver.resolve(shared: nil, cached: nil, now: now, calendar: calendar)
        #expect(resolved.source == .basic)
        #expect(!resolved.hasTasks)
        #expect(resolved.snapshot.day == today)
        #expect(resolved.snapshot.tasks.isEmpty)
        #expect(resolved.snapshot.noticeTitles == ["Christmas Day"])
        #expect(resolved.snapshot.theme == .dark)
    }

    @Test func basicModeKeepsAKnownLook() {
        let old = snapshot(day: today.adding(days: -2), theme: .light, style: .lightVintage)
        let resolved = WidgetDataResolver.resolve(shared: old, cached: nil, now: now, calendar: calendar)
        #expect(resolved.source == .basic)
        #expect(resolved.snapshot.theme == .light)
        #expect(resolved.snapshot.widgetStyle == .lightVintage)
    }

    @Test func widgetReadsItsOwnCacheWithoutASharedFolder() throws {
        let suite = "df.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let empty = WidgetDataStore.loadForWidget(now: now, calendar: calendar, defaults: defaults)
        #expect(empty.source == .basic || WidgetDataStore.isShared)

        let cached = snapshot(day: today, tasks: [item("Seminar")])
        defaults.set(try cached.encoded(), forKey: WidgetDataStore.cacheKey)
        let loaded = WidgetDataStore.loadForWidget(now: now, calendar: calendar, defaults: defaults)
        #expect(loaded.snapshot.tasks.map(\.title) == ["Seminar"])
    }

    // MARK: Finding the shared folder

    @Test func sideloadedGroupNamesComeFirst() {
        let groups = SharedContainer.candidateGroups(from: [
            [SharedContainer.sideloadGroupsKey: ["group.com.example.dailyflow.TEAM1"]],
            [SharedContainer.sideloadGroupsKey: ["group.com.example.dailyflow.TEAM1", "not-a-group"]],
            nil
        ])
        #expect(groups == ["group.com.example.dailyflow.TEAM1", SharedContainer.requestedGroup])
    }

    @Test func singleStringAndNothingAtAll() {
        #expect(SharedContainer.candidateGroups(from: [[SharedContainer.sideloadGroupsKey: " group.other "]])
            == ["group.other", SharedContainer.requestedGroup])
        #expect(SharedContainer.candidateGroups(from: []) == [SharedContainer.requestedGroup])
        #expect(SharedContainer.candidateGroups(from: [[SharedContainer.sideloadGroupsKey: 42]]) == [SharedContainer.requestedGroup])
    }

    // MARK: Style

    @Test func widgetStyleResolution() {
        #expect(WidgetStyle.resolvedTheme(widget: .darkChrome, global: .lightVintage, appTheme: .light) == .dark)
        #expect(WidgetStyle.resolvedTheme(widget: .lightVintage, global: .darkChrome, appTheme: .dark) == .light)
        #expect(WidgetStyle.resolvedTheme(widget: .matchApp, global: .lightVintage, appTheme: .dark) == .light)
        #expect(WidgetStyle.resolvedTheme(widget: .matchApp, global: .matchApp, appTheme: .light) == .light)
        #expect(WidgetStyle.resolvedTheme(widget: .matchApp, global: .matchApp, appTheme: .dark) == .dark)
    }

    // MARK: Snapshot helpers

    @Test func tickingChangesOnlyThatTask() {
        let lecture = item("Lecture")
        let gym = item("Gym")
        let base = snapshot(day: today, tasks: [lecture, gym])
        let ticked = base.settingTask(lecture.id, done: true, now: now)
        #expect(ticked.tasks.map(\.isDone) == [true, false])
        #expect(ticked.progress == DayProgress(done: 1, total: 2))
        #expect(!ticked.hasSameContent(as: base))
        #expect(ticked.settingTask(lecture.id, done: false, now: now).hasSameContent(as: base))
    }

    @Test func upNextIsTimedAheadThenAnytime() {
        let base = snapshot(day: today, tasks: [
            item("Gym", start: 7 * 60, duration: 60),
            item("Shopping", index: 1),
            item("Lecture", start: 9 * 60 + 30, duration: 60),
            item("Seminar", start: 14 * 60, duration: 60),
            item("Done one", start: 15 * 60, duration: 30, done: true)
        ])
        #expect(base.upNext(atMinute: 10 * 60, limit: 5).map(\.title) == ["Lecture", "Seminar", "Shopping"])
        #expect(base.upNext(atMinute: 10 * 60, limit: 2).map(\.title) == ["Lecture", "Seminar"])
        #expect(base.upNext(atMinute: 23 * 60, limit: 2).map(\.title) == ["Shopping"])
    }

    // MARK: Tick queue

    @Test func tickQueueKeepsTheLatestPerTaskAndRemovesOnlyApplied() {
        let lecture = UUID()
        let gym = UUID()
        var queue = WidgetTickQueue()
        queue.append(WidgetTick(taskID: lecture, isDone: true, at: Fixture.moment(20301225, 9)))
        queue.append(WidgetTick(taskID: gym, isDone: true, at: Fixture.moment(20301225, 9, 1)))
        queue.append(WidgetTick(taskID: lecture, isDone: false, at: Fixture.moment(20301225, 9, 2)))

        let latest = queue.latestPerTask
        #expect(latest.map(\.taskID) == [gym, lecture])
        #expect(latest.map(\.isDone) == [true, false])

        let applied = Set(queue.ticks.prefix(2).map(\.id))
        #expect(queue.removing(applied).ticks.map(\.taskID) == [lecture])
        #expect(WidgetTickQueue.decode(queue.encoded()) == queue)
        #expect(WidgetTickQueue.decode(Data("{".utf8)) == WidgetTickQueue())
    }
}

@Suite("Widget timeline")
struct WidgetTimelineTests {
    let calendar = Fixture.london

    func snapshot(_ key: Int, tasks: [(Int, Int)]) -> DaySnapshot {
        DaySnapshot(
            generatedAt: .now,
            day: Fixture.day(key),
            tasks: tasks.enumerated().map { index, pair in
                TaskSnapshot(
                    id: UUID(), title: "Task \(index)", category: .other, startMinute: pair.0, durationMinutes: pair.1,
                    isUrgent: false, isDone: false, sortIndex: index, createdAt: Date(timeIntervalSince1970: 0)
                )
            },
            noticeTitles: [], widgetStyle: .matchApp, theme: .dark
        )
    }

    @Test func quarterHoursAndTaskBoundariesWithinTheHorizon() {
        let now = Fixture.moment(20300304, 10, 7)
        let dates = WidgetTimeline.entryDates(
            now: now,
            snapshot: snapshot(20300304, tasks: [(10 * 60 + 40, 50), (20 * 60, 60)]),
            calendar: calendar
        )
        #expect(dates.first == now)
        #expect(dates.contains(Fixture.moment(20300304, 10, 15)))
        #expect(dates.contains(Fixture.moment(20300304, 16)))
        #expect(!dates.contains(Fixture.moment(20300304, 16, 15)))
        #expect(dates.contains(Fixture.moment(20300304, 10, 40))) // start
        #expect(dates.contains(Fixture.moment(20300304, 11, 30))) // end
        #expect(!dates.contains(Fixture.moment(20300304, 20))) // beyond 6 hours
        #expect(dates == dates.sorted())
        #expect(Set(dates).count == dates.count)
    }

    @Test func includesMidnightWhenItIsClose() {
        let now = Fixture.moment(20300304, 22, 50)
        let dates = WidgetTimeline.entryDates(now: now, snapshot: nil, calendar: calendar)
        #expect(dates.contains(Fixture.moment(20300305, 0)))
        #expect(dates.last.map { $0 <= now.addingTimeInterval(6 * 3600) } == true)
    }
}
