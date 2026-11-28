import Foundation

/// When a widget timeline needs a new entry. Widgets cannot animate, so the clock hand, now line and
/// "Up next" advance by stepping through entries: every quarter hour, at each timed task's start and
/// end, and at midnight (when the day, and possibly the data source, changes).
public enum WidgetTimeline {
    public static let horizonHours = 6
    public static let stepMinutes = 15

    public static func entryDates(now: Date, snapshot: DaySnapshot?, calendar: Calendar) -> [Date] {
        let end = now.addingTimeInterval(Double(horizonHours) * 3600)
        var dates: Set<Date> = [now]

        // Quarter-hour marks, on whole minutes.
        let minuteStart = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        let toNext = stepMinutes - calendar.component(.minute, from: now) % stepMinutes
        var step = minuteStart.addingTimeInterval(Double(toNext) * 60)
        while step <= end {
            dates.insert(step)
            step = step.addingTimeInterval(Double(stepMinutes) * 60)
        }

        // Task boundaries on the snapshot's day.
        if let snapshot {
            for task in snapshot.tasks {
                guard let start = task.startMinute, let finish = task.endMinute else { continue }
                for boundary in [start, min(finish, DaySchedule.minutesPerDay - 1)] {
                    let date = snapshot.day.date(atMinute: boundary, in: calendar)
                    if date > now && date <= end {
                        dates.insert(date)
                    }
                }
            }
        }

        // Midnight.
        let tomorrow = CalendarDay.today(now: now, calendar: calendar).adding(days: 1).startDate(in: calendar)
        if tomorrow > now && tomorrow <= end {
            dates.insert(tomorrow)
        }

        return dates.sorted()
    }
}
