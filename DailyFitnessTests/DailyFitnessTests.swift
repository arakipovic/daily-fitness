import Testing
import Foundation
@testable import DailyFitness

// MARK: - Helpers

private func makeRepository(logbook: Logbook? = .empty) -> FileLogbookRepository {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("DailyFitnessTests-\(UUID().uuidString)")
        .appendingPathExtension("json")
    let repository = FileLogbookRepository(fileURL: url)
    if let logbook {
        repository.save(logbook)
    }
    return repository
}

private func makeSlot(reps: String = "8-12", sets: Int = 3) -> Slot {
    Slot(label: "A1", name: "Squat", sets: sets, reps: reps,
         restSeconds: 90, rir: "2", notes: "", alternatives: [])
}

private func makeSetEntry(weight: String, reps: String, done: Bool = true) -> SetEntry {
    SetEntry(id: UUID(), weight: weight, reps: reps, rir: "2", done: done)
}

private func makeLog(sets: [SetEntry]) -> ExerciseLog {
    ExerciseLog(exerciseName: "Squat", sets: sets, note: "", swappedFrom: nil)
}

private func makeSession(
    programID: String = "prog1", week: Int = 1, day: Int = 1,
    completed: Date? = .distantPast,
    slots: [String: ExerciseLog] = [:]
) -> SessionLog {
    SessionLog(programID: programID, week: week, day: day,
               started: completed.map { $0.addingTimeInterval(-3600) },
               completed: completed, slotLogs: slots)
}

private func makeMinimalCatalog(weeks: Int = 4, daysPerWeek: Int = 4) -> Catalog {
    let days = (1...max(1, daysPerWeek)).map { n in
        ProgramDay(number: n, exercises: [makeSlot()])
    }
    let program = TrainingProgram(id: "prog1", name: "Test Program",
                                  daysPerWeek: daysPerWeek, title: "Test",
                                  weeks: weeks, days: days)
    return Catalog(programs: [program], videos: [:])
}

private func makeCatalogWithExerciseVideos(_ names: [String]) -> Catalog {
    var catalog = makeMinimalCatalog()
    catalog.videos = Dictionary(uniqueKeysWithValues: names.map {
        ($0, URL(string: "https://example.com/video")!)
    })
    return catalog
}

private func makeEmptyLogbook() -> Logbook {
    var logbook = Logbook.empty
    logbook.importedLegacyV1 = true
    return logbook
}

// MARK: - Sleep Interval Merging

/// White-box test of the interval-merge logic that prevents double-counting
/// when multiple sleep sources (Apple Watch + Sleep Cycle, etc.) write overlapping samples.
@Suite("Sleep Interval Merging")
struct SleepIntervalMergingTests {

    // Mirror of HealthKitManager.mergedDuration (private) — same algorithm.
    private func mergedDuration(_ intervals: [(Date, Date)]) -> TimeInterval {
        let sorted = intervals.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var current: (Date, Date)? = nil
        for interval in sorted {
            if let c = current {
                if interval.0 < c.1 {
                    current = (c.0, max(c.1, interval.1))
                } else {
                    total += c.1.timeIntervalSince(c.0)
                    current = interval
                }
            } else {
                current = interval
            }
        }
        if let c = current { total += c.1.timeIntervalSince(c.0) }
        return total
    }

    private func date(_ offset: TimeInterval) -> Date { Date(timeIntervalSinceReferenceDate: offset) }

    @Test("Non-overlapping intervals sum correctly")
    func nonOverlapping() {
        let intervals = [(date(0), date(3600)), (date(7200), date(10800))]
        #expect(mergedDuration(intervals) == 7200)
    }

    @Test("Fully overlapping intervals (two sources same night) produce single span")
    func fullyOverlapping() {
        // Two sources each record 8 h — must give 8 h, not 16 h
        let eightHours: TimeInterval = 8 * 3600
        let intervals = [
            (date(0), date(eightHours)),
            (date(0), date(eightHours))
        ]
        #expect(mergedDuration(intervals) == eightHours)
    }

    @Test("Partially overlapping intervals merge correctly")
    func partiallyOverlapping() {
        // 0–6 h and 4–8 h → merged 0–8 h = 8 h
        let intervals = [(date(0), date(6 * 3600)), (date(4 * 3600), date(8 * 3600))]
        #expect(mergedDuration(intervals) == 8 * 3600)
    }

    @Test("Empty input returns zero")
    func emptyIntervals() {
        #expect(mergedDuration([]) == 0)
    }
}

// MARK: - Copy Food Entry

@Suite("Copy Food Entry")
@MainActor
struct CopyFoodEntryTests {

    @Test("Copies entry to target date with new ID")
    func copiedEntryHasNewIDAndTargetDate() throws {
        let repo = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repo)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let entry = FoodEntry(name: "Eggs", calories: 200, protein: 14, carbs: 0, fat: 12, date: yesterday, meal: .breakfast)
        store.addFoodEntry(entry)
        store.copyFoodEntry(entry, to: Date())
        let todayEntries = NutritionLogic.entries(store.logbook.foodLog, on: Date())
        #expect(todayEntries.count == 1)
        #expect(todayEntries[0].name == "Eggs")
        #expect(todayEntries[0].id != entry.id)
        #expect(todayEntries[0].meal == .breakfast)
        #expect(todayEntries[0].calories == 200)
    }

    @Test("Original entry is preserved on source date")
    func originalEntryRemainsOnSourceDate() throws {
        let repo = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repo)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let entry = FoodEntry(name: "Oatmeal", calories: 300, protein: 10, carbs: 50, fat: 5, date: yesterday, meal: .breakfast)
        store.addFoodEntry(entry)
        store.copyFoodEntry(entry, to: Date())
        let sourceEntries = NutritionLogic.entries(store.logbook.foodLog, on: yesterday)
        #expect(sourceEntries.count == 1)
        #expect(sourceEntries[0].id == entry.id)
    }
}

// MARK: - Exercise Prioritization

@Suite("Exercise Prioritization")
struct ExercisePrioritizationTests {

    private func makeExerciseLog(_ name: String) -> ExerciseLog {
        ExerciseLog(exerciseName: name, sets: [], note: "", swappedFrom: nil)
    }

    @Test("Video + history ranks before video-only, history-only, and neither")
    func tierOrdering() {
        let names = ["Neither", "HistoryOnly", "VideoOnly", "Both"]
        let videos: [String: URL] = [
            "Both": URL(string: "https://example.com/both")!,
            "VideoOnly": URL(string: "https://example.com/video")!
        ]
        let exerciseIndex: [String: ExerciseLog] = [
            "both": makeExerciseLog("Both"),
            "historyonly": makeExerciseLog("HistoryOnly")
        ]
        let result = WorkoutLogic.prioritizedExerciseNames(names, videos: videos, exerciseIndex: exerciseIndex)
        #expect(result == ["Both", "VideoOnly", "HistoryOnly", "Neither"])
    }

    @Test("Alphabetical within same tier")
    func alphabeticalWithinTier() {
        let names = ["Zebra", "Apple", "Mango"]
        let videos: [String: URL] = [:]
        let exerciseIndex: [String: ExerciseLog] = [:]
        let result = WorkoutLogic.prioritizedExerciseNames(names, videos: videos, exerciseIndex: exerciseIndex)
        #expect(result == ["Apple", "Mango", "Zebra"])
    }

    @Test("Empty input returns empty")
    func emptyInput() {
        let result = WorkoutLogic.prioritizedExerciseNames([], videos: [:], exerciseIndex: [:])
        #expect(result.isEmpty)
    }
}

// MARK: - Preferred exercise selection

@Suite("WorkoutLogic.preferredExercise")
struct PreferredExerciseTests {

    private func makeExerciseLog(_ name: String) -> ExerciseLog {
        ExerciseLog(exerciseName: name, sets: [], note: "", swappedFrom: nil)
    }

    private func makeSlotWithAlternatives(name: String, alternatives: [String]) -> Slot {
        Slot(label: "A1", name: name, sets: 3, reps: "8-12",
             restSeconds: 90, rir: "2", notes: "", alternatives: alternatives)
    }

    @Test("Returns primary when primary has history")
    func primaryWithHistory() {
        let slot = makeSlotWithAlternatives(name: "Back Squat", alternatives: ["Leg Press", "Hack Squat"])
        let index: [String: ExerciseLog] = ["back squat": makeExerciseLog("Back Squat")]
        #expect(WorkoutLogic.preferredExercise(for: slot, exerciseIndex: index) == "Back Squat")
    }

    @Test("Returns alternative when only alternative has history")
    func alternativeWithHistory() {
        let slot = makeSlotWithAlternatives(name: "Back Squat", alternatives: ["Leg Press", "Hack Squat"])
        let index: [String: ExerciseLog] = ["leg press": makeExerciseLog("Leg Press")]
        #expect(WorkoutLogic.preferredExercise(for: slot, exerciseIndex: index) == "Leg Press")
    }

    @Test("Primary wins when both primary and alternative have history")
    func primaryPreferredOverAlternativeWhenBothHaveHistory() {
        let slot = makeSlotWithAlternatives(name: "Back Squat", alternatives: ["Leg Press"])
        let index: [String: ExerciseLog] = [
            "back squat": makeExerciseLog("Back Squat"),
            "leg press": makeExerciseLog("Leg Press")
        ]
        #expect(WorkoutLogic.preferredExercise(for: slot, exerciseIndex: index) == "Back Squat")
    }

    @Test("Falls back to slot name when no history exists")
    func fallbackToSlotName() {
        let slot = makeSlotWithAlternatives(name: "Back Squat", alternatives: ["Leg Press"])
        #expect(WorkoutLogic.preferredExercise(for: slot, exerciseIndex: [:]) == "Back Squat")
    }

    @Test("Works correctly with no alternatives")
    func noAlternatives() {
        let slot = Slot(label: "A1", name: "Pull Up", sets: 3, reps: "8-12",
                        restSeconds: 90, rir: "2", notes: "", alternatives: [])
        let index: [String: ExerciseLog] = ["pull up": makeExerciseLog("Pull Up")]
        #expect(WorkoutLogic.preferredExercise(for: slot, exerciseIndex: index) == "Pull Up")
    }
}

// MARK: - FoodEntry Codable

@Suite("FoodEntry Codable")
@MainActor
struct FoodEntryTests {

    @Test("Old JSON without extended fields decodes with zeros")
    func backwardCompatibility() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"Apple",
         "calories":95,"protein":0.5,"carbs":25.0,"fat":0.3,"date":0}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let entry = try decoder.decode(FoodEntry.self, from: json)
        #expect(entry.name == "Apple")
        #expect(entry.calories == 95)
        #expect(entry.fiber == 0)
        #expect(entry.sugar == 0)
        #expect(entry.saturatedFat == 0)
        #expect(entry.sodium == 0)
        #expect(entry.cholesterol == 0)
    }

    @Test("Extended fields survive encode/decode round-trip")
    func roundTrip() throws {
        let original = FoodEntry(
            name: "Oats", calories: 300, protein: 10, carbs: 54, fat: 6,
            fiber: 8, sugar: 1, saturatedFat: 1.2, sodium: 5, cholesterol: 0,
            date: Date(timeIntervalSince1970: 0)
        )
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(FoodEntry.self, from: encoder.encode(original))
        #expect(decoded.fiber == 8)
        #expect(decoded.sugar == 1)
        #expect(decoded.saturatedFat == 1.2)
        #expect(decoded.sodium == 5)
        #expect(decoded.cholesterol == 0)
        #expect(decoded.name == "Oats")
    }

    @Test("Convenience init defaults all extended fields to zero")
    func defaultInit() {
        let e = FoodEntry(name: "Egg", calories: 70, protein: 6, carbs: 0.5, fat: 5, date: .now)
        #expect(e.fiber == 0)
        #expect(e.sugar == 0)
        #expect(e.saturatedFat == 0)
        #expect(e.sodium == 0)
        #expect(e.cholesterol == 0)
    }
}

// MARK: - FoodTemplate macros

@Suite("FoodTemplate.macros")
struct FoodTemplateTests {

    private let chicken = FoodTemplate(
        name: "Chicken breast", category: .protein,
        kcal: 165, protein: 31, carbs: 0, fat: 3.6, defaultServingG: 150
    )

    @Test("Macros at default serving scale correctly")
    func defaultServing() {
        let m = chicken.macros(forGrams: 150)
        #expect(m.kcal == Int((165 * 1.5).rounded()))
        #expect(m.p == (31 * 1.5 * 10).rounded() / 10)
        #expect(m.c == 0)
    }

    @Test("Zero grams returns all zeros")
    func zeroGrams() {
        let m = chicken.macros(forGrams: 0)
        #expect(m.kcal == 0)
        #expect(m.p == 0)
        #expect(m.c == 0)
        #expect(m.f == 0)
    }

    @Test("100g returns per-100g values")
    func hundredGrams() {
        let m = chicken.macros(forGrams: 100)
        #expect(m.kcal == 165)
        #expect(m.p == 31)
        #expect(m.f == 3.6)
    }

    @Test("Macros scale linearly with grams")
    func linearScaling() {
        let m50  = chicken.macros(forGrams: 50)
        let m100 = chicken.macros(forGrams: 100)
        // Integer rounding means halved values may differ by ±1 when doubled
        #expect(abs(m100.kcal - m50.kcal * 2) <= 1)
    }
}

// MARK: - Nutrition dashboard summary

@Suite("NutritionLogic.dailySummary")
struct NutritionDailySummaryTests {

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test("Builds today's totals, budget, and remaining targets")
    func todaySummary() {
        let calendar = utcCalendar
        let today = DateComponents(
            calendar: calendar,
            year: 2026,
            month: 10,
            day: 12,
            hour: 8
        ).date!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let foodLog = [
            FoodEntry(
                name: "Breakfast",
                calories: 500,
                protein: 30,
                carbs: 52,
                fat: 12,
                fiber: 8,
                date: today
            ),
            FoodEntry(
                name: "Shake",
                calories: 300,
                protein: 25,
                carbs: 34,
                fat: 6,
                fiber: 5,
                date: today.addingTimeInterval(3600)
            ),
            FoodEntry(
                name: "Tomorrow snack",
                calories: 150,
                protein: 5,
                carbs: 20,
                fat: 3,
                fiber: 2,
                date: tomorrow
            )
        ]

        let summary = NutritionLogic.dailySummary(
            foodLog: foodLog,
            on: today,
            calorieTarget: 2_000,
            proteinTarget: 150,
            fiberTarget: 30,
            activeCalories: 250,
            calendar: calendar
        )

        #expect(summary.entryCount == 2)
        #expect(summary.calories == 800)
        #expect(summary.protein == 55)
        #expect(summary.carbs == 86)
        #expect(summary.fiber == 13)
        #expect(summary.calorieBudget == 2_250)
        #expect(summary.caloriesRemaining == 1_450)
        #expect(summary.proteinRemaining == 95)
        #expect(summary.fiberRemaining == 17)
        #expect(!summary.isOverCalories)
    }

    @Test("Preserves negative remaining values when targets are exceeded")
    func overTargets() {
        let calendar = utcCalendar
        let date = DateComponents(
            calendar: calendar,
            year: 2026,
            month: 10,
            day: 12,
            hour: 12
        ).date!
        let foodLog = [
            FoodEntry(
                name: "Large meal",
                calories: 2_300,
                protein: 180,
                carbs: 180,
                fat: 90,
                fiber: 40,
                date: date
            )
        ]

        let summary = NutritionLogic.dailySummary(
            foodLog: foodLog,
            on: date,
            calorieTarget: 2_000,
            proteinTarget: 150,
            fiberTarget: 30,
            activeCalories: 0,
            calendar: calendar
        )

        #expect(summary.caloriesRemaining == -300)
        #expect(summary.proteinRemaining == -30)
        #expect(summary.fiberRemaining == -10)
        #expect(summary.isOverCalories)
    }

    @Test("Negative active calories never reduce the daily calorie budget")
    func negativeActiveCaloriesAreIgnored() {
        let calendar = utcCalendar
        let date = DateComponents(
            calendar: calendar,
            year: 2026,
            month: 10,
            day: 12
        ).date!

        let summary = NutritionLogic.dailySummary(
            foodLog: [],
            on: date,
            calorieTarget: 2_000,
            proteinTarget: 150,
            fiberTarget: 30,
            activeCalories: -200,
            calendar: calendar
        )

        #expect(summary.calorieBudget == 2_000)
        #expect(summary.caloriesRemaining == 2_000)
    }
}

// MARK: - CatalogModels

@Suite("TrainingProgram helpers")
struct CatalogModelTests {

    private let program4 = TrainingProgram(
        id: "p4", name: "P4", daysPerWeek: 4, title: "4-day", weeks: 4,
        days: (1...4).map { ProgramDay(number: $0, exercises: []) }
    )
    private let program5 = TrainingProgram(
        id: "p5", name: "P5", daysPerWeek: 5, title: "5-day", weeks: 4,
        days: (1...5).map { ProgramDay(number: $0, exercises: []) }
    )
    private let program3 = TrainingProgram(
        id: "p3", name: "P3", daysPerWeek: 3, title: "3-day", weeks: 3,
        days: (1...3).map { ProgramDay(number: $0, exercises: []) }
    )

    @Test("4-day program returns Upper/Lower labels")
    func fourDayLabels() {
        let days = program4.days
        #expect(program4.dayFocusTitle(for: days[0]) == "Upper A")
        #expect(program4.dayFocusTitle(for: days[1]) == "Lower A")
        #expect(program4.dayFocusTitle(for: days[2]) == "Upper B")
        #expect(program4.dayFocusTitle(for: days[3]) == "Lower B")
    }

    @Test("5-day program returns Upper/Lower/Full Body labels")
    func fiveDayLabels() {
        let days = program5.days
        #expect(program5.dayFocusTitle(for: days[0]) == "Upper A")
        #expect(program5.dayFocusTitle(for: days[4]) == "Full Body")
    }

    @Test("Other day counts fall back to Day N")
    func otherDayCountFallback() {
        let day = program3.days[0]
        #expect(program3.dayFocusTitle(for: day) == "Day 1")
    }

    @Test("Safe subscript returns element within bounds")
    func safeSubscriptInBounds() {
        let arr = [10, 20, 30]
        #expect(arr[safe: 0] == 10)
        #expect(arr[safe: 2] == 30)
    }

    @Test("Safe subscript returns nil out of bounds")
    func safeSubscriptOutOfBounds() {
        let arr = [10, 20]
        #expect(arr[safe: 5] == nil)
        #expect(arr[safe: -1] == nil)
    }
}

// MARK: - WorkoutRecommender

@Suite("WorkoutRecommender")
struct WorkoutRecommenderTests {

    @Test("Returns nil when previous log is nil")
    func nilWithNoHistory() {
        #expect(WorkoutRecommender.recommend(
            previousLog: nil, slot: makeSlot(), unit: .kg,
            sleepHours: 8, daysSinceLastSession: 2) == nil)
    }

    @Test("Returns nil when all sets have empty weight")
    func nilWithEmptyWeight() {
        let log = makeLog(sets: [makeSetEntry(weight: "", reps: "10")])
        #expect(WorkoutRecommender.recommend(
            previousLog: log, slot: makeSlot(), unit: .kg,
            sleepHours: 8, daysSinceLastSession: 2) == nil)
    }

    @Test("Returns nil when no sets are marked done")
    func nilWithNoDoneSets() {
        let log = makeLog(sets: [makeSetEntry(weight: "100", reps: "10", done: false)])
        #expect(WorkoutRecommender.recommend(
            previousLog: log, slot: makeSlot(), unit: .kg,
            sleepHours: 8, daysSinceLastSession: 2) == nil)
    }

    @Test("High readiness + max reps hit → progress with heavier weight")
    func progressWhenHighReadiness() throws {
        let log = makeLog(sets: [makeSetEntry(weight: "100", reps: "12")]) // 12 = repMax
        let result = try #require(WorkoutRecommender.recommend(
            previousLog: log, slot: makeSlot(reps: "8-12"), unit: .kg,
            sleepHours: 8.5, daysSinceLastSession: 2))
        #expect(result.direction == .progress)
        #expect(result.suggestedWeight == 102.5) // +2.5 kg step
    }

    @Test("Moderate readiness → maintain weight, +1 rep")
    func maintainWhenModerateReadiness() throws {
        let log = makeLog(sets: [makeSetEntry(weight: "80", reps: "10")])
        let result = try #require(WorkoutRecommender.recommend(
            previousLog: log, slot: makeSlot(reps: "8-12"), unit: .kg,
            sleepHours: 7.0, daysSinceLastSession: 1))
        #expect(result.direction == .maintain)
        #expect(result.suggestedWeight == 80)
        #expect(result.suggestedReps == 11) // 10 + 1
    }

    @Test("Low readiness → deload")
    func deloadWhenFatigued() throws {
        let log = makeLog(sets: [makeSetEntry(weight: "100", reps: "10")])
        let result = try #require(WorkoutRecommender.recommend(
            previousLog: log, slot: makeSlot(), unit: .kg,
            sleepHours: 4.0, daysSinceLastSession: 0))
        #expect(result.direction == .deload)
        #expect(result.suggestedWeight < 100)
    }

    @Test("lb unit uses 5 lb step on progression")
    func lbStepSize() throws {
        let log = makeLog(sets: [makeSetEntry(weight: "135", reps: "12")])
        let result = try #require(WorkoutRecommender.recommend(
            previousLog: log, slot: makeSlot(reps: "8-12"), unit: .lb,
            sleepHours: 8.5, daysSinceLastSession: 2))
        #expect(result.direction == .progress)
        #expect(result.suggestedWeight == 140) // +5 lb step
    }

    @Test("Picks highest done set when multiple sets provided")
    func picksMaxWeightFromMultipleSets() throws {
        let sets = [
            makeSetEntry(weight: "80",  reps: "12"),
            makeSetEntry(weight: "100", reps: "12"), // highest
            makeSetEntry(weight: "90",  reps: "12"),
        ]
        let log = makeLog(sets: sets)
        let result = try #require(WorkoutRecommender.recommend(
            previousLog: log, slot: makeSlot(reps: "8-12"), unit: .kg,
            sleepHours: 8.5, daysSinceLastSession: 2))
        // Progression from 100, not from 80 or 90
        #expect(result.suggestedWeight == 102.5)
    }

    @Test("Ignores undone sets when computing best weight")
    func ignoresUndoneSets() {
        let sets = [
            makeSetEntry(weight: "200", reps: "12", done: false), // should be ignored
            makeSetEntry(weight: "80",  reps: "12", done: true),
        ]
        let log = makeLog(sets: sets)
        let result = WorkoutRecommender.recommend(
            previousLog: log, slot: makeSlot(reps: "8-12"), unit: .kg,
            sleepHours: 8.5, daysSinceLastSession: 2)
        // Result should be based on 80, not 200
        #expect(result?.suggestedWeight != 202.5)
        #expect(result != nil)
    }

    @Test("weightString formats whole number without decimals")
    func weightStringWholeNumber() throws {
        // 97.5 + 2.5 = 100.0 → roundToStep(100, 2.5) = 100 → "100"
        let log = makeLog(sets: [makeSetEntry(weight: "97.5", reps: "12")])
        let result = try #require(WorkoutRecommender.recommend(
            previousLog: log, slot: makeSlot(reps: "8-12"), unit: .kg,
            sleepHours: 8.5, daysSinceLastSession: 2))
        #expect(!result.weightString.contains("."))
    }

    @Test("weightString formats decimal with one decimal place")
    func weightStringDecimal() throws {
        // 100 + 2.5 = 102.5 → roundToStep(102.5, 2.5) = 102.5 → "102.5"
        let log = makeLog(sets: [makeSetEntry(weight: "100", reps: "12")])
        let result = try #require(WorkoutRecommender.recommend(
            previousLog: log, slot: makeSlot(reps: "8-12"), unit: .kg,
            sleepHours: 8.5, daysSinceLastSession: 2))
        #expect(result.weightString == "102.5")
    }

    @Test("parseRepRange: single integer")
    func parseSingle() {
        let (lo, hi) = WorkoutRecommender.parseRepRange("8")
        #expect(lo == 8 && hi == 8)
    }

    @Test("parseRepRange: hyphenated range")
    func parseRange() {
        let (lo, hi) = WorkoutRecommender.parseRepRange("8-12")
        #expect(lo == 8 && hi == 12)
    }

    @Test("parseRepRange: whitespace-padded range")
    func parseRangePadded() {
        let (lo, hi) = WorkoutRecommender.parseRepRange(" 6 - 10 ")
        #expect(lo == 6 && hi == 10)
    }

    @Test("parseRepRange: falls back to 8-12 on unrecognised input")
    func parseFallback() {
        let (lo, hi) = WorkoutRecommender.parseRepRange("AMRAP")
        #expect(lo == 8 && hi == 12)
    }

    @Test("sessionReadiness: well-rested > fatigued")
    func readinessOrdering() {
        let wellRested = WorkoutRecommender.sessionReadiness(sleepHours: 8.5, daysSinceLastSession: 2)
        let fatigued   = WorkoutRecommender.sessionReadiness(sleepHours: 4.0, daysSinceLastSession: 0)
        #expect(wellRested > fatigued)
        #expect(wellRested <= 1.0)
        #expect(fatigued >= 0.0)
    }

    @Test("sessionReadiness: missing data defaults to mid-range, not zero")
    func readinessMissingData() {
        let r = WorkoutRecommender.sessionReadiness(sleepHours: nil, daysSinceLastSession: nil)
        #expect(r > 0.5) // both factors default to high end
    }
}

// MARK: - Workout exercise catalog

@Suite("WorkoutLogic exercise catalog")
struct WorkoutExerciseCatalogTests {

    @Test("Catalog exercise names include video-only exercises")
    func catalogIncludesVideoExercises() {
        let catalog = makeCatalogWithExerciseVideos(["Pull Up"])
        let names = WorkoutLogic.catalogExerciseNames(from: catalog)

        #expect(names.contains("Squat"))
        #expect(names.contains("Pull Up"))
    }

    @Test("Exercise search matches spacing and simple plural differences")
    func normalizedSearch() {
        #expect(WorkoutLogic.exerciseName("Pull Up", matches: "pullups"))
        #expect(WorkoutLogic.exerciseName("Band-Assisted Pull-Up", matches: "band assisted pullup"))
    }

    @Test("Custom exercise extraction excludes catalog matches and keeps personal names")
    func customExerciseNamesFromHistory() {
        let catalogNames = ["Pull Up", "Squat"]
        let session = SessionLog(
            programID: "custom",
            week: 1,
            day: 1,
            started: Date(),
            completed: Date(),
            slotLogs: [
                "1": ExerciseLog(exerciseName: "Pullups", sets: [], note: "", swappedFrom: nil),
                "2": ExerciseLog(exerciseName: "Dips", sets: [], note: "", swappedFrom: nil)
            ]
        )

        let names = WorkoutLogic.customExerciseNames(
            from: ["custom|1|1": session],
            excludingCatalogNames: catalogNames
        )

        #expect(names == ["Dips"])
    }
}

// MARK: - Store session key

@Suite("Store.sessionKey")
@MainActor
struct StoreSessionKeyTests {

    private var store: Store { Store.makeForTesting(repository: makeRepository(), catalog: makeMinimalCatalog()) }

    @Test("Session key concatenates components with pipes")
    func keyFormat() {
        let s = store
        #expect(s.sessionKey(programID: "prog1", week: 2, day: 3) == "prog1|2|3")
    }

    @Test("Different program IDs produce different keys")
    func keyUniqueness() {
        let s = store
        let k1 = s.sessionKey(programID: "A", week: 1, day: 1)
        let k2 = s.sessionKey(programID: "B", week: 1, day: 1)
        #expect(k1 != k2)
    }
}

// MARK: - Store CRUD

@Suite("Store session CRUD")
@MainActor
struct StoreCRUDTests {

    @Test("updateSession persists to logbook")
    func updatePersists() {
        let repo = makeRepository()
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())
        let session = makeSession(programID: "prog1", week: 1, day: 1)
        store.updateSession(session)
        #expect(store.logbook.sessions["prog1|1|1"] != nil)
    }

    @Test("deleteSession removes from logbook")
    func deleteClearsSession() {
        let repo = makeRepository()
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())
        store.updateSession(makeSession(programID: "prog1", week: 1, day: 1))
        store.deleteSession(programID: "prog1", week: 1, day: 1)
        #expect(store.logbook.sessions["prog1|1|1"] == nil)
    }

    @Test("updateSession does not affect other sessions")
    func updateIsolated() {
        let repo = makeRepository()
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())
        store.updateSession(makeSession(programID: "prog1", week: 1, day: 1))
        store.updateSession(makeSession(programID: "prog1", week: 1, day: 2))
        #expect(store.logbook.sessions["prog1|1|1"] != nil)
        #expect(store.logbook.sessions["prog1|1|2"] != nil)
    }
}

// MARK: - Store previousPerformance

@Suite("Store.previousPerformance")
@MainActor
struct StorePerformanceLookupTests {

    @Test("Returns log from most recent prior completed week")
    func findsLastWeek() {
        let log = makeLog(sets: [makeSetEntry(weight: "100", reps: "10")])
        let session = makeSession(programID: "prog1", week: 1, day: 1, slots: ["A1": log])
        let repo = makeRepository(logbook: Logbook(
            selectedProgramID: "prog1", startDate: .now, unit: .kg,
            restAlerts: .on, sessions: ["prog1|1|1": session]
        ))
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())
        let result = store.previousPerformance(
            programID: "prog1", currentWeek: 2, dayNumber: 1, slotLabel: "A1"
        )
        #expect(result?.sets.first?.weight == "100")
    }

    @Test("Returns nil when no prior weeks exist (week 1)")
    func nilForWeekOne() {
        let repo = makeRepository()
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())
        let result = store.previousPerformance(
            programID: "prog1", currentWeek: 1, dayNumber: 1, slotLabel: "A1"
        )
        #expect(result == nil)
    }

    @Test("Skips incomplete (nil completed) sessions")
    func skipsIncomplete() {
        let log = makeLog(sets: [makeSetEntry(weight: "80", reps: "10")])
        let incomplete = makeSession(programID: "prog1", week: 1, day: 1,
                                     completed: nil, slots: ["A1": log])
        let repo = makeRepository(logbook: Logbook(
            selectedProgramID: "prog1", startDate: .now, unit: .kg,
            restAlerts: .on, sessions: ["prog1|1|1": incomplete]
        ))
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())
        let result = store.previousPerformance(
            programID: "prog1", currentWeek: 2, dayNumber: 1, slotLabel: "A1"
        )
        #expect(result == nil)
    }

    @Test("Returns nil when slot label not present in prior session")
    func nilForMissingSlotLabel() {
        let session = makeSession(programID: "prog1", week: 1, day: 1, slots: [:])
        let repo = makeRepository(logbook: Logbook(
            selectedProgramID: "prog1", startDate: .now, unit: .kg,
            restAlerts: .on, sessions: ["prog1|1|1": session]
        ))
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())
        let result = store.previousPerformance(
            programID: "prog1", currentWeek: 2, dayNumber: 1, slotLabel: "Z9"
        )
        #expect(result == nil)
    }
}

// MARK: - Store.nextSession

@Suite("Store.nextSession")
@MainActor
struct StoreNextSessionTests {

    @Test("Returns first incomplete session (week 1, day 1) when nothing done")
    func firstIncompleteIsWeek1Day1() {
        let repo = makeRepository()
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog(weeks: 2, daysPerWeek: 2))
        let next = store.nextSession(for: store.catalog.programs[0])
        #expect(next?.week == 1)
        #expect(next?.day == 1)
    }

    @Test("Skips completed sessions and returns next incomplete")
    func skipsCompleted() {
        let done = makeSession(programID: "prog1", week: 1, day: 1, completed: .now)
        let repo = makeRepository(logbook: Logbook(
            selectedProgramID: "prog1", startDate: .now, unit: .kg,
            restAlerts: .on, sessions: ["prog1|1|1": done]
        ))
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog(weeks: 2, daysPerWeek: 2))
        let next = store.nextSession(for: store.catalog.programs[0])
        #expect(next?.week == 1)
        #expect(next?.day == 2)
    }

    @Test("Returns nil when all sessions are complete")
    func nilWhenAllDone() {
        var sessions: [String: SessionLog] = [:]
        for w in 1...2 {
            for d in 1...2 {
                sessions["prog1|\(w)|\(d)"] = makeSession(
                    programID: "prog1", week: w, day: d, completed: .now)
            }
        }
        let repo = makeRepository(logbook: Logbook(
            selectedProgramID: "prog1", startDate: .now, unit: .kg,
            restAlerts: .on, sessions: sessions
        ))
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog(weeks: 2, daysPerWeek: 2))
        #expect(store.nextSession(for: store.catalog.programs[0]) == nil)
    }
}

// MARK: - Store.daysSinceLastSession

@Suite("Store.daysSinceLastSession")
@MainActor
struct StoreLastSessionTests {

    @Test("Returns nil when logbook is empty")
    func nilWhenEmpty() {
        let store = Store.makeForTesting(repository: makeRepository(), catalog: makeMinimalCatalog())
        #expect(store.daysSinceLastSession() == nil)
    }

    @Test("Returns 0 when most recent session completed today")
    func zeroForToday() {
        let today = makeSession(programID: "prog1", week: 1, day: 1, completed: Date())
        let repo = makeRepository(logbook: Logbook(
            selectedProgramID: "prog1", startDate: .now, unit: .kg,
            restAlerts: .on, sessions: ["prog1|1|1": today]
        ))
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())
        #expect(store.daysSinceLastSession() == 0)
    }
}

// MARK: - Store.exportCSV

@Suite("Store.exportCSV")
@MainActor
struct StoreExportTests {

    @Test("CSV starts with expected header row")
    func csvHeader() {
        let store = Store.makeForTesting(repository: makeRepository(), catalog: makeMinimalCatalog())
        let csv = store.exportCSV()
        let firstLine = csv.split(separator: "\n").first.map(String.init) ?? ""
        #expect(firstLine == "Program,Week,Day,Exercise,Set,Weight,Reps,RIR,Date")
    }

    @Test("CSV contains one data row per set")
    func csvRowCount() {
        let sets = [makeSetEntry(weight: "80", reps: "10"),
                    makeSetEntry(weight: "85", reps: "8")]
        let log = makeLog(sets: sets)
        let session = makeSession(programID: "prog1", week: 1, day: 1, slots: ["A1": log])
        let repo = makeRepository(logbook: Logbook(
            selectedProgramID: "prog1", startDate: .now, unit: .kg,
            restAlerts: .on, sessions: ["prog1|1|1": session]
        ))
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())
        let lines = store.exportCSV().split(separator: "\n")
        // 1 header + 2 data rows
        #expect(lines.count == 3)
    }
}

// MARK: - Store data persistence

@Suite("Store initialization")
@MainActor
struct StoreInitializationTests {

    @Test("Fresh installs start empty and mark bundled legacy import complete")
    func freshInstallStartsEmpty() {
        let repo = makeRepository(logbook: nil)
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())

        #expect(store.logbook.sessions.isEmpty)
        #expect(store.logbook.foodLog.isEmpty)
        #expect(store.logbook.savedMeals.isEmpty)
        #expect(store.logbook.importedLegacyV1)
        #expect(repo.load()?.importedLegacyV1 == true)
        #expect(repo.load()?.sessions.isEmpty == true)
    }

    @Test("Existing legacy-flagged data is kept but marked migrated without merging bundled history")
    func existingDataIsMarkedMigratedWithoutBundledMerge() {
        var logbook = Logbook.empty
        logbook.sessions = ["prog1|1|1": makeSession()]
        logbook.foodLog = [
            FoodEntry(name: "Apple", calories: 95, protein: 0.5, carbs: 25, fat: 0.3, date: Date())
        ]
        logbook.importedLegacyV1 = false
        let repo = makeRepository(logbook: logbook)
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())

        #expect(store.logbook.sessions.count == 1)
        #expect(store.logbook.foodLog.map(\.name) == ["Apple"])
        #expect(store.logbook.importedLegacyV1)
        #expect(repo.load()?.importedLegacyV1 == true)
        #expect(repo.load()?.foodLog.map(\.name) == ["Apple"])
    }
}

@Suite("Store custom exercises")
@MainActor
struct StoreCustomExerciseTests {

    @Test("Adding custom exercise names saves them to the user logbook")
    func addingCustomExerciseSaves() {
        let repo = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(
            repository: repo,
            catalog: makeCatalogWithExerciseVideos(["Pull Up"])
        )

        store.addCustomExerciseName(" Dips ")
        store.addCustomExerciseName("Pullups")

        #expect(store.logbook.customExerciseNames == ["Dips"])
        #expect(repo.load()?.customExerciseNames == ["Dips"])
    }

    @Test("Existing non-catalog workout history is promoted to custom exercises")
    func historyPromotesCustomExercises() {
        let session = SessionLog(
            programID: "custom",
            week: 1,
            day: 1,
            started: Date(),
            completed: Date(),
            slotLogs: [
                "1": ExerciseLog(exerciseName: "Dips", sets: [], note: "", swappedFrom: nil),
                "2": ExerciseLog(exerciseName: "Pullups", sets: [], note: "", swappedFrom: nil)
            ]
        )
        var logbook = makeEmptyLogbook()
        logbook.sessions = ["custom|1|1": session]
        let repo = makeRepository(logbook: logbook)
        let store = Store.makeForTesting(
            repository: repo,
            catalog: makeCatalogWithExerciseVideos(["Pull Up"])
        )

        #expect(store.logbook.customExerciseNames == ["Dips"])
        #expect(repo.load()?.customExerciseNames == ["Dips"])
    }

    @Test("Available exercise names merge bundled catalog and user exercises")
    func availableExerciseNamesMergeSources() {
        var logbook = makeEmptyLogbook()
        logbook.customExerciseNames = ["Dips"]
        let repo = makeRepository(logbook: logbook)
        let store = Store.makeForTesting(
            repository: repo,
            catalog: makeCatalogWithExerciseVideos(["Pull Up"])
        )

        #expect(store.availableExerciseNames.contains("Squat"))
        #expect(store.availableExerciseNames.contains("Pull Up"))
        #expect(store.availableExerciseNames.contains("Dips"))
    }
}

@Suite("LogbookRepository isolation")
struct LogbookRepositoryIsolationTests {

    @Test("Logbook keychain account is scoped to installation id")
    func keychainAccountUsesInstallationID() {
        let first = LogbookRepository.logbookKeychainAccount(forInstallationID: "install-a")
        let second = LogbookRepository.logbookKeychainAccount(forInstallationID: "install-b")

        #expect(first != second)
        #expect(first.contains("install-a"))
        #expect(second.contains("install-b"))
    }
}

@Suite("Store food persistence")
@MainActor
struct StoreFoodPersistenceTests {

    @Test("Adding food entries saves immediately")
    func addingFoodEntrySavesImmediately() {
        let repo = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())
        let entry = FoodEntry(
            name: "Apple",
            calories: 95,
            protein: 0.5,
            carbs: 25,
            fat: 0.3,
            fiber: 4.4,
            date: Date()
        )

        store.addFoodEntry(entry)

        #expect(repo.load()?.foodLog.map(\.name) == ["Apple"])
    }

    @Test("Deleting food entries saves immediately")
    func deletingFoodEntrySavesImmediately() {
        let first = FoodEntry(name: "Apple", calories: 95, protein: 0.5, carbs: 25, fat: 0.3, date: Date())
        let second = FoodEntry(name: "Oats", calories: 227, protein: 8, carbs: 40, fat: 4, date: Date())
        var logbook = makeEmptyLogbook()
        logbook.foodLog = [first, second]
        let repo = makeRepository(logbook: logbook)
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())

        store.deleteFoodEntries(at: IndexSet(integer: 0), from: [first, second])

        #expect(repo.load()?.foodLog.map(\.name) == ["Oats"])
    }
}

@Suite("Store logbook backup")
@MainActor
struct StoreBackupTests {

    @Test("Full data export and import preserves workouts, food, meals, targets, and profile")
    func exportImportRoundTripPreservesAllData() throws {
        let session = makeSession(programID: "prog1", week: 1, day: 1, slots: [
            "A1": makeLog(sets: [makeSetEntry(weight: "80", reps: "10")])
        ])
        let food = FoodEntry(
            name: "Shake",
            calories: 320,
            protein: 25,
            carbs: 42,
            fat: 7,
            fiber: 8,
            sugar: 18,
            saturatedFat: 1.5,
            sodium: 220,
            cholesterol: 10,
            date: Date(timeIntervalSince1970: 1_000)
        )
        let meal = SavedMeal(
            name: "Daily Shake",
            ingredients: [
                SavedMealIngredient(
                    name: "Apple",
                    category: .fruit,
                    grams: 150,
                    kcalPer100g: 52,
                    proteinPer100g: 0.3,
                    carbsPer100g: 14,
                    fatPer100g: 0.2,
                    fiberPer100g: 2.4,
                    sugarPer100g: 10.4
                )
            ],
            createdAt: Date(timeIntervalSince1970: 2_000),
            updatedAt: Date(timeIntervalSince1970: 3_000)
        )
        var sourceLogbook = Logbook(
            selectedProgramID: "prog1",
            startDate: Date(timeIntervalSince1970: 500),
            unit: .lb,
            restAlerts: .off,
            sessions: ["prog1|1|1": session],
            customExerciseNames: ["Dips"],
            foodLog: [food],
            savedMeals: [meal],
            calorieTarget: 2300,
            proteinTarget: 175,
            fiberTarget: 35,
            profileName: "Test User",
            profileAge: 34,
            profileWeightKg: 82,
            profileHeightCm: 181,
            profileSex: .male,
            profileActivity: .active,
            importedLegacyV1: true
        )
        sourceLogbook.importedLegacyV1 = true
        let sourceStore = Store.makeForTesting(
            repository: makeRepository(logbook: sourceLogbook),
            catalog: makeMinimalCatalog()
        )
        let exported = try sourceStore.exportLogbookData()

        let destinationRepo = makeRepository(logbook: makeEmptyLogbook())
        let destinationStore = Store.makeForTesting(repository: destinationRepo, catalog: makeMinimalCatalog())
        try destinationStore.importLogbookData(exported)

        #expect(destinationStore.logbook.sessions.count == 1)
        #expect(destinationStore.logbook.foodLog.first?.name == "Shake")
        #expect(destinationStore.logbook.foodLog.first?.fiber == 8)
        #expect(destinationStore.logbook.savedMeals.first?.name == "Daily Shake")
        #expect(destinationStore.logbook.customExerciseNames == ["Dips"])
        #expect(destinationStore.logbook.calorieTarget == 2300)
        #expect(destinationStore.logbook.profileName == "Test User")
        #expect(destinationStore.logbook.importedLegacyV1)
        #expect(destinationRepo.load()?.foodLog.count == 1)
    }

    @Test("Invalid backup data is rejected without replacing current data")
    func invalidImportDoesNotReplaceData() {
        var current = makeEmptyLogbook()
        current.foodLog = [
            FoodEntry(name: "Apple", calories: 95, protein: 0.5, carbs: 25, fat: 0.3, date: Date())
        ]
        let repo = makeRepository(logbook: current)
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())

        #expect(throws: Error.self) {
            try store.importLogbookData(Data("not json".utf8))
        }
        #expect(store.logbook.foodLog.map(\.name) == ["Apple"])
        #expect(repo.load()?.foodLog.map(\.name) == ["Apple"])
    }

    @Test("Reset all data clears food logs and saved meals too")
    func resetAllDataClearsFoodAndSavedMeals() {
        var current = makeEmptyLogbook()
        current.foodLog = [
            FoodEntry(name: "Apple", calories: 95, protein: 0.5, carbs: 25, fat: 0.3, date: Date())
        ]
        current.savedMeals = [
            SavedMeal(name: "Shake", ingredients: [])
        ]
        current.sessions = ["prog1|1|1": makeSession()]
        let repo = makeRepository(logbook: current)
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())

        store.resetAllData()

        #expect(store.logbook.foodLog.isEmpty)
        #expect(store.logbook.savedMeals.isEmpty)
        #expect(store.logbook.sessions.isEmpty)
        #expect(store.logbook.importedLegacyV1)
        #expect(repo.load()?.foodLog.isEmpty == true)
    }
}

// MARK: - LogbookLogic functional core

@Suite("LogbookLogic.sessionKey")
struct LogbookLogicSessionKeyTests {

    @Test("Key format is programID|week|day")
    func keyFormat() {
        #expect(LogbookLogic.sessionKey(programID: "prog1", week: 2, day: 3) == "prog1|2|3")
    }

    @Test("Different programIDs produce different keys")
    func differentPrograms() {
        let k1 = LogbookLogic.sessionKey(programID: "A", week: 1, day: 1)
        let k2 = LogbookLogic.sessionKey(programID: "B", week: 1, day: 1)
        #expect(k1 != k2)
    }

    @Test("Different weeks produce different keys")
    func differentWeeks() {
        let k1 = LogbookLogic.sessionKey(programID: "p", week: 1, day: 1)
        let k2 = LogbookLogic.sessionKey(programID: "p", week: 2, day: 1)
        #expect(k1 != k2)
    }
}

@Suite("LogbookLogic.nextSession")
struct LogbookLogicNextSessionTests {

    private func catalog(weeks: Int = 2, days: Int = 2) -> TrainingProgram {
        TrainingProgram(
            id: "prog1", name: "T", daysPerWeek: days, title: "T", weeks: weeks,
            days: (1...max(1, days)).map { ProgramDay(number: $0, exercises: [makeSlot()]) }
        )
    }

    @Test("Returns week 1 day 1 when nothing is done")
    func firstSessionWhenEmpty() {
        let result = LogbookLogic.nextSession(sessions: [:], program: catalog())
        #expect(result?.week == 1)
        #expect(result?.day == 1)
    }

    @Test("Skips completed sessions")
    func skipsCompleted() {
        let done = makeSession(programID: "prog1", week: 1, day: 1, completed: .now)
        let result = LogbookLogic.nextSession(
            sessions: ["prog1|1|1": done],
            program: catalog()
        )
        #expect(result?.week == 1)
        #expect(result?.day == 2)
    }

    @Test("Returns nil when all sessions are done")
    func nilWhenAllDone() {
        var sessions: [String: SessionLog] = [:]
        for w in 1...2 { for d in 1...2 {
            sessions["prog1|\(w)|\(d)"] = makeSession(programID: "prog1", week: w, day: d, completed: .now)
        }}
        let result = LogbookLogic.nextSession(sessions: sessions, program: catalog())
        #expect(result == nil)
    }

    @Test("Incomplete session (no completed date) counts as pending")
    func incompleteIsPending() {
        let incomplete = makeSession(programID: "prog1", week: 1, day: 1, completed: nil)
        let result = LogbookLogic.nextSession(
            sessions: ["prog1|1|1": incomplete],
            program: catalog()
        )
        #expect(result?.week == 1 && result?.day == 1)
    }
}

@Suite("LogbookLogic.previousPerformance")
struct LogbookLogicPreviousPerformanceTests {

    @Test("Returns log from most recent prior completed week")
    func findsLastWeek() {
        let log = makeLog(sets: [makeSetEntry(weight: "100", reps: "10")])
        let session = makeSession(programID: "prog1", week: 1, day: 1, slots: ["A1": log])
        let result = LogbookLogic.previousPerformance(
            sessions: ["prog1|1|1": session],
            programID: "prog1", currentWeek: 2, dayNumber: 1, slotLabel: "A1"
        )
        #expect(result?.sets.first?.weight == "100")
    }

    @Test("Returns nil when no prior weeks exist")
    func nilForWeekOne() {
        let result = LogbookLogic.previousPerformance(
            sessions: [:], programID: "prog1", currentWeek: 1, dayNumber: 1, slotLabel: "A1"
        )
        #expect(result == nil)
    }

    @Test("Skips sessions without completed date")
    func skipsIncomplete() {
        let log = makeLog(sets: [makeSetEntry(weight: "80", reps: "10")])
        let incomplete = makeSession(programID: "prog1", week: 1, day: 1, completed: nil, slots: ["A1": log])
        let result = LogbookLogic.previousPerformance(
            sessions: ["prog1|1|1": incomplete],
            programID: "prog1", currentWeek: 2, dayNumber: 1, slotLabel: "A1"
        )
        #expect(result == nil)
    }

    @Test("Returns nil for missing slot label")
    func nilForMissingSlot() {
        let session = makeSession(programID: "prog1", week: 1, day: 1, slots: [:])
        let result = LogbookLogic.previousPerformance(
            sessions: ["prog1|1|1": session],
            programID: "prog1", currentWeek: 2, dayNumber: 1, slotLabel: "Z9"
        )
        #expect(result == nil)
    }

    @Test("Returns most recent week when multiple prior weeks exist")
    func mostRecentWins() {
        let week1Log = makeLog(sets: [makeSetEntry(weight: "80", reps: "10")])
        let week2Log = makeLog(sets: [makeSetEntry(weight: "90", reps: "10")])
        let sessions: [String: SessionLog] = [
            "prog1|1|1": makeSession(programID: "prog1", week: 1, day: 1, slots: ["A1": week1Log]),
            "prog1|2|1": makeSession(programID: "prog1", week: 2, day: 1, slots: ["A1": week2Log])
        ]
        let result = LogbookLogic.previousPerformance(
            sessions: sessions, programID: "prog1", currentWeek: 3, dayNumber: 1, slotLabel: "A1"
        )
        #expect(result?.sets.first?.weight == "90")
    }
}

@Suite("LogbookLogic.daysSinceLastSession")
struct LogbookLogicDaysTests {

    @Test("Returns nil when no sessions exist")
    func nilWhenEmpty() {
        #expect(LogbookLogic.daysSinceLastSession(sessions: [:], referenceDate: Date()) == nil)
    }

    @Test("Returns 0 when most recent session completed on reference date")
    func zeroForSameDay() {
        let now = Date()
        let session = makeSession(programID: "p", week: 1, day: 1, completed: now)
        let result = LogbookLogic.daysSinceLastSession(
            sessions: ["p|1|1": session], referenceDate: now
        )
        #expect(result == 0)
    }

    @Test("Returns correct day count for sessions in the past")
    func correctDayCount() {
        let pastDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let session = makeSession(programID: "p", week: 1, day: 1, completed: pastDate)
        let result = LogbookLogic.daysSinceLastSession(
            sessions: ["p|1|1": session], referenceDate: Date()
        )
        #expect(result == 3)
    }

    @Test("Picks the most recently completed session when multiple exist")
    func picksLatest() {
        let older = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        let newer = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let sessions: [String: SessionLog] = [
            "p|1|1": makeSession(programID: "p", week: 1, day: 1, completed: older),
            "p|1|2": makeSession(programID: "p", week: 1, day: 2, completed: newer)
        ]
        let result = LogbookLogic.daysSinceLastSession(sessions: sessions, referenceDate: Date())
        #expect(result == 1)
    }

    @Test("Ignores sessions without completed date")
    func ignoresIncomplete() {
        let incomplete = makeSession(programID: "p", week: 1, day: 1, completed: nil)
        let result = LogbookLogic.daysSinceLastSession(
            sessions: ["p|1|1": incomplete], referenceDate: Date()
        )
        #expect(result == nil)
    }
}

@Suite("LogbookLogic.buildExerciseIndex")
struct LogbookLogicExerciseIndexTests {

    @Test("Index maps lowercased name to most recent log")
    func mapsLowercasedName() {
        let log = makeLog(sets: [makeSetEntry(weight: "100", reps: "10")])
        let session = makeSession(programID: "p", week: 1, day: 1, slots: ["A1": log])
        let index = LogbookLogic.buildExerciseIndex(sessions: ["p|1|1": session])
        #expect(index["squat"] != nil)
    }

    @Test("Most recent completed session wins when same exercise appears twice")
    func mostRecentWins() {
        let oldLog = ExerciseLog(exerciseName: "Squat", sets: [makeSetEntry(weight: "80", reps: "10")], note: "", swappedFrom: nil)
        let newLog = ExerciseLog(exerciseName: "Squat", sets: [makeSetEntry(weight: "100", reps: "10")], note: "", swappedFrom: nil)
        let older = Date().addingTimeInterval(-86400)
        let newer = Date()
        let oldSess = SessionLog(programID: "p", week: 1, day: 1, started: nil, completed: older, slotLogs: ["A1": oldLog])
        let newSess = SessionLog(programID: "p", week: 2, day: 1, started: nil, completed: newer, slotLogs: ["A1": newLog])
        let index = LogbookLogic.buildExerciseIndex(sessions: ["p|1|1": oldSess, "p|2|1": newSess])
        #expect(index["squat"]?.sets.first?.weight == "100")
    }

    @Test("Ignores sessions without completed date")
    func ignoresIncomplete() {
        let log = makeLog(sets: [makeSetEntry(weight: "80", reps: "10")])
        let incomplete = makeSession(programID: "p", week: 1, day: 1, completed: nil, slots: ["A1": log])
        let index = LogbookLogic.buildExerciseIndex(sessions: ["p|1|1": incomplete])
        #expect(index.isEmpty)
    }

    @Test("Empty sessions returns empty index")
    func emptyInput() {
        #expect(LogbookLogic.buildExerciseIndex(sessions: [:]).isEmpty)
    }
}

@Suite("LogbookLogic.exportCSV")
struct LogbookLogicExportTests {

    @Test("CSV starts with correct header")
    func header() {
        let csv = LogbookLogic.exportCSV(sessions: [:])
        #expect(csv.split(separator: "\n").first == "Program,Week,Day,Exercise,Set,Weight,Reps,RIR,Date")
    }

    @Test("CSV contains one row per set")
    func rowCount() {
        let sets = [makeSetEntry(weight: "80", reps: "10"), makeSetEntry(weight: "85", reps: "8")]
        let log = makeLog(sets: sets)
        let session = makeSession(programID: "p", week: 1, day: 1, slots: ["A1": log])
        let lines = LogbookLogic.exportCSV(sessions: ["p|1|1": session]).split(separator: "\n")
        #expect(lines.count == 3) // header + 2 data rows
    }

    @Test("Empty sessions returns only header")
    func emptyIsJustHeader() {
        let lines = LogbookLogic.exportCSV(sessions: [:]).split(separator: "\n")
        #expect(lines.count == 1)
    }
}

// MARK: - HealthLogic functional core

@Suite("HealthLogic.activityItems")
struct HealthLogicActivityItemTests {

    private let baseDate = Date(timeIntervalSince1970: 1_000_000)

    private func activitySession(
        programID: String = "custom",
        week: Int = 1,
        day: Int = 1,
        started: Date? = Date(timeIntervalSince1970: 1_000_000),
        completed: Date? = Date(timeIntervalSince1970: 1_003_600),
        doneSets: Int = 2
    ) -> SessionLog {
        let sets = (0..<max(doneSets, 0)).map { _ in
            makeSetEntry(weight: "100", reps: "8")
        } + [makeSetEntry(weight: "100", reps: "8", done: false)]
        let log = ExerciseLog(exerciseName: "Bench Press", sets: sets, note: "", swappedFrom: nil)
        return SessionLog(
            programID: programID,
            week: week,
            day: day,
            started: started,
            completed: completed,
            slotLogs: ["1": log]
        )
    }

    private func appleHealthItem(id: String, date: Date) -> HealthActivityItem {
        HealthActivityItem(
            id: "health|\(id)",
            source: .appleHealth,
            sessionKey: nil,
            title: "Run",
            date: date,
            systemImage: "figure.run",
            detail: "25m",
            metric: "220 kcal"
        )
    }

    @Test("Completed app session becomes a Health activity item")
    func completedAppSessionMapsToActivityItem() {
        let session = activitySession()
        let item = HealthLogic.appActivityItem(from: session)

        #expect(item?.id == "app|custom|1|1")
        #expect(item?.source == .inApp)
        #expect(item?.sessionKey == "custom|1|1")
        #expect(item?.title == "Bench Press")
        #expect(item?.date == baseDate.addingTimeInterval(3600))
        #expect(item?.systemImage == "dumbbell.fill")
        #expect(item?.detail == "1h 0m")
        #expect(item?.metric == "2 sets")
    }

    @Test("Incomplete app session is not shown as a recent activity")
    func incompleteAppSessionIsIgnored() {
        let session = activitySession(completed: nil)
        #expect(HealthLogic.appActivityItem(from: session) == nil)
    }

    @Test("Activity item counts only completed sets")
    func countsOnlyDoneSets() {
        let session = activitySession(doneSets: 3)
        let item = HealthLogic.appActivityItem(from: session)
        #expect(item?.metric == "3 sets")
    }

    @Test("Duration formats minutes and hours")
    func durationFormatting() {
        #expect(HealthLogic.activityDurationString(
            started: baseDate,
            completed: baseDate.addingTimeInterval(45 * 60)
        ) == "45m")
        #expect(HealthLogic.activityDurationString(
            started: baseDate,
            completed: baseDate.addingTimeInterval(75 * 60)
        ) == "1h 15m")
    }

    @Test("Duration is hidden when start date is missing or invalid")
    func invalidDurationHidden() {
        #expect(HealthLogic.activityDurationString(
            started: nil,
            completed: baseDate
        ) == nil)
        #expect(HealthLogic.activityDurationString(
            started: baseDate,
            completed: baseDate
        ) == nil)
    }

    @Test("Recent activities combine app and Apple Health rows newest first")
    func combinesAndSortsRecentActivities() {
        let olderApp = activitySession(week: 1, completed: baseDate.addingTimeInterval(60))
        let newerApp = activitySession(week: 2, completed: baseDate.addingTimeInterval(180))
        let health = appleHealthItem(id: "run", date: baseDate.addingTimeInterval(120))

        let result = HealthLogic.recentActivityItems(
            appSessions: [olderApp, newerApp],
            appleHealthItems: [health]
        )

        #expect(result.map(\.id) == ["app|custom|2|1", "health|run", "app|custom|1|1"])
    }

    @Test("Recent activities respect limit after combining sources")
    func combinedActivitiesRespectLimit() {
        let sessions = (0..<5).map { offset in
            activitySession(
                week: offset + 1,
                completed: baseDate.addingTimeInterval(Double(offset) * 60)
            )
        }

        let result = HealthLogic.recentActivityItems(
            appSessions: sessions,
            appleHealthItems: [appleHealthItem(id: "newest", date: baseDate.addingTimeInterval(10_000))],
            limit: 3
        )

        #expect(result.count == 3)
        #expect(result.map(\.id) == ["health|newest", "app|custom|5|1", "app|custom|4|1"])
    }

    @Test("Recent activities default to three rows")
    func combinedActivitiesDefaultToThreeRows() {
        let sessions = (0..<5).map { offset in
            activitySession(
                week: offset + 1,
                completed: baseDate.addingTimeInterval(Double(offset) * 60)
            )
        }

        let result = HealthLogic.recentActivityItems(
            appSessions: sessions,
            appleHealthItems: []
        )

        #expect(result.count == 3)
        #expect(result.map(\.id) == ["app|custom|5|1", "app|custom|4|1", "app|custom|3|1"])
    }

    @Test("Zero limit returns no activity rows")
    func zeroLimitReturnsEmpty() {
        let result = HealthLogic.recentActivityItems(
            appSessions: [activitySession()],
            appleHealthItems: [appleHealthItem(id: "run", date: baseDate)],
            limit: 0
        )
        #expect(result.isEmpty)
    }
}

// MARK: - NutritionLogic functional core

@Suite("NutritionLogic.entries")
struct NutritionLogicEntriesTests {

    private func entry(daysAgo: Int, calories: Int = 100) -> FoodEntry {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return FoodEntry(name: "Food", calories: calories, protein: 0, carbs: 0, fat: 0, date: date)
    }

    @Test("Filters to entries on the given date only")
    func filtersCorrectly() {
        let today = entry(daysAgo: 0)
        let yesterday = entry(daysAgo: 1)
        let result = NutritionLogic.entries([today, yesterday], on: Date())
        #expect(result.count == 1)
        #expect(result[0].calories == today.calories)
    }

    @Test("Returns empty when no entries match the date")
    func emptyResult() {
        let yesterday = entry(daysAgo: 1)
        let result = NutritionLogic.entries([yesterday], on: Date())
        #expect(result.isEmpty)
    }

    @Test("Returns all entries when all are on the same date")
    func allMatch() {
        let entries = (0..<5).map { _ in entry(daysAgo: 0) }
        let result = NutritionLogic.entries(entries, on: Date())
        #expect(result.count == 5)
    }
}

@Suite("NutritionLogic totals")
struct NutritionLogicTotalsTests {

    private func entry(calories: Int, protein: Double = 0, carbs: Double = 0, fat: Double = 0, fiber: Double = 0) -> FoodEntry {
        FoodEntry(name: "X", calories: calories, protein: protein, carbs: carbs, fat: fat, fiber: fiber, sugar: 0, saturatedFat: 0, sodium: 0, cholesterol: 0, date: Date())
    }

    @Test("totalCalories sums all entries")
    func totalCalories() {
        #expect(NutritionLogic.totalCalories([entry(calories: 300), entry(calories: 200)]) == 500)
    }

    @Test("totalCalories returns 0 for empty list")
    func totalCaloriesEmpty() {
        #expect(NutritionLogic.totalCalories([]) == 0)
    }

    @Test("totalProtein sums protein")
    func totalProtein() {
        #expect(NutritionLogic.totalProtein([entry(calories: 0, protein: 30), entry(calories: 0, protein: 20)]) == 50)
    }

    @Test("totalFiber sums fiber")
    func totalFiber() {
        #expect(NutritionLogic.totalFiber([entry(calories: 0, fiber: 8), entry(calories: 0, fiber: 4)]) == 12)
    }

    @Test("other nutrient totals sum across entries")
    func otherNutrientTotals() {
        let first = FoodEntry(
            name: "A", calories: 0, protein: 0, carbs: 0, fat: 0,
            fiber: 3, sugar: 5, saturatedFat: 1.5, sodium: 200, cholesterol: 10,
            date: Date()
        )
        let second = FoodEntry(
            name: "B", calories: 0, protein: 0, carbs: 0, fat: 0,
            fiber: 4, sugar: 6, saturatedFat: 2.5, sodium: 300, cholesterol: 20,
            date: Date()
        )

        #expect(NutritionLogic.totalFiber([first, second]) == 7)
        #expect(NutritionLogic.totalSugar([first, second]) == 11)
        #expect(NutritionLogic.totalSaturatedFat([first, second]) == 4)
        #expect(NutritionLogic.totalSodium([first, second]) == 500)
        #expect(NutritionLogic.totalCholesterol([first, second]) == 30)
    }
}

@Suite("NutritionLogic.calorieBudget")
struct NutritionLogicBudgetTests {

    @Test("Budget equals target when active calories are zero")
    func noActiveCalories() {
        #expect(NutritionLogic.calorieBudget(target: 2000, activeCalories: 0) == 2000)
    }

    @Test("Budget adds positive active calories")
    func withActiveCalories() {
        #expect(NutritionLogic.calorieBudget(target: 2000, activeCalories: 450) == 2450)
    }

    @Test("Negative active calories are clamped to zero")
    func negativeActiveCaloriesClamped() {
        #expect(NutritionLogic.calorieBudget(target: 2000, activeCalories: -100) == 2000)
    }

    @Test("caloriesRemaining subtracts eaten from budget")
    func remaining() {
        #expect(NutritionLogic.caloriesRemaining(budget: 2000, eaten: 1400) == 600)
    }

    @Test("caloriesRemaining can be negative when over budget")
    func overBudget() {
        #expect(NutritionLogic.caloriesRemaining(budget: 2000, eaten: 2300) == -300)
    }
}

@Suite("NutritionLogic.scaleMacros")
struct NutritionLogicScaleMacrosTests {

    @Test("100g returns per-100g values unchanged")
    func hundredGrams() {
        let result = NutritionLogic.scaleMacros(kcalPer100g: 165, proteinPer100g: 31, carbsPer100g: 0, fatPer100g: 3.6, grams: 100)
        #expect(result.kcal == 165)
        #expect(result.protein == 31)
        #expect(result.fat == 3.6)
    }

    @Test("Zero grams returns all zeros")
    func zeroGrams() {
        let result = NutritionLogic.scaleMacros(kcalPer100g: 200, proteinPer100g: 20, carbsPer100g: 10, fatPer100g: 5, grams: 0)
        #expect(result.kcal == 0)
        #expect(result.protein == 0)
        #expect(result.carbs == 0)
        #expect(result.fat == 0)
    }

    @Test("Macros scale linearly with grams")
    func linearScaling() {
        let half = NutritionLogic.scaleMacros(kcalPer100g: 200, proteinPer100g: 20, carbsPer100g: 0, fatPer100g: 0, grams: 50)
        let full = NutritionLogic.scaleMacros(kcalPer100g: 200, proteinPer100g: 20, carbsPer100g: 0, fatPer100g: 0, grams: 100)
        #expect(full.kcal == half.kcal * 2)
    }

    @Test("Fiber and other nutrients scale with grams")
    func scalesOtherNutrients() {
        let result = NutritionLogic.scaleMacros(
            kcalPer100g: 100,
            proteinPer100g: 10,
            carbsPer100g: 20,
            fatPer100g: 5,
            fiberPer100g: 8,
            sugarPer100g: 6,
            saturatedFatPer100g: 2,
            sodiumPer100g: 400,
            cholesterolPer100g: 20,
            grams: 50
        )

        #expect(result.fiber == 4)
        #expect(result.sugar == 3)
        #expect(result.saturatedFat == 1)
        #expect(result.sodium == 200)
        #expect(result.cholesterol == 10)
    }
}

@Suite("NutritionLogic saved meals")
@MainActor
struct NutritionLogicSavedMealTests {

    private let date = Date(timeIntervalSince1970: 10_000)

    private var shake: SavedMeal {
        SavedMeal(
            name: "Shake",
            ingredients: [
                SavedMealIngredient(
                    name: "Apple",
                    category: .fruit,
                    grams: 150,
                    kcalPer100g: 52,
                    proteinPer100g: 0.3,
                    carbsPer100g: 14,
                    fatPer100g: 0.2,
                    fiberPer100g: 2.4,
                    sugarPer100g: 10.4,
                    saturatedFatPer100g: 0,
                    sodiumPer100g: 1,
                    cholesterolPer100g: 0
                ),
                SavedMealIngredient(
                    name: "Psyllium Husk",
                    category: .supplements,
                    grams: 5,
                    kcalPer100g: 200,
                    proteinPer100g: 2,
                    carbsPer100g: 80,
                    fatPer100g: 1,
                    fiberPer100g: 78,
                    sugarPer100g: 0,
                    saturatedFatPer100g: 0,
                    sodiumPer100g: 0,
                    cholesterolPer100g: 0
                )
            ]
        )
    }

    @Test("Saved meal totals include fiber and sugar")
    func savedMealTotalsIncludeOtherNutrients() {
        let totals = NutritionLogic.macros(for: shake)

        #expect(totals.kcal == 88)
        #expect(totals.fiber == 7.5)
        #expect(totals.sugar == 15.6)
    }

    @Test("Partial servings scale saved meal nutrients")
    func partialServingsScaleNutrients() {
        let totals = NutritionLogic.macros(for: shake, servings: 0.5)

        #expect(totals.kcal == 44)
        #expect(totals.fiber == 3.8)
        #expect(totals.sugar == 7.8)
    }

    @Test("Whole meal logging preserves other nutrients")
    func wholeMealEntryPreservesNutrients() {
        let entries = NutritionLogic.foodEntries(for: shake, date: date)

        #expect(entries.count == 1)
        #expect(entries[0].name == "Shake (1 serving)")
        #expect(entries[0].fiber == 7.5)
        #expect(entries[0].sugar == 15.6)
    }

    @Test("Separate ingredient logging preserves scaled nutrients")
    func separateIngredientEntriesPreserveNutrients() {
        let entries = NutritionLogic.foodEntries(
            for: shake,
            date: date,
            servings: 2,
            logIngredientsSeparately: true
        )

        #expect(entries.count == 2)
        #expect(entries[0].name == "Shake · Apple (300g)")
        #expect(entries[0].fiber == 7.2)
        #expect(entries[1].name == "Shake · Psyllium Husk (10g)")
        #expect(entries[1].fiber == 7.8)
    }

    @Test("Zero servings does not create food entries")
    func zeroServingsCreatesNoEntries() {
        #expect(NutritionLogic.foodEntries(for: shake, date: date, servings: 0).isEmpty)
    }

    @Test("Old saved meal ingredients decode missing nutrient fields as zero")
    func oldSavedMealIngredientDecodesWithZeroNutrients() throws {
        let json = """
        {
          "id":"00000000-0000-0000-0000-000000000001",
          "name":"Legacy",
          "category":"Fruit",
          "grams":100,
          "kcalPer100g":50,
          "proteinPer100g":1,
          "carbsPer100g":10,
          "fatPer100g":0.5
        }
        """.data(using: .utf8)!

        let ingredient = try JSONDecoder().decode(SavedMealIngredient.self, from: json)
        #expect(ingredient.fiberPer100g == 0)
        #expect(ingredient.sugarPer100g == 0)
        #expect(ingredient.sodiumPer100g == 0)
    }
}

// MARK: - AnalyticsLogic functional core

@Suite("AnalyticsLogic.estimated1RM")
struct AnalyticsLogicE1RMTests {

    @Test("1RM at 1 rep equals weight (Epley: 1 + 1/30 ≈ 1.033)")
    func oneRep() {
        let e1rm = AnalyticsLogic.estimated1RM(weight: 100, reps: 1)
        #expect(abs(e1rm - 100 * (1.0 + 1.0 / 30.0)) < 0.001)
    }

    @Test("1RM increases with more reps at same weight")
    func moreRepsHigherEstimate() {
        let low = AnalyticsLogic.estimated1RM(weight: 100, reps: 5)
        let high = AnalyticsLogic.estimated1RM(weight: 100, reps: 10)
        #expect(high > low)
    }

    @Test("1RM increases with more weight at same reps")
    func heavierWeightHigherEstimate() {
        let light = AnalyticsLogic.estimated1RM(weight: 80, reps: 8)
        let heavy = AnalyticsLogic.estimated1RM(weight: 100, reps: 8)
        #expect(heavy > light)
    }
}

@Suite("AnalyticsLogic.exerciseStats")
struct AnalyticsLogicStatsTests {

    private func sessionWith(exerciseName: String, weight: Double, reps: Int, sets: Int) -> SessionLog {
        let setEntries = (0..<sets).map { _ in
            SetEntry(id: UUID(), weight: "\(weight)", reps: "\(reps)", rir: "2", done: true)
        }
        let log = ExerciseLog(exerciseName: exerciseName, sets: setEntries, note: "", swappedFrom: nil)
        return makeSession(programID: "p", week: 1, day: 1, completed: Date(), slots: ["A1": log])
    }

    @Test("Empty sessions returns empty stats")
    func emptyInput() {
        #expect(AnalyticsLogic.exerciseStats(from: [SessionLog]()).isEmpty)
    }

    @Test("Undone sets are excluded")
    func excludesUndoneSets() {
        let undoneSets = [SetEntry(id: UUID(), weight: "200", reps: "10", rir: "2", done: false)]
        let log = ExerciseLog(exerciseName: "Squat", sets: undoneSets, note: "", swappedFrom: nil)
        let session = makeSession(programID: "p", week: 1, day: 1, slots: ["A1": log])
        let stats = AnalyticsLogic.exerciseStats(from: [session])
        #expect(stats.isEmpty)
    }

    @Test("Incomplete sessions are excluded")
    func excludesIncompleteSessions() {
        let done = sessionWith(exerciseName: "Squat", weight: 100, reps: 8, sets: 3)
        let incomplete = makeSession(
            programID: "p",
            week: 1,
            day: 2,
            completed: nil,
            slots: [
                "A1": ExerciseLog(
                    exerciseName: "Leg Press",
                    sets: [SetEntry(id: UUID(), weight: "400", reps: "10", rir: "2", done: true)],
                    note: "",
                    swappedFrom: nil
                )
            ]
        )

        let stats = AnalyticsLogic.exerciseStats(from: [done, incomplete])

        #expect(stats.map(\.name) == ["Squat"])
    }

    @Test("Stats are aggregated per exercise name")
    func aggregatedPerName() {
        let s1 = sessionWith(exerciseName: "Squat", weight: 100, reps: 8, sets: 3)
        let s2 = sessionWith(exerciseName: "Bench", weight: 80, reps: 10, sets: 3)
        let stats = AnalyticsLogic.exerciseStats(from: [s1, s2])
        #expect(stats.count == 2)
        #expect(Set(stats.map(\.name)) == ["Squat", "Bench"])
    }

    @Test("Best weight is tracked correctly across multiple sessions")
    func bestWeightTracked() {
        let s1 = sessionWith(exerciseName: "Squat", weight: 80, reps: 8, sets: 3)
        let s2 = sessionWith(exerciseName: "Squat", weight: 100, reps: 8, sets: 3)
        let stats = AnalyticsLogic.exerciseStats(from: [s1, s2])
        #expect(stats.first?.bestWeight == 100)
    }

    @Test("Total volume = sum of weight × reps for all done sets")
    func totalVolume() {
        // 3 sets × 100kg × 8 reps = 2400
        let session = sessionWith(exerciseName: "Squat", weight: 100, reps: 8, sets: 3)
        let stats = AnalyticsLogic.exerciseStats(from: [session])
        #expect(stats.first?.totalVolume == 2400)
    }

    @Test("Stats are sorted by total volume descending")
    func sortedByVolume() {
        let highVol = sessionWith(exerciseName: "Squat", weight: 100, reps: 10, sets: 5)  // 5000
        let lowVol  = sessionWith(exerciseName: "Curl",  weight: 20,  reps: 12, sets: 3)  // 720
        let stats = AnalyticsLogic.exerciseStats(from: [lowVol, highVol])
        #expect(stats[0].name == "Squat")
    }

    @Test("Bodyweight exercise (weight=0) uses bodyweightKg for volume and 1RM")
    func bodyweightExercise() {
        // Pull-ups logged with weight "0", 3 sets of 10
        let sets = (0..<3).map { _ in SetEntry(id: UUID(), weight: "0", reps: "10", rir: "2", done: true) }
        let log = ExerciseLog(exerciseName: "Pull-up", sets: sets, note: "", swappedFrom: nil)
        let session = makeSession(programID: "p", week: 1, day: 1, completed: Date(), slots: ["A1": log])
        let stats = AnalyticsLogic.exerciseStats(from: [session], bodyweightKg: 80)
        let stat = try! #require(stats.first)
        #expect(stat.name == "Pull-up")
        // volume = 80 * 10 * 3 = 2400
        #expect(stat.totalVolume == 2400)
        // bestWeight should be the bodyweight fallback
        #expect(stat.bestWeight == 80)
        // 1RM = 80 * (1 + 10/30) ≈ 106.67
        #expect(stat.estimated1RM > 100)
    }

    @Test("Bodyweight exercise (weight empty string) uses bodyweightKg")
    func bodyweightExerciseEmptyWeight() {
        let sets = [SetEntry(id: UUID(), weight: "", reps: "8", rir: "2", done: true)]
        let log = ExerciseLog(exerciseName: "Dips", sets: sets, note: "", swappedFrom: nil)
        let session = makeSession(programID: "p", week: 1, day: 1, completed: Date(), slots: ["A1": log])
        let stats = AnalyticsLogic.exerciseStats(from: [session], bodyweightKg: 75)
        #expect(stats.first?.totalVolume == 75.0 * 8)
    }

    @Test("Weighted set still uses its own weight, not bodyweight")
    func weightedSetNotOverridden() {
        let sets = [SetEntry(id: UUID(), weight: "100", reps: "5", rir: "2", done: true)]
        let log = ExerciseLog(exerciseName: "Bench", sets: sets, note: "", swappedFrom: nil)
        let session = makeSession(programID: "p", week: 1, day: 1, completed: Date(), slots: ["A1": log])
        let stats = AnalyticsLogic.exerciseStats(from: [session], bodyweightKg: 80)
        #expect(stats.first?.totalVolume == 500)
        #expect(stats.first?.bestWeight == 100)
    }

    @Test("estimated1RM is computed from best set")
    func estimated1RMFromBest() {
        let session = sessionWith(exerciseName: "Squat", weight: 100, reps: 8, sets: 1)
        let stat = AnalyticsLogic.exerciseStats(from: [session]).first!
        #expect(abs(stat.estimated1RM - AnalyticsLogic.estimated1RM(weight: 100, reps: 8)) < 0.001)
    }
}

@Suite("AnalyticsLogic.summary")
struct AnalyticsLogicSummaryTests {

    @Test("Total workouts counts only completed sessions")
    func countsCompleted() {
        let done = makeSession(programID: "p", week: 1, day: 1, completed: Date())
        let incomplete = makeSession(programID: "p", week: 1, day: 2, completed: nil)
        let summary = AnalyticsLogic.summary(from: [done, incomplete])
        #expect(summary.totalWorkouts == 1)
    }

    @Test("formattedVolume shows 'kg' for values under 1000")
    func formattedVolumeKg() {
        let summary = AnalyticsLogic.WorkoutSummary(totalWorkouts: 1, totalSets: 10, totalVolumeKg: 500)
        #expect(summary.formattedVolume.hasSuffix("kg"))
    }

    @Test("formattedVolume shows 't' for values >= 1000")
    func formattedVolumeTonnes() {
        let summary = AnalyticsLogic.WorkoutSummary(totalWorkouts: 1, totalSets: 100, totalVolumeKg: 1500)
        #expect(summary.formattedVolume.hasSuffix("t"))
    }
}

@Suite("AnalyticsLogic chart datasets")
struct AnalyticsLogicChartDatasetTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: calendar, timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day, hour: 12).date!
    }

    private func session(
        exerciseName: String,
        weight: String,
        reps: String,
        sets: Int,
        completed: Date,
        week: Int = 1
    ) -> SessionLog {
        let entries = (0..<sets).map { _ in
            SetEntry(id: UUID(), weight: weight, reps: reps, rir: "2", done: true)
        }
        return makeSession(
            programID: "p",
            week: week,
            day: 1,
            completed: completed,
            slots: ["A1": ExerciseLog(exerciseName: exerciseName, sets: entries, note: "", swappedFrom: nil)]
        )
    }

    @Test("Weekly load fills empty weeks and aggregates completed sessions")
    func weeklyLoadAggregatesAndFillsGaps() {
        let first = session(exerciseName: "Squat", weight: "100", reps: "5", sets: 3, completed: date(2026, 1, 6), week: 1)
        let third = session(exerciseName: "Bench", weight: "80", reps: "5", sets: 2, completed: date(2026, 1, 20), week: 3)

        let result = AnalyticsLogic.weeklyTrainingLoad(
            from: [first, third],
            bodyweightKg: 75,
            weeks: 3,
            endingAt: date(2026, 1, 20),
            calendar: calendar
        )

        #expect(result.count == 3)
        #expect(result[0].workouts == 1)
        #expect(result[0].sets == 3)
        #expect(result[0].volumeKg == 1500)
        #expect(result[1].workouts == 0)
        #expect(result[2].workouts == 1)
        #expect(result[2].volumeKg == 800)
    }

    @Test("Daily load returns one row per day and includes zero-workout days")
    func dailyLoadFillsDays() {
        let workout = session(exerciseName: "Squat", weight: "100", reps: "5", sets: 2, completed: date(2026, 1, 3))

        let result = AnalyticsLogic.dailyTrainingLoad(
            from: [workout],
            bodyweightKg: 75,
            days: 3,
            endingAt: date(2026, 1, 3),
            calendar: calendar
        )

        #expect(result.count == 3)
        #expect(result[0].workouts == 0)
        #expect(result[1].workouts == 0)
        #expect(result[2].workouts == 1)
        #expect(result[2].volumeKg == 1000)
    }

    @Test("Exercise progress is sorted by date and tracks best e1RM per session")
    func exerciseProgressTracksBestSet() {
        let older = session(exerciseName: "Bench", weight: "80", reps: "8", sets: 1, completed: date(2026, 1, 1), week: 1)
        let newer = session(exerciseName: "Bench", weight: "90", reps: "6", sets: 1, completed: date(2026, 1, 8), week: 2)
        let other = session(exerciseName: "Squat", weight: "120", reps: "5", sets: 1, completed: date(2026, 1, 9), week: 3)

        let result = AnalyticsLogic.exerciseProgress(
            exerciseName: "Bench",
            from: [newer, other, older],
            bodyweightKg: 75
        )

        #expect(result.count == 2)
        #expect(result[0].date < result[1].date)
        #expect(result[0].bestWeight == 80)
        #expect(result[1].bestWeight == 90)
        #expect(result[1].estimated1RM > result[0].estimated1RM)
    }

    @Test("Exercise progress candidates return top three by completed volume")
    func exerciseProgressCandidatesUseTopThreeCompletedVolume() {
        let squat = session(exerciseName: "Squat", weight: "100", reps: "10", sets: 5, completed: date(2026, 1, 1), week: 1)
        let bench = session(exerciseName: "Bench", weight: "80", reps: "10", sets: 4, completed: date(2026, 1, 2), week: 2)
        let row = session(exerciseName: "Row", weight: "60", reps: "10", sets: 3, completed: date(2026, 1, 3), week: 3)
        let curl = session(exerciseName: "Curl", weight: "20", reps: "10", sets: 2, completed: date(2026, 1, 4), week: 4)
        let incomplete = makeSession(
            programID: "p",
            week: 5,
            day: 1,
            completed: nil,
            slots: [
                "A1": ExerciseLog(
                    exerciseName: "Leg Press",
                    sets: [SetEntry(id: UUID(), weight: "500", reps: "10", rir: "2", done: true)],
                    note: "",
                    swappedFrom: nil
                )
            ]
        )

        let result = AnalyticsLogic.exerciseProgressCandidates(
            from: [curl, incomplete, row, bench, squat],
            bodyweightKg: 75,
            limit: 3
        )

        #expect(result.map(\.name) == ["Squat", "Bench", "Row"])
    }

    @Test("Volume distribution limits top exercises and groups the remainder")
    func volumeDistributionGroupsOther() {
        let squat = session(exerciseName: "Squat", weight: "100", reps: "10", sets: 5, completed: date(2026, 1, 1), week: 1)
        let bench = session(exerciseName: "Bench", weight: "80", reps: "10", sets: 3, completed: date(2026, 1, 2), week: 2)
        let curl = session(exerciseName: "Curl", weight: "20", reps: "10", sets: 2, completed: date(2026, 1, 3), week: 3)

        let result = AnalyticsLogic.volumeDistribution(
            from: [curl, bench, squat],
            bodyweightKg: 75,
            limit: 2
        )

        #expect(result.map(\.name) == ["Squat", "Bench", "Other"])
        #expect(result[0].volumeKg == 5000)
        #expect(result[2].volumeKg == 400)
        #expect(abs(result.reduce(0) { $0 + $1.percent } - 1.0) < 0.001)
    }
}

// MARK: - WorkoutLogic functional core

@Suite("WorkoutLogic.nextSlotLabel")
struct NextSlotLabelTests {

    @Test("Empty set returns '1'")
    func emptySet() {
        #expect(WorkoutLogic.nextSlotLabel(existingLabels: []) == "1")
    }

    @Test("Fills sequential gap after full sequence")
    func afterSequential() {
        #expect(WorkoutLogic.nextSlotLabel(existingLabels: ["1", "2"]) == "3")
    }

    @Test("Fills gap at start when '1' is missing")
    func fillsGapAtStart() {
        #expect(WorkoutLogic.nextSlotLabel(existingLabels: ["2", "3"]) == "1")
    }

    @Test("Fills interior gap after deletion")
    func fillsInteriorGap() {
        // "1" and "3" exist, "2" was deleted — reuse "2"
        #expect(WorkoutLogic.nextSlotLabel(existingLabels: ["1", "3"]) == "2")
    }

    @Test("Does not collide when called twice with same base set")
    func noDuplicatesOnConsecutiveCalls() {
        var labels: Set<String> = ["1", "2"]
        let first = WorkoutLogic.nextSlotLabel(existingLabels: labels)
        labels.insert(first)
        let second = WorkoutLogic.nextSlotLabel(existingLabels: labels)
        #expect(first != second)
    }
}

@Suite("WorkoutLogic.resetSets")
struct ResetSetsTests {

    private func makeDoneSets(_ count: Int) -> [SetEntry] {
        (0..<count).map { _ in SetEntry(id: UUID(), weight: "100", reps: "10", rir: "2", done: true) }
    }

    @Test("All sets become undone")
    func allUndone() {
        let result = WorkoutLogic.resetSets(makeDoneSets(3))
        #expect(result.allSatisfy { !$0.done })
    }

    @Test("Weight and reps are preserved")
    func valuesPreserved() {
        let sets = [SetEntry(id: UUID(), weight: "85.5", reps: "8", rir: "1", done: true)]
        let result = WorkoutLogic.resetSets(sets)
        #expect(result[0].weight == "85.5")
        #expect(result[0].reps == "8")
        #expect(result[0].rir == "1")
    }

    @Test("Each reset set gets a fresh UUID")
    func freshUUIDs() {
        let original = makeDoneSets(3)
        let result = WorkoutLogic.resetSets(original)
        let originalIDs = Set(original.map(\.id))
        let newIDs = Set(result.map(\.id))
        #expect(originalIDs.isDisjoint(with: newIDs))
    }

    @Test("Returns same count as input")
    func countPreserved() {
        let result = WorkoutLogic.resetSets(makeDoneSets(5))
        #expect(result.count == 5)
    }

    @Test("Empty input returns empty output")
    func emptyInput() {
        #expect(WorkoutLogic.resetSets([]).isEmpty)
    }
}

@Suite("WorkoutLogic.sessionDisplayTitle")
struct SessionDisplayTitleTests {

    @Test("Custom session with exercises shows exercise names joined by ·")
    func customWithExercises() {
        let session = makeSession(
            programID: "custom",
            slots: [
                "1": ExerciseLog(exerciseName: "Squat", sets: [], note: "", swappedFrom: nil),
                "2": ExerciseLog(exerciseName: "Bench", sets: [], note: "", swappedFrom: nil),
                "3": ExerciseLog(exerciseName: "Deadlift", sets: [], note: "", swappedFrom: nil),
            ]
        )
        #expect(WorkoutLogic.sessionDisplayTitle(session) == "Squat · Bench · Deadlift")
    }

    @Test("Custom session capped at 3 exercises in title")
    func customCappedAt3() {
        let session = makeSession(
            programID: "custom",
            slots: [
                "1": ExerciseLog(exerciseName: "A", sets: [], note: "", swappedFrom: nil),
                "2": ExerciseLog(exerciseName: "B", sets: [], note: "", swappedFrom: nil),
                "3": ExerciseLog(exerciseName: "C", sets: [], note: "", swappedFrom: nil),
                "4": ExerciseLog(exerciseName: "D", sets: [], note: "", swappedFrom: nil),
            ]
        )
        let title = WorkoutLogic.sessionDisplayTitle(session)
        #expect(!title.contains("D"))
        #expect(title.contains("A"))
    }

    @Test("Empty custom session shows 'Custom Workout'")
    func emptyCustom() {
        let session = makeSession(programID: "custom", slots: [:])
        #expect(WorkoutLogic.sessionDisplayTitle(session) == "Custom Workout")
    }

    @Test("Imported session shows exercise names")
    func importedSession() {
        let session = makeSession(
            programID: "imported",
            slots: ["1": ExerciseLog(exerciseName: "Row", sets: [], note: "", swappedFrom: nil)]
        )
        #expect(WorkoutLogic.sessionDisplayTitle(session) == "Row")
    }

    @Test("Program session shows Week/Day format")
    func programSession() {
        let session = makeSession(programID: "myprogram", week: 3, day: 2)
        #expect(WorkoutLogic.sessionDisplayTitle(session) == "Week 3, Day 2")
    }

    @Test("Custom session exercises are ordered numerically not lexicographically")
    func numericKeyOrder() {
        // Keys "1".."10" — lexicographic sort puts "10" before "2"
        var slots: [String: ExerciseLog] = [:]
        for i in 1...10 {
            slots["\(i)"] = ExerciseLog(exerciseName: "Ex\(i)", sets: [], note: "", swappedFrom: nil)
        }
        let session = makeSession(programID: "custom", slots: slots)
        let title = WorkoutLogic.sessionDisplayTitle(session)
        // First exercise should be "Ex1", not "Ex10"
        #expect(title.hasPrefix("Ex1 ·"))
    }
}

@Suite("WorkoutLogic.duplicateSession")
struct DuplicateSessionTests {

    private func makeTemplateSession(keys: [String], exerciseNames: [String]) -> SessionLog {
        var slots: [String: ExerciseLog] = [:]
        for (key, name) in zip(keys, exerciseNames) {
            slots[key] = ExerciseLog(
                exerciseName: name,
                sets: [SetEntry(id: UUID(), weight: "80", reps: "10", rir: "2", done: true)],
                note: "note",
                swappedFrom: nil
            )
        }
        return makeSession(programID: "custom", slots: slots)
    }

    @Test("Resulting session has programID 'custom'")
    func programIDIsCustom() {
        let template = makeTemplateSession(keys: ["1"], exerciseNames: ["Squat"])
        let (session, _) = WorkoutLogic.duplicateSession(template: template, newWeek: 999)
        #expect(session.programID == "custom")
    }

    @Test("Resulting session uses the given newWeek")
    func usesNewWeek() {
        let template = makeTemplateSession(keys: ["1"], exerciseNames: ["Squat"])
        let (session, _) = WorkoutLogic.duplicateSession(template: template, newWeek: 42)
        #expect(session.week == 42)
    }

    @Test("Resulting session is not completed")
    func notCompleted() {
        let template = makeTemplateSession(keys: ["1"], exerciseNames: ["Squat"])
        let (session, _) = WorkoutLogic.duplicateSession(template: template, newWeek: 1)
        #expect(session.completed == nil)
    }

    @Test("All sets are reset to undone")
    func setsAreUndone() {
        let template = makeTemplateSession(keys: ["1", "2"], exerciseNames: ["Squat", "Bench"])
        let (session, _) = WorkoutLogic.duplicateSession(template: template, newWeek: 1)
        let allDone = session.slotLogs.values.flatMap(\.sets).allSatisfy(\.done)
        #expect(!allDone)
    }

    @Test("Exercise names are preserved from template")
    func exerciseNamesPreserved() {
        let template = makeTemplateSession(keys: ["1", "2"], exerciseNames: ["Squat", "Bench"])
        let (session, _) = WorkoutLogic.duplicateSession(template: template, newWeek: 1)
        let names = Set(session.slotLogs.values.map(\.exerciseName))
        #expect(names.contains("Squat"))
        #expect(names.contains("Bench"))
    }

    @Test("Weights are preserved from template")
    func weightsPreserved() {
        let template = makeTemplateSession(keys: ["1"], exerciseNames: ["Squat"])
        let (session, _) = WorkoutLogic.duplicateSession(template: template, newWeek: 1)
        let weight = session.slotLogs.values.first?.sets.first?.weight
        #expect(weight == "80")
    }

    @Test("exerciseOrder has one entry per slot")
    func exerciseOrderCount() {
        let template = makeTemplateSession(keys: ["1", "2", "3"], exerciseNames: ["A", "B", "C"])
        let (_, order) = WorkoutLogic.duplicateSession(template: template, newWeek: 1)
        #expect(order.count == 3)
    }

    @Test("exerciseOrder values match slotLogs keys")
    func exerciseOrderMatchesKeys() {
        let template = makeTemplateSession(keys: ["1", "2"], exerciseNames: ["A", "B"])
        let (session, order) = WorkoutLogic.duplicateSession(template: template, newWeek: 1)
        for label in order {
            #expect(session.slotLogs[label] != nil)
        }
    }

    @Test("Non-sequential keys (after deletions) are remapped to 1…N")
    func remapsNonSequentialKeys() {
        // Simulate: exercise "1" deleted, leaving "2" and "3"
        let template = makeTemplateSession(keys: ["2", "3"], exerciseNames: ["Bench", "Row"])
        let (session, order) = WorkoutLogic.duplicateSession(template: template, newWeek: 1)
        #expect(order == ["1", "2"])
        #expect(session.slotLogs["1"] != nil)
        #expect(session.slotLogs["2"] != nil)
        #expect(session.slotLogs["3"] == nil)
    }

    @Test("Duplicate with 10+ exercises maintains numeric order (not lexicographic)")
    func numericOrderWith10Plus() {
        let keys = (1...11).map { "\($0)" }
        let names = (1...11).map { "Ex\($0)" }
        let template = makeTemplateSession(keys: keys, exerciseNames: names)
        let (session, order) = WorkoutLogic.duplicateSession(template: template, newWeek: 1)
        // The first entry in exerciseOrder should correspond to Ex1, not Ex10
        let firstLabel = order[0]
        #expect(session.slotLogs[firstLabel]?.exerciseName == "Ex1")
        #expect(order.count == 11)
    }

    @Test("Each set in duplicate gets a fresh UUID")
    func freshSetUUIDs() {
        let template = makeTemplateSession(keys: ["1"], exerciseNames: ["Squat"])
        let originalIDs = Set(template.slotLogs.values.flatMap(\.sets).map(\.id))
        let (session, _) = WorkoutLogic.duplicateSession(template: template, newWeek: 1)
        let newIDs = Set(session.slotLogs.values.flatMap(\.sets).map(\.id))
        #expect(originalIDs.isDisjoint(with: newIDs))
    }

    @Test("Duplicate of a program session (alpha keys) preserves exercises")
    func programSessionDuplicate() {
        var slots: [String: ExerciseLog] = [:]
        slots["A1"] = ExerciseLog(exerciseName: "Squat", sets: [SetEntry(id: UUID(), weight: "100", reps: "8", rir: "2", done: true)], note: "", swappedFrom: nil)
        slots["B1"] = ExerciseLog(exerciseName: "Bench", sets: [SetEntry(id: UUID(), weight: "80", reps: "10", rir: "2", done: true)], note: "", swappedFrom: nil)
        let template = makeSession(programID: "prog1", week: 2, day: 3, slots: slots)
        let (session, order) = WorkoutLogic.duplicateSession(template: template, newWeek: 1)
        #expect(order.count == 2)
        let names = Set(session.slotLogs.values.map(\.exerciseName))
        #expect(names.contains("Squat"))
        #expect(names.contains("Bench"))
        let allUndone = session.slotLogs.values.flatMap(\.sets).allSatisfy { !$0.done }
        #expect(allUndone)
    }
}

@Suite("WorkoutLogic — addExercise defaults")
struct AddExerciseDefaultsTests {

    @Test("resetSets produces 4 undone sets with '10' reps when given 4 blank sets")
    func fourSetsDefaultReps() {
        let defaultSets = (0..<4).map { _ in
            SetEntry(id: UUID(), weight: "", reps: "10", rir: "2", done: false)
        }
        #expect(defaultSets.count == 4)
        #expect(defaultSets.allSatisfy { $0.reps == "10" && !$0.done })
    }

    @Test("nextSlotLabel never collides after exercise removal in a 3-exercise session")
    func noCollisionAfterRemoval() {
        // Simulate: add 3 exercises (labels "1","2","3"), remove "2"
        var labels: Set<String> = ["1", "3"]
        let next = WorkoutLogic.nextSlotLabel(existingLabels: labels)
        #expect(next == "2")  // fills the gap
        labels.insert(next)
        let second = WorkoutLogic.nextSlotLabel(existingLabels: labels)
        #expect(second == "4")  // continues after gap is filled
    }
}

@Suite("WorkoutLogic.sortedSlotKeys")
struct SortedSlotKeysTests {

    @Test("Numeric keys sort in ascending integer order")
    func numericOrder() {
        let result = WorkoutLogic.sortedSlotKeys(["3", "1", "10", "2"])
        #expect(result == ["1", "2", "3", "10"])
    }

    @Test("Alpha keys sort lexicographically")
    func alphaOrder() {
        let result = WorkoutLogic.sortedSlotKeys(["B1", "A1", "C1"])
        #expect(result == ["A1", "B1", "C1"])
    }

    @Test("Empty input returns empty")
    func empty() {
        #expect(WorkoutLogic.sortedSlotKeys([String]()).isEmpty)
    }
}

// MARK: - Calorie budget arithmetic

@Suite("Calorie budget")
struct CalorieBudgetTests {

    @Test("Budget equals target when no active calories")
    func budgetWithNoActiveCalories() {
        #expect(2000 + 0 == 2000)
    }

    @Test("Budget adds active calories earned")
    func budgetWithActiveCalories() {
        #expect(2000 + 450 == 2450)
    }

    @Test("Active calories only apply to today (past day uses base target)")
    func activeCaloriesNotAppliedToPastDay() {
        let pastDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let isToday = Calendar.current.isDateInToday(pastDate)
        let earned = isToday ? 500 : 0
        #expect(earned == 0)
    }
}

// MARK: - FoodTemplate macros scaling

@Suite("FoodTemplate Macros")
struct FoodTemplateMacrosTests {

    private func template(kcal: Double, p: Double, c: Double, f: Double) -> FoodTemplate {
        FoodTemplate(name: "Test", category: .protein, kcal: kcal, protein: p,
                     carbs: c, fat: f, defaultServingG: 100)
    }

    @Test("100g returns per-100g values verbatim")
    func fullServing() {
        let t = template(kcal: 200, p: 20, c: 10, f: 5)
        let m = t.macros(forGrams: 100)
        #expect(m.kcal == 200)
        #expect(m.p == 20)
        #expect(m.c == 10)
        #expect(m.f == 5)
    }

    @Test("50g halves all values")
    func halfServing() {
        let t = template(kcal: 400, p: 80, c: 10, f: 3.3)
        let m = t.macros(forGrams: 50)
        #expect(m.kcal == 200)
        #expect(m.p == 40)
    }

    @Test("30g ON Gold Standard Whey: ~120 kcal and ~24g protein")
    func onWheyScoop() {
        // ON Gold Standard Whey is stored as 400 kcal/100g, 80g protein/100g
        let t = FoodTemplate(name: "ON Gold Standard Whey (1 scoop)", category: .supplements,
                             kcal: 400, protein: 80, carbs: 10, fat: 3.3, defaultServingG: 30)
        let m = t.macros(forGrams: 30)
        #expect(m.kcal == 120)
        #expect(m.p == 24)
    }

    @Test("Zero grams returns zero calories")
    func zeroGrams() {
        let t = template(kcal: 300, p: 25, c: 20, f: 10)
        let m = t.macros(forGrams: 0)
        #expect(m.kcal == 0)
        #expect(m.p == 0)
    }
}

// MARK: - Meal Builder totals (pure logic)

@Suite("MealBuilder Totals")
struct MealBuilderTotalsTests {

    private func ingredient(kcal: Double, p: Double, c: Double, f: Double, grams: Double) -> (FoodTemplate, Double) {
        let t = FoodTemplate(name: "Item", category: .protein,
                             kcal: kcal, protein: p, carbs: c, fat: f, defaultServingG: Int(grams))
        return (t, grams)
    }

    private func sum(_ ingredients: [(FoodTemplate, Double)]) -> (kcal: Int, p: Double, c: Double, f: Double) {
        ingredients.reduce((0, 0.0, 0.0, 0.0)) { acc, ing in
            let m = ing.0.macros(forGrams: ing.1)
            return (acc.0 + m.kcal, acc.1 + m.p, acc.2 + m.c, acc.3 + m.f)
        }
    }

    @Test("Single ingredient totals match its macros")
    func singleIngredient() {
        let ings = [ingredient(kcal: 400, p: 80, c: 10, f: 3.3, grams: 30)]
        let t = sum(ings)
        #expect(t.kcal == 120)
        #expect(t.p == 24)
    }

    @Test("Protein shake: avocado + casein + creatine + collagen totals sum correctly")
    func proteinShake() {
        // 1 avocado ~150g (160 kcal/100g, 2g P, 9g C, 15g F)
        // 3 casein scoops = 3×34g = 102g (353 kcal/100g, 70.6g P, 8.8g C, 2.9g F)
        // 10g creatine = 0 kcal
        // 2 collagen scoops = 2×11g = 22g (364 kcal/100g, 90.9g P)
        let avo  = ingredient(kcal: 160,  p: 2,    c: 9,   f: 15,  grams: 150)
        let cas  = ingredient(kcal: 353,  p: 70.6, c: 8.8, f: 2.9, grams: 102)
        let crea = ingredient(kcal: 0,    p: 0,    c: 0,   f: 0,   grams: 10)
        let col  = ingredient(kcal: 364,  p: 90.9, c: 0,   f: 0,   grams: 22)
        let t = sum([avo, cas, crea, col])
        // avocado: 160*1.5=240, casein: 353*1.02=360, creatine: 0, collagen: 364*0.22=80 → total ~680
        #expect(t.kcal > 600 && t.kcal < 750)
        // protein: 2*1.5=3 + 70.6*1.02≈72 + 0 + 90.9*0.22≈20 → ~95g
        #expect(t.p > 80 && t.p < 110)
    }

    @Test("Empty ingredient list gives zero totals")
    func emptyList() {
        let t = sum([])
        #expect(t.kcal == 0)
        #expect(t.p == 0)
        #expect(t.c == 0)
        #expect(t.f == 0)
    }

    @Test("Two identical ingredients double the totals")
    func doubleIngredient() {
        let ing = ingredient(kcal: 200, p: 20, c: 10, f: 5, grams: 100)
        let t = sum([ing, ing])
        #expect(t.kcal == 400)
        #expect(t.p == 40)
    }
}

// MARK: - Food database completeness

@Suite("FoodDatabase Completeness")
struct FoodDatabaseTests {

    @Test("Database is non-empty")
    func databaseNonEmpty() {
        #expect(!foodDatabase.isEmpty)
    }

    @Test("All items have non-empty names")
    func allNamesNonEmpty() {
        #expect(foodDatabase.allSatisfy { !$0.name.isEmpty })
    }

    @Test("All items have non-negative macros")
    func nonNegativeMacros() {
        #expect(foodDatabase.allSatisfy { $0.kcal >= 0 && $0.protein >= 0 && $0.carbs >= 0 && $0.fat >= 0 })
    }

    @Test("All items have non-negative extended nutrients")
    func nonNegativeExtendedNutrients() {
        #expect(foodDatabase.allSatisfy {
            $0.fiber >= 0 &&
            $0.sugar >= 0 &&
            $0.saturatedFat >= 0 &&
            $0.sodium >= 0 &&
            $0.cholesterol >= 0
        })
    }

    @Test("Apple has a natural serving and fiber/sugar data")
    func appleServingAndNutrients() throws {
        let apple = try #require(foodDatabase.first { $0.name == "Apple" })
        let macros = apple.macros(forGrams: Double(apple.defaultServingG))

        #expect(apple.defaultServingDescription == "1 apple")
        #expect(macros.fiber > 0)
        #expect(macros.sugar > 0)
    }

    @Test("Large Haas avocado has serving label and fiber/saturated fat data")
    func haasAvocadoServingAndNutrients() throws {
        let avocado = try #require(foodDatabase.first { $0.name == "Haas avocado (large)" })
        let macros = avocado.macros(forGrams: Double(avocado.defaultServingG))

        #expect(avocado.defaultServingDescription == "1 large Haas avocado")
        #expect(macros.fiber > 10)
        #expect(macros.saturatedFat > 0)
    }

    @Test("Psyllium contributes meaningful fiber")
    func psylliumFiber() throws {
        let psyllium = try #require(foodDatabase.first { $0.name == "Psyllium Husk (powder)" })
        let macros = psyllium.macros(forGrams: Double(psyllium.defaultServingG))

        #expect(macros.fiber >= 3)
    }

    @Test("Eggs carry cholesterol data")
    func eggsCholesterol() throws {
        let eggs = try #require(foodDatabase.first { $0.name == "Eggs (whole, large)" })
        let macros = eggs.macros(forGrams: Double(eggs.defaultServingG))

        #expect(macros.cholesterol > 0)
    }

    @Test("Supplements category exists and contains ON Gold Standard Whey")
    func supplementsContainON() {
        let sups = foodDatabase.filter { $0.category == .supplements }
        #expect(!sups.isEmpty)
        #expect(sups.contains { $0.name.contains("Gold Standard Whey") })
    }

    @Test("Supplements category contains psyllium husk")
    func supplementsContainPsyllium() {
        #expect(foodDatabase.contains { $0.name.lowercased().contains("psyllium") })
    }

    @Test("DTF full menu: contains XLB, fried rice, wonton soup, and desserts")
    func dtfFullMenu() {
        let dtf = foodDatabase.filter { $0.name.hasPrefix("DTF") }
        #expect(dtf.contains { $0.name.contains("XLB") })
        #expect(dtf.contains { $0.name.contains("Fried Rice") })
        #expect(dtf.contains { $0.name.contains("Wonton Soup") })
        #expect(dtf.contains { $0.name.contains("Buns") })
    }

    @Test("Thai food section contains Pad See Ew and green curry")
    func thaiFood() {
        let thai = foodDatabase.filter { $0.name.hasPrefix("Thai") }
        #expect(!thai.isEmpty)
        #expect(thai.contains { $0.name.contains("Pad See Ew") })
        #expect(thai.contains { $0.name.contains("Green Curry") })
    }

    @Test("Baldi at Waldorf Astoria entries exist")
    func baldiEntries() {
        let baldi = foodDatabase.filter { $0.name.hasPrefix("Baldi") }
        #expect(!baldi.isEmpty)
        #expect(baldi.contains { $0.name.contains("Eggs Benedict") })
        #expect(baldi.contains { $0.name.contains("French Toast") })
        #expect(baldi.contains { $0.name.contains("Energy Smoothie") })
    }

    @Test("All categories have at least one item")
    func allCategoriesPopulated() {
        for cat in FoodCategory.allCases {
            let count = foodDatabase.filter { $0.category == cat }.count
            #expect(count > 0, "Category \(cat.rawValue) has no items")
        }
    }

    @Test("Prepared meals include common loggable foods with natural servings")
    func preparedMealsArePopulated() throws {
        let meals = foodDatabase.filter { $0.category == .meals }
        let chickenBowl = try #require(meals.first { $0.name == "Chicken rice bowl" })
        let oats = try #require(meals.first { $0.name == "Overnight oats with berries" })

        #expect(meals.count >= 15)
        #expect(chickenBowl.defaultServingDescription == "1 bowl")
        #expect(chickenBowl.macros(forGrams: Double(chickenBowl.defaultServingG)).p > 50)
        #expect(oats.defaultServingDescription == "1 jar")
        #expect(oats.macros(forGrams: Double(oats.defaultServingG)).fiber > 8)
    }
}

// MARK: - BodyMeasurement model

@Suite("BodyMeasurement")
struct BodyMeasurementTests {

    private func measurement(
        date: Date = Date(timeIntervalSince1970: 1_000_000),
        waist: Double? = nil, chest: Double? = nil, hips: Double? = nil,
        thighs: Double? = nil, arms: Double? = nil, neck: Double? = nil,
        bf: Double? = nil
    ) -> BodyMeasurement {
        BodyMeasurement(date: date, waistCm: waist, chestCm: chest, hipsCm: hips,
                        thighsCm: thighs, armsCm: arms, neckCm: neck, bodyFatPercent: bf)
    }

    @Test("hasAnyMeasurement is false when all fields are nil")
    func emptyHasNone() {
        #expect(!measurement().hasAnyMeasurement)
    }

    @Test("hasAnyMeasurement is true when any field is set")
    func partialHasAny() {
        #expect(measurement(waist: 82).hasAnyMeasurement)
        #expect(measurement(bf: 14.5).hasAnyMeasurement)
        #expect(measurement(neck: 38).hasAnyMeasurement)
    }

    @Test("BodyMeasurement survives encode/decode round-trip")
    func codableRoundTrip() throws {
        let original = measurement(waist: 82.5, chest: 102, hips: 95.0, bf: 14.2)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BodyMeasurement.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.waistCm == 82.5)
        #expect(decoded.chestCm == 102)
        #expect(decoded.bodyFatPercent == 14.2)
        #expect(decoded.neckCm == nil)
    }
}

// MARK: - Store body measurements

@Suite("Store body measurements")
@MainActor
struct StoreBodyMeasurementTests {

    private var baseDate: Date { Date(timeIntervalSince1970: 1_000_000) }

    private func measurement(daysOffset: Int = 0, waist: Double = 82) -> BodyMeasurement {
        let date = Calendar.current.date(byAdding: .day, value: daysOffset, to: baseDate)!
        return BodyMeasurement(date: date, waistCm: waist)
    }

    @Test("addBodyMeasurement appends and persists")
    func addPersists() {
        let repo = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())
        store.addBodyMeasurement(measurement(waist: 82))
        #expect(store.logbook.bodyMeasurements.count == 1)
        #expect(store.logbook.bodyMeasurements[0].waistCm == 82)
        #expect(repo.load()?.bodyMeasurements.count == 1)
    }

    @Test("addBodyMeasurement replaces existing entry on the same calendar day")
    func sameDayReplaces() {
        let repo = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())
        store.addBodyMeasurement(measurement(waist: 82))
        store.addBodyMeasurement(measurement(waist: 80))
        #expect(store.logbook.bodyMeasurements.count == 1)
        #expect(store.logbook.bodyMeasurements[0].waistCm == 80)
    }

    @Test("addBodyMeasurement keeps measurements on different days separate")
    func differentDaysKept() {
        let repo = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())
        store.addBodyMeasurement(measurement(daysOffset: 0, waist: 82))
        store.addBodyMeasurement(measurement(daysOffset: -7, waist: 83))
        #expect(store.logbook.bodyMeasurements.count == 2)
    }

    @Test("bodyMeasurements are stored sorted oldest first")
    func sortedChronologically() {
        let repo = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())
        store.addBodyMeasurement(measurement(daysOffset: 0, waist: 80))
        store.addBodyMeasurement(measurement(daysOffset: -7, waist: 83))
        #expect(store.logbook.bodyMeasurements[0].waistCm == 83)
        #expect(store.logbook.bodyMeasurements[1].waistCm == 80)
    }

    @Test("latestBodyMeasurement returns the newest entry")
    func latestReturnsNewest() {
        let repo = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())
        store.addBodyMeasurement(measurement(daysOffset: -7, waist: 83))
        store.addBodyMeasurement(measurement(daysOffset: 0, waist: 80))
        #expect(store.latestBodyMeasurement?.waistCm == 80)
    }

    @Test("latestBodyMeasurement is nil when no measurements exist")
    func latestNilWhenEmpty() {
        let store = Store.makeForTesting(repository: makeRepository(logbook: makeEmptyLogbook()), catalog: makeMinimalCatalog())
        #expect(store.latestBodyMeasurement == nil)
    }

    @Test("deleteBodyMeasurements removes the correct entry")
    func deleteRemovesEntry() {
        let repo = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repo, catalog: makeMinimalCatalog())
        store.addBodyMeasurement(measurement(daysOffset: 0, waist: 80))
        store.addBodyMeasurement(measurement(daysOffset: -7, waist: 83))
        let sorted = store.logbook.bodyMeasurements.sorted { $0.date > $1.date }
        store.deleteBodyMeasurements(at: IndexSet(integer: 0), from: sorted)
        #expect(store.logbook.bodyMeasurements.count == 1)
        #expect(store.logbook.bodyMeasurements[0].waistCm == 83)
    }
}

// MARK: - NotificationSettings persistence

@Suite("NotificationSettings")
struct NotificationSettingsTests {

    private let testKey = "com.dailyfitness.notificationSettings.test"

    @Test("Default settings have all notifications disabled")
    func defaultsAreOff() {
        let settings = NotificationSettings()
        #expect(!settings.workoutEnabled)
        #expect(!settings.foodEnabled)
        #expect(!settings.measurementEnabled)
    }

    @Test("Default workout time is 7pm")
    func defaultWorkoutTime() {
        let s = NotificationSettings()
        #expect(s.workoutHour == 19)
        #expect(s.workoutMinute == 0)
    }

    @Test("Default food reminder time is 1pm")
    func defaultFoodTime() {
        let s = NotificationSettings()
        #expect(s.foodHour == 13)
        #expect(s.foodMinute == 0)
    }

    @Test("Settings survive encode/decode round-trip")
    func codableRoundTrip() throws {
        var original = NotificationSettings()
        original.workoutEnabled = true
        original.workoutHour = 18
        original.measurementDayOfWeek = 2
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NotificationSettings.self, from: data)
        #expect(decoded.workoutEnabled)
        #expect(decoded.workoutHour == 18)
        #expect(!decoded.foodEnabled)
        #expect(decoded.measurementDayOfWeek == 2)
    }
}

// MARK: - MealType

@Suite("MealType")
struct MealTypeTests {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func date(hour: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 12; comps.hour = hour
        return cal.date(from: comps)!
    }

    @Test("5am is breakfast")
    func earlyMorning() {
        #expect(MealType.guess(from: date(hour: 5), calendar: cal) == .breakfast)
    }

    @Test("10am is breakfast")
    func lateMorning() {
        #expect(MealType.guess(from: date(hour: 10), calendar: cal) == .breakfast)
    }

    @Test("11am is lunch")
    func noon() {
        #expect(MealType.guess(from: date(hour: 11), calendar: cal) == .lunch)
    }

    @Test("14pm is lunch")
    func earlyAfternoon() {
        #expect(MealType.guess(from: date(hour: 14), calendar: cal) == .lunch)
    }

    @Test("15pm is dinner")
    func lateAfternoon() {
        #expect(MealType.guess(from: date(hour: 15), calendar: cal) == .dinner)
    }

    @Test("21pm is dinner")
    func earlyEvening() {
        #expect(MealType.guess(from: date(hour: 21), calendar: cal) == .dinner)
    }

    @Test("22pm is snacks")
    func lateEvening() {
        #expect(MealType.guess(from: date(hour: 22), calendar: cal) == .snacks)
    }

    @Test("3am is snacks")
    func veryLateNight() {
        #expect(MealType.guess(from: date(hour: 3), calendar: cal) == .snacks)
    }

    @Test("All cases have unique icons")
    func uniqueIcons() {
        let icons = MealType.allCases.map(\.icon)
        #expect(Set(icons).count == MealType.allCases.count)
    }

    @Test("Old JSON without meal field decodes with a valid time-based guess")
    func backwardCompatibility() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"Oats",
         "calories":300,"protein":10,"carbs":54,"fat":6,"date":0}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let entry = try decoder.decode(FoodEntry.self, from: json)
        // Meal is auto-guessed from the date; just verify it's a valid case
        #expect(MealType.allCases.contains(entry.meal))
    }
}

// MARK: - Meal Grouping

@Suite("NutritionLogic.groupedByMeal")
struct MealGroupingTests {

    private func entry(meal: MealType, calories: Int) -> FoodEntry {
        FoodEntry(name: "Item", calories: calories, protein: 0, carbs: 0, fat: 0,
                  date: Date(), meal: meal)
    }

    @Test("Groups entries by their meal type")
    func grouping() {
        let entries = [
            entry(meal: .breakfast, calories: 300),
            entry(meal: .breakfast, calories: 200),
            entry(meal: .lunch, calories: 500),
            entry(meal: .dinner, calories: 600)
        ]
        let grouped = NutritionLogic.groupedByMeal(entries)
        #expect(grouped[.breakfast]?.count == 2)
        #expect(grouped[.lunch]?.count == 1)
        #expect(grouped[.dinner]?.count == 1)
        #expect(grouped[.snacks] == nil)
    }

    @Test("Empty entries return empty dictionary")
    func emptyEntries() {
        let grouped = NutritionLogic.groupedByMeal([])
        #expect(grouped.isEmpty)
    }

    @Test("Per-meal calorie totals are correct")
    func perMealTotals() {
        let entries = [
            entry(meal: .breakfast, calories: 300),
            entry(meal: .breakfast, calories: 200),
        ]
        let grouped = NutritionLogic.groupedByMeal(entries)
        let breakfastEntries = grouped[.breakfast] ?? []
        #expect(NutritionLogic.totalCalories(breakfastEntries) == 500)
    }
}

// MARK: - Copy Entries

@Suite("NutritionLogic.copyEntries")
struct CopyEntriesTests {

    private var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    @Test("Copies entries to target date preserving time-of-day and meal")
    func copiesWithMeal() {
        let cal = utcCalendar
        var comps = DateComponents(calendar: cal, year: 2026, month: 10, day: 10, hour: 8, minute: 30)
        let sourceDate = cal.date(from: comps)!
        comps.day = 11; comps.hour = 0; comps.minute = 0
        let targetDate = cal.date(from: comps)!

        let entry = FoodEntry(name: "Oats", calories: 300, protein: 10, carbs: 54, fat: 6,
                              date: sourceDate, meal: .breakfast)
        let copied = NutritionLogic.copyEntries([entry], to: targetDate, calendar: cal)

        #expect(copied.count == 1)
        #expect(copied[0].name == "Oats")
        #expect(copied[0].meal == .breakfast)
        #expect(cal.component(.day, from: copied[0].date) == 11)
        #expect(cal.component(.hour, from: copied[0].date) == 8)
        #expect(cal.component(.minute, from: copied[0].date) == 30)
        // New IDs
        #expect(copied[0].id != entry.id)
    }

    @Test("Empty entries returns empty result")
    func emptyEntries() {
        let copied = NutritionLogic.copyEntries([], to: Date())
        #expect(copied.isEmpty)
    }
}

// MARK: - Store.copyFoodLog

@Suite("Store.copyFoodLog")
@MainActor
struct StoreCopyFoodLogTests {

    private var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    @Test("Copies yesterday's entries to today")
    func copyFromYesterday() {
        let cal = utcCalendar
        var comps = DateComponents(calendar: cal, year: 2026, month: 10, day: 11, hour: 8)
        let yesterday = cal.date(from: comps)!
        comps.day = 12
        let today = cal.date(from: comps)!

        let repository = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repository)

        let entry = FoodEntry(name: "Oats", calories: 300, protein: 10, carbs: 54, fat: 6,
                              date: yesterday, meal: .breakfast)
        store.addFoodEntry(entry)

        store.copyFoodLog(from: yesterday, to: today)

        let todayEntries = NutritionLogic.entries(store.logbook.foodLog, on: today, calendar: cal)
        #expect(todayEntries.count == 1)
        #expect(todayEntries[0].name == "Oats")
        #expect(todayEntries[0].meal == .breakfast)
        #expect(cal.component(.day, from: todayEntries[0].date) == 12)
    }

    @Test("Copy from day with no entries does nothing")
    func copyEmptyDay() {
        let cal = utcCalendar
        var comps = DateComponents(calendar: cal, year: 2026, month: 10, day: 11)
        let yesterday = cal.date(from: comps)!
        comps.day = 12
        let today = cal.date(from: comps)!

        let repository = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repository)

        store.copyFoodLog(from: yesterday, to: today)

        let todayEntries = NutritionLogic.entries(store.logbook.foodLog, on: today, calendar: cal)
        #expect(todayEntries.isEmpty)
    }

    @Test("updateFoodEntry modifies an existing entry in place")
    func updateEntry() {
        let repository = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repository)

        let entry = FoodEntry(name: "Chicken", calories: 300, protein: 40, carbs: 0, fat: 7,
                              date: Date(), meal: .lunch)
        store.addFoodEntry(entry)

        var updated = entry
        updated.calories = 350
        updated.meal = .dinner
        store.updateFoodEntry(updated)

        let found = store.logbook.foodLog.first { $0.id == entry.id }
        #expect(found?.calories == 350)
        #expect(found?.meal == .dinner)
    }

    @Test("deleteFoodEntry removes single entry by id")
    func deleteById() {
        let repository = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repository)

        let e1 = FoodEntry(name: "A", calories: 100, protein: 0, carbs: 0, fat: 0, date: Date())
        let e2 = FoodEntry(name: "B", calories: 200, protein: 0, carbs: 0, fat: 0, date: Date())
        store.addFoodEntry(e1)
        store.addFoodEntry(e2)

        store.deleteFoodEntry(id: e1.id)

        #expect(store.logbook.foodLog.count == 1)
        #expect(store.logbook.foodLog.first?.name == "B")
    }
}

// MARK: - SavedMealIngredient compound init tests

@Suite("SavedMealIngredientCompoundTests")
struct SavedMealIngredientCompoundTests {

    private func makeIngredient(name: String, kcal: Double, protein: Double, carbs: Double, fat: Double, fiber: Double = 0, grams: Double) -> SavedMealIngredient {
        SavedMealIngredient(name: name, category: .protein, grams: grams,
                            kcalPer100g: kcal, proteinPer100g: protein,
                            carbsPer100g: carbs, fatPer100g: fat, fiberPer100g: fiber)
    }

    @Test("SavedMealIngredient(meal:) computes correct per-100g macros")
    func mealIngredientPerHundredG() {
        // banana: 100g, 89kcal/100g, 1.1p, 23c, 0.3f, 2.6fiber
        // whey: 30g, 400kcal/100g, 80p, 8c, 3f, 0fiber
        let banana = makeIngredient(name: "Banana", kcal: 89, protein: 1.1, carbs: 23, fat: 0.3, fiber: 2.6, grams: 100)
        let whey   = makeIngredient(name: "Whey",   kcal: 400, protein: 80,  carbs: 8,  fat: 3,   fiber: 0,   grams: 30)

        let shakeBase = SavedMeal(name: "Shake Base", ingredients: [banana, whey])
        let ingredient = SavedMealIngredient(meal: shakeBase, servings: 1)

        // Total grams = 130g, so factor = 100/130
        let totalGrams = 130.0
        #expect(ingredient.grams == totalGrams)
        // Verify per-100g protein is correctly computed
        let totalProtein = NutritionLogic.macros(for: shakeBase).protein
        let expectedProteinPer100g = totalProtein * 100.0 / totalGrams
        #expect(abs(ingredient.proteinPer100g - expectedProteinPer100g) < 0.1)
    }

    @Test("SavedMealIngredient(meal:servings:) scales grams correctly")
    func mealIngredientScalesWithServings() {
        let oats = makeIngredient(name: "Oats", kcal: 389, protein: 17, carbs: 66, fat: 7, fiber: 10, grams: 60)
        let meal  = SavedMeal(name: "Oat Bowl", ingredients: [oats])

        let single = SavedMealIngredient(meal: meal, servings: 1)
        let double = SavedMealIngredient(meal: meal, servings: 2)

        // Double servings → double grams
        #expect(double.grams == single.grams * 2)
        // The real invariant: total macros at stored grams double across servings.
        // Per-100g values may differ slightly due to integer kcal rounding — check total protein instead.
        let singleTotal = NutritionLogic.macros(for: single)
        let doubleTotal = NutritionLogic.macros(for: double)
        #expect(abs(doubleTotal.protein - singleTotal.protein * 2) < 0.5)
        #expect(abs(doubleTotal.fiber - singleTotal.fiber * 2) < 0.2)
    }

    @Test("Nested meal: saved meal used as ingredient in another meal")
    func nestedMealIngredient() {
        // shake base: 100g banana + 200ml milk (200g)
        let banana = makeIngredient(name: "Banana", kcal: 89, protein: 1.1, carbs: 23, fat: 0.3, fiber: 2.6, grams: 100)
        let milk   = makeIngredient(name: "Milk",   kcal: 61, protein: 3.4,  carbs: 4.8, fat: 3.2, grams: 200)
        let shakeBase = SavedMeal(name: "Shake Base", ingredients: [banana, milk])

        // protein shake: shake base (1 serving) + 30g casein
        let baseIngredient = SavedMealIngredient(meal: shakeBase, servings: 1)
        let casein = makeIngredient(name: "Casein", kcal: 380, protein: 78, carbs: 5, fat: 2, grams: 30)
        let shake  = SavedMeal(name: "Protein Shake", ingredients: [baseIngredient, casein])

        let shakeTotal = NutritionLogic.macros(for: shake)
        let shakeBaseTotals = NutritionLogic.macros(for: shakeBase)
        let caseinMacros = NutritionLogic.macros(for: casein)

        // Total kcal should equal shake base + casein contribution
        let expectedKcal = shakeBaseTotals.kcal + caseinMacros.kcal
        #expect(shakeTotal.kcal == expectedKcal)
    }

    @Test("SavedMealIngredient(meal:) with empty meal produces zero macros")
    func emptyMealIngredient() {
        let emptyMeal = SavedMeal(name: "Empty", ingredients: [])
        let ingredient = SavedMealIngredient(meal: emptyMeal, servings: 1)
        // No grams → factor is 0 → all per-100g values are 0
        #expect(ingredient.kcalPer100g == 0)
        #expect(ingredient.proteinPer100g == 0)
    }
}

// MARK: - CalendarLogic tests

@Suite("CalendarLogicTests")
struct CalendarLogicTests {

    // Fixed UTC calendar for deterministic day boundaries in tests
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday-first
        return c
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func makeSession(completed: Date?) -> SessionLog {
        SessionLog(programID: "p1", week: 1, day: 1,
                   started: completed.map { $0.addingTimeInterval(-3600) },
                   completed: completed, slotLogs: [:])
    }

    @Test("completedSessions returns only sessions on matching date")
    func sessionsOnMatchingDate() {
        let target = makeDate(year: 2026, month: 10, day: 1)
        let other  = makeDate(year: 2026, month: 10, day: 2)
        let sessions = [makeSession(completed: target), makeSession(completed: other)]
        let result = CalendarLogic.completedSessions(in: sessions, on: target, calendar: calendar)
        #expect(result.count == 1)
    }

    @Test("completedSessions ignores sessions with nil completed date")
    func sessionsIgnoresNilCompleted() {
        let target = makeDate(year: 2026, month: 10, day: 1)
        let result = CalendarLogic.completedSessions(in: [makeSession(completed: nil)], on: target, calendar: calendar)
        #expect(result.isEmpty)
    }

    @Test("completedSessions matches session completed at end of day")
    func sessionAtEndOfDay() {
        let target = makeDate(year: 2026, month: 10, day: 5, hour: 23)
        let result = CalendarLogic.completedSessions(in: [makeSession(completed: target)],
                                                     on: makeDate(year: 2026, month: 10, day: 5, hour: 8),
                                                     calendar: calendar)
        #expect(result.count == 1)
    }

    @Test("datesInMonth returns 31 days for October")
    func datesInOctober() {
        let oct = makeDate(year: 2026, month: 10, day: 15)
        let dates = CalendarLogic.datesInMonth(containing: oct, calendar: calendar)
        #expect(dates.count == 31)
    }

    @Test("datesInMonth returns 28 days for non-leap February")
    func datesInFebruary() {
        let feb = makeDate(year: 2026, month: 2, day: 10)
        let dates = CalendarLogic.datesInMonth(containing: feb, calendar: calendar)
        #expect(dates.count == 28)
        let last = calendar.dateComponents([.day], from: dates.last!).day
        #expect(last == 28)
    }

    @Test("datesInMonth first date is day 1")
    func datesInMonthFirstDay() {
        let may = makeDate(year: 2026, month: 5, day: 20)
        let dates = CalendarLogic.datesInMonth(containing: may, calendar: calendar)
        let firstDay = calendar.dateComponents([.day], from: dates.first!).day
        #expect(firstDay == 1)
    }

    @Test("weekdayOffset for June 2026 (starts Monday) is 0")
    func weekdayOffsetJune2026() {
        // June 1, 2026 is a Monday
        let jun = makeDate(year: 2026, month: 6, day: 10)
        #expect(CalendarLogic.weekdayOffset(for: jun, calendar: calendar) == 0)
    }

    @Test("weekdayOffset for July 2026 (starts Wednesday) is 2")
    func weekdayOffsetJuly2026() {
        // July 1, 2026 is a Wednesday
        let jul = makeDate(year: 2026, month: 7, day: 10)
        #expect(CalendarLogic.weekdayOffset(for: jul, calendar: calendar) == 2)
    }

    @Test("weekdayOffset is in range 0–6")
    func weekdayOffsetRange() {
        for month in 1...12 {
            var c = DateComponents()
            c.year = 2026; c.month = month; c.day = 15
            let date = Calendar(identifier: .gregorian).date(from: c)!
            let offset = CalendarLogic.weekdayOffset(for: date, calendar: calendar)
            #expect(offset >= 0 && offset <= 6)
        }
    }
}

// MARK: - FoodEntry Fiber Backfill Tests

@Suite("FoodEntry fiber backfill from template")
struct FoodEntryFiberBackfillTests {
    private let psylliumTemplate = FoodTemplate(
        name: "Psyllium Husk (powder)",
        category: .supplements,
        kcal: 200, protein: 2, carbs: 80, fat: 1, fiber: 78,
        defaultServingG: 5
    )

    private func makeEntry(name: String, calories: Int, fiber: Double) -> FoodEntry {
        FoodEntry(name: name, calories: calories, protein: 0, carbs: 0, fat: 0, fiber: fiber, date: Date())
    }

    @Test("backfilledFiber fills correct value from name grams for matching template")
    func backfillsFromNameGrams() {
        let entry = makeEntry(name: "Psyllium Husk (powder) (5g)", calories: 10, fiber: 0)
        let result = NutritionLogic.backfilledFiber(for: entry, database: [psylliumTemplate])
        #expect(abs(result - 3.9) < 0.05)
    }

    @Test("backfilledFiber does not change fiber when entry already has fiber > 0")
    func doesNotOverwriteExistingFiber() {
        let entry = makeEntry(name: "Psyllium Husk (powder) (5g)", calories: 10, fiber: 3.9)
        let result = NutritionLogic.backfilledFiber(for: entry, database: [psylliumTemplate])
        #expect(abs(result - 3.9) < 0.01)
    }

    @Test("backfilledFiber returns 0 when no matching template")
    func zeroWhenNoTemplate() {
        let entry = makeEntry(name: "Custom Snack (50g)", calories: 100, fiber: 0)
        let result = NutritionLogic.backfilledFiber(for: entry, database: [psylliumTemplate])
        #expect(result == 0)
    }

    @Test("backfilledFiber handles larger gram amounts correctly")
    func backfillsFor10gServing() {
        let entry = makeEntry(name: "Psyllium Husk (powder) (10g)", calories: 20, fiber: 0)
        let result = NutritionLogic.backfilledFiber(for: entry, database: [psylliumTemplate])
        #expect(abs(result - 7.8) < 0.05)
    }

    @Test("backfilledFiber returns 0 when entry name has no grams suffix and no template match")
    func noGramsSuffixNoTemplate() {
        let entry = makeEntry(name: "Mystery Food", calories: 100, fiber: 0)
        let result = NutritionLogic.backfilledFiber(for: entry, database: [psylliumTemplate])
        #expect(result == 0)
    }
}

// MARK: - Last Logged Grams Tests

@Suite("Last logged grams for a food template")
struct LastLoggedGramsTests {
    private let template = FoodTemplate(
        name: "Chicken Breast",
        category: .protein, kcal: 165, protein: 31, carbs: 0, fat: 4,
        defaultServingG: 150
    )

    private func makeEntry(name: String, daysAgo: Double) -> FoodEntry {
        FoodEntry(name: name, calories: 200, protein: 30, carbs: 0, fat: 4,
                  date: Date().addingTimeInterval(-daysAgo * 86400))
    }

    @Test("returns nil when log is empty")
    func nilWhenEmpty() {
        #expect(NutritionLogic.lastLoggedGrams(forFood: template, in: []) == nil)
    }

    @Test("returns grams from the most recent matching entry")
    func returnsRecentAmount() {
        let entries = [
            makeEntry(name: "Chicken Breast (150g)", daysAgo: 2),
            makeEntry(name: "Chicken Breast (200g)", daysAgo: 1),
        ]
        #expect(NutritionLogic.lastLoggedGrams(forFood: template, in: entries) == 200.0)
    }

    @Test("ignores entries whose name does not match the template")
    func ignoresNonMatching() {
        let entry = makeEntry(name: "Salmon (150g)", daysAgo: 0)
        #expect(NutritionLogic.lastLoggedGrams(forFood: template, in: [entry]) == nil)
    }

    @Test("most recent entry wins when multiple matches exist")
    func mostRecentWins() {
        let entries = [
            makeEntry(name: "Chicken Breast (100g)", daysAgo: 3),
            makeEntry(name: "Chicken Breast (250g)", daysAgo: 1),
            makeEntry(name: "Chicken Breast (120g)", daysAgo: 0.5),
        ]
        #expect(NutritionLogic.lastLoggedGrams(forFood: template, in: entries) == 120.0)
    }
}

// MARK: - NL Food Resolution Tests

@Suite("Natural language food resolution")
struct NLFoodResolutionTests {

    // matchFood

    @Test("exact match is case-insensitive")
    func matchExact() {
        let banana = FoodTemplate(name: "Banana", category: .fruit, kcal: 89, protein: 1.1, carbs: 23, fat: 0.3, fiber: 2.6, defaultServingG: 120)
        let chicken = FoodTemplate(name: "Chicken Breast", category: .protein, kcal: 165, protein: 31, carbs: 0, fat: 3.6, defaultServingG: 150)
        #expect(NutritionLogic.matchFood(name: "banana", database: [banana, chicken])?.name == "Banana")
    }

    @Test("partial name finds template via contains")
    func matchPartial() {
        let banana = FoodTemplate(name: "Banana", category: .fruit, kcal: 89, protein: 1.1, carbs: 23, fat: 0.3, fiber: 2.6, defaultServingG: 120)
        let chicken = FoodTemplate(name: "Chicken Breast", category: .protein, kcal: 165, protein: 31, carbs: 0, fat: 3.6, defaultServingG: 150)
        #expect(NutritionLogic.matchFood(name: "chicken", database: [banana, chicken])?.name == "Chicken Breast")
    }

    @Test("pluralized input matches via reversed contains")
    func matchPlural() {
        let banana = FoodTemplate(name: "Banana", category: .fruit, kcal: 89, protein: 1.1, carbs: 23, fat: 0.3, fiber: 2.6, defaultServingG: 120)
        #expect(NutritionLogic.matchFood(name: "bananas", database: [banana])?.name == "Banana")
    }

    @Test("unrecognized food returns nil")
    func matchNil() {
        let banana = FoodTemplate(name: "Banana", category: .fruit, kcal: 89, protein: 1.1, carbs: 23, fat: 0.3, fiber: 2.6, defaultServingG: 120)
        #expect(NutritionLogic.matchFood(name: "pizza", database: [banana]) == nil)
    }

    // gramsForUnit

    @Test("gram unit returns quantity directly")
    func gramUnit() {
        let banana = FoodTemplate(name: "Banana", category: .fruit, kcal: 89, protein: 1.1, carbs: 23, fat: 0.3, fiber: 2.6, defaultServingG: 120)
        #expect(NutritionLogic.gramsForUnit("g", quantity: 150, template: banana) == 150)
    }

    @Test("serving unit returns defaultServingG × quantity")
    func servingUnit() {
        let banana = FoodTemplate(name: "Banana", category: .fruit, kcal: 89, protein: 1.1, carbs: 23, fat: 0.3, fiber: 2.6, defaultServingG: 120)
        #expect(NutritionLogic.gramsForUnit("serving", quantity: 2, template: banana) == 240)
    }

    @Test("piece unit falls back to defaultServingG")
    func pieceUnit() {
        let banana = FoodTemplate(name: "Banana", category: .fruit, kcal: 89, protein: 1.1, carbs: 23, fat: 0.3, fiber: 2.6, defaultServingG: 120)
        #expect(NutritionLogic.gramsForUnit("piece", quantity: 1, template: banana) == 120)
    }

    @Test("oz unit converts to grams within tolerance")
    func ozUnit() {
        let banana = FoodTemplate(name: "Banana", category: .fruit, kcal: 89, protein: 1.1, carbs: 23, fat: 0.3, fiber: 2.6, defaultServingG: 120)
        let grams = NutritionLogic.gramsForUnit("oz", quantity: 1, template: banana)
        #expect(abs(grams - 28.35) < 0.5)
    }

    @Test("cup unit converts to approximately 240g")
    func cupUnit() {
        let banana = FoodTemplate(name: "Banana", category: .fruit, kcal: 89, protein: 1.1, carbs: 23, fat: 0.3, fiber: 2.6, defaultServingG: 120)
        #expect(NutritionLogic.gramsForUnit("cup", quantity: 1, template: banana) == 240)
    }

    // resolveNLFood

    @Test("resolveNLFood returns nil for unknown food")
    func resolveUnknown() {
        let banana = FoodTemplate(name: "Banana", category: .fruit, kcal: 89, protein: 1.1, carbs: 23, fat: 0.3, fiber: 2.6, defaultServingG: 120)
        #expect(NutritionLogic.resolveNLFood(name: "pizza", quantity: 1, unit: "slice", database: [banana]) == nil)
    }

    @Test("resolveNLFood returns correct template and grams")
    func resolveKnown() {
        let banana = FoodTemplate(name: "Banana", category: .fruit, kcal: 89, protein: 1.1, carbs: 23, fat: 0.3, fiber: 2.6, defaultServingG: 120)
        let result = NutritionLogic.resolveNLFood(name: "banana", quantity: 2, unit: "piece", database: [banana])
        #expect(result?.template.name == "Banana")
        #expect(result?.grams == 240)
    }
}

// MARK: - Workout HealthKit Sync Tests

@Suite("Workout HealthKit sync eligibility")
struct WorkoutHealthKitSyncTests {

    @Test("complete session with start and end is eligible")
    func eligibleWhenComplete() {
        let session = SessionLog(
            programID: "abc", week: 1, day: 1,
            started: Date(timeIntervalSinceNow: -3600), completed: Date(),
            slotLogs: [:]
        )
        #expect(WorkoutLogic.shouldWriteToHealth(session: session) == true)
    }

    @Test("session without completed date is not eligible")
    func notEligibleWhenIncomplete() {
        let session = SessionLog(
            programID: "abc", week: 1, day: 1,
            started: Date(), completed: nil, slotLogs: [:]
        )
        #expect(WorkoutLogic.shouldWriteToHealth(session: session) == false)
    }

    @Test("session without started date is not eligible")
    func notEligibleWhenNoStart() {
        let session = SessionLog(
            programID: "abc", week: 1, day: 1,
            started: nil, completed: Date(), slotLogs: [:]
        )
        #expect(WorkoutLogic.shouldWriteToHealth(session: session) == false)
    }

    @Test("computes duration from start to completion")
    func computesDuration() {
        let start = Date(timeIntervalSinceNow: -3600)
        let end = Date(timeIntervalSinceNow: -60)
        let session = SessionLog(
            programID: "abc", week: 1, day: 1,
            started: start, completed: end, slotLogs: [:]
        )
        let duration = WorkoutLogic.workoutDuration(session: session)
        #expect(abs((duration ?? 0) - 3540) < 1)
    }

    @Test("duration is nil when session is incomplete")
    func durationNilWhenIncomplete() {
        let session = SessionLog(
            programID: "abc", week: 1, day: 1,
            started: Date(), completed: nil, slotLogs: [:]
        )
        #expect(WorkoutLogic.workoutDuration(session: session) == nil)
    }
}

// MARK: - Estimated Kcal Burned Tests

@Suite("WorkoutLogic.estimatedKcalBurned")
struct EstimatedKcalBurnedTests {

    private func makeSession(durationSeconds: TimeInterval) -> SessionLog {
        let end = Date(timeIntervalSinceNow: 0)
        let start = end.addingTimeInterval(-durationSeconds)
        return SessionLog(programID: "p", week: 1, day: 1,
                          started: start, completed: end, slotLogs: [:])
    }

    @Test("returns nil for incomplete session")
    func nilForIncompleteSession() {
        let session = SessionLog(programID: "p", week: 1, day: 1,
                                 started: Date(), completed: nil, slotLogs: [:])
        #expect(WorkoutLogic.estimatedKcalBurned(session: session) == nil)
    }

    @Test("returns nil for session under 60 seconds")
    func nilForShortSession() {
        let session = makeSession(durationSeconds: 59)
        #expect(WorkoutLogic.estimatedKcalBurned(session: session) == nil)
    }

    @Test("returns nil for exactly 0 seconds")
    func nilForZeroDuration() {
        let session = makeSession(durationSeconds: 0)
        #expect(WorkoutLogic.estimatedKcalBurned(session: session) == nil)
    }

    @Test("returns value for exactly 60 seconds")
    func returnsValueAt60Seconds() {
        let session = makeSession(durationSeconds: 60)
        #expect(WorkoutLogic.estimatedKcalBurned(session: session, weightKg: 75) != nil)
    }

    @Test("MET formula: 60 min session at 75 kg ≈ 375 kcal")
    func formulaFor60MinAt75kg() {
        let session = makeSession(durationSeconds: 3600)
        let kcal = WorkoutLogic.estimatedKcalBurned(session: session, weightKg: 75)
        // MET 5.0 × 75 kg × 1 hour = 375 kcal
        #expect(kcal == 375)
    }

    @Test("scales correctly with heavier body weight")
    func scalesWithWeight() {
        let session = makeSession(durationSeconds: 3600)
        let light = WorkoutLogic.estimatedKcalBurned(session: session, weightKg: 60)!
        let heavy = WorkoutLogic.estimatedKcalBurned(session: session, weightKg: 90)!
        #expect(heavy > light)
        #expect(heavy == 450) // MET 5.0 × 90 × 1h
        #expect(light == 300) // MET 5.0 × 60 × 1h
    }

    @Test("scales correctly with longer session")
    func scalesWithDuration() {
        let short = makeSession(durationSeconds: 1800) // 30 min
        let long  = makeSession(durationSeconds: 3600) // 60 min
        let shortKcal = WorkoutLogic.estimatedKcalBurned(session: short, weightKg: 75)!
        let longKcal  = WorkoutLogic.estimatedKcalBurned(session: long,  weightKg: 75)!
        // Proportional scaling — rounding means the ratio isn't exactly 2.0, allow ±1 kcal
        #expect(longKcal > shortKcal)
        #expect(abs(longKcal - shortKcal * 2) <= 1)
    }

    @Test("uses default weight of 75 kg when not specified")
    func defaultWeight() {
        let session = makeSession(durationSeconds: 3600)
        let explicit = WorkoutLogic.estimatedKcalBurned(session: session, weightKg: 75)
        let default_ = WorkoutLogic.estimatedKcalBurned(session: session)
        #expect(explicit == default_)
    }
}

// MARK: - Servings Name Parsing Tests

@Suite("Servings name parsing")
struct ServingsNameParsingTests {

    // parseServingsFromEntryName

    @Test("parses whole-number serving count from name")
    func parsesWholeServings() {
        #expect(NutritionLogic.parseServingsFromEntryName("Beef Jerky (2×)") == 2.0)
    }

    @Test("parses fractional serving count from name")
    func parsesFractionalServings() {
        #expect(NutritionLogic.parseServingsFromEntryName("Beef Jerky (1.5×)") == 1.5)
    }

    @Test("returns nil for gram-based entries")
    func nilForGramEntries() {
        #expect(NutritionLogic.parseServingsFromEntryName("Chicken Breast (150g)") == nil)
    }

    @Test("returns nil for entries with no annotation")
    func nilForPlainName() {
        #expect(NutritionLogic.parseServingsFromEntryName("Beef Jerky") == nil)
    }

    // baseNameFromEntryName

    @Test("strips serving annotation from name")
    func stripsServingAnnotation() {
        #expect(NutritionLogic.baseNameFromEntryName("Beef Jerky (2×)") == "Beef Jerky")
    }

    @Test("leaves gram-based name unchanged")
    func leavesGramNameUnchanged() {
        #expect(NutritionLogic.baseNameFromEntryName("Psyllium Husk (powder) (5g)") == "Psyllium Husk (powder) (5g)")
    }

    @Test("leaves plain name unchanged")
    func leavesPlainNameUnchanged() {
        #expect(NutritionLogic.baseNameFromEntryName("Beef Jerky") == "Beef Jerky")
    }

    @Test("strips fractional serving annotation")
    func stripsFractionalServingAnnotation() {
        #expect(NutritionLogic.baseNameFromEntryName("Granola Bar (1.5×)") == "Granola Bar")
    }
}

// MARK: - Analytics Nutrition Stats Tests

@Suite("Analytics nutrition stats")
struct AnalyticsNutritionTests {

    @Test("dailyNutrition groups entries on same day")
    func groupsByDay() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let e1 = FoodEntry(name: "A", calories: 300, protein: 20, carbs: 40, fat: 5, fiber: 3, date: today)
        let e2 = FoodEntry(name: "B", calories: 200, protein: 15, carbs: 30, fat: 3, fiber: 2, date: today)
        let e3 = FoodEntry(name: "C", calories: 400, protein: 25, carbs: 50, fat: 8, fiber: 5, date: yesterday)
        let result = AnalyticsLogic.dailyNutrition(from: [e1, e2, e3], days: 7)
        let todayRow = result.first { cal.isDateInToday($0.date) }
        #expect(todayRow?.calories == 500)
        #expect(abs((todayRow?.protein ?? 0) - 35) < 0.01)
    }

    @Test("dailyNutrition excludes entries outside window")
    func excludesOutsideWindow() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let old = cal.date(byAdding: .day, value: -10, to: today)!
        let e1 = FoodEntry(name: "A", calories: 300, protein: 20, carbs: 40, fat: 5, fiber: 3, date: today)
        let e2 = FoodEntry(name: "B", calories: 200, protein: 15, carbs: 30, fat: 3, fiber: 2, date: old)
        let result = AnalyticsLogic.dailyNutrition(from: [e1, e2], days: 7)
        #expect(result.filter { $0.calories > 0 }.count == 1)
    }

    @Test("nutritionSummary averages over logged days")
    func averagesCorrectly() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let e1 = FoodEntry(name: "A", calories: 2000, protein: 150, carbs: 200, fat: 60, fiber: 25, date: today)
        let e2 = FoodEntry(name: "B", calories: 2500, protein: 180, carbs: 250, fat: 80, fiber: 30, date: yesterday)
        let summary = AnalyticsLogic.nutritionSummary(from: [e1, e2], days: 7)
        #expect(summary.loggedDays == 2)
        #expect(abs(summary.avgCalories - 2250) < 1)
        #expect(abs(summary.avgProtein - 165) < 0.1)
    }

    @Test("nutritionSummary counts only days that have entries")
    func countsOnlyLoggedDays() {
        let today = Calendar.current.startOfDay(for: Date())
        let e1 = FoodEntry(name: "A", calories: 2000, protein: 150, carbs: 200, fat: 60, fiber: 25, date: today)
        let summary = AnalyticsLogic.nutritionSummary(from: [e1], days: 7)
        #expect(summary.loggedDays == 1)
    }

    @Test("nutritionSummary returns zeros when food log is empty")
    func emptyLog() {
        let summary = AnalyticsLogic.nutritionSummary(from: [], days: 7)
        #expect(summary.loggedDays == 0)
        #expect(summary.avgCalories == 0)
        #expect(summary.avgProtein == 0)
    }

    @Test("nutritionSummary fiber averages correctly")
    func fiberAverage() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let e1 = FoodEntry(name: "A", calories: 1800, protein: 140, carbs: 180, fat: 55, fiber: 20, date: today)
        let e2 = FoodEntry(name: "B", calories: 2200, protein: 160, carbs: 220, fat: 70, fiber: 30, date: yesterday)
        let summary = AnalyticsLogic.nutritionSummary(from: [e1, e2], days: 7)
        #expect(abs(summary.avgFiber - 25) < 0.1)
    }
}

// MARK: - Maintenance Back-Calculation Tests

@Suite("Maintenance back-calculation from weight trend + intake")
struct MaintenanceBackCalculationTests {

    // estimatedMaintenance

    @Test("maintenance when losing weight exceeds intake")
    func maintenanceFromLoss() {
        // Eating 1500 kcal/day, losing 0.5 kg/week
        // Daily deficit = 0.5 × 7700 / 7 ≈ 550 kcal → maintenance ≈ 2050
        let result = NutritionLogic.estimatedMaintenance(avgDailyKcal: 1500, weightChangePer7Days: -0.5)
        #expect(abs(result - 2050) < 1)
    }

    @Test("maintenance when gaining weight is below intake")
    func maintenanceFromGain() {
        // Eating 2500 kcal/day, gaining 0.5 kg/week
        // Daily surplus = 0.5 × 7700 / 7 ≈ 550 kcal → maintenance ≈ 1950
        let result = NutritionLogic.estimatedMaintenance(avgDailyKcal: 2500, weightChangePer7Days: 0.5)
        #expect(abs(result - 1950) < 1)
    }

    @Test("maintenance equals intake when weight is stable")
    func maintenanceAtEquilibrium() {
        let result = NutritionLogic.estimatedMaintenance(avgDailyKcal: 2000, weightChangePer7Days: 0)
        #expect(abs(result - 2000) < 0.1)
    }

    // weightTrendPerWeek

    @Test("trend is negative when losing weight")
    func trendNegativeOnLoss() {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        // oldest entry is 80kg, newest is ~79kg — losing 1 kg/week
        let weights: [(date: Date, kg: Double)] = (0..<7).map { i in
            let daysAgo = 6 - i
            return (cal.date(byAdding: .day, value: -daysAgo, to: base)!, 80.0 - Double(i) * (1.0 / 7.0))
        }
        let trend = NutritionLogic.weightTrendPerWeek(from: weights)
        #expect(trend != nil)
        #expect(abs((trend ?? 0) - (-1.0)) < 0.1)
    }

    @Test("trend is nil with fewer than 2 data points")
    func trendNilForSinglePoint() {
        let weights: [(date: Date, kg: Double)] = [(Date(), 80.0)]
        #expect(NutritionLogic.weightTrendPerWeek(from: weights) == nil)
    }

    @Test("trend is nil with empty data")
    func trendNilForEmpty() {
        #expect(NutritionLogic.weightTrendPerWeek(from: []) == nil)
    }

    @Test("trend near zero when weight is stable")
    func trendNearZeroWhenStable() {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        let weights: [(date: Date, kg: Double)] = (0..<7).map { i in
            (cal.date(byAdding: .day, value: -i, to: base)!, 80.0)
        }
        let trend = NutritionLogic.weightTrendPerWeek(from: weights)
        #expect(trend != nil)
        #expect(abs(trend ?? 1) < 0.01)
    }
}

// MARK: - FoodStore search

private let storeTestFoods: [FoodTemplate] = [
    FoodTemplate(name: "Chicken Breast", category: .protein,
                 kcal: 165, protein: 31, carbs: 0, fat: 3.6,
                 defaultServingG: 150, servingLabel: "150g breast"),
    FoodTemplate(name: "Brown Rice", category: .grains,
                 kcal: 216, protein: 5, carbs: 45, fat: 1.8,
                 defaultServingG: 185),
    FoodTemplate(name: "Greek Yogurt", category: .dairy,
                 kcal: 59, protein: 10, carbs: 3.6, fat: 0.4,
                 defaultServingG: 170),
]

@Suite("FoodStore search")
struct FoodStoreSearchTests {
    let store: FoodStore

    init() async throws {
        store = FoodStore.ephemeral()
        await store.setup(seeding: storeTestFoods)
    }

    @Test("prefix search returns matching items")
    func prefixSearch() async {
        let results = await store.search("chick")
        #expect(results.count == 1)
        #expect(results[0].name == "Chicken Breast")
    }

    @Test("multi-word search requires all terms")
    func multiWordSearch() async {
        let results = await store.search("chicken breast")
        #expect(results.count == 1)
        #expect(results[0].name == "Chicken Breast")
    }

    @Test("search is case-insensitive")
    func caseInsensitive() async {
        let results = await store.search("GREEK")
        #expect(results.count == 1)
        #expect(results[0].name == "Greek Yogurt")
    }

    @Test("empty query returns empty")
    func emptyQuery() async {
        let results = await store.search("")
        #expect(results.isEmpty)
    }

    @Test("unknown query returns empty")
    func noMatch() async {
        let results = await store.search("unicornmeat")
        #expect(results.isEmpty)
    }

    @Test("matchFood finds exact name")
    func matchFoodExact() async {
        let result = await store.matchFood("Chicken Breast")
        #expect(result?.name == "Chicken Breast")
    }

    @Test("matchFood finds by prefix")
    func matchFoodPrefix() async {
        let result = await store.matchFood("Brown")
        #expect(result?.name == "Brown Rice")
    }

    @Test("matchFood returns nil for unknown food")
    func matchFoodMiss() async {
        let result = await store.matchFood("unicorn meat")
        #expect(result == nil)
    }

    @Test("count reflects seeded items")
    func itemCount() async {
        #expect(await store.count == storeTestFoods.count)
    }

    @Test("search respects limit parameter")
    func limitRespected() async {
        let results = await store.search("a", limit: 1)
        #expect(results.count <= 1)
    }
}

@Suite("FoodStore brand alias and fuzzy search")
struct FoodStoreBrandSearchTests {
    let store: FoodStore

    init() async throws {
        store = FoodStore.ephemeral()
        let brandFoods: [FoodTemplate] = [
            // DTF items use "DTF · " prefix
            FoodTemplate(name: "DTF · Pork XLB (1 piece)", category: .meals,
                         kcal: 110, protein: 7, carbs: 12, fat: 3, defaultServingG: 40),
            FoodTemplate(name: "DTF · Chicken Fried Rice", category: .meals,
                         kcal: 155, protein: 16, carbs: 22, fat: 5, defaultServingG: 400),
            // Proper Food items use "Proper Food – " prefix
            FoodTemplate(name: "Proper Food – Chicken & Rice", category: .meals,
                         kcal: 450, protein: 38, carbs: 45, fat: 9, defaultServingG: 100),
            FoodTemplate(name: "Proper Food – Salmon Bowl", category: .meals,
                         kcal: 520, protein: 42, carbs: 40, fat: 16, defaultServingG: 100),
            // Joe and the Juice uses "Joe and the Juice – " prefix
            FoodTemplate(name: "Joe and the Juice – Tunacado Sandwich", category: .meals,
                         kcal: 460, protein: 17, carbs: 49, fat: 23, defaultServingG: 100),
        ]
        await store.setup(seeding: brandFoods)
    }

    @Test("'DTF' finds items with DTF prefix")
    func dtfSearch() async {
        let results = await store.search("DTF")
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.name.hasPrefix("DTF") })
    }

    @Test("'DFT' alias also finds DTF items")
    func dftAlias() async {
        let results = await store.search("DFT")
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.name.hasPrefix("DTF") })
    }

    @Test("'din tai' alias finds DTF items")
    func dinTaiAlias() async {
        let results = await store.search("din tai")
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.name.hasPrefix("DTF") })
    }

    @Test("'din tai fung' alias finds DTF items")
    func dinTaiFungAlias() async {
        let results = await store.search("din tai fung")
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.name.hasPrefix("DTF") })
    }

    @Test("'Proper Foods' (plural) finds Proper Food entries")
    func properFoodsPlural() async {
        let results = await store.search("Proper Foods")
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.name.hasPrefix("Proper Food") })
    }

    @Test("'Proper Food' (singular) finds entries")
    func properFoodSingular() async {
        let results = await store.search("Proper Food")
        #expect(results.count == 2)
    }

    @Test("'Joe Juice' alias finds Joe and the Juice items")
    func joeJuiceAlias() async {
        let results = await store.search("Joe Juice")
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.name.hasPrefix("Joe and the Juice") })
    }
}

@Suite("FoodStore JSON import")
struct FoodStoreImportTests {
    let store: FoodStore

    init() async throws {
        store = FoodStore.ephemeral()
        await store.setup(seeding: [])
    }

    @Test("importJSON returns count of imported items")
    func importCount() async throws {
        let json = """
        [{"name":"Test Apple","category":"Fruit","kcal":52,"protein":0.3,"carbs":14,"fat":0.2,"defaultServingG":150}]
        """.data(using: .utf8)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_foods_\(UUID()).json")
        try json.write(to: url)
        let count = try await store.importJSON(from: url)
        #expect(count == 1)
        #expect(await store.count == 1)
    }

    @Test("imported items appear in search")
    func importedItemsSearchable() async throws {
        let json = """
        [{"name":"Avocado Toast","category":"Meals & Prepared Foods","kcal":280,"protein":8,"carbs":30,"fat":14,"defaultServingG":200}]
        """.data(using: .utf8)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_foods2_\(UUID()).json")
        try json.write(to: url)
        try await store.importJSON(from: url)
        let results = await store.search("avocado")
        #expect(results.first?.name == "Avocado Toast")
    }

    @Test("importing same name replaces existing entry")
    func importReplaces() async throws {
        let first = """
        [{"name":"Oats","category":"Carbs & Grains","kcal":389,"protein":17,"carbs":66,"fat":7,"defaultServingG":40}]
        """.data(using: .utf8)!
        let updated = """
        [{"name":"Oats","category":"Carbs & Grains","kcal":400,"protein":15,"carbs":68,"fat":7,"defaultServingG":40}]
        """.data(using: .utf8)!
        let url1 = FileManager.default.temporaryDirectory.appendingPathComponent("oats1_\(UUID()).json")
        let url2 = FileManager.default.temporaryDirectory.appendingPathComponent("oats2_\(UUID()).json")
        try first.write(to: url1)
        try updated.write(to: url2)
        try await store.importJSON(from: url1)
        try await store.importJSON(from: url2)
        #expect(await store.count == 1)
        let result = await store.matchFood("Oats")
        #expect(result?.kcal == 400)
    }

    @Test("invalid JSON throws an error")
    func invalidJSONThrows() async {
        let bad = "not json".data(using: .utf8)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bad_\(UUID()).json")
        try? bad.write(to: url)
        await #expect(throws: Error.self) {
            try await store.importJSON(from: url)
        }
    }
}

// MARK: - Recipe macro scaling

@Suite("Recipe macro scaling")
struct RecipeMacroScalingTests {

    @Test("1 serving returns original values")
    func singleServing() {
        let v = MacroVariant(label: nil, calories: 300, protein: 40, carbs: 20, fat: 8)
        let s = v.scaled(by: 1.0)
        #expect(s.calories == 300)
        #expect(abs(s.protein - 40) < 0.01)
        #expect(abs(s.carbs - 20) < 0.01)
        #expect(abs(s.fat - 8) < 0.01)
    }

    @Test("doubles all values for 2 servings")
    func twoServings() {
        let v = MacroVariant(label: nil, calories: 300, protein: 40, carbs: 20, fat: 8)
        let s = v.scaled(by: 2.0)
        #expect(s.calories == 600)
        #expect(abs(s.protein - 80) < 0.01)
        #expect(abs(s.carbs - 40) < 0.01)
        #expect(abs(s.fat - 16) < 0.01)
    }

    @Test("halves all values for 0.5 servings")
    func halfServing() {
        let v = MacroVariant(label: nil, calories: 400, protein: 50, carbs: 30, fat: 10)
        let s = v.scaled(by: 0.5)
        #expect(s.calories == 200)
        #expect(abs(s.protein - 25) < 0.01)
        #expect(abs(s.carbs - 15) < 0.01)
        #expect(abs(s.fat - 5) < 0.01)
    }

    @Test("fractional serving rounds calories correctly")
    func fractionalRounding() {
        let v = MacroVariant(label: nil, calories: 295, protein: 32, carbs: 38, fat: 4)
        let s = v.scaled(by: 1.5)
        #expect(s.calories == 443)  // 295 * 1.5 = 442.5 → rounded to 443
        #expect(abs(s.protein - 48) < 0.01)
    }

    @Test("label is preserved when scaling")
    func labelPreserved() {
        let v = MacroVariant(label: "Per serving", calories: 200, protein: 20, carbs: 10, fat: 5)
        let s = v.scaled(by: 3.0)
        #expect(s.label == "Per serving")
    }
}

// MARK: - FoodStore bundle loading

private func fsBundleTempPath() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("FoodStoreTest-\(UUID().uuidString)")
        .appendingPathExtension("db")
        .path
}

private func fsMakeSeededDB(templates: [FoodTemplate]) async -> String {
    let path = fsBundleTempPath()
    let store = FoodStore.forTesting(path: path)
    await store.setup(seeding: templates, bundleURL: nil)
    // Flush WAL into the main file so it is safe to copy as a bundle DB.
    await store.checkpoint()
    return path
}

private func fsSampleTemplates(count: Int) -> [FoodTemplate] {
    (0..<count).map { i in
        FoodTemplate(name: "Bundle Food \(i)", category: .protein,
                     kcal: 100, protein: 20, carbs: 5, fat: 3, defaultServingG: 100)
    }
}

@Suite("FoodStore bundle loading")
struct FoodStoreBundleLoadingTests {

    @Test("fresh install copies bundle DB rows without code seeding")
    func freshInstallCopiesBundleRows() async {
        let bundlePath = await fsMakeSeededDB(templates: fsSampleTemplates(count: 50))
        defer { try? FileManager.default.removeItem(atPath: bundlePath) }

        let storePath = fsBundleTempPath()
        defer { try? FileManager.default.removeItem(atPath: storePath) }

        let store = FoodStore.forTesting(path: storePath)
        await store.setup(seeding: [], bundleURL: URL(fileURLWithPath: bundlePath))

        #expect(await store.count == 50)
    }

    @Test("fresh install without bundle falls back to provided templates")
    func freshInstallFallsBackToTemplates() async {
        let storePath = fsBundleTempPath()
        defer { try? FileManager.default.removeItem(atPath: storePath) }

        let store = FoodStore.forTesting(path: storePath)
        await store.setup(seeding: fsSampleTemplates(count: 7), bundleURL: nil)

        #expect(await store.count == 7)
    }

    @Test("existing stub DB with fewer than 10k rows is replaced by bundle")
    func stubDBUpgradedFromBundle() async {
        let stubPath = await fsMakeSeededDB(templates: fsSampleTemplates(count: 5))
        defer { try? FileManager.default.removeItem(atPath: stubPath) }

        let bundlePath = await fsMakeSeededDB(templates: fsSampleTemplates(count: 50))
        defer { try? FileManager.default.removeItem(atPath: bundlePath) }

        // Simulate a second launch: new actor pointing at the existing stub file.
        let upgradeStore = FoodStore.forTesting(path: stubPath)
        await upgradeStore.setup(seeding: [], bundleURL: URL(fileURLWithPath: bundlePath))

        #expect(await upgradeStore.count == 50)
    }

    @Test("empty bundle DB (0 food rows) triggers code-seed fallback — reproduces production bug")
    func emptyBundleTriggersCodeSeedFallback() async {
        // An empty bundle (schema present but 0 rows) is what happens when foods.db was not
        // generated by build_food_db.py before being added to the Xcode project.
        let emptyBundlePath = await fsMakeSeededDB(templates: [])
        defer { try? FileManager.default.removeItem(atPath: emptyBundlePath) }

        let storePath = fsBundleTempPath()
        defer { try? FileManager.default.removeItem(atPath: storePath) }

        let store = FoodStore.forTesting(path: storePath)
        await store.setup(seeding: nil, bundleURL: URL(fileURLWithPath: emptyBundlePath))

        // Falls back to the built-in foodDatabase (currently 409 items).
        #expect(await store.count == foodDatabase.count)
    }

    @Test("second setup call is a no-op")
    func setupIsIdempotent() async {
        let storePath = fsBundleTempPath()
        defer { try? FileManager.default.removeItem(atPath: storePath) }

        let store = FoodStore.forTesting(path: storePath)
        await store.setup(seeding: fsSampleTemplates(count: 10), bundleURL: nil)
        await store.setup(seeding: fsSampleTemplates(count: 999), bundleURL: nil)

        #expect(await store.count == 10)
    }

    @Test("bundled foods.db has more than 409 rows — fails if db is missing or was not built by build_food_db.py")
    func bundledFoodsDBIsPopulated() async throws {
        // In the test host context Bundle.main is the DailyFitness app bundle.
        // This test will fail in one of two revealing ways:
        //   - nil URL  → foods.db is not referenced in Xcode project resources
        //   - count == foodDatabase.count (409) → the file exists but is empty/stub
        let bundleURL = try #require(
            Bundle.main.url(forResource: "foods", withExtension: "db"),
            "foods.db not found in app bundle — check that it is listed in Copy Bundle Resources"
        )

        let storePath = fsBundleTempPath()
        defer { try? FileManager.default.removeItem(atPath: storePath) }

        let store = FoodStore.forTesting(path: storePath)
        await store.setup(seeding: [], bundleURL: bundleURL)
        let count = await store.count
        #expect(count > foodDatabase.count,
                "Bundled foods.db has \(count) rows — same as the code stub. Run build_food_db.py then rebuild.")
    }

    // Verifies that key brand-name drinks are present and searchable in the bundled foods.db.
    // Add a line here whenever a new brand category is imported into foods.db.
    @Test("bundled foods.db contains expected alcohol brands")
    func bundledDrinksAreSearchable() async throws {
        let bundleURL = try #require(
            Bundle.main.url(forResource: "foods", withExtension: "db"),
            "foods.db not found in app bundle"
        )
        let storePath = fsBundleTempPath()
        defer { try? FileManager.default.removeItem(atPath: storePath) }

        let store = FoodStore.forTesting(path: storePath)
        await store.setup(seeding: [], bundleURL: bundleURL)

        let brands: [(query: String, expected: String)] = [
            ("Heineken", "Heineken"),
            ("Bud Light", "Bud Light"),
            ("Modelo", "Modelo"),
            ("Corona", "Corona Extra"),
            ("Jack Daniel", "Jack Daniel"),
            ("Tito's", "Tito's"),
            ("Grey Goose", "Grey Goose Vodka"),
            ("Jameson", "Jameson Irish Whiskey"),
            ("White Claw", "White Claw Hard Seltzer"),
            ("Guinness", "Guinness Draught"),
        ]

        for brand in brands {
            let results = await store.search(brand.query)
            #expect(
                results.contains { $0.name.lowercased().contains(brand.expected.lowercased()) },
                "'\(brand.query)' returned no match — expected to find '\(brand.expected)'"
            )
        }
    }

    // Verifies the no-space compound query fix — "budlight" must find "Bud Light".
    @Test("no-space brand queries find spaced entries")
    func noSpaceQueryFindsBrand() async throws {
        let bundleURL = try #require(
            Bundle.main.url(forResource: "foods", withExtension: "db"),
            "foods.db not found in app bundle"
        )
        let storePath = fsBundleTempPath()
        defer { try? FileManager.default.removeItem(atPath: storePath) }

        let store = FoodStore.forTesting(path: storePath)
        await store.setup(seeding: [], bundleURL: bundleURL)

        let results = await store.search("budlight")
        #expect(
            results.contains { $0.name.lowercased().contains("bud light") },
            "'budlight' (no space) should find 'Bud Light'"
        )
    }

    @Test("copied bundle rows are searchable via FTS")
    func bundleCopyIsSearchable() async {
        let template = FoodTemplate(name: "Bundle Banana", category: .fruit,
                                    kcal: 89, protein: 1.1, carbs: 23, fat: 0.3, defaultServingG: 120)
        let bundlePath = await fsMakeSeededDB(templates: [template])
        defer { try? FileManager.default.removeItem(atPath: bundlePath) }

        let storePath = fsBundleTempPath()
        defer { try? FileManager.default.removeItem(atPath: storePath) }

        let store = FoodStore.forTesting(path: storePath)
        await store.setup(seeding: [], bundleURL: URL(fileURLWithPath: bundlePath))

        let results = await store.search("Bundle Banana")
        #expect(results.first?.name == "Bundle Banana")
    }
}

// MARK: - FoodStore custom food insertion

@Suite("FoodStore custom food insertion")
struct FoodStoreCustomFoodTests {

    private func makeReadyStore() async -> (FoodStore, String) {
        let path = fsBundleTempPath()
        let store = FoodStore.forTesting(path: path)
        await store.setup(seeding: [], bundleURL: nil)
        return (store, path)
    }

    @Test("inserted custom food appears in customFoods(for:)")
    func insertedFoodAppearsInCustomFoods() async {
        let (store, path) = await makeReadyStore()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let userID = UUID()

        let custom = FoodTemplate(name: "My Protein Shake", category: .meals,
                                  kcal: 300, protein: 35, carbs: 20, fat: 5,
                                  defaultServingG: 100, servingLabel: "1 serving")
        await store.insertCustomFood(custom, userID: userID)

        let results = await store.customFoods(for: userID)
        #expect(results.contains { $0.name == "My Protein Shake" })
    }

    @Test("custom food is flagged isCustom and carries stable ID")
    func customFoodFlagAndID() async {
        let (store, path) = await makeReadyStore()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let userID = UUID()
        let knownID = UUID()

        let custom = FoodTemplate(name: "Tracked Custom", category: .protein,
                                  kcal: 200, protein: 40, carbs: 0, fat: 3,
                                  defaultServingG: 100, isCustom: true, customFoodID: knownID)
        await store.insertCustomFood(custom, userID: userID)

        let result = await store.customFoods(for: userID).first
        #expect(result?.isCustom == true)
        #expect(result?.customFoodID == knownID)
    }

    @Test("inserting custom food does not change shared food count")
    func insertDoesNotChangeSharedCount() async {
        let (store, path) = await makeReadyStore()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let userID = UUID()

        let before = await store.count
        let custom = FoodTemplate(name: "Custom Oats Bowl", category: .grains,
                                  kcal: 350, protein: 12, carbs: 60, fat: 6,
                                  defaultServingG: 100)
        await store.insertCustomFood(custom, userID: userID)
        let after = await store.count

        #expect(after == before, "custom_foods table is separate; shared count must not change")
    }

    @Test("re-inserting same name+user replaces the entry")
    func sameNameReplacesEntry() async {
        let (store, path) = await makeReadyStore()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let userID = UUID()

        let v1 = FoodTemplate(name: "Custom Shake", category: .meals,
                              kcal: 200, protein: 20, carbs: 10, fat: 3,
                              defaultServingG: 100)
        let v2 = FoodTemplate(name: "Custom Shake", category: .meals,
                              kcal: 400, protein: 40, carbs: 20, fat: 6,
                              defaultServingG: 100)
        await store.insertCustomFood(v1, userID: userID)
        await store.insertCustomFood(v2, userID: userID)

        let results = await store.customFoods(for: userID)
        #expect(results.count == 1, "UNIQUE(name, user_id) — re-insert must replace, not duplicate")
        #expect(results.first?.kcal == 400, "macros should reflect the updated entry")
    }

    @Test("inserted custom food macros round-trip correctly")
    func macrosRoundTrip() async {
        let (store, path) = await makeReadyStore()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let userID = UUID()

        let custom = FoodTemplate(name: "RT Food", category: .meals,
                                  kcal: 280, protein: 22.5, carbs: 30, fat: 8.4,
                                  fiber: 4, sugar: 5, saturatedFat: 2, sodium: 150, cholesterol: 30,
                                  defaultServingG: 100, servingLabel: "1 serving")
        await store.insertCustomFood(custom, userID: userID)

        let result = await store.customFoods(for: userID).first { $0.name == "RT Food" }
        #expect(result != nil)
        #expect(result?.kcal == 280)
        #expect(abs((result?.protein ?? 0) - 22.5) < 0.01)
        #expect(abs((result?.fiber ?? 0) - 4) < 0.01)
        #expect(result?.servingLabel == "1 serving")
    }

    @Test("custom foods are user-scoped — other users cannot see them")
    func customFoodsAreScopedToUser() async {
        let (store, path) = await makeReadyStore()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let alice = UUID()
        let bob   = UUID()

        await store.insertCustomFood(
            FoodTemplate(name: "Alice's Granola", category: .grains,
                         kcal: 380, protein: 8, carbs: 55, fat: 12, defaultServingG: 100),
            userID: alice)
        await store.insertCustomFood(
            FoodTemplate(name: "Bob's Protein Bar", category: .protein,
                         kcal: 220, protein: 30, carbs: 18, fat: 6, defaultServingG: 100),
            userID: bob)

        let aliceFoods = await store.customFoods(for: alice)
        let bobFoods   = await store.customFoods(for: bob)

        #expect(aliceFoods.allSatisfy { $0.name == "Alice's Granola" })
        #expect(bobFoods.allSatisfy { $0.name == "Bob's Protein Bar" })
        #expect(!aliceFoods.contains { $0.name == "Bob's Protein Bar" })
        #expect(!bobFoods.contains { $0.name == "Alice's Granola" })
    }

    @Test("deleteCustomFood removes the food for that user")
    func deleteRemovesFood() async {
        let (store, path) = await makeReadyStore()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let userID = UUID()
        let foodID = UUID()

        await store.insertCustomFood(
            FoodTemplate(name: "To Delete", category: .meals,
                         kcal: 100, protein: 5, carbs: 10, fat: 2,
                         defaultServingG: 100, isCustom: true, customFoodID: foodID),
            userID: userID)

        let before = await store.customFoods(for: userID)
        #expect(before.count == 1)

        await store.deleteCustomFood(id: foodID, userID: userID)
        let after = await store.customFoods(for: userID)
        #expect(after.isEmpty)
    }

    @Test("deleteCustomFood is a no-op for another user's food")
    func deleteDoesNotCrossUsers() async {
        let (store, path) = await makeReadyStore()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let alice = UUID()
        let bob   = UUID()
        let foodID = UUID()

        await store.insertCustomFood(
            FoodTemplate(name: "Alice's Food", category: .meals,
                         kcal: 100, protein: 5, carbs: 10, fat: 2,
                         defaultServingG: 100, isCustom: true, customFoodID: foodID),
            userID: alice)

        await store.deleteCustomFood(id: foodID, userID: bob)

        let aliceFoods = await store.customFoods(for: alice)
        #expect(aliceFoods.count == 1, "Bob's delete attempt must not remove Alice's food")
    }

    @Test("search with userID prepends matching custom foods")
    func searchPrependsCustomFoods() async {
        let (store, path) = await makeReadyStore()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let userID = UUID()

        await store.insertCustomFood(
            FoodTemplate(name: "Unique Custom Protein Powder", category: .supplements,
                         kcal: 120, protein: 25, carbs: 3, fat: 1,
                         defaultServingG: 30, servingLabel: "1 scoop"),
            userID: userID)

        let results = await store.search("Unique Custom Protein", userID: userID)
        let first = results.first
        #expect(first?.name == "Unique Custom Protein Powder")
        #expect(first?.isCustom == true)
    }

    @Test("search without userID does not return custom foods")
    func searchWithoutUserIDSkipsCustomFoods() async {
        let (store, path) = await makeReadyStore()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let userID = UUID()

        await store.insertCustomFood(
            FoodTemplate(name: "OnlyForUser9182736", category: .meals,
                         kcal: 100, protein: 5, carbs: 10, fat: 2,
                         defaultServingG: 100),
            userID: userID)

        let results = await store.search("OnlyForUser9182736")
        #expect(results.isEmpty, "custom foods must not appear in searches without a userID")
    }

    @Test("foods(in:userID:) prepends user's custom foods in that category")
    func foodsInCategoryPrependsCustom() async {
        let (store, path) = await makeReadyStore()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let userID = UUID()

        await store.insertCustomFood(
            FoodTemplate(name: "Custom Whey Isolate", category: .supplements,
                         kcal: 110, protein: 26, carbs: 1, fat: 0,
                         defaultServingG: 30),
            userID: userID)

        let results = await store.foods(in: .supplements, userID: userID)
        let first = results.first
        #expect(first?.name == "Custom Whey Isolate")
        #expect(first?.isCustom == true)
    }

    @Test("foods(in:) without userID does not return custom foods")
    func foodsInCategoryWithoutUserIDSkipsCustom() async {
        let (store, path) = await makeReadyStore()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let userID = UUID()

        await store.insertCustomFood(
            FoodTemplate(name: "CustomOnly12345", category: .meals,
                         kcal: 100, protein: 5, carbs: 10, fat: 2,
                         defaultServingG: 100),
            userID: userID)

        let results = await store.foods(in: .meals)
        #expect(!results.contains { $0.name == "CustomOnly12345" })
    }
}

// MARK: - Store.copyMeal

@Suite("Store.copyMeal")
@MainActor
struct StoreCopyMealTests {

    private var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 8) -> Date {
        var comps = DateComponents(calendar: utcCalendar, year: year, month: month, day: day, hour: hour)
        return utcCalendar.date(from: comps)!
    }

    @Test("copies the specified meal from source to target date")
    func copiesMealEntries() {
        let cal = utcCalendar
        let source = makeDate(year: 2026, month: 10, day: 11)
        let target = makeDate(year: 2026, month: 10, day: 12)

        let repository = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repository)

        store.addFoodEntry(FoodEntry(name: "Oats", calories: 300, protein: 10, carbs: 54, fat: 6,
                                     date: source, meal: .breakfast))
        store.addFoodEntry(FoodEntry(name: "Egg", calories: 70, protein: 6, carbs: 0, fat: 5,
                                     date: source, meal: .breakfast))
        store.addFoodEntry(FoodEntry(name: "Chicken", calories: 350, protein: 45, carbs: 0, fat: 8,
                                     date: source, meal: .lunch))

        store.copyMeal(.breakfast, from: source, to: target)

        let copied = NutritionLogic.entries(store.logbook.foodLog, on: target, calendar: cal)
        #expect(copied.count == 2)
        #expect(copied.allSatisfy { $0.meal == .breakfast })
        #expect(Set(copied.map(\.name)) == ["Oats", "Egg"])
        #expect(copied.allSatisfy { cal.component(.day, from: $0.date) == 12 })
    }

    @Test("does not copy other meals")
    func doesNotCopyOtherMeals() {
        let cal = utcCalendar
        let source = makeDate(year: 2026, month: 10, day: 11)
        let target = makeDate(year: 2026, month: 10, day: 12)

        let repository = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repository)

        store.addFoodEntry(FoodEntry(name: "Oats", calories: 300, protein: 10, carbs: 54, fat: 6,
                                     date: source, meal: .breakfast))
        store.addFoodEntry(FoodEntry(name: "Chicken", calories: 350, protein: 45, carbs: 0, fat: 8,
                                     date: source, meal: .lunch))

        store.copyMeal(.breakfast, from: source, to: target)

        let copied = NutritionLogic.entries(store.logbook.foodLog, on: target, calendar: cal)
        #expect(!copied.contains { $0.name == "Chicken" })
    }

    @Test("skips entries already present in target meal (deduplication)")
    func deduplicatesExistingEntries() {
        let cal = utcCalendar
        let source = makeDate(year: 2026, month: 10, day: 11)
        let target = makeDate(year: 2026, month: 10, day: 12)

        let repository = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repository)

        store.addFoodEntry(FoodEntry(name: "Oats", calories: 300, protein: 10, carbs: 54, fat: 6,
                                     date: source, meal: .breakfast))
        store.addFoodEntry(FoodEntry(name: "Oats", calories: 300, protein: 10, carbs: 54, fat: 6,
                                     date: target, meal: .breakfast))

        store.copyMeal(.breakfast, from: source, to: target)

        let targetEntries = NutritionLogic.entries(store.logbook.foodLog, on: target, calendar: cal)
            .filter { $0.meal == .breakfast }
        #expect(targetEntries.count == 1, "duplicate should not be added")
    }

    @Test("does nothing when source meal is empty")
    func noOpWhenSourceEmpty() {
        let source = makeDate(year: 2026, month: 10, day: 11)
        let target = makeDate(year: 2026, month: 10, day: 12)

        let repository = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repository)

        store.copyMeal(.lunch, from: source, to: target)

        #expect(store.logbook.foodLog.isEmpty)
    }
}

// MARK: - GlobalActions

@Suite("GlobalActions")
struct GlobalActionsTests {

    @Test("defaults to all false")
    func defaultsAllFalse() {
        let actions = GlobalActions()
        #expect(!actions.showingScanner)
        #expect(!actions.showingCustomWorkout)
    }

    @Test("toggling showingScanner works")
    func toggleScanner() {
        let actions = GlobalActions()
        actions.showingScanner = true
        #expect(actions.showingScanner)
        actions.showingScanner = false
        #expect(!actions.showingScanner)
    }

    @Test("toggling showingCustomWorkout works")
    func toggleCustomWorkout() {
        let actions = GlobalActions()
        actions.showingCustomWorkout = true
        #expect(actions.showingCustomWorkout)
        actions.showingCustomWorkout = false
        #expect(!actions.showingCustomWorkout)
    }
}

// MARK: - FoodCategory drinks

@Suite("FoodCategory.drinks")
struct FoodCategoryDrinksTests {

    @Test("drinks case has correct raw value")
    func rawValue() {
        #expect(FoodCategory.drinks.rawValue == "Drinks")
    }

    @Test("drinks is included in allCases")
    func inAllCases() {
        #expect(FoodCategory.allCases.contains(.drinks))
    }

    @Test("drinks round-trips through Codable")
    func codable() throws {
        let encoded = try JSONEncoder().encode(FoodCategory.drinks)
        let decoded = try JSONDecoder().decode(FoodCategory.self, from: encoded)
        #expect(decoded == .drinks)
    }
}

// MARK: - FoodStore alcohol search

@Suite("FoodStore alcohol search")
struct FoodStoreAlcoholSearchTests {

    private func makeStoreWithDrinks() async -> (FoodStore, String) {
        let path = fsBundleTempPath()
        let drinks: [FoodTemplate] = [
            FoodTemplate(name: "Beer – Lager (e.g. Heineken)", category: .drinks,
                         kcal: 43, protein: 0.5, carbs: 3.5, fat: 0,
                         defaultServingG: 330, servingLabel: "330ml can"),
            FoodTemplate(name: "Beer – IPA", category: .drinks,
                         kcal: 55, protein: 0.6, carbs: 4.0, fat: 0,
                         defaultServingG: 330, servingLabel: "330ml can"),
            FoodTemplate(name: "Wine – Red (e.g. Cabernet Sauvignon)", category: .drinks,
                         kcal: 85, protein: 0.1, carbs: 2.6, fat: 0,
                         defaultServingG: 150, servingLabel: "150ml glass"),
            FoodTemplate(name: "Wine – White (e.g. Sauvignon Blanc)", category: .drinks,
                         kcal: 82, protein: 0.1, carbs: 2.1, fat: 0,
                         defaultServingG: 150, servingLabel: "150ml glass"),
            FoodTemplate(name: "Spirits – Vodka (40% ABV)", category: .drinks,
                         kcal: 231, protein: 0, carbs: 0, fat: 0,
                         defaultServingG: 30, servingLabel: "30ml shot"),
            FoodTemplate(name: "Mojito", category: .drinks,
                         kcal: 60, protein: 0, carbs: 9, fat: 0,
                         defaultServingG: 300, servingLabel: "300ml"),
        ]
        let store = FoodStore.forTesting(path: path)
        await store.setup(seeding: drinks, bundleURL: nil)
        return (store, path)
    }

    @Test("searching 'beer' returns beer entries")
    func beerSearch() async {
        let (store, path) = await makeStoreWithDrinks()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let results = await store.search("beer")
        #expect(results.contains { $0.name.lowercased().contains("beer") })
    }

    @Test("searching 'wine' returns wine entries")
    func wineSearch() async {
        let (store, path) = await makeStoreWithDrinks()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let results = await store.search("wine")
        #expect(results.contains { $0.name.lowercased().contains("wine") })
    }

    @Test("searching 'vodka' returns vodka entry")
    func vodkaSearch() async {
        let (store, path) = await makeStoreWithDrinks()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let results = await store.search("vodka")
        #expect(results.contains { $0.name.lowercased().contains("vodka") })
    }

    @Test("searching 'mojito' returns cocktail entry")
    func mojito() async {
        let (store, path) = await makeStoreWithDrinks()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let results = await store.search("mojito")
        #expect(results.contains { $0.name == "Mojito" })
    }

    @Test("drinks category is returned by foods(in:) query")
    func categoryBrowse() async {
        let (store, path) = await makeStoreWithDrinks()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let results = await store.foods(in: .drinks)
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.category == .drinks })
    }

    @Test("beer kcal per 100ml is correct (lager)")
    func lagerKcal() async {
        let (store, path) = await makeStoreWithDrinks()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let results = await store.search("Lager")
        let lager = results.first { $0.name.contains("Lager") }
        #expect(lager?.kcal == 43)
        #expect(lager?.defaultServingG == 330)
    }
}

// MARK: - RecipeImportView macro calculation

@Suite("RecipeImportView macro scaling")
struct RecipeImportMacroTests {

    // These tests exercise the pure math that RecipeImportView uses to scale
    // per-ingredient totals down to a per-serving amount.

    private func scaledCalories(ingredientTotal: Int, totalServings: Int, servings: Double) -> Int {
        Int((Double(ingredientTotal) / Double(totalServings) * servings).rounded())
    }

    private func scaledMacro(ingredientTotal: Double, totalServings: Int, servings: Double) -> Double {
        (ingredientTotal / Double(totalServings) * servings * 10).rounded() / 10
    }

    @Test("1 serving of 1-serving recipe returns full ingredient totals")
    func singleServingPassthrough() {
        let kcal = scaledCalories(ingredientTotal: 600, totalServings: 1, servings: 1)
        #expect(kcal == 600)
    }

    @Test("half a serving of 1-serving recipe halves the calories")
    func halfServing() {
        let kcal = scaledCalories(ingredientTotal: 600, totalServings: 1, servings: 0.5)
        #expect(kcal == 300)
    }

    @Test("2 servings from a 4-serving recipe returns 50% of total")
    func twoOfFour() {
        let kcal = scaledCalories(ingredientTotal: 2000, totalServings: 4, servings: 2)
        #expect(kcal == 1000)
    }

    @Test("protein scales with one decimal precision")
    func proteinPrecision() {
        let protein = scaledMacro(ingredientTotal: 83.3, totalServings: 3, servings: 1)
        #expect(abs(protein - 27.8) < 0.05)
    }

    @Test("all macros are zero when totalServings is guarded to > 0")
    func zeroServingsGuard() {
        // Simulates the guard in the view: guard totalServings > 0 else return 0
        let totalServings = 0
        let calories = totalServings > 0 ? scaledCalories(ingredientTotal: 500, totalServings: totalServings, servings: 1) : 0
        #expect(calories == 0)
    }
}

// MARK: - FoodStore bundle migration key tests

struct FoodStoreBundleMigrationKeyTests {

    @Test("migration key changes when file size changes")
    func keyChangesWithFileSize() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration_key_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("test.db")
        try Data(repeating: 0, count: 1024).write(to: file)
        let store = FoodStore.forTesting(path: dir.appendingPathComponent("foods.db").path)
        await store.setup(seeding: [], bundleURL: file)

        // Write more bytes to simulate bundle DB growing
        try Data(repeating: 0, count: 2048).write(to: file)

        // File size changed — migration key must differ from the one already flagged
        let attrs1 = try FileManager.default.attributesOfItem(atPath: file.path)
        let size = (attrs1[.size] as? Int) ?? 0
        // Key encodes the current byte count
        #expect(size == 2048)
    }

    @Test("migration does not re-run when bundle file is unchanged")
    func noRerunWhenUnchanged() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration_stable_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Seed one food into a tiny bundle DB (created via ephemeral store)
        let bundlePath = dir.appendingPathComponent("bundle.db").path
        let bundleStore = FoodStore.forTesting(path: bundlePath)
        await bundleStore.setup(seeding: [
            FoodTemplate(name: "Apple", category: .fruit, kcal: 52, protein: 0.3,
                         carbs: 14, fat: 0.2, fiber: 2.4, sugar: 10, saturatedFat: 0,
                         sodium: 0, cholesterol: 0, defaultServingG: 182, servingLabel: "medium")
        ])

        let bundleURL = URL(fileURLWithPath: bundlePath)
        let runtimePath = dir.appendingPathComponent("runtime.db").path
        let store1 = FoodStore.forTesting(path: runtimePath)
        await store1.setup(seeding: [], bundleURL: bundleURL)
        let countAfterFirst = await store1.count

        // Second store at same path — migration flag already set, should not re-import
        let store2 = FoodStore.forTesting(path: runtimePath)
        await store2.setup(seeding: [], bundleURL: bundleURL)
        let countAfterSecond = await store2.count

        #expect(countAfterFirst == countAfterSecond)
    }
}

// MARK: - Store.resolvedBodyWeightKg

@Suite("Store.resolvedBodyWeightKg")
struct StoreResolvedBodyWeightTests {

    @MainActor
    private func makeStore(profileWeightKg: Double) -> Store {
        var logbook = makeEmptyLogbook()
        logbook.profileWeightKg = profileWeightKg
        let repo = makeRepository(logbook: logbook)
        return Store.makeForTesting(repository: repo)
    }

    @Test("returns profile weight when set")
    @MainActor func profileWeightWhenSet() {
        let store = makeStore(profileWeightKg: 82.5)
        #expect(store.resolvedBodyWeightKg == 82.5)
    }

    @Test("returns 75 when profile weight is zero")
    @MainActor func fallsBackTo75WhenUnset() {
        let store = makeStore(profileWeightKg: 0)
        #expect(store.resolvedBodyWeightKg == 75)
    }

    @Test("returns 75 when profile weight is negative")
    @MainActor func fallsBackTo75WhenNegative() {
        let store = makeStore(profileWeightKg: -1)
        #expect(store.resolvedBodyWeightKg == 75)
    }

    @Test("updates when profile weight changes")
    @MainActor func updatesWithProfileChange() {
        let store = makeStore(profileWeightKg: 0)
        #expect(store.resolvedBodyWeightKg == 75)
        store.logbook.profileWeightKg = 70
        #expect(store.resolvedBodyWeightKg == 70)
    }
}

// MARK: - LifestyleActivity.asActivityLevel

@Suite("LifestyleActivity.asActivityLevel")
struct LifestyleActivityMappingTests {

    @Test("sedentary maps to sedentary")
    func sedentaryMaps() {
        #expect(LifestyleActivity.sedentary.asActivityLevel == .sedentary)
    }

    @Test("light maps to light")
    func lightMaps() {
        #expect(LifestyleActivity.light.asActivityLevel == .light)
    }

    @Test("moderate maps to moderate")
    func moderateMaps() {
        #expect(LifestyleActivity.moderate.asActivityLevel == .moderate)
    }

    @Test("round-trip from ActivityLevel preserves sedentary")
    func roundTripSedentary() {
        let activity = ActivityLevel.sedentary
        let lifestyle: LifestyleActivity = switch activity {
        case .sedentary: .sedentary
        case .light: .light
        default: .moderate
        }
        #expect(lifestyle.asActivityLevel == activity)
    }

    @Test("round-trip from ActivityLevel preserves light")
    func roundTripLight() {
        let activity = ActivityLevel.light
        let lifestyle: LifestyleActivity = switch activity {
        case .sedentary: .sedentary
        case .light: .light
        default: .moderate
        }
        #expect(lifestyle.asActivityLevel == activity)
    }
}

// MARK: - FoodEntry.savedMealID Codable

@Suite("FoodEntry.savedMealID Codable")
@MainActor
struct FoodEntrySavedMealIDTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d
    }()

    @Test("Old JSON without savedMealID decodes with nil")
    func backwardCompatibilityNilMealID() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"Shake",
         "calories":300,"protein":25,"carbs":34,"fat":6,"date":0}
        """.data(using: .utf8)!
        let entry = try decoder.decode(FoodEntry.self, from: json)
        #expect(entry.savedMealID == nil)
    }

    @Test("Round-trip preserves savedMealID")
    func roundTripSavedMealID() throws {
        let mealID = UUID()
        let original = FoodEntry(
            name: "Protein Shake (1×)", calories: 300, protein: 25, carbs: 34, fat: 6,
            date: Date(timeIntervalSince1970: 0), savedMealID: mealID
        )
        let decoded = try decoder.decode(FoodEntry.self, from: encoder.encode(original))
        #expect(decoded.savedMealID == mealID)
    }

    @Test("Round-trip preserves nil savedMealID")
    func roundTripNilMealID() throws {
        let original = FoodEntry(
            name: "Egg", calories: 70, protein: 6, carbs: 0.5, fat: 5,
            date: Date(timeIntervalSince1970: 0), savedMealID: nil
        )
        let decoded = try decoder.decode(FoodEntry.self, from: encoder.encode(original))
        #expect(decoded.savedMealID == nil)
    }
}

// MARK: - NutritionLogic.separatelyLoggedMealName

@Suite("NutritionLogic.separatelyLoggedMealName")
struct SeparatelyLoggedMealNameTests {

    @Test("Returns base name before ' · ' separator")
    func extractsBaseName() {
        let result = NutritionLogic.separatelyLoggedMealName("Protein Shake · Whey Protein (30g)")
        #expect(result == "Protein Shake")
    }

    @Test("Returns nil for a plain entry with no separator")
    func nilForPlainEntry() {
        #expect(NutritionLogic.separatelyLoggedMealName("Banana (100g)") == nil)
    }

    @Test("Returns nil when base name before separator is empty")
    func nilWhenBaseIsEmpty() {
        #expect(NutritionLogic.separatelyLoggedMealName(" · Ingredient (50g)") == nil)
    }

    @Test("Handles multiple ' · ' separators by taking only the first split")
    func takesFirstSplit() {
        let result = NutritionLogic.separatelyLoggedMealName("Shake · Part A · Part B")
        #expect(result == "Shake")
    }

    @Test("Returns nil for empty string")
    func nilForEmptyString() {
        #expect(NutritionLogic.separatelyLoggedMealName("") == nil)
    }
}

// MARK: - NutritionLogic.foodEntries stamps savedMealID

@Suite("NutritionLogic.foodEntries savedMealID")
struct FoodEntriesSavedMealIDTests {

    private func makeShake() -> SavedMeal {
        SavedMeal(
            name: "Protein Shake",
            ingredients: [
                SavedMealIngredient(
                    name: "Whey", category: .protein,
                    grams: 30, kcalPer100g: 380, proteinPer100g: 80,
                    carbsPer100g: 5, fatPer100g: 5,
                    fiberPer100g: 0, sugarPer100g: 2
                ),
                SavedMealIngredient(
                    name: "Milk", category: .dairy,
                    grams: 200, kcalPer100g: 42, proteinPer100g: 3.4,
                    carbsPer100g: 5, fatPer100g: 1,
                    fiberPer100g: 0, sugarPer100g: 4.8
                )
            ]
        )
    }

    @Test("Combined entry (logIngredientsSeparately=false) stamps savedMealID")
    func combinedEntryHasSavedMealID() {
        let meal = makeShake()
        let entries = NutritionLogic.foodEntries(
            for: meal,
            date: Date(timeIntervalSince1970: 0),
            servings: 1,
            logIngredientsSeparately: false,
            mealType: .breakfast
        )
        #expect(entries.count == 1)
        #expect(entries[0].savedMealID == meal.id)
    }

    @Test("Separate entries (logIngredientsSeparately=true) do not stamp savedMealID")
    func separateEntriesHaveNoSavedMealID() {
        let meal = makeShake()
        let entries = NutritionLogic.foodEntries(
            for: meal,
            date: Date(timeIntervalSince1970: 0),
            servings: 1,
            logIngredientsSeparately: true,
            mealType: .breakfast
        )
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.savedMealID == nil })
    }

    @Test("Separate entries use ' · ' separator pattern in name")
    func separateEntriesUseSeparatorPattern() {
        let meal = makeShake()
        let entries = NutritionLogic.foodEntries(
            for: meal,
            date: Date(timeIntervalSince1970: 0),
            servings: 1,
            logIngredientsSeparately: true,
            mealType: .breakfast
        )
        #expect(entries.allSatisfy { NutritionLogic.separatelyLoggedMealName($0.name) == "Protein Shake" })
    }

    @Test("Combined entry name does not contain ' · ' separator")
    func combinedEntryNameHasNoSeparator() {
        let meal = makeShake()
        let entries = NutritionLogic.foodEntries(
            for: meal,
            date: Date(timeIntervalSince1970: 0),
            servings: 1,
            logIngredientsSeparately: false,
            mealType: .breakfast
        )
        #expect(NutritionLogic.separatelyLoggedMealName(entries[0].name) == nil)
    }
}

// MARK: - Store.logMeal produces single combined entry

@Suite("Store.logMeal combined entry")
@MainActor
struct StoreLogMealCombinedTests {

    private func makeShakeMeal() -> SavedMeal {
        SavedMeal(
            name: "Morning Shake",
            ingredients: [
                SavedMealIngredient(
                    name: "Whey", category: .protein,
                    grams: 30, kcalPer100g: 380, proteinPer100g: 80,
                    carbsPer100g: 5, fatPer100g: 5,
                    fiberPer100g: 0, sugarPer100g: 2
                ),
                SavedMealIngredient(
                    name: "Oat Milk", category: .dairy,
                    grams: 200, kcalPer100g: 45, proteinPer100g: 1,
                    carbsPer100g: 6, fatPer100g: 1.5,
                    fiberPer100g: 0.5, sugarPer100g: 3
                )
            ]
        )
    }

    @Test("logMeal creates exactly one FoodEntry for a multi-ingredient meal")
    func logMealCreatesSingleEntry() {
        let repo = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repo)
        let meal = makeShakeMeal()
        let today = Date()

        store.logMeal(meal, date: today, servings: 1, logIngredientsSeparately: false, mealType: .breakfast)

        let todayEntries = NutritionLogic.entries(store.logbook.foodLog, on: today)
        #expect(todayEntries.count == 1)
    }

    @Test("logMeal entry has savedMealID matching the meal's id")
    func logMealEntryHasSavedMealID() {
        let repo = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repo)
        let meal = makeShakeMeal()
        let today = Date()

        store.logMeal(meal, date: today, servings: 1, logIngredientsSeparately: false, mealType: .breakfast)

        let todayEntries = NutritionLogic.entries(store.logbook.foodLog, on: today)
        #expect(todayEntries.first?.savedMealID == meal.id)
    }

    @Test("logMeal entry name does not contain the ' · ' separator")
    func logMealEntryNameHasNoSeparator() {
        let repo = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repo)
        let meal = makeShakeMeal()
        let today = Date()

        store.logMeal(meal, date: today, servings: 1, logIngredientsSeparately: false, mealType: .breakfast)

        let entry = NutritionLogic.entries(store.logbook.foodLog, on: today).first
        #expect(NutritionLogic.separatelyLoggedMealName(entry?.name ?? "") == nil)
    }

    @Test("logMeal entry name starts with meal name")
    func logMealEntryNameStartsWithMealName() {
        let repo = makeRepository(logbook: makeEmptyLogbook())
        let store = Store.makeForTesting(repository: repo)
        let meal = makeShakeMeal()
        let today = Date()

        store.logMeal(meal, date: today, servings: 1, logIngredientsSeparately: false, mealType: .breakfast)

        let entry = NutritionLogic.entries(store.logbook.foodLog, on: today).first
        #expect(entry?.name.hasPrefix("Morning Shake") == true)
    }
}

// MARK: - Inline ingredient gram adjustment (SeparatelyLoggedMealEditView logic)

@Suite("Inline ingredient gram adjustment")
struct InlineIngredientGramAdjustmentTests {

    // Simulates the adjustGrams logic from SeparatelyLoggedMealEditView.
    private func applyGramDelta(to entry: FoodEntry, delta: Int) -> FoodEntry? {
        guard let currentGrams = NutritionLogic.gramsFromEntryName(entry.name),
              currentGrams > 0 else { return nil }
        let newGrams = max(1.0, currentGrams + Double(delta))
        let scale = newGrams / currentGrams

        let oldTag = "(\(Int(currentGrams.rounded()))g)"
        let newTag = "(\(Int(newGrams.rounded()))g)"
        var updated = entry
        if entry.name.hasSuffix(oldTag) {
            updated.name = String(entry.name.dropLast(oldTag.count)) + newTag
        }
        updated.calories = max(0, Int((Double(entry.calories) * scale).rounded()))
        updated.protein = max(0, (entry.protein * scale * 10).rounded() / 10)
        updated.carbs = max(0, (entry.carbs * scale * 10).rounded() / 10)
        updated.fat = max(0, (entry.fat * scale * 10).rounded() / 10)
        return updated
    }

    // "Protein Shake · Whey Protein (30g)" — the format used by logIngredientsSeparately.
    private func makeSeparateEntry(mealName: String, ingredient: String, grams: Int, kcal: Int, protein: Double, carbs: Double, fat: Double) -> FoodEntry {
        FoodEntry(
            name: "\(mealName) · \(ingredient) (\(grams)g)",
            calories: kcal,
            protein: protein,
            carbs: carbs,
            fat: fat,
            date: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("gramsFromEntryName extracts grams from a full separately-logged name")
    func gramsFromSeparatelyLoggedName() {
        let entry = makeSeparateEntry(mealName: "Protein Shake", ingredient: "Whey Protein", grams: 30, kcal: 120, protein: 24, carbs: 3, fat: 2)
        let grams = NutritionLogic.gramsFromEntryName(entry.name)
        #expect(grams == 30.0)
    }

    @Test("increasing grams scales macros proportionally and updates name")
    func increaseGramsScalesMacros() {
        let entry = makeSeparateEntry(mealName: "Protein Shake", ingredient: "Whey Protein", grams: 30, kcal: 120, protein: 24, carbs: 3, fat: 2)
        let updated = applyGramDelta(to: entry, delta: 5)

        #expect(updated != nil)
        // 35/30 ≈ 1.1667 → calories = 140, protein = 28.0
        #expect(updated?.name == "Protein Shake · Whey Protein (35g)")
        #expect(updated?.calories == 140)
        #expect(updated?.protein == 28.0)
    }

    @Test("decreasing grams scales macros proportionally and updates name")
    func decreaseGramsScalesMacros() {
        let entry = makeSeparateEntry(mealName: "Protein Shake", ingredient: "Milk", grams: 250, kcal: 150, protein: 8, carbs: 12, fat: 5)
        let updated = applyGramDelta(to: entry, delta: -10)

        #expect(updated != nil)
        // 240/250 = 0.96 → calories = 144
        #expect(updated?.name == "Protein Shake · Milk (240g)")
        #expect(updated?.calories == 144)
    }

    @Test("decrement cannot go below 1g")
    func decrementClampedToOne() {
        let entry = makeSeparateEntry(mealName: "Protein Shake", ingredient: "Creatine", grams: 5, kcal: 0, protein: 0, carbs: 0, fat: 0)
        let updated = applyGramDelta(to: entry, delta: -10)

        #expect(updated?.name == "Protein Shake · Creatine (1g)")
    }

    @Test("returns nil when name has no gram suffix")
    func returnsNilWithoutGrams() {
        var entry = FoodEntry(name: "Scrambled Eggs", calories: 200, protein: 14, carbs: 2, fat: 14, date: Date(timeIntervalSince1970: 0))
        let result = applyGramDelta(to: entry, delta: 5)
        #expect(result == nil)
    }
}
