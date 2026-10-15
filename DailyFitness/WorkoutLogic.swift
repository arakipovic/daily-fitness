import Foundation

// MARK: - Functional core for workout session operations
// Pure static functions — no side effects, no Store access, fully testable.

enum WorkoutLogic {

    // MARK: - Slot label management

    /// Returns the smallest positive integer label not already in `existingLabels`.
    /// Guarantees uniqueness even after arbitrary deletions.
    nonisolated static func nextSlotLabel(existingLabels: Set<String>) -> String {
        var i = 1
        while existingLabels.contains("\(i)") { i += 1 }
        return "\(i)"
    }

    // MARK: - Session duplication

    /// Builds a fresh custom session from a template, remapping slot keys to a
    /// clean "1", "2", … sequence and resetting all sets to undone.
    /// - Parameters:
    ///   - template:  the source session to copy
    ///   - newWeek:   the `week` value for the new session (typically a unix timestamp)
    ///   - startDate: the `started` timestamp for the new session (injectable for tests)
    nonisolated static func duplicateSession(
        template: SessionLog,
        newWeek: Int,
        startDate: Date = Date()
    ) -> (session: SessionLog, exerciseOrder: [String]) {
        let sortedKeys = sortedSlotKeys(template.slotLogs.keys)
        var logs: [String: ExerciseLog] = [:]
        for (i, key) in sortedKeys.enumerated() {
            guard var log = template.slotLogs[key] else { continue }
            log.sets = resetSets(log.sets)
            logs["\(i + 1)"] = log
        }
        let newSession = SessionLog(
            programID: "custom", week: newWeek, day: 1,
            started: startDate, completed: nil,
            slotLogs: logs
        )
        let order = sortedKeys.indices.map { "\($0 + 1)" }
        return (newSession, order)
    }

    // MARK: - Set helpers

    /// Returns a copy of `sets` with every set marked `done = false` and a fresh UUID.
    nonisolated static func resetSets(_ sets: [SetEntry]) -> [SetEntry] {
        sets.map { original in
            SetEntry(id: UUID(), weight: original.weight, reps: original.reps,
                     rir: original.rir, done: false)
        }
    }

    // MARK: - HealthKit sync

    /// Returns true if the session has both a start and completion date and can be written to HealthKit.
    nonisolated static func shouldWriteToHealth(session: SessionLog) -> Bool {
        session.started != nil && session.completed != nil
    }

    /// Duration from session start to completion, or nil if incomplete.
    nonisolated static func workoutDuration(session: SessionLog) -> TimeInterval? {
        guard let start = session.started, let end = session.completed else { return nil }
        return end.timeIntervalSince(start)
    }

    /// Estimates kilocalories burned during a strength training session.
    /// Uses MET 5.0 (moderate strength training) × body weight × duration.
    /// Returns nil when duration is unknown or under 1 minute.
    nonisolated static func estimatedKcalBurned(
        session: SessionLog,
        weightKg: Double = 75
    ) -> Int? {
        guard let duration = workoutDuration(session: session),
              duration >= 60 else { return nil }
        return Int((5.0 * weightKg * (duration / 3600)).rounded())
    }

    // MARK: - Display title

    /// Human-readable title for a session used in history rows, cards, and nav bars.
    nonisolated static func sessionDisplayTitle(_ session: SessionLog) -> String {
        if session.programID == "custom" || session.programID == "imported" {
            let names = sortedSlotKeys(session.slotLogs.keys)
                .prefix(3)
                .compactMap { session.slotLogs[$0]?.exerciseName }
            return names.isEmpty ? "Custom Workout" : names.joined(separator: " · ")
        }
        return "Week \(session.week), Day \(session.day)"
    }

    // MARK: - Exercise catalog helpers

    nonisolated static func cleanedExerciseName(_ name: String) -> String {
        name
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    nonisolated static func normalizedExerciseName(_ name: String) -> String {
        cleanedExerciseName(name)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    nonisolated static func catalogExerciseNames(from catalog: Catalog) -> [String] {
        var names: [String] = []
        for program in catalog.programs {
            for day in program.days {
                for slot in day.exercises {
                    names.append(slot.name)
                    names.append(contentsOf: slot.alternatives)
                }
            }
        }
        names.append(contentsOf: catalog.videos.keys)
        return uniqueExerciseNames(names)
    }

    nonisolated static func availableExerciseNames(
        catalog: Catalog,
        customExerciseNames: [String],
        sessions: [String: SessionLog]
    ) -> [String] {
        var names = catalogExerciseNames(from: catalog)
        names.append(contentsOf: customExerciseNames)
        for session in sessions.values {
            names.append(contentsOf: session.slotLogs.values.map(\.exerciseName))
        }
        return uniqueExerciseNames(names)
    }

    nonisolated static func recentExerciseNames(sessions: [String: SessionLog]) -> [String] {
        let sessions = sessions.values
            .filter { $0.completed != nil }
            .sorted { ($0.completed ?? .distantPast) > ($1.completed ?? .distantPast) }

        var names: [String] = []
        for session in sessions {
            for key in sortedSlotKeys(session.slotLogs.keys) {
                if let name = session.slotLogs[key]?.exerciseName {
                    names.append(name)
                }
            }
        }
        return uniqueExerciseNames(names, sorted: false)
    }

    nonisolated static func customExerciseNames(
        from sessions: [String: SessionLog],
        excludingCatalogNames catalogNames: [String]
    ) -> [String] {
        let names = sessions.values.flatMap { session in
            session.slotLogs.values.map(\.exerciseName)
        }
        return uniqueExerciseNames(names.filter { !containsExerciseName(catalogNames, matching: $0) })
    }

    nonisolated static func mergedCustomExerciseNames(
        existing: [String],
        adding newNames: [String],
        excludingCatalogNames catalogNames: [String]
    ) -> [String] {
        let customNames = newNames.filter { !containsExerciseName(catalogNames, matching: $0) }
        return uniqueExerciseNames(existing + customNames)
    }

    /// Sorts `names` so exercises with a video and prior history appear first,
    /// then video-only, then history-only, then everything else. Alphabetical within each tier.
    nonisolated static func prioritizedExerciseNames(
        _ names: [String],
        videos: [String: URL],
        exerciseIndex: [String: ExerciseLog]
    ) -> [String] {
        func tier(_ name: String) -> Int {
            let hasVideo = videos[name] != nil
            let hasHistory = exerciseIndex[name.lowercased()] != nil
            switch (hasVideo, hasHistory) {
            case (true, true):   return 0
            case (true, false):  return 1
            case (false, true):  return 2
            case (false, false): return 3
            }
        }
        return names.sorted {
            let ta = tier($0), tb = tier($1)
            if ta != tb { return ta < tb }
            return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    /// Returns the exercise from `slot.name` or `slot.alternatives` that the user has
    /// done before (exists in `exerciseIndex`), keeping the original order as tiebreaker.
    /// Falls back to `slot.name` when none have history.
    nonisolated static func preferredExercise(
        for slot: Slot,
        exerciseIndex: [String: ExerciseLog]
    ) -> String {
        let candidates = [slot.name] + slot.alternatives
        return candidates.first { exerciseIndex[$0.lowercased()] != nil } ?? slot.name
    }

    nonisolated static func exerciseName(_ name: String, matches query: String) -> Bool {
        let cleanedQuery = cleanedExerciseName(query)
        guard !cleanedQuery.isEmpty else { return true }
        if name.localizedCaseInsensitiveContains(cleanedQuery) { return true }

        let normalizedName = normalizedExerciseName(name)
        return normalizedQueryVariants(cleanedQuery).contains { variant in
            !variant.isEmpty && normalizedName.contains(variant)
        }
    }

    nonisolated static func containsExerciseName(_ names: [String], matching name: String) -> Bool {
        let keys = Set(names.map(normalizedExerciseName))
        return normalizedQueryVariants(name).contains { keys.contains($0) }
    }

    // MARK: - Internal helpers

    /// Sorts slot-log keys numerically when they are integers, lexicographically otherwise.
    nonisolated static func sortedSlotKeys(_ keys: some Collection<String>) -> [String] {
        keys.sorted { a, b in
            if let ia = Int(a), let ib = Int(b) { return ia < ib }
            return a < b
        }
    }

    nonisolated static func uniqueExerciseNames(_ names: [String], sorted: Bool = true) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for rawName in names {
            let name = cleanedExerciseName(rawName)
            let key = normalizedExerciseName(name)
            guard !name.isEmpty, !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(name)
        }

        guard sorted else { return result }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private nonisolated static func normalizedQueryVariants(_ name: String) -> [String] {
        let key = normalizedExerciseName(name)
        guard !key.isEmpty else { return [] }
        if key.hasSuffix("s") {
            return [key, String(key.dropLast())]
        }
        return [key]
    }
}
