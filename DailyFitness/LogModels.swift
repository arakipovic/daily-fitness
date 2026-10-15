// LogModels.swift
// Models for user logbook and workout logging

import Foundation

enum Unit: String, Codable, CaseIterable, Identifiable {
    case kg, lb
    var id: String { rawValue }

    var weightLabel: String     { self == .kg ? "kg"  : "lbs" }
    var weightAltLabel: String  { self == .kg ? "lbs" : "kg"  }
    var heightLabel: String     { self == .kg ? "cm"  : "ft / in" }

    func kgToDisplay(_ kg: Double) -> Double {
        self == .kg ? kg : kg * 2.20462
    }
    func displayToKg(_ val: Double) -> Double {
        self == .kg ? val : val / 2.20462
    }
    func displayWeightString(_ kg: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", kgToDisplay(kg))
    }

    func cmToFeetInches(_ cm: Double) -> (feet: Int, inches: Int) {
        let total = Int((cm / 2.54).rounded())
        return (total / 12, total % 12)
    }
    func feetInchesToCm(feet: Int, inches: Int) -> Double {
        Double(feet * 12 + inches) * 2.54
    }
}

enum RestAlertSetting: String, Codable, CaseIterable, Identifiable {
    case on, off
    var id: String { rawValue }
}

struct SetEntry: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var weight: String // "" or stringified Double
    var reps: String   // "" or stringified Int
    var rir: String    // "F", "0", "1"..."5"
    var done: Bool
}

struct ExerciseLog: Codable, Hashable, Sendable {
    var exerciseName: String
    var sets: [SetEntry]
    var note: String
    var swappedFrom: String? // nil if not swapped
}

struct SessionLog: Codable, Hashable, Sendable {
    var programID: String
    var week: Int
    var day: Int
    var started: Date?
    var completed: Date?
    var slotLogs: [String: ExerciseLog] // key: slot label
}

// Shared enums used in both profile storage and TDEE calculator
enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
    case male = "Male"
    case female = "Female"
    var id: String { rawValue }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary = "Sedentary"
    case light = "Lightly Active"
    case moderate = "Moderately Active"
    case active = "Very Active"
    case extra = "Extremely Active"
    var id: String { rawValue }
    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light:     return 1.375
        case .moderate:  return 1.55
        case .active:    return 1.725
        case .extra:     return 1.9
        }
    }
    var description: String {
        switch self {
        case .sedentary: return "Desk job, little or no exercise"
        case .light:     return "Light exercise 1–3 days/week"
        case .moderate:  return "Moderate exercise 3–5 days/week"
        case .active:    return "Hard exercise 6–7 days/week"
        case .extra:     return "Physical job + daily training"
        }
    }
}

enum MealType: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snacks = "Snacks"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch:     return "sun.max.fill"
        case .dinner:    return "moon.stars.fill"
        case .snacks:    return "popcorn.fill"
        }
    }

    static func guess(from date: Date, calendar: Calendar = .current) -> MealType {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<11:  return .breakfast
        case 11..<15: return .lunch
        case 15..<22: return .dinner
        default:      return .snacks
        }
    }
}

struct FoodEntry: Codable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var sugar: Double
    var saturatedFat: Double
    var sodium: Double      // mg
    var cholesterol: Double // mg
    var date: Date
    var meal: MealType
    /// When this entry was logged from a SavedMeal, the meal's stable ID is stored here
    /// so the user can open the meal builder and edit the day-specific log entry.
    var savedMealID: UUID?

    init(id: UUID = UUID(), name: String, calories: Int, protein: Double,
         carbs: Double, fat: Double, fiber: Double = 0, sugar: Double = 0,
         saturatedFat: Double = 0, sodium: Double = 0, cholesterol: Double = 0,
         date: Date, meal: MealType? = nil, savedMealID: UUID? = nil) {
        self.id = id; self.name = name; self.calories = calories
        self.protein = protein; self.carbs = carbs; self.fat = fat
        self.fiber = fiber; self.sugar = sugar; self.saturatedFat = saturatedFat
        self.sodium = sodium; self.cholesterol = cholesterol; self.date = date
        self.meal = meal ?? MealType.guess(from: date)
        self.savedMealID = savedMealID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        calories = try c.decode(Int.self, forKey: .calories)
        protein = try c.decode(Double.self, forKey: .protein)
        carbs = try c.decode(Double.self, forKey: .carbs)
        fat = try c.decode(Double.self, forKey: .fat)
        fiber = (try? c.decode(Double.self, forKey: .fiber)) ?? 0
        sugar = (try? c.decode(Double.self, forKey: .sugar)) ?? 0
        saturatedFat = (try? c.decode(Double.self, forKey: .saturatedFat)) ?? 0
        sodium = (try? c.decode(Double.self, forKey: .sodium)) ?? 0
        cholesterol = (try? c.decode(Double.self, forKey: .cholesterol)) ?? 0
        date = try c.decode(Date.self, forKey: .date)
        meal = (try? c.decode(MealType.self, forKey: .meal)) ?? MealType.guess(from: date)
        savedMealID = try? c.decode(UUID.self, forKey: .savedMealID)
    }
}

struct SavedMealIngredient: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var category: FoodCategory
    var grams: Double
    var kcalPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var fiberPer100g: Double
    var sugarPer100g: Double
    var saturatedFatPer100g: Double
    var sodiumPer100g: Double
    var cholesterolPer100g: Double
    var servingLabel: String?

    init(
        id: UUID = UUID(),
        name: String,
        category: FoodCategory,
        grams: Double,
        kcalPer100g: Double,
        proteinPer100g: Double,
        carbsPer100g: Double,
        fatPer100g: Double,
        fiberPer100g: Double = 0,
        sugarPer100g: Double = 0,
        saturatedFatPer100g: Double = 0,
        sodiumPer100g: Double = 0,
        cholesterolPer100g: Double = 0,
        servingLabel: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.grams = grams
        self.kcalPer100g = kcalPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g
        self.fatPer100g = fatPer100g
        self.fiberPer100g = fiberPer100g
        self.sugarPer100g = sugarPer100g
        self.saturatedFatPer100g = saturatedFatPer100g
        self.sodiumPer100g = sodiumPer100g
        self.cholesterolPer100g = cholesterolPer100g
        self.servingLabel = servingLabel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(FoodCategory.self, forKey: .category)
        grams = try c.decode(Double.self, forKey: .grams)
        kcalPer100g = try c.decode(Double.self, forKey: .kcalPer100g)
        proteinPer100g = try c.decode(Double.self, forKey: .proteinPer100g)
        carbsPer100g = try c.decode(Double.self, forKey: .carbsPer100g)
        fatPer100g = try c.decode(Double.self, forKey: .fatPer100g)
        fiberPer100g = (try? c.decode(Double.self, forKey: .fiberPer100g)) ?? 0
        sugarPer100g = (try? c.decode(Double.self, forKey: .sugarPer100g)) ?? 0
        saturatedFatPer100g = (try? c.decode(Double.self, forKey: .saturatedFatPer100g)) ?? 0
        sodiumPer100g = (try? c.decode(Double.self, forKey: .sodiumPer100g)) ?? 0
        cholesterolPer100g = (try? c.decode(Double.self, forKey: .cholesterolPer100g)) ?? 0
        servingLabel = try? c.decode(String.self, forKey: .servingLabel)
    }
}

struct SavedMeal: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var ingredients: [SavedMealIngredient]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        ingredients: [SavedMealIngredient],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.ingredients = ingredients
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct Logbook: Codable, Sendable {
    var selectedProgramID: String
    var startDate: Date
    var unit: Unit
    var restAlerts: RestAlertSetting
    var sessions: [String: SessionLog] // key: "programID|week|day"
    var customExerciseNames: [String]
    var foodLog: [FoodEntry]
    var savedMeals: [SavedMeal]
    var calorieTarget: Int
    var proteinTarget: Double
    var fiberTarget: Double
    // User profile
    var profileName: String
    var profileAge: Int
    var profileWeightKg: Double
    var profileTargetWeightKg: Double
    var profileHeightCm: Double
    var profileSex: BiologicalSex
    var profileActivity: ActivityLevel
    // Migration flag: true once the bundled legacy import has been merged
    var importedLegacyV1: Bool
    // Migration flag: true once personalSeedSessionsV2 has been merged
    var importedPersonalSeedV2: Bool
    // Set once the restore migration has re-inserted accidentally purged sessions.
    var restoredPersonalSeedV2: Bool
    // Time-series body measurements
    var bodyMeasurements: [BodyMeasurement]

    init(selectedProgramID: String, startDate: Date, unit: Unit,
         restAlerts: RestAlertSetting, sessions: [String: SessionLog],
         customExerciseNames: [String] = [],
         foodLog: [FoodEntry] = [], savedMeals: [SavedMeal] = [],
         calorieTarget: Int = 2000,
         proteinTarget: Double = 150, fiberTarget: Double = 30,
         profileName: String = "", profileAge: Int = 25,
         profileWeightKg: Double = 75, profileTargetWeightKg: Double = 0,
         profileHeightCm: Double = 175,
         profileSex: BiologicalSex = .male, profileActivity: ActivityLevel = .moderate,
         importedLegacyV1: Bool = false,
         importedPersonalSeedV2: Bool = false,
         restoredPersonalSeedV2: Bool = false,
         bodyMeasurements: [BodyMeasurement] = []) {
        self.selectedProgramID = selectedProgramID
        self.startDate = startDate
        self.unit = unit
        self.restAlerts = restAlerts
        self.sessions = sessions
        self.customExerciseNames = customExerciseNames
        self.foodLog = foodLog
        self.savedMeals = savedMeals
        self.calorieTarget = calorieTarget
        self.proteinTarget = proteinTarget
        self.fiberTarget = fiberTarget
        self.profileName = profileName
        self.profileAge = profileAge
        self.profileWeightKg = profileWeightKg
        self.profileTargetWeightKg = profileTargetWeightKg
        self.profileHeightCm = profileHeightCm
        self.profileSex = profileSex
        self.profileActivity = profileActivity
        self.importedLegacyV1 = importedLegacyV1
        self.importedPersonalSeedV2 = importedPersonalSeedV2
        self.restoredPersonalSeedV2 = restoredPersonalSeedV2
        self.bodyMeasurements = bodyMeasurements
    }

    static let empty = Logbook(
        selectedProgramID: "",
        startDate: Date(),
        unit: .kg,
        restAlerts: .on,
        sessions: [:]
    )

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedProgramID = try c.decode(String.self, forKey: .selectedProgramID)
        startDate = try c.decode(Date.self, forKey: .startDate)
        unit = try c.decode(Unit.self, forKey: .unit)
        restAlerts = try c.decode(RestAlertSetting.self, forKey: .restAlerts)
        sessions = try c.decode([String: SessionLog].self, forKey: .sessions)
        customExerciseNames = (try? c.decode([String].self, forKey: .customExerciseNames)) ?? []
        foodLog = (try? c.decode([FoodEntry].self, forKey: .foodLog)) ?? []
        savedMeals = (try? c.decode([SavedMeal].self, forKey: .savedMeals)) ?? []
        calorieTarget = (try? c.decode(Int.self, forKey: .calorieTarget)) ?? 2000
        proteinTarget = (try? c.decode(Double.self, forKey: .proteinTarget)) ?? 150
        fiberTarget = (try? c.decode(Double.self, forKey: .fiberTarget)) ?? 30
        profileName = (try? c.decode(String.self, forKey: .profileName)) ?? ""
        profileAge = (try? c.decode(Int.self, forKey: .profileAge)) ?? 25
        profileWeightKg = (try? c.decode(Double.self, forKey: .profileWeightKg)) ?? 75
        profileTargetWeightKg = (try? c.decode(Double.self, forKey: .profileTargetWeightKg)) ?? 0
        profileHeightCm = (try? c.decode(Double.self, forKey: .profileHeightCm)) ?? 175
        profileSex = (try? c.decode(BiologicalSex.self, forKey: .profileSex)) ?? .male
        profileActivity = (try? c.decode(ActivityLevel.self, forKey: .profileActivity)) ?? .moderate
        importedLegacyV1 = (try? c.decode(Bool.self, forKey: .importedLegacyV1)) ?? false
        importedPersonalSeedV2 = (try? c.decode(Bool.self, forKey: .importedPersonalSeedV2)) ?? false
        restoredPersonalSeedV2 = (try? c.decode(Bool.self, forKey: .restoredPersonalSeedV2)) ?? false
        bodyMeasurements = (try? c.decode([BodyMeasurement].self, forKey: .bodyMeasurements)) ?? []
    }
}

// MARK: - Body measurements

struct BodyMeasurement: Codable, Identifiable, Sendable {
    var id: UUID
    var date: Date
    var waistCm: Double?
    var chestCm: Double?
    var hipsCm: Double?
    var thighsCm: Double?
    var armsCm: Double?
    var neckCm: Double?
    var bodyFatPercent: Double?
    var note: String

    init(id: UUID = UUID(), date: Date,
         waistCm: Double? = nil, chestCm: Double? = nil, hipsCm: Double? = nil,
         thighsCm: Double? = nil, armsCm: Double? = nil, neckCm: Double? = nil,
         bodyFatPercent: Double? = nil, note: String = "") {
        self.id = id
        self.date = date
        self.waistCm = waistCm
        self.chestCm = chestCm
        self.hipsCm = hipsCm
        self.thighsCm = thighsCm
        self.armsCm = armsCm
        self.neckCm = neckCm
        self.bodyFatPercent = bodyFatPercent
        self.note = note
    }

    var hasAnyMeasurement: Bool {
        [waistCm, chestCm, hipsCm, thighsCm, armsCm, neckCm, bodyFatPercent].contains { $0 != nil }
    }
}
