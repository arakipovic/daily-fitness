import Foundation

// MARK: - Analytics data model

struct ExerciseStat: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let bestWeight: Double
    let bestReps: Int
    let estimated1RM: Double
    let totalVolume: Double
    let totalSets: Int
}

struct WeeklyTrainingLoad: Identifiable, Hashable, Sendable {
    var id: Date { weekStart }
    let weekStart: Date
    let workouts: Int
    let sets: Int
    let volumeKg: Double

    var volumeTonnes: Double { volumeKg / 1000 }
}

struct DailyTrainingLoad: Identifiable, Hashable, Sendable {
    var id: Date { date }
    let date: Date
    let workouts: Int
    let sets: Int
    let volumeKg: Double
}

struct ExerciseProgressPoint: Identifiable, Hashable, Sendable {
    let id: String
    let exerciseName: String
    let date: Date
    let bestWeight: Double
    let bestReps: Int
    let estimated1RM: Double
    let volumeKg: Double
    let sets: Int
}

struct VolumeShare: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let volumeKg: Double
    let sets: Int
    let percent: Double
}

struct DailyNutrition: Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
}

struct NutritionSummary: Sendable {
    let avgCalories: Double
    let avgProtein: Double
    let avgCarbs: Double
    let avgFat: Double
    let avgFiber: Double
    let loggedDays: Int
}

// MARK: - Functional core for workout analytics
// Pure static functions — no Store access, no side effects, fully testable.

enum AnalyticsLogic {

    // MARK: - 1RM estimate (Epley formula)

    nonisolated static func estimated1RM(weight: Double, reps: Int) -> Double {
        weight * (1.0 + Double(reps) / 30.0)
    }

    // MARK: - Per-exercise aggregation

    /// Aggregates all completed sets across `sessions` into per-exercise stats,
    /// sorted by total volume descending.
    /// When a set has weight "0" or "", `bodyweightKg` is used as the load
    /// so bodyweight exercises (pull-ups, dips, etc.) count toward volume and 1RM.
    nonisolated static func exerciseStats(
        from sessions: some Collection<SessionLog>,
        bodyweightKg: Double = 75
    ) -> [ExerciseStat] {
        var byName: [String: (bw: Double, br: Int, vol: Double, sets: Int)] = [:]

        for session in sessions {
            guard session.completed != nil else { continue }
            for (_, log) in session.slotLogs {
                for set in log.sets where set.done {
                    guard let r = Int(set.reps), r > 0 else { continue }
                    let rawWeight = Double(set.weight) ?? 0
                    let w = rawWeight == 0 ? bodyweightKg : rawWeight
                    var e = byName[log.exerciseName] ?? (0, 0, 0, 0)
                    if w > e.bw || (w == e.bw && r > e.br) { e.bw = w; e.br = r }
                    e.vol += w * Double(r)
                    e.sets += 1
                    byName[log.exerciseName] = e
                }
            }
        }

        return byName.map { name, e in
            ExerciseStat(
                name: name,
                bestWeight: e.bw,
                bestReps: e.br,
                estimated1RM: estimated1RM(weight: e.bw, reps: e.br),
                totalVolume: e.vol,
                totalSets: e.sets
            )
        }.sorted { $0.totalVolume > $1.totalVolume }
    }

    // MARK: - Chart datasets

    nonisolated static func weeklyTrainingLoad(
        from sessions: some Collection<SessionLog>,
        bodyweightKg: Double = 75,
        weeks: Int = 12,
        endingAt endDate: Date? = nil,
        calendar: Calendar = .current
    ) -> [WeeklyTrainingLoad] {
        guard weeks > 0 else { return [] }
        let completedDates = sessions.compactMap(\.completed)
        guard let anchor = endDate ?? completedDates.max(),
              let endWeek = startOfWeek(containing: anchor, calendar: calendar),
              let startWeek = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: endWeek)
        else { return [] }

        var grouped: [Date: (workouts: Int, sets: Int, volumeKg: Double)] = [:]
        for session in sessions {
            guard let completed = session.completed,
                  let weekStart = startOfWeek(containing: completed, calendar: calendar),
                  weekStart >= startWeek,
                  weekStart <= endWeek
            else { continue }

            let metrics = sessionMetrics(session, bodyweightKg: bodyweightKg)
            var row = grouped[weekStart] ?? (0, 0, 0)
            row.workouts += 1
            row.sets += metrics.sets
            row.volumeKg += metrics.volumeKg
            grouped[weekStart] = row
        }

        return (0..<weeks).compactMap { offset in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: offset, to: startWeek) else {
                return nil
            }
            let row = grouped[weekStart] ?? (0, 0, 0)
            return WeeklyTrainingLoad(
                weekStart: weekStart,
                workouts: row.workouts,
                sets: row.sets,
                volumeKg: row.volumeKg
            )
        }
    }

    nonisolated static func dailyTrainingLoad(
        from sessions: some Collection<SessionLog>,
        bodyweightKg: Double = 75,
        days: Int = 28,
        endingAt endDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [DailyTrainingLoad] {
        guard days > 0,
              let startDate = calendar.date(
                byAdding: .day,
                value: -(days - 1),
                to: calendar.startOfDay(for: endDate)
              )
        else { return [] }

        let endDay = calendar.startOfDay(for: endDate)
        var grouped: [Date: (workouts: Int, sets: Int, volumeKg: Double)] = [:]

        for session in sessions {
            guard let completed = session.completed else { continue }
            let day = calendar.startOfDay(for: completed)
            guard day >= startDate, day <= endDay else { continue }

            let metrics = sessionMetrics(session, bodyweightKg: bodyweightKg)
            var row = grouped[day] ?? (0, 0, 0)
            row.workouts += 1
            row.sets += metrics.sets
            row.volumeKg += metrics.volumeKg
            grouped[day] = row
        }

        return (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                return nil
            }
            let row = grouped[date] ?? (0, 0, 0)
            return DailyTrainingLoad(
                date: date,
                workouts: row.workouts,
                sets: row.sets,
                volumeKg: row.volumeKg
            )
        }
    }

    nonisolated static func exerciseProgress(
        exerciseName: String,
        from sessions: some Collection<SessionLog>,
        bodyweightKg: Double = 75
    ) -> [ExerciseProgressPoint] {
        let trimmedName = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return [] }

        return sessions.compactMap { session -> ExerciseProgressPoint? in
            guard let completed = session.completed else { return nil }

            var sets = 0
            var volumeKg = 0.0
            var bestWeight = 0.0
            var bestReps = 0
            var bestEstimated1RM = 0.0

            for log in session.slotLogs.values where log.exerciseName.caseInsensitiveCompare(trimmedName) == .orderedSame {
                for set in log.sets where set.done {
                    guard let reps = Int(set.reps), reps > 0 else { continue }
                    let weight = normalizedWeight(set.weight, bodyweightKg: bodyweightKg)
                    let estimated = estimated1RM(weight: weight, reps: reps)
                    sets += 1
                    volumeKg += weight * Double(reps)
                    if estimated > bestEstimated1RM {
                        bestEstimated1RM = estimated
                        bestWeight = weight
                        bestReps = reps
                    }
                }
            }

            guard sets > 0 else { return nil }
            let sessionKey = LogbookLogic.sessionKey(
                programID: session.programID,
                week: session.week,
                day: session.day
            )
            return ExerciseProgressPoint(
                id: "\(trimmedName)|\(sessionKey)|\(Int(completed.timeIntervalSince1970))",
                exerciseName: trimmedName,
                date: completed,
                bestWeight: bestWeight,
                bestReps: bestReps,
                estimated1RM: bestEstimated1RM,
                volumeKg: volumeKg,
                sets: sets
            )
        }
        .sorted { $0.date < $1.date }
    }

    nonisolated static func exerciseProgressCandidates(
        from sessions: some Collection<SessionLog>,
        bodyweightKg: Double = 75,
        limit: Int = 3
    ) -> [ExerciseStat] {
        guard limit > 0 else { return [] }
        let completedSessions = sessions.filter { $0.completed != nil }
        return Array(
            exerciseStats(from: completedSessions, bodyweightKg: bodyweightKg)
                .filter { stat in
                    !exerciseProgress(
                        exerciseName: stat.name,
                        from: completedSessions,
                        bodyweightKg: bodyweightKg
                    ).isEmpty
                }
                .prefix(limit)
        )
    }

    nonisolated static func volumeDistribution(
        from sessions: some Collection<SessionLog>,
        bodyweightKg: Double = 75,
        limit: Int = 8
    ) -> [VolumeShare] {
        guard limit > 0 else { return [] }
        let stats = exerciseStats(from: sessions, bodyweightKg: bodyweightKg)
        let totalVolume = stats.reduce(0) { $0 + $1.totalVolume }
        guard totalVolume > 0 else { return [] }

        var shares = stats.prefix(limit).map { stat in
            VolumeShare(
                name: stat.name,
                volumeKg: stat.totalVolume,
                sets: stat.totalSets,
                percent: stat.totalVolume / totalVolume
            )
        }

        let remaining = stats.dropFirst(limit)
        let otherVolume = remaining.reduce(0) { $0 + $1.totalVolume }
        if otherVolume > 0 {
            shares.append(VolumeShare(
                name: "Other",
                volumeKg: otherVolume,
                sets: remaining.reduce(0) { $0 + $1.totalSets },
                percent: otherVolume / totalVolume
            ))
        }

        return shares
    }

    // MARK: - Summary stats

    struct WorkoutSummary {
        let totalWorkouts: Int
        let totalSets: Int
        let totalVolumeKg: Double

        var formattedVolume: String {
            totalVolumeKg >= 1000
                ? String(format: "%.1ft", totalVolumeKg / 1000)
                : "\(Int(totalVolumeKg))kg"
        }
    }

    nonisolated static func summary(from sessions: some Collection<SessionLog>, bodyweightKg: Double = 75) -> WorkoutSummary {
        let stats = exerciseStats(from: sessions, bodyweightKg: bodyweightKg)
        let completedSessions = sessions.filter { $0.completed != nil }
        let totalSets = completedSessions.reduce(0) {
            $0 + $1.slotLogs.values.reduce(0) { $0 + $1.sets.filter(\.done).count }
        }
        return WorkoutSummary(
            totalWorkouts: completedSessions.count,
            totalSets: totalSets,
            totalVolumeKg: stats.reduce(0) { $0 + $1.totalVolume }
        )
    }

    private nonisolated static func sessionMetrics(
        _ session: SessionLog,
        bodyweightKg: Double
    ) -> (sets: Int, volumeKg: Double) {
        var sets = 0
        var volumeKg = 0.0

        for log in session.slotLogs.values {
            for set in log.sets where set.done {
                guard let reps = Int(set.reps), reps > 0 else { continue }
                let weight = normalizedWeight(set.weight, bodyweightKg: bodyweightKg)
                sets += 1
                volumeKg += weight * Double(reps)
            }
        }

        return (sets, volumeKg)
    }

    private nonisolated static func normalizedWeight(_ value: String, bodyweightKg: Double) -> Double {
        let rawWeight = Double(value) ?? 0
        return rawWeight == 0 ? bodyweightKg : rawWeight
    }

    private nonisolated static func startOfWeek(containing date: Date, calendar: Calendar) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }

    // MARK: - Nutrition analytics

    nonisolated static func dailyNutrition(
        from foodLog: [FoodEntry],
        days: Int = 28,
        endingAt endDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [DailyNutrition] {
        guard days > 0 else { return [] }
        let endDay = calendar.startOfDay(for: endDate)
        guard let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) else { return [] }

        var grouped: [Date: (calories: Int, protein: Double, carbs: Double, fat: Double, fiber: Double)] = [:]
        for entry in foodLog {
            let day = calendar.startOfDay(for: entry.date)
            guard day >= startDay, day <= endDay else { continue }
            var row = grouped[day] ?? (0, 0.0, 0.0, 0.0, 0.0)
            row.calories += entry.calories
            row.protein  += entry.protein
            row.carbs    += entry.carbs
            row.fat      += entry.fat
            row.fiber    += entry.fiber
            grouped[day] = row
        }

        return (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDay) else { return nil }
            let row = grouped[date] ?? (0, 0.0, 0.0, 0.0, 0.0)
            return DailyNutrition(date: date, calories: row.calories,
                                  protein: row.protein, carbs: row.carbs,
                                  fat: row.fat, fiber: row.fiber)
        }
    }

    nonisolated static func nutritionSummary(
        from foodLog: [FoodEntry],
        days: Int = 28,
        endingAt endDate: Date = Date(),
        calendar: Calendar = .current
    ) -> NutritionSummary {
        let daily = dailyNutrition(from: foodLog, days: days, endingAt: endDate, calendar: calendar)
        let logged = daily.filter { $0.calories > 0 || $0.protein > 0 }
        guard !logged.isEmpty else {
            return NutritionSummary(avgCalories: 0, avgProtein: 0, avgCarbs: 0, avgFat: 0, avgFiber: 0, loggedDays: 0)
        }
        let n = Double(logged.count)
        return NutritionSummary(
            avgCalories: Double(logged.reduce(0) { $0 + $1.calories }) / n,
            avgProtein:  logged.reduce(0) { $0 + $1.protein }  / n,
            avgCarbs:    logged.reduce(0) { $0 + $1.carbs }    / n,
            avgFat:      logged.reduce(0) { $0 + $1.fat }      / n,
            avgFiber:    logged.reduce(0) { $0 + $1.fiber }    / n,
            loggedDays:  logged.count
        )
    }
}
