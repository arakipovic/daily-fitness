import Foundation

// MARK: - Pure calendar helpers — no Store access, fully testable.

enum CalendarLogic {

    /// Sessions from a flat array that were completed on the given date.
    static func completedSessions(
        in sessions: [SessionLog],
        on date: Date,
        calendar: Calendar = .current
    ) -> [SessionLog] {
        sessions.filter { session in
            guard let completed = session.completed else { return false }
            return calendar.isDate(completed, inSameDayAs: date)
        }
    }

    static func hasCompletedSession(
        in sessions: [SessionLog],
        on date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        !completedSessions(in: sessions, on: date, calendar: calendar).isEmpty
    }

    /// All dates in the calendar month containing the given date.
    static func datesInMonth(
        containing date: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard
            let firstDay = calendar.date(from: components),
            let range = calendar.range(of: .day, in: .month, for: firstDay)
        else { return [] }
        return range.compactMap { day in
            var c = components
            c.day = day
            return calendar.date(from: c)
        }
    }

    /// Number of empty leading cells before day 1 when the calendar grid starts on `calendar.firstWeekday`.
    static func weekdayOffset(
        for date: Date,
        calendar: Calendar = .current
    ) -> Int {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let firstDay = calendar.date(from: components) else { return 0 }
        let weekday = calendar.component(.weekday, from: firstDay)
        return (weekday - calendar.firstWeekday + 7) % 7
    }
}
