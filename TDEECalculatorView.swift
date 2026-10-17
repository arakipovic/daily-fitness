import SwiftUI

// BiologicalSex and ActivityLevel are defined in LogModels.swift

// MARK: - Calculator-specific enums

enum ProteinPreference: String, CaseIterable, Identifiable {
    case moderate = "Moderate"
    case high     = "High"
    var id: String { rawValue }
    var description: String {
        switch self {
        case .moderate: return "~1.6g per kg bodyweight"
        case .high:     return "~2.0g per kg bodyweight"
        }
    }
    var multiplier: Double { self == .moderate ? 1.6 : 2.0 }
}

enum LifestyleActivity: String, CaseIterable, Identifiable {
    case sedentary = "Sedentary"
    case light     = "Lightly Active"
    case moderate  = "Moderately Active"
    var id: String { rawValue }
    var description: String {
        switch self {
        case .sedentary: return "Desk job, minimal walking"
        case .light:     return "Some walking, standing job"
        case .moderate:  return "Physical job or active lifestyle"
        }
    }
    // Represents non-exercise NEAT only — workouts are added separately via HealthKit
    var baseMultiplier: Double {
        switch self { case .sedentary: 1.20; case .light: 1.27; case .moderate: 1.35 }
    }
    var asActivityLevel: ActivityLevel {
        switch self {
        case .sedentary: .sedentary
        case .light: .light
        case .moderate: .moderate
        }
    }
}

enum GoalType: String, CaseIterable, Identifiable {
    case lose     = "Lose Fat"
    case maintain = "Maintain Weight"
    case gain     = "Build Muscle"
    var id: String { rawValue }
    var description: String {
        switch self {
        case .lose:     return "Reduce body fat while preserving muscle"
        case .maintain: return "Eat at maintenance — no weight change intended"
        case .gain:     return "Add muscle with a controlled calorie surplus"
        }
    }
}

// MARK: - View

struct TDEECalculatorView: View {
    let onApply: (Int, Double, Double) -> Void  // (calories, protein, fiber)
    let showsCancelButton: Bool
    let dismissOnApply: Bool
    let showsTargetControls: Bool
    let showsNutritionShortcuts: Bool
    let navigationTitle: String

    @Environment(Store.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(\.dismiss) private var dismiss

    // Stats (display units — lbs or kg, ft/in or cm)
    @State private var weightDisplay = ""
    @State private var targetWeightDisplay = ""
    @State private var heightCm = ""    // metric display
    @State private var heightFt = ""    // imperial display
    @State private var heightIn = ""    // imperial display
    @State private var age = ""
    @State private var sex: BiologicalSex = .male

    // Goal
    @State private var goalType: GoalType = .maintain

    // Activity
    @State private var lifestyle: LifestyleActivity = .sedentary

    // Preference
    @State private var proteinPref: ProteinPreference = .moderate

    // MARK: Computed

    private var unit: Unit { store.logbook.unit }

    /// Current weight in kg, regardless of display unit.
    private var weightVal: Double {
        unit.displayToKg(Double(weightDisplay) ?? 0)
    }
    /// Target weight in kg, regardless of display unit.
    private var targetWeightVal: Double {
        unit.displayToKg(Double(targetWeightDisplay) ?? 0)
    }
    /// Height in cm, regardless of display unit.
    private var heightVal: Double {
        unit == .kg
            ? (Double(heightCm) ?? 0)
            : unit.feetInchesToCm(feet: Int(heightFt) ?? 0, inches: Int(heightIn) ?? 0)
    }
    private var ageVal:    Double { Double(age)       ?? 0 }

    private var bmr: Double {
        guard weightVal > 0, heightVal > 0, ageVal > 0 else { return 0 }
        let base = 10 * weightVal + 6.25 * heightVal - 5 * ageVal
        return sex == .male ? base + 5 : base - 161
    }

    /// Formula fallback: BMR × lifestyle multiplier. Only used when HealthKit resting energy is unavailable.
    private var tdee: Double { bmr * lifestyle.baseMultiplier }

    /// Measured resting energy from Apple Watch (7-day average). Preferred over formula when available.
    private var measuredRestingEnergy: Double? { healthKit.avgRestingEnergyKcal }

    /// Weight trend from HealthKit 7-day data (kg/week), nil if insufficient
    private var weightTrendPerWeek: Double? {
        let pairs = healthKit.weeklyWeightKg.map { (date: $0.date, kg: $0.weightKg) }
        return NutritionLogic.weightTrendPerWeek(from: pairs)
    }

    /// 14-day avg calories from food log — nil if fewer than 5 days logged (too noisy)
    private var avgDailyIntake: Double? {
        let summary = AnalyticsLogic.nutritionSummary(from: store.logbook.foodLog, days: 14)
        guard summary.loggedDays >= 5 else { return nil }
        return summary.avgCalories
    }

    /// Maintenance back-calculated from actual intake + weight trend (more reliable than formula)
    private var backCalculatedMaintenance: Double? {
        guard let intake = avgDailyIntake, let trend = weightTrendPerWeek else { return nil }
        let m = NutritionLogic.estimatedMaintenance(avgDailyKcal: intake, weightChangePer7Days: trend)
        guard m > 1000, m < 5000 else { return nil }
        return m
    }

    /// Priority: back-calculated (most accurate) → measured resting energy (Apple Watch) → formula (no HealthKit)
    private var targetCalories: Int {
        Int((backCalculatedMaintenance ?? measuredRestingEnergy ?? tdee).rounded())
    }

    /// Estimated weeks the user has been consistently below maintenance (from food log).
    private var weeksInDeficit: Int {
        guard targetCalories > 0 else { return 0 }
        let daily = AnalyticsLogic.dailyNutrition(from: store.logbook.foodLog, days: 56)
        let daysBelow = daily.filter { $0.calories > 0 && $0.calories < targetCalories }.count
        return daysBelow / 7
    }

    private var goalRecommendation: NutritionLogic.WeightGoalRecommendation? {
        guard targetWeightVal > 0, weightVal > 0 else { return nil }
        return NutritionLogic.weightGoalRecommendation(
            currentWeightKg: weightVal,
            targetWeightKg: targetWeightVal,
            weeksInDeficit: weeksInDeficit
        )
    }

    /// Calories adjusted for the user's chosen goal. Never below 1,200 kcal.
    private var goalAdjustedCalories: Int {
        switch goalType {
        case .maintain:
            return targetCalories
        case .lose:
            if let rec = goalRecommendation { return max(1200, targetCalories + rec.dailyCalorieAdjustment) }
            return max(1200, targetCalories - 500)
        case .gain:
            if let rec = goalRecommendation { return max(1200, targetCalories + rec.dailyCalorieAdjustment) }
            return targetCalories + 300
        }
    }

    private var proteinG: Double {
        guard weightVal > 0 else { return 0 }
        let raw = weightVal * proteinPref.multiplier
        return (raw / 5).rounded() * 5  // round to nearest 5g
    }

    private var fiberG: Double {
        let cal = goalAdjustedCalories > 0 ? goalAdjustedCalories : targetCalories
        guard cal > 0 else { return 0 }
        return (Double(cal) / 1000.0 * 14.0).rounded()
    }

    private var isReady: Bool { bmr > 0 }

    init(
        onApply: @escaping (Int, Double, Double) -> Void,
        showsCancelButton: Bool = true,
        dismissOnApply: Bool = true,
        showsTargetControls: Bool = false,
        showsNutritionShortcuts: Bool = false,
        navigationTitle: String = "Nutrition Calculator"
    ) {
        self.onApply = onApply
        self.showsCancelButton = showsCancelButton
        self.dismissOnApply = dismissOnApply
        self.showsTargetControls = showsTargetControls
        self.showsNutritionShortcuts = showsNutritionShortcuts
        self.navigationTitle = navigationTitle
    }

    var body: some View {
        NavigationStack {
            Form {
                if showsTargetControls {
                    Section {
                        LabeledContent("Calories") {
                            Text("\(store.logbook.calorieTarget) kcal")
                                .fontWeight(.semibold)
                        }
                        LabeledContent("Protein") {
                            Text("\(Int(store.logbook.proteinTarget))g")
                                .fontWeight(.semibold)
                        }
                        LabeledContent("Fiber") {
                            Text("\(Int(store.logbook.fiberTarget))g")
                                .fontWeight(.semibold)
                        }
                    } header: {
                        Text("Current Targets")
                    } footer: {
                        Text("Use the calculator below to update your targets.")
                    }
                }

                Section {
                    ForEach(GoalType.allCases) { g in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.rawValue).font(.subheadline)
                                Text(g.description).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if goalType == g {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { goalType = g }
                    }
                } header: {
                    Text("What's Your Goal?")
                }

                Section("Your Stats") {
                    LabeledContent("Weight (\(unit.weightLabel))") {
                        TextField(unit == .kg ? "75" : "165", text: $weightDisplay)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if goalType != .maintain {
                        LabeledContent("Goal Weight (\(unit.weightLabel))") {
                            TextField("optional · for timeline", text: $targetWeightDisplay)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if unit == .kg {
                        LabeledContent("Height (cm)") {
                            TextField("175", text: $heightCm)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    } else {
                        LabeledContent("Height") {
                            HStack(spacing: 4) {
                                TextField("5", text: $heightFt)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 40)
                                Text("ft").foregroundStyle(.secondary)
                                TextField("10", text: $heightIn)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 40)
                                Text("in").foregroundStyle(.secondary)
                            }
                        }
                    }
                    LabeledContent("Age") {
                        TextField("30", text: $age)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Sex", selection: $sex) {
                        ForEach(BiologicalSex.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                }

                if measuredRestingEnergy == nil {
                    Section {
                        ForEach(LifestyleActivity.allCases) { level in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(level.rawValue).font(.subheadline)
                                    Text(level.description).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if lifestyle == level {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { lifestyle = level }
                        }
                    } header: {
                        Text("Lifestyle Activity")
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Select the level that best matches your overall daily activity including exercise. Connect Apple Watch to replace this with a measured resting energy instead.")
                            if let suggested = healthKit.suggestedLifestyle {
                                let avgSteps = healthKit.weeklySteps.isEmpty ? 0
                                    : Int(healthKit.weeklySteps.map(\.steps).reduce(0, +) / Double(healthKit.weeklySteps.count))
                                Label("~\(avgSteps.formatted()) steps/day average suggests \(suggested.rawValue).",
                                      systemImage: "figure.walk")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Protein Preference") {
                    ForEach(ProteinPreference.allCases) { pref in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pref.rawValue).font(.subheadline)
                                Text(pref.description).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if proteinPref == pref {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { proteinPref = pref }
                    }
                }

                if isReady {
                    Section {
                        // All three estimates shown for comparison — checkmark indicates which is in use
                        if let maintenance = backCalculatedMaintenance {
                            ResultRow(label: "Back-calculated",
                                      value: "\(Int(maintenance.rounded())) kcal",
                                      note: "food log + weight trend · includes all activity",
                                      icon: "checkmark.circle.fill", iconColor: .green)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .foregroundStyle(.secondary)
                                Text("Log food for 5+ days and sync weight to Apple Health for a back-calculated estimate.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let resting = measuredRestingEnergy {
                            ResultRow(label: "Apple Watch",
                                      value: "\(Int(resting.rounded())) kcal",
                                      note: "7-day avg resting energy",
                                      icon: backCalculatedMaintenance == nil ? "checkmark.circle.fill" : nil,
                                      iconColor: .green)
                        } else {
                            ResultRow(label: "Apple Watch",
                                      value: "not paired",
                                      note: "connect to measure resting energy directly")
                        }

                        ResultRow(label: "Formula",
                                  value: "\(Int(tdee.rounded())) kcal",
                                  note: "BMR \(Int(bmr.rounded())) × \(String(format: "%.2f", lifestyle.baseMultiplier)) \(lifestyle.rawValue.lowercased())",
                                  icon: backCalculatedMaintenance == nil && measuredRestingEnergy == nil ? "checkmark.circle.fill" : nil,
                                  iconColor: .green)

                        Divider()

                        if goalType == .maintain {
                            ResultRow(label: "Daily Target",
                                      value: "\(targetCalories) kcal",
                                      note: backCalculatedMaintenance != nil ? "maintenance · using back-calculated"
                                          : measuredRestingEnergy != nil ? "maintenance · using Apple Watch"
                                          : "maintenance · using formula")
                        } else if let rec = goalRecommendation {
                            let dirIcon = rec.direction == .lose ? "arrow.down.circle.fill" : "arrow.up.circle.fill"
                            let dirColor: Color = rec.direction == .lose ? .orange : .green
                            ResultRow(
                                label: rec.direction == .lose
                                    ? "Goal: lose \(String(format: "%.1f", unit.kgToDisplay(weightVal - targetWeightVal))) \(unit.weightLabel)"
                                    : "Goal: gain \(String(format: "%.1f", unit.kgToDisplay(targetWeightVal - weightVal))) \(unit.weightLabel)",
                                value: "\(abs(rec.dailyCalorieAdjustment)) kcal \(rec.direction == .lose ? "deficit" : "surplus")",
                                note: String(format: "~%.2f kg/week", rec.weeklyRateKg)
                                    + (rec.estimatedWeeks.map { " · ~\($0) weeks to goal" } ?? ""),
                                icon: dirIcon, iconColor: dirColor
                            )
                            if rec.suggestDietBreak {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.yellow)
                                    Text("You've been in a deficit for 8+ weeks. Consider 1–2 weeks at maintenance before continuing.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            ResultRow(label: "Daily Target",
                                      value: "\(goalAdjustedCalories) kcal",
                                      note: "maintenance \(targetCalories) \(rec.direction == .lose ? "−" : "+")\(abs(rec.dailyCalorieAdjustment))")
                        } else {
                            let adj = goalType == .lose ? 500 : 300
                            ResultRow(label: "Daily Target",
                                      value: "\(goalAdjustedCalories) kcal",
                                      note: "maintenance \(targetCalories) \(goalType == .lose ? "− \(adj) (standard deficit)" : "+ \(adj) (lean bulk)")")
                        }

                        ResultRow(label: "Protein",  value: "\(Int(proteinG))g",
                                  note: "\(String(format: "%.1f", proteinPref.multiplier))g/kg · \(proteinPref.rawValue.lowercased())")
                        ResultRow(label: "Fiber",    value: "\(Int(fiberG))g",
                                  note: "14g per 1,000 kcal")
                    } header: {
                        Text("Your Targets")
                    }

                    Section {
                        Text("All three estimates are shown so you can see how far apart the formula is from your real data. The formula is a rough starting point — after 1–2 weeks of tracking your weight trend will back-calculate your actual maintenance.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        Button {
                            if let w = Double(weightDisplay), w > 0 { store.logbook.profileWeightKg = unit.displayToKg(w) }
                            if let t = Double(targetWeightDisplay), t > 0 { store.logbook.profileTargetWeightKg = unit.displayToKg(t) }
                            else { store.logbook.profileTargetWeightKg = 0 }
                            let hCm = unit == .kg
                                ? (Double(heightCm) ?? 0)
                                : unit.feetInchesToCm(feet: Int(heightFt) ?? 0, inches: Int(heightIn) ?? 0)
                            if hCm > 0 { store.logbook.profileHeightCm = hCm }
                            if let a = Int(age), a > 0 { store.logbook.profileAge = a }
                            store.logbook.profileSex = sex
                            store.logbook.profileActivity = lifestyle.asActivityLevel
                            store.updateTargets(
                                calories: goalAdjustedCalories,
                                protein: proteinG,
                                fiber: fiberG
                            )
                            onApply(goalAdjustedCalories, proteinG, fiberG)
                            if dismissOnApply {
                                dismiss()
                            }
                        } label: {
                            Text(dismissOnApply ? "Apply These Targets" : "Update Targets")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                    } footer: {
                        Text("Revisit every 2–3 weeks as your weight changes.")
                            .font(.caption)
                    }
                }

                if showsNutritionShortcuts {
                    Section("Tracking") {
                        NavigationLink {
                            FoodLogView()
                        } label: {
                            Label("Food Log", systemImage: "fork.knife.circle.fill")
                        }
                        NavigationLink {
                            FoodDatabaseBrowserView()
                        } label: {
                            Label("Food Database", systemImage: "list.bullet.rectangle")
                        }
                    }

                    Section("Tools") {
                        NavigationLink {
                            MacroCalculatorView()
                        } label: {
                            Label("Meal Macro Calculator", systemImage: "scalemass")
                        }
                        NavigationLink {
                            AlcoholCalculatorView()
                        } label: {
                            Label("Alcohol Macro Adjuster", systemImage: "wineglass")
                        }
                    }

                    Section("Learn") {
                        NavigationLink {
                            NutritionGuideView()
                        } label: {
                            Label("Nutrition Guide", systemImage: "book.pages")
                        }
                        NavigationLink {
                            RecipesView()
                        } label: {
                            Label("Recipe Book", systemImage: "fork.knife.circle")
                        }
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(showsCancelButton ? .inline : .large)
            .trackScreen("tdee_calculator")
            .toolbar {
                if showsCancelButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .onAppear {
                let lb = store.logbook
                let sourceWeightKg = lb.profileWeightKg > 0 ? lb.profileWeightKg : healthKit.recentWeightKg
                if let w = sourceWeightKg, w > 0 {
                    weightDisplay = String(format: "%.1f", unit.kgToDisplay(w))
                }
                if lb.profileTargetWeightKg > 0 {
                    targetWeightDisplay = String(format: "%.1f", unit.kgToDisplay(lb.profileTargetWeightKg))
                    let currentKg = lb.profileWeightKg > 0 ? lb.profileWeightKg : (healthKit.recentWeightKg ?? 0)
                    if lb.profileTargetWeightKg < currentKg { goalType = .lose }
                    else if lb.profileTargetWeightKg > currentKg { goalType = .gain }
                }
                if lb.profileHeightCm > 0 {
                    if unit == .kg {
                        heightCm = String(format: "%.0f", lb.profileHeightCm)
                    } else {
                        let (ft, inches) = unit.cmToFeetInches(lb.profileHeightCm)
                        heightFt = "\(ft)"
                        heightIn = "\(inches)"
                    }
                }
                if lb.profileAge > 0 { age = "\(lb.profileAge)" }
                sex = lb.profileSex
                lifestyle = switch lb.profileActivity {
                    case .sedentary: LifestyleActivity.sedentary
                    case .light: LifestyleActivity.light
                    default: LifestyleActivity.moderate
                }
                // On first setup (no profile data yet), suggest activity level from step data
                if lb.profileWeightKg == 0, let suggested = healthKit.suggestedLifestyle {
                    lifestyle = suggested
                }
            }
        }
    }
}

private struct ResultRow: View {
    let label: String
    let value: String
    let note: String
    var icon: String? = nil
    var iconColor: Color = .accentColor

    var body: some View {
        HStack {
            if let icon {
                Image(systemName: icon).foregroundStyle(iconColor).frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline)
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value).font(.subheadline.weight(.semibold))
        }
    }
}
