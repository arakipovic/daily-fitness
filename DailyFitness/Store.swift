import Foundation
import SwiftUI

@MainActor
@Observable
final class Store {

    // MARK: - Public state

    private(set) var catalog: Catalog
    var logbook: Logbook
    /// Stable UUID identifying this user's data partition. Used to scope custom foods and future per-user stores.
    let profileID: UUID

    // MARK: - Precomputed cache

    /// Maps lowercased exercise name → the most-recent completed ExerciseLog for that exercise.
    /// Rebuilt off the main thread after every session write.
    private(set) var exerciseIndex: [String: ExerciseLog] = [:]

    /// Maps session key → completed SessionLog. Rebuilt alongside exerciseIndex.
    /// Use this in views instead of iterating store.logbook.sessions on every render.
    private(set) var completedSessionIndex: [String: SessionLog] = [:]

    // MARK: - Internals

    private var saveTask: Task<Void, Never>?
    private let repository: any LogbookPersisting

    static let shared = Store(repository: LogbookRepository.shared)

    /// Creates an isolated Store instance for unit tests.
    /// Personal seed data is not merged so tests start with a clean state.
    static func makeForTesting(repository: any LogbookPersisting, catalog: Catalog? = nil) -> Store {
        Store(repository: repository, profileID: UUID(), catalog: catalog, skipPersonalSeed: true)
    }

    /// Creates a Store backed by a profile-specific repository.
    /// For the default profile, callers should use Store.shared directly.
    static func makeForProfile(profileID: UUID) -> Store {
        Store(repository: LogbookRepository.forProfile(profileID), profileID: profileID)
    }

    private init(repository: any LogbookPersisting, profileID: UUID? = nil, catalog: Catalog? = nil, skipPersonalSeed: Bool = false) {
        // Resolve a stable profile UUID: explicit > persisted default > new
        if let profileID {
            self.profileID = profileID
        } else {
            let key = "app.dailyfitness.defaultProfileID"
            if let s = UserDefaults.standard.string(forKey: key), let uuid = UUID(uuidString: s) {
                self.profileID = uuid
            } else {
                let new = UUID()
                UserDefaults.standard.set(new.uuidString, forKey: key)
                self.profileID = new
            }
        }
        self.repository = repository
        self.catalog = catalog ?? Bundle.main.decode(Catalog.self, from: "programs.json")

        if let loaded = repository.load() {
            var loaded = loaded
            // Older app builds used a bundled import file. Mark it complete so
            // fresh devices and different users never receive bundled history.
            if !loaded.importedLegacyV1 {
                loaded.importedLegacyV1 = true
                self.logbook = loaded
                repository.save(loaded)
            } else {
                self.logbook = loaded
            }
        } else {
            var empty = Logbook.empty
            empty.importedLegacyV1 = true
            self.logbook = empty
            repository.save(empty)
        }

        if mergeCustomExercisesFromHistory() {
            repository.save(logbook)
        }

        if !skipPersonalSeed && mergePersonalSeedV2() {
            repository.save(logbook)
        }

        // Build exercise index from the already-loaded sessions
        rebuildExerciseIndex()
    }

    // MARK: - Exercise index

    /// Rebuilds the exercise index on a background thread then assigns on the main actor.
    /// Call after any operation that writes session data.
    func rebuildExerciseIndex() {
        let sessions = logbook.sessions   // capture value-type snapshot before leaving actor
        Task.detached(priority: .utility) { [weak self, sessions] in
            let built = LogbookLogic.buildExerciseIndex(sessions: sessions)
            var completedIdx: [String: SessionLog] = [:]
            for session in sessions.values where session.completed != nil {
                let key = LogbookLogic.sessionKey(
                    programID: session.programID, week: session.week, day: session.day)
                completedIdx[key] = session
            }
            await MainActor.run { [weak self] in
                self?.exerciseIndex = built
                self?.completedSessionIndex = completedIdx
            }
        }
    }

    var availableExerciseNames: [String] {
        WorkoutLogic.availableExerciseNames(
            catalog: catalog,
            customExerciseNames: logbook.customExerciseNames,
            sessions: logbook.sessions
        )
    }

    var recentExerciseNames: [String] {
        WorkoutLogic.recentExerciseNames(sessions: logbook.sessions)
    }

    func addCustomExerciseName(_ name: String) {
        let merged = WorkoutLogic.mergedCustomExerciseNames(
            existing: logbook.customExerciseNames,
            adding: [name],
            excludingCatalogNames: WorkoutLogic.catalogExerciseNames(from: catalog)
        )
        guard merged != logbook.customExerciseNames else { return }
        logbook.customExerciseNames = merged
        saveImmediately()
    }

    // MARK: - Session key (delegates to LogbookLogic)

    func sessionKey(programID: String, week: Int, day: Int) -> String {
        LogbookLogic.sessionKey(programID: programID, week: week, day: day)
    }

    // MARK: - Session CRUD

    func getOrCreateSession(programID: String, week: Int, day: Int) -> SessionLog {
        let key = sessionKey(programID: programID, week: week, day: day)
        return logbook.sessions[key] ?? SessionLog(
            programID: programID, week: week, day: day,
            started: nil, completed: nil, slotLogs: [:]
        )
    }

    func updateSession(_ session: SessionLog) {
        let key = sessionKey(programID: session.programID, week: session.week, day: session.day)
        let wasCompleted = logbook.sessions[key]?.completed != nil
        mergeCustomExercises(from: session)
        logbook.sessions[key] = session
        saveLogbook()
        rebuildExerciseIndex()
        if !wasCompleted && session.completed != nil {
            Analytics.shared.track("workout_completed", ["week": String(session.week), "day": String(session.day)])
        }
        if !wasCompleted && WorkoutLogic.shouldWriteToHealth(session: session) {
            Task { await HealthKitManager.shared.writeWorkout(session: session) }
        }
    }

    /// Same as `updateSession` but bypasses the debounce — use for discrete
    /// user actions (completing a set, adding/removing an exercise) where losing
    /// the write on a force-quit would be unacceptable.
    func updateSessionImmediately(_ session: SessionLog) {
        let key = sessionKey(programID: session.programID, week: session.week, day: session.day)
        let wasCompleted = logbook.sessions[key]?.completed != nil
        mergeCustomExercises(from: session)
        logbook.sessions[key] = session
        saveImmediately()
        rebuildExerciseIndex()
        if !wasCompleted && session.completed != nil {
            Analytics.shared.track("workout_completed", ["week": String(session.week), "day": String(session.day)])
        }
        if !wasCompleted && WorkoutLogic.shouldWriteToHealth(session: session) {
            Task { await HealthKitManager.shared.writeWorkout(session: session) }
        }
    }

    func deleteSession(programID: String, week: Int, day: Int) {
        let key = sessionKey(programID: programID, week: week, day: day)
        logbook.sessions.removeValue(forKey: key)
        saveLogbook()
        rebuildExerciseIndex()
    }

    func nextSession(for program: TrainingProgram) -> (week: Int, day: Int)? {
        LogbookLogic.nextSession(sessions: logbook.sessions, program: program)
    }

    // MARK: - Performance lookup

    func previousPerformance(programID: String, currentWeek: Int, dayNumber: Int, slotLabel: String) -> ExerciseLog? {
        LogbookLogic.previousPerformance(
            sessions: logbook.sessions,
            programID: programID,
            currentWeek: currentWeek,
            dayNumber: dayNumber,
            slotLabel: slotLabel
        )
    }

    /// O(1) lookup using the precomputed exerciseIndex. Falls back to nil when index is still building.
    func lastKnownPerformance(exerciseName: String) -> ExerciseLog? {
        exerciseIndex[exerciseName.lowercased()]
    }

    /// Best available body weight: profile if set, otherwise 75 kg as a neutral fallback.
    /// Views that also have HealthKit access should prefer `healthKit.recentWeightKg ?? store.resolvedBodyWeightKg`.
    var resolvedBodyWeightKg: Double {
        logbook.profileWeightKg > 0 ? logbook.profileWeightKg : 75
    }

    // MARK: - Save

    func saveLogbook() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self.repository.save(self.logbook)
        }
    }

    func saveImmediately() {
        saveTask?.cancel()
        repository.save(logbook)
    }

    // MARK: - Food log

    func addFoodEntry(_ entry: FoodEntry) {
        logbook.foodLog.append(entry)
        Analytics.shared.track("food_logged", ["meal": entry.meal.rawValue])
        saveImmediately()
    }

    func updateFoodEntry(_ entry: FoodEntry) {
        guard let index = logbook.foodLog.firstIndex(where: { $0.id == entry.id }) else { return }
        logbook.foodLog[index] = entry
        saveImmediately()
    }

    func deleteFoodEntry(id: UUID) {
        logbook.foodLog.removeAll { $0.id == id }
        saveImmediately()
    }

    func deleteFoodEntries(at offsets: IndexSet, from entries: [FoodEntry]) {
        let ids = Set(offsets.map { entries[$0].id })
        logbook.foodLog.removeAll { ids.contains($0.id) }
        saveImmediately()
    }

    func copyFoodLog(from sourceDate: Date, to targetDate: Date) {
        let existingKeys = Set(
            NutritionLogic.entries(logbook.foodLog, on: targetDate).map { "\($0.meal.rawValue):\($0.name)" }
        )
        let newEntries = NutritionLogic.entries(logbook.foodLog, on: sourceDate)
            .filter { !existingKeys.contains("\($0.meal.rawValue):\($0.name)") }
        guard !newEntries.isEmpty else { return }
        logbook.foodLog.append(contentsOf: NutritionLogic.copyEntries(newEntries, to: targetDate))
        saveImmediately()
    }

    func copyFoodEntry(_ entry: FoodEntry, to date: Date) {
        var copied = entry
        copied.id = UUID()
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute, .second], from: entry.date)
        copied.date = cal.date(
            bySettingHour: t.hour ?? 12, minute: t.minute ?? 0, second: t.second ?? 0, of: date
        ) ?? date
        addFoodEntry(copied)
    }

    func copyMeal(_ meal: MealType, from sourceDate: Date, to targetDate: Date) {
        let existingNames = Set(
            NutritionLogic.entries(logbook.foodLog, on: targetDate)
                .filter { $0.meal == meal }.map(\.name)
        )
        let newEntries = NutritionLogic.entries(logbook.foodLog, on: sourceDate)
            .filter { $0.meal == meal && !existingNames.contains($0.name) }
        guard !newEntries.isEmpty else { return }
        logbook.foodLog.append(contentsOf: NutritionLogic.copyEntries(newEntries, to: targetDate))
        saveImmediately()
    }

    func updateTargets(calories: Int, protein: Double, fiber: Double) {
        logbook.calorieTarget = calories
        logbook.proteinTarget = protein
        logbook.fiberTarget = fiber
        saveImmediately()
    }

    // MARK: - Saved meals

    func saveMeal(_ meal: SavedMeal) {
        var meal = meal
        meal.updatedAt = Date()
        if let index = logbook.savedMeals.firstIndex(where: { $0.id == meal.id }) {
            logbook.savedMeals[index] = meal
        } else {
            logbook.savedMeals.append(meal)
        }
        saveImmediately()
    }

    func deleteSavedMeal(id: UUID) {
        logbook.savedMeals.removeAll { $0.id == id }
        saveImmediately()
    }

    func logMeal(
        _ meal: SavedMeal,
        date: Date,
        servings: Double,
        logIngredientsSeparately: Bool,
        mealType: MealType? = nil
    ) {
        let entries = NutritionLogic.foodEntries(
            for: meal,
            date: date,
            servings: servings,
            logIngredientsSeparately: logIngredientsSeparately,
            mealType: mealType
        )
        guard !entries.isEmpty else { return }
        logbook.foodLog.append(contentsOf: entries)
        Analytics.shared.track("meal_logged", ["name": meal.name, "servings": String(format: "%.1f", servings)])
        saveImmediately()
    }

    // MARK: - Body measurements

    func addBodyMeasurement(_ measurement: BodyMeasurement) {
        logbook.bodyMeasurements.removeAll {
            Calendar.current.isDate($0.date, inSameDayAs: measurement.date)
        }
        logbook.bodyMeasurements.append(measurement)
        logbook.bodyMeasurements.sort { $0.date < $1.date }
        Analytics.shared.track("measurement_added")
        saveImmediately()
    }

    func deleteBodyMeasurements(at offsets: IndexSet, from sorted: [BodyMeasurement]) {
        let ids = Set(offsets.map { sorted[$0].id })
        logbook.bodyMeasurements.removeAll { ids.contains($0.id) }
        saveImmediately()
    }

    var latestBodyMeasurement: BodyMeasurement? {
        logbook.bodyMeasurements.max { $0.date < $1.date }
    }

    // MARK: - Misc

    func daysSinceLastSession() -> Int? {
        LogbookLogic.daysSinceLastSession(sessions: logbook.sessions, referenceDate: Date())
    }

    func exportCSV() -> String {
        LogbookLogic.exportCSV(sessions: logbook.sessions)
    }

    func exportLogbookData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(logbook)
    }

    func decodeLogbookData(_ data: Data) throws -> Logbook {
        try JSONDecoder().decode(Logbook.self, from: data)
    }

    func importLogbookData(_ data: Data) throws {
        let imported = try decodeLogbookData(data)
        replaceLogbook(with: imported)
    }

    func replaceLogbook(with imported: Logbook) {
        var imported = imported
        imported.importedLegacyV1 = true
        logbook = imported
        mergeCustomExercisesFromHistory()
        saveImmediately()
        rebuildExerciseIndex()
    }

    func resetAllData() {
        logbook = .empty
        logbook.importedLegacyV1 = true
        exerciseIndex = [:]
        saveImmediately()
    }

    @discardableResult
    private func mergePersonalSeedV2() -> Bool {
        guard !logbook.importedPersonalSeedV2 else { return false }
        for session in personalSeedSessionsV2 {
            let key = LogbookLogic.sessionKey(programID: session.programID, week: session.week, day: session.day)
            if logbook.sessions[key] == nil {
                logbook.sessions[key] = session
            }
        }
        logbook.importedPersonalSeedV2 = true
        return true
    }

    @discardableResult
    private func mergeCustomExercises(from session: SessionLog) -> Bool {
        let merged = WorkoutLogic.mergedCustomExerciseNames(
            existing: logbook.customExerciseNames,
            adding: session.slotLogs.values.map(\.exerciseName),
            excludingCatalogNames: WorkoutLogic.catalogExerciseNames(from: catalog)
        )
        guard merged != logbook.customExerciseNames else { return false }
        logbook.customExerciseNames = merged
        return true
    }

    @discardableResult
    private func mergeCustomExercisesFromHistory() -> Bool {
        let catalogExerciseNames = WorkoutLogic.catalogExerciseNames(from: catalog)
        let historyNames = WorkoutLogic.customExerciseNames(
            from: logbook.sessions,
            excludingCatalogNames: catalogExerciseNames
        )
        let merged = WorkoutLogic.mergedCustomExerciseNames(
            existing: logbook.customExerciseNames,
            adding: historyNames,
            excludingCatalogNames: catalogExerciseNames
        )
        guard merged != logbook.customExerciseNames else { return false }
        logbook.customExerciseNames = merged
        return true
    }
}

// MARK: - Bundle helper

extension Bundle {
    func decode<T: Decodable>(_ type: T.Type, from file: String) -> T {
        guard let url = self.url(forResource: file, withExtension: nil),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(T.self, from: data) else {
            fatalError("Could not load \(file) from bundle.")
        }
        return value
    }
}
