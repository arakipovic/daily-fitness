import Foundation

// MARK: - Functional core for HealthKit date-window calculations
// Pure static functions — no HealthKit imports, no side effects, fully testable.

struct HealthActivityItem: Identifiable, Hashable, Sendable {
    enum Source: String, Hashable, Sendable {
        case inApp
        case appleHealth
    }

    let id: String
    let source: Source
    let sessionKey: String?
    let title: String
    let date: Date
    let systemImage: String
    let detail: String?
    let metric: String?
}

enum HealthLogic {

    nonisolated static func appActivityItem(from session: SessionLog) -> HealthActivityItem? {
        guard let completed = session.completed else { return nil }

        let key = LogbookLogic.sessionKey(
            programID: session.programID,
            week: session.week,
            day: session.day
        )
        let setsCompleted = session.slotLogs.values.reduce(0) { total, log in
            total + log.sets.filter(\.done).count
        }

        return HealthActivityItem(
            id: "app|\(key)",
            source: .inApp,
            sessionKey: key,
            title: WorkoutLogic.sessionDisplayTitle(session),
            date: completed,
            systemImage: "dumbbell.fill",
            detail: activityDurationString(started: session.started, completed: completed),
            metric: "\(setsCompleted) sets"
        )
    }

    nonisolated static func recentActivityItems(
        appSessions: [SessionLog],
        appleHealthItems: [HealthActivityItem],
        limit: Int = 3
    ) -> [HealthActivityItem] {
        guard limit > 0 else { return [] }
        let appItems = appSessions.compactMap(appActivityItem(from:))
        return Array((appItems + appleHealthItems)
            .sorted {
                if $0.date != $1.date { return $0.date > $1.date }
                return $0.id < $1.id
            }
            .prefix(limit))
    }

    nonisolated static func activityDurationString(started: Date?, completed: Date) -> String? {
        guard let started, completed > started else { return nil }
        let minutes = Int(completed.timeIntervalSince(started) / 60)
        guard minutes > 0 else { return nil }
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// Returns the (start, end) query window for "last night's" sleep.
    ///
    /// Uses a noon-to-noon anchor so early bedtimes (e.g. 10 PM) are never
    /// cut off by a fixed-hour lookback from "now". Matches the window that
    /// Apple Health itself uses for nightly sleep attribution.
    ///
    /// - windowStart: yesterday at noon
    /// - windowEnd:   today at noon, capped at `now` when called before noon
    nonisolated static func lastNightSleepWindow(
        now: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date)? {
        guard
            let todayNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now),
            let yesterdayNoon = calendar.date(byAdding: .day, value: -1, to: todayNoon)
        else { return nil }
        return (yesterdayNoon, min(todayNoon, now))
    }

    /// Returns the (start, end) query window for a single night in a weekly summary.
    ///
    /// The window covers the 24 hours ending at noon on `referenceDate`,
    /// capped at `now` so future windows are never queried.
    nonisolated static func nightlySleepWindow(
        referenceDate: Date,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> (start: Date, end: Date)? {
        guard
            let noonCurr = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: referenceDate),
            let noonPrev = calendar.date(byAdding: .day, value: -1, to: noonCurr)
        else { return nil }
        return (noonPrev, min(noonCurr, now))
    }
}
