import Foundation

// MARK: - Functional core for logbook/session queries
// Pure static functions — no Store access, no side effects, fully testable.

enum LogbookLogic {

    // MARK: - Session key

    nonisolated static func sessionKey(programID: String, week: Int, day: Int) -> String {
        "\(programID)|\(week)|\(day)"
    }

    // MARK: - Session queries

    /// Returns the first (week, day) pair in `program` that has no completed session, or nil if all are done.
    nonisolated static func nextSession(
        sessions: [String: SessionLog],
        program: TrainingProgram
    ) -> (week: Int, day: Int)? {
        for week in 1...max(1, program.weeks) {
            for day in program.days {
                let key = sessionKey(programID: program.id, week: week, day: day.number)
                if sessions[key]?.completed == nil {
                    return (week, day.number)
                }
            }
        }
        return nil
    }

    /// Searches backwards through prior weeks for the most-recent completed session at the same day/slot.
    nonisolated static func previousPerformance(
        sessions: [String: SessionLog],
        programID: String,
        currentWeek: Int,
        dayNumber: Int,
        slotLabel: String
    ) -> ExerciseLog? {
        for week in stride(from: currentWeek - 1, through: 1, by: -1) {
            let key = sessionKey(programID: programID, week: week, day: dayNumber)
            if let session = sessions[key], session.completed != nil {
                return session.slotLogs[slotLabel]
            }
        }
        return nil
    }

    /// Returns how many calendar days have elapsed since the most-recently completed session.
    /// Injectable `referenceDate` makes it fully testable without relying on `Date()`.
    nonisolated static func daysSinceLastSession(
        sessions: [String: SessionLog],
        referenceDate: Date
    ) -> Int? {
        let dates = sessions.values.compactMap(\.completed)
        guard let mostRecent = dates.max() else { return nil }
        return Calendar.current.dateComponents([.day], from: mostRecent, to: referenceDate).day
    }

    // MARK: - Exercise index

    /// Builds a name → most-recent-completed-log dictionary from all sessions.
    /// Expensive: run off the main thread.
    nonisolated static func buildExerciseIndex(sessions: [String: SessionLog]) -> [String: ExerciseLog] {
        var index: [String: ExerciseLog] = [:]
        let sorted = sessions.values
            .filter { $0.completed != nil }
            .sorted { ($0.completed ?? .distantPast) > ($1.completed ?? .distantPast) }
        for session in sorted {
            for (_, log) in session.slotLogs {
                let key = log.exerciseName.lowercased()
                if index.index(forKey: key) == nil { index[key] = log }
            }
        }
        return index
    }

    // MARK: - CSV export

    nonisolated static func exportCSV(sessions: [String: SessionLog]) -> String {
        var lines = ["Program,Week,Day,Exercise,Set,Weight,Reps,RIR,Date"]
        let sorted = sessions.values.sorted {
            ($0.completed ?? $0.started ?? .distantPast) < ($1.completed ?? $1.started ?? .distantPast)
        }
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        for session in sorted {
            let dateStr = session.completed.map { fmt.string(from: $0) } ?? ""
            for (_, exLog) in session.slotLogs.sorted(by: { $0.key < $1.key }) {
                for (i, s) in exLog.sets.enumerated() {
                    lines.append(
                        "\(session.programID),\(session.week),\(session.day)" +
                        ",\(exLog.exerciseName),\(i + 1),\(s.weight),\(s.reps),\(s.rir),\(dateStr)"
                    )
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
