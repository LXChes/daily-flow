import Foundation
import Testing
@testable import DailyFlowCore

@Suite("CalendarDay")
struct CalendarDayTests {
    @Test func rejectsDatesThatDoNotExist() {
        #expect(CalendarDay(year: 2027, month: 2, day: 29) == nil)
        #expect(CalendarDay(year: 2028, month: 2, day: 29) != nil)
        #expect(CalendarDay(year: 2100, month: 2, day: 29) == nil)
        #expect(CalendarDay(year: 2000, month: 2, day: 29) != nil)
        #expect(CalendarDay(year: 2030, month: 4, day: 31) == nil)
        #expect(CalendarDay(year: 2030, month: 13, day: 1) == nil)
        #expect(CalendarDay(year: 2030, month: 1, day: 0) == nil)
    }

    @Test func keyRoundTrips() {
        let day = Fixture.day(20300304)
        #expect(day.year == 2030 && day.month == 3 && day.day == 4)
        #expect(day.key == 20300304)
        #expect(CalendarDay(key: 20301345) == nil)
        #expect(day.description == "2030-03-04")
    }

    @Test func dayNumbersMatchKnownValues() {
        #expect(Fixture.day(19700101).dayNumber == 0)
        #expect(Fixture.day(19691231).dayNumber == -1)
        #expect(Fixture.day(20000301).dayNumber == 11_017)
    }

    @Test func dayNumberRoundTripsAcrossCenturies() {
        for number in stride(from: -100_000, through: 150_000, by: 97) {
            #expect(CalendarDay(dayNumber: number).dayNumber == number)
        }
    }

    @Test func weekdayAgreesWithFoundation() throws {
        let utc = Fixture.calendar("UTC")
        for offset in stride(from: -2_000, through: 30_000, by: 13) {
            let day = CalendarDay(dayNumber: offset)
            let date = try #require(utc.date(from: DateComponents(year: day.year, month: day.month, day: day.day)))
            #expect(day.weekday == utc.component(.weekday, from: date))
        }
    }

    @Test func addingDaysCrossesMonthsYearsAndLeapDays() {
        #expect(Fixture.day(20280228).adding(days: 1) == Fixture.day(20280229))
        #expect(Fixture.day(20270228).adding(days: 1) == Fixture.day(20270301))
        #expect(Fixture.day(20301231).adding(days: 1) == Fixture.day(20310101))
        #expect(Fixture.day(20300101).adding(days: -1) == Fixture.day(20291231))
        #expect(Fixture.day(20300310).days(since: Fixture.day(20300301)) == 9)
    }

    @Test func readsTheDayInTheInjectedTimeZone() {
        // 23:30 UTC on 10 June 2030 is already 11 June in London (BST) and in Tokyo.
        let instant = Date(timeIntervalSince1970: TimeInterval(Fixture.day(20300610).dayNumber * 86_400 + 23 * 3_600 + 1_800))
        #expect(CalendarDay(instant, calendar: Fixture.calendar("UTC")) == Fixture.day(20300610))
        #expect(CalendarDay(instant, calendar: Fixture.london) == Fixture.day(20300611))
        #expect(CalendarDay(instant, calendar: Fixture.tokyo) == Fixture.day(20300611))
    }

    @Test func nonGregorianCalendarsStillUseGregorianDays() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = Fixture.london.timeZone
        let instant = Fixture.moment(20300304, 12)
        #expect(CalendarDay(instant, calendar: buddhist) == Fixture.day(20300304))
    }

    @Test func minuteOfDayRoundTrips() {
        let day = Fixture.day(20300304)
        let date = day.date(atMinute: 14 * 60 + 25, in: Fixture.london)
        #expect(MinuteOfDay.of(date, calendar: Fixture.london) == 14 * 60 + 25)
        #expect(CalendarDay(date, calendar: Fixture.london) == day)
        #expect(MinuteOfDay.clamp(-5) == 0)
        #expect(MinuteOfDay.clamp(5_000) == 1_439)
    }

    @Test func daylightSavingGapStaysOnTheSameDay() {
        // UK clocks jump from 01:00 to 02:00 on 31 March 2030, so 01:30 does not exist.
        let day = Fixture.day(20300331)
        let date = day.date(atMinute: 90, in: Fixture.london)
        #expect(CalendarDay(date, calendar: Fixture.london) == day)
        #expect(day.startDate(in: Fixture.london) < date)
    }
}
