import Foundation
import Testing
@testable import DailyFlowCore

@Suite("Notice days")
struct NoticeTests {
    @Test(arguments: [
        (2000, 20000423), (2019, 20190421), (2024, 20240331), (2025, 20250420), (2026, 20260405),
        (2027, 20270328), (2030, 20300421), (2038, 20380425), (2285, 22850322)
    ])
    func easterSunday(year: Int, expected: Int) {
        #expect(NoticeMath.easterSunday(year: year) == Fixture.day(expected))
    }

    @Test(arguments: [(2024, 20240310), (2025, 20250330), (2026, 20260315), (2027, 20270307)])
    func mothersDayIsThreeWeeksBeforeEaster(year: Int, expected: Int) {
        #expect(BuiltInNotice.mothersDayUK.day(in: year) == Fixture.day(expected))
    }

    @Test(arguments: [(2024, 20240616), (2025, 20250615), (2026, 20260621), (2027, 20270620)])
    func fathersDayIsThirdSundayOfJune(year: Int, expected: Int) {
        #expect(BuiltInNotice.fathersDayUK.day(in: year) == Fixture.day(expected))
    }

    @Test func computedNoticesHoldTheirRulesForCenturies() {
        for year in 1900...2200 {
            let easter = BuiltInNotice.easterSunday.day(in: year)
            #expect(easter.weekday == 1)
            #expect(easter >= CalendarDay(year: year, month: 3, day: 22)!)
            #expect(easter <= CalendarDay(year: year, month: 4, day: 25)!)

            let mothers = BuiltInNotice.mothersDayUK.day(in: year)
            #expect(mothers.weekday == 1)
            #expect(easter.days(since: mothers) == 21)

            let fathers = BuiltInNotice.fathersDayUK.day(in: year)
            #expect(fathers.weekday == 1)
            #expect(fathers.month == 6 && (15...21).contains(fathers.day))
        }
    }

    @Test func fixedNotices() {
        #expect(BuiltInNotice.christmasDay.day(in: 2030) == Fixture.day(20301225))
        #expect(BuiltInNotice.newYearsEve.day(in: 2030) == Fixture.day(20301231))
        #expect(BuiltInNotice.newYearsDay.day(in: 2030) == Fixture.day(20300101))
        #expect(BuiltInNotice.halloween.day(in: 2030) == Fixture.day(20301031))
    }

    @Test func findsTheNoticeOnItsDayOnly() {
        let rules = NoticeCalendar.builtInRules
        #expect(NoticeCalendar.notices(on: Fixture.day(20301225), rules: rules).map(\.title) == ["Christmas Day"])
        #expect(NoticeCalendar.notices(on: Fixture.day(20301226), rules: rules).isEmpty)
    }

    @Test func switchedOffRulesAreNotFound() {
        let rules = NoticeCalendar.builtInRules.filter { $0.schedule != .builtIn(.christmasDay) }
        #expect(NoticeCalendar.notices(on: Fixture.day(20301225), rules: rules).isEmpty)
    }

    @Test func everyYearOnLeapDayFallsBackToTheTwentyEighth() {
        let rule = NoticeRule(id: "custom.test", title: "Leap day notice", schedule: .everyYear(month: 2, day: 29))
        #expect(rule.schedule.occurrence(in: 2027) == Fixture.day(20270228))
        #expect(rule.schedule.occurrence(in: 2028) == Fixture.day(20280229))
        #expect(NoticeCalendar.notices(on: Fixture.day(20270228), rules: [rule]).count == 1)
    }

    @Test func oneOffNoticeOnlyInItsYear() {
        let rule = NoticeRule(id: "custom.once", title: "Open day", schedule: .once(Fixture.day(20300614)))
        #expect(rule.schedule.occurrence(in: 2030) == Fixture.day(20300614))
        #expect(rule.schedule.occurrence(in: 2031) == nil)
    }

    @Test func upcomingCrossesTheYearInOrder() {
        let custom = NoticeRule(id: "custom.party", title: "Board games", schedule: .everyYear(month: 12, day: 25))
        let found = NoticeCalendar.upcoming(
            from: Fixture.day(20301220),
            days: 14,
            rules: NoticeCalendar.builtInRules + [custom]
        )
        #expect(found.map(\.title) == ["Board games", "Christmas Day", "New Year's Eve", "New Year's Day"])
        #expect(found.last?.day == Fixture.day(20310101))
        #expect(NoticeCalendar.upcoming(from: Fixture.day(20301220), days: -1, rules: NoticeCalendar.builtInRules).isEmpty)
    }
}
