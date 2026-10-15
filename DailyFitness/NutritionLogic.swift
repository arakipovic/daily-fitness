import Foundation

// MARK: - Functional core for nutrition calculations
// Pure static functions — no Store access, no HealthKit, fully testable.

struct NutritionDailySummary: Equatable, Sendable {
    let entryCount: Int
    let calories: Int
    let protein: Double
    let carbs: Double
    let fiber: Double
    let calorieBudget: Int
    let caloriesRemaining: Int
    let proteinRemaining: Double
    let carbsTarget: Double
    let carbsRemaining: Double
    let fiberRemaining: Double

    var isOverCalories: Bool {
        caloriesRemaining < 0
    }
}

enum NutritionLogic {

    // MARK: - Daily entries

    /// Filters a food log to entries logged on the given date.
    static func entries(
        _ foodLog: [FoodEntry],
        on date: Date,
        calendar: Calendar = .current
    ) -> [FoodEntry] {
        foodLog.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    // MARK: - Daily totals

    static func totalCalories(_ entries: [FoodEntry]) -> Int {
        entries.reduce(0) { $0 + $1.calories }
    }

    static func totalProtein(_ entries: [FoodEntry]) -> Double {
        entries.reduce(0) { $0 + $1.protein }
    }

    static func totalCarbs(_ entries: [FoodEntry]) -> Double {
        entries.reduce(0) { $0 + $1.carbs }
    }

    static func totalFat(_ entries: [FoodEntry]) -> Double {
        entries.reduce(0) { $0 + $1.fat }
    }

    static func totalFiber(_ entries: [FoodEntry]) -> Double {
        entries.reduce(0) { $0 + $1.fiber }
    }

    static func totalSugar(_ entries: [FoodEntry]) -> Double {
        entries.reduce(0) { $0 + $1.sugar }
    }

    static func totalSaturatedFat(_ entries: [FoodEntry]) -> Double {
        entries.reduce(0) { $0 + $1.saturatedFat }
    }

    static func totalSodium(_ entries: [FoodEntry]) -> Double {
        entries.reduce(0) { $0 + $1.sodium }
    }

    static func totalCholesterol(_ entries: [FoodEntry]) -> Double {
        entries.reduce(0) { $0 + $1.cholesterol }
    }

    // MARK: - Calorie budget

    /// Total available calories: base target plus any activity-earned calories.
    static func calorieBudget(target: Int, activeCalories: Int) -> Int {
        target + max(0, activeCalories)
    }

    /// Remaining calories after food intake.
    static func caloriesRemaining(budget: Int, eaten: Int) -> Int {
        budget - eaten
    }

    static func defaultCarbsTarget(calorieTarget: Int) -> Double {
        // ~45% of calories from carbs at 4 kcal/g
        Double(calorieTarget) * 0.45 / 4
    }

    static func dailySummary(
        foodLog: [FoodEntry],
        on date: Date,
        calorieTarget: Int,
        proteinTarget: Double,
        fiberTarget: Double,
        activeCalories: Int,
        calendar: Calendar = .current
    ) -> NutritionDailySummary {
        let dayEntries = entries(foodLog, on: date, calendar: calendar)
        let calories = totalCalories(dayEntries)
        let protein = totalProtein(dayEntries)
        let carbs = totalCarbs(dayEntries)
        let fiber = totalFiber(dayEntries)
        let budget = calorieBudget(target: calorieTarget, activeCalories: activeCalories)
        let cTarget = defaultCarbsTarget(calorieTarget: calorieTarget)

        return NutritionDailySummary(
            entryCount: dayEntries.count,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fiber: fiber,
            calorieBudget: budget,
            caloriesRemaining: caloriesRemaining(budget: budget, eaten: calories),
            proteinRemaining: proteinTarget - protein,
            carbsTarget: cTarget,
            carbsRemaining: cTarget - carbs,
            fiberRemaining: fiberTarget - fiber
        )
    }

    static func groupedByMeal(_ entries: [FoodEntry]) -> [MealType: [FoodEntry]] {
        Dictionary(grouping: entries) { $0.meal }
    }

    static func copyEntries(
        _ entries: [FoodEntry],
        to targetDate: Date,
        calendar: Calendar = .current
    ) -> [FoodEntry] {
        let targetComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
        return entries.map { entry in
            let sourceComponents = calendar.dateComponents([.hour, .minute, .second], from: entry.date)
            var combined = targetComponents
            combined.hour = sourceComponents.hour
            combined.minute = sourceComponents.minute
            combined.second = sourceComponents.second
            let newDate = calendar.date(from: combined) ?? targetDate
            return FoodEntry(
                name: entry.name,
                calories: entry.calories,
                protein: entry.protein,
                carbs: entry.carbs,
                fat: entry.fat,
                fiber: entry.fiber,
                sugar: entry.sugar,
                saturatedFat: entry.saturatedFat,
                sodium: entry.sodium,
                cholesterol: entry.cholesterol,
                date: newDate,
                meal: entry.meal
            )
        }
    }

    // MARK: - Macro scaling

    /// Scales per-100g macros to the given serving size. Returns a tuple matching FoodTemplate.macros().
    static func scaleMacros(
        kcalPer100g: Int,
        proteinPer100g: Double,
        carbsPer100g: Double,
        fatPer100g: Double,
        fiberPer100g: Double = 0,
        sugarPer100g: Double = 0,
        saturatedFatPer100g: Double = 0,
        sodiumPer100g: Double = 0,
        cholesterolPer100g: Double = 0,
        grams: Double
    ) -> (
        kcal: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double,
        sugar: Double,
        saturatedFat: Double,
        sodium: Double,
        cholesterol: Double
    ) {
        let factor = grams / 100.0
        return (
            kcal: Int((Double(kcalPer100g) * factor).rounded()),
            protein: (proteinPer100g * factor * 10).rounded() / 10,
            carbs: (carbsPer100g * factor * 10).rounded() / 10,
            fat: (fatPer100g * factor * 10).rounded() / 10,
            fiber: (fiberPer100g * factor * 10).rounded() / 10,
            sugar: (sugarPer100g * factor * 10).rounded() / 10,
            saturatedFat: (saturatedFatPer100g * factor * 10).rounded() / 10,
            sodium: (sodiumPer100g * factor).rounded(),
            cholesterol: (cholesterolPer100g * factor).rounded()
        )
    }

    static func scaleMacros(
        kcalPer100g: Double,
        proteinPer100g: Double,
        carbsPer100g: Double,
        fatPer100g: Double,
        fiberPer100g: Double = 0,
        sugarPer100g: Double = 0,
        saturatedFatPer100g: Double = 0,
        sodiumPer100g: Double = 0,
        cholesterolPer100g: Double = 0,
        grams: Double
    ) -> (
        kcal: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double,
        sugar: Double,
        saturatedFat: Double,
        sodium: Double,
        cholesterol: Double
    ) {
        let factor = max(0, grams) / 100.0
        return (
            kcal: Int((kcalPer100g * factor).rounded()),
            protein: (proteinPer100g * factor * 10).rounded() / 10,
            carbs: (carbsPer100g * factor * 10).rounded() / 10,
            fat: (fatPer100g * factor * 10).rounded() / 10,
            fiber: (fiberPer100g * factor * 10).rounded() / 10,
            sugar: (sugarPer100g * factor * 10).rounded() / 10,
            saturatedFat: (saturatedFatPer100g * factor * 10).rounded() / 10,
            sodium: (sodiumPer100g * factor).rounded(),
            cholesterol: (cholesterolPer100g * factor).rounded()
        )
    }

    // MARK: - Saved meals

    static func macros(
        for ingredient: SavedMealIngredient,
        servings: Double = 1
    ) -> (
        kcal: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double,
        sugar: Double,
        saturatedFat: Double,
        sodium: Double,
        cholesterol: Double
    ) {
        scaleMacros(
            kcalPer100g: ingredient.kcalPer100g,
            proteinPer100g: ingredient.proteinPer100g,
            carbsPer100g: ingredient.carbsPer100g,
            fatPer100g: ingredient.fatPer100g,
            fiberPer100g: ingredient.fiberPer100g,
            sugarPer100g: ingredient.sugarPer100g,
            saturatedFatPer100g: ingredient.saturatedFatPer100g,
            sodiumPer100g: ingredient.sodiumPer100g,
            cholesterolPer100g: ingredient.cholesterolPer100g,
            grams: ingredient.grams * max(0, servings)
        )
    }

    static func macros(
        for meal: SavedMeal,
        servings: Double = 1
    ) -> (
        kcal: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double,
        sugar: Double,
        saturatedFat: Double,
        sodium: Double,
        cholesterol: Double
    ) {
        meal.ingredients.reduce((0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)) { total, ingredient in
            let macros = macros(for: ingredient, servings: servings)
            return (
                total.0 + macros.kcal,
                total.1 + macros.protein,
                total.2 + macros.carbs,
                total.3 + macros.fat,
                total.4 + macros.fiber,
                total.5 + macros.sugar,
                total.6 + macros.saturatedFat,
                total.7 + macros.sodium,
                total.8 + macros.cholesterol
            )
        }
    }

    static func foodEntries(
        for meal: SavedMeal,
        date: Date,
        servings: Double = 1,
        logIngredientsSeparately: Bool = false,
        mealType: MealType? = nil
    ) -> [FoodEntry] {
        let servings = max(0, servings)
        guard servings > 0 else { return [] }
        let resolvedMeal = mealType ?? MealType.guess(from: date)

        if logIngredientsSeparately {
            return meal.ingredients.map { ingredient in
                let macros = macros(for: ingredient, servings: servings)
                let grams = Int((ingredient.grams * servings).rounded())
                return FoodEntry(
                    name: "\(meal.name) · \(ingredient.name) (\(grams)g)",
                    calories: macros.kcal,
                    protein: macros.protein,
                    carbs: macros.carbs,
                    fat: macros.fat,
                    fiber: macros.fiber,
                    sugar: macros.sugar,
                    saturatedFat: macros.saturatedFat,
                    sodium: macros.sodium,
                    cholesterol: macros.cholesterol,
                    date: date,
                    meal: resolvedMeal
                )
            }
        }

        let totals = macros(for: meal, servings: servings)
        return [
            FoodEntry(
                name: "\(meal.name) (\(servingText(servings)))",
                calories: totals.kcal,
                protein: totals.protein,
                carbs: totals.carbs,
                fat: totals.fat,
                fiber: totals.fiber,
                sugar: totals.sugar,
                saturatedFat: totals.saturatedFat,
                sodium: totals.sodium,
                cholesterol: totals.cholesterol,
                date: date,
                meal: resolvedMeal,
                savedMealID: meal.id
            )
        ]
    }

    // When a FoodEntry was logged before fiber tracking was added, its stored fiber is 0.
    // This function returns the correct fiber value by looking up the matching template
    // and computing fiber from the gram amount encoded in the entry name.
    static func backfilledFiber(for entry: FoodEntry, database: [FoodTemplate] = foodDatabase) -> Double {
        guard entry.fiber == 0 else { return entry.fiber }
        guard let template = database.first(where: { entry.name.hasPrefix($0.name + " (") || entry.name == $0.name }),
              template.fiber > 0 else { return 0 }
        guard let grams = gramsFromEntryName(entry.name), grams > 0 else { return 0 }
        return (template.fiber * grams / 100 * 10).rounded() / 10
    }

    // Returns the gram amount from the most recently logged entry that matches the given template.
    static func lastLoggedGrams(forFood food: FoodTemplate, in log: [FoodEntry]) -> Double? {
        log
            .filter { $0.name.hasPrefix(food.name + " (") || $0.name == food.name }
            .sorted { $0.date > $1.date }
            .compactMap { gramsFromEntryName($0.name) }
            .first
    }

    // Extracts the "N×" serving multiplier from names like "Beef Jerky (2×)".
    // Returns nil for plain names or gram-based names like "Chicken Breast (150g)".
    static func parseServingsFromEntryName(_ name: String) -> Double? {
        guard name.hasSuffix("×)") else { return nil }
        let withoutSuffix = name.dropLast(2)
        guard let parenIdx = withoutSuffix.lastIndex(of: "(") else { return nil }
        let numStr = String(withoutSuffix[withoutSuffix.index(after: parenIdx)...])
        return Double(numStr)
    }

    /// If an entry was logged with the old "separately" format ("MealName · Ingredient (Xg)"),
    /// returns the base meal name before " · ". Returns nil for normal entries.
    static func separatelyLoggedMealName(_ name: String) -> String? {
        guard let range = name.range(of: " · ") else { return nil }
        let base = String(name[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        return base.isEmpty ? nil : base
    }

    // Returns the base food name, stripping the "N×" serving annotation if present.
    // "Beef Jerky (2×)" → "Beef Jerky"; "Chicken Breast (150g)" → unchanged.
    static func baseNameFromEntryName(_ name: String) -> String {
        guard name.hasSuffix("×)") else { return name }
        let withoutSuffix = name.dropLast(2)
        guard let parenIdx = withoutSuffix.lastIndex(of: "(") else { return name }
        return String(withoutSuffix[..<parenIdx]).trimmingCharacters(in: .whitespaces)
    }

    // Extracts gram count from names like "Food Name (5g)" or "Food Name (serving) (100g)".
    static func gramsFromEntryName(_ name: String) -> Double? {
        guard name.hasSuffix("g)") else { return nil }
        let withoutSuffix = name.dropLast(2)
        guard let parenIdx = withoutSuffix.lastIndex(of: "(") else { return nil }
        let gramsStr = String(withoutSuffix[withoutSuffix.index(after: parenIdx)...])
        return Double(gramsStr)
    }

    // MARK: - Natural language food matching

    /// Matches a food name extracted from NL to a database entry.
    /// Tries exact → DB-name-contains-input → input-contains-DB-name.
    static func matchFood(name: String, database: [FoodTemplate] = foodDatabase) -> FoodTemplate? {
        let q = name.lowercased().trimmingCharacters(in: .whitespaces)
        return database.first { $0.name.lowercased() == q }
            ?? database.first { $0.name.lowercased().contains(q) }
            ?? database.first { q.contains($0.name.lowercased()) }
    }

    /// Converts a NL quantity + unit to grams using the template's default serving when no metric unit is given.
    static func gramsForUnit(_ unit: String, quantity: Double, template: FoodTemplate) -> Double {
        let q = max(0.1, quantity)
        switch unit.lowercased().trimmingCharacters(in: .whitespaces) {
        case "g", "gram", "grams":                  return q
        case "oz", "ounce", "ounces":               return (q * 28.35 * 10).rounded() / 10
        case "ml", "milliliter", "milliliters":     return q
        case "cup", "cups":                          return (q * 240).rounded()
        case "tbsp", "tablespoon", "tablespoons":   return (q * 15).rounded()
        case "tsp", "teaspoon", "teaspoons":        return (q * 5).rounded()
        case "kg", "kilogram", "kilograms":         return (q * 1000).rounded()
        default: // serving, piece, slice, scoop, bar, item, can, etc.
            return Double(template.defaultServingG) * q
        }
    }

    /// Resolves an NL-extracted food name + quantity + unit to a database template and gram amount. Returns nil if no match.
    static func resolveNLFood(
        name: String,
        quantity: Double,
        unit: String,
        database: [FoodTemplate] = foodDatabase
    ) -> (template: FoodTemplate, grams: Double)? {
        guard let template = matchFood(name: name, database: database) else { return nil }
        return (template, gramsForUnit(unit, quantity: quantity, template: template))
    }

    static func servingText(_ servings: Double) -> String {
        if servings == 1 { return "1 serving" }
        if servings.rounded() == servings {
            return "\(Int(servings)) servings"
        }
        return "\(String(format: "%.2f", servings).trimmingTrailingZeros) serving"
    }

    // MARK: - Maintenance back-calculation

    /// Back-calculates estimated maintenance from tracked intake and weight trend.
    /// `weightChangePer7Days`: negative = losing (kg/week), positive = gaining.
    /// 1 kg ≈ 7,700 kcal; formula: maintenance = intake - (weight_change_kcal_per_day)
    nonisolated static func estimatedMaintenance(
        avgDailyKcal: Double,
        weightChangePer7Days: Double
    ) -> Double {
        let dailyWeightKcal = weightChangePer7Days * 7700.0 / 7.0
        return avgDailyKcal - dailyWeightKcal
    }

    /// Linear regression over (date, kg) pairs → returns slope in kg per 7 days (kg/week).
    /// Returns nil when fewer than 2 data points or all dates are identical.
    nonisolated static func weightTrendPerWeek(from weights: [(date: Date, kg: Double)]) -> Double? {
        guard weights.count >= 2 else { return nil }
        let sorted = weights.sorted { $0.date < $1.date }
        let x = sorted.map { $0.date.timeIntervalSince1970 }
        let y = sorted.map { $0.kg }
        let n = Double(sorted.count)
        let meanX = x.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n
        let numerator   = zip(x, y).reduce(0.0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let denominator = x.reduce(0.0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard denominator > 0 else { return nil }
        let slopePerSecond = numerator / denominator
        return slopePerSecond * 7 * 24 * 3600  // convert to kg/week
    }

    // MARK: - Weight goal recommendation

    struct WeightGoalRecommendation: Sendable {
        enum Direction: Sendable { case lose, gain, maintain }
        let direction: Direction
        /// Recommended weekly rate of change in kg
        let weeklyRateKg: Double
        /// Recommended daily calorie adjustment from maintenance (negative = deficit)
        let dailyCalorieAdjustment: Int
        /// Estimated weeks to goal, nil when already at goal
        let estimatedWeeks: Int?
        /// True when prolonged deficit detected (suggest maintenance break)
        let suggestDietBreak: Bool
    }

    /// Computes a safe, evidence-based calorie adjustment toward a target weight.
    ///
    /// Deficit scales linearly with how far from goal (200 kcal for ≤1.3 kg gap,
    /// 500 kcal at ≥3.3 kg gap), capped at 500 kcal/day. After 8+ weeks consistently
    /// below maintenance a diet break is flagged.
    ///
    /// - Parameters:
    ///   - currentWeightKg: User's current body weight.
    ///   - targetWeightKg: User's desired body weight (0 = no goal set).
    ///   - weeksInDeficit: Estimated number of weeks the user has been below maintenance.
    nonisolated static func weightGoalRecommendation(
        currentWeightKg: Double,
        targetWeightKg: Double,
        weeksInDeficit: Int = 0
    ) -> WeightGoalRecommendation {
        let delta = currentWeightKg - targetWeightKg  // positive = need to lose
        let absD  = abs(delta)

        guard absD >= 0.3 else {
            return WeightGoalRecommendation(direction: .maintain, weeklyRateKg: 0,
                                            dailyCalorieAdjustment: 0, estimatedWeeks: nil,
                                            suggestDietBreak: false)
        }

        if delta > 0 {
            // Fat loss: deficit = clamp(absD * 150, 200, 500) kcal/day
            // → 1 kg away ≈ 150 kcal, 2 kg ≈ 300 kcal, 3.3+ kg ≈ 500 kcal (capped)
            var rawDeficit = absD * 150.0
            rawDeficit = max(200, min(500, rawDeficit))
            // Reduce by 10% after 4 weeks, 20% after 8 weeks (metabolic adaptation)
            let adaptationFactor: Double = weeksInDeficit >= 8 ? 0.80 : weeksInDeficit >= 4 ? 0.90 : 1.0
            let deficit = Int((rawDeficit * adaptationFactor).rounded())
            let weeklyRate = Double(deficit) * 7.0 / 7700.0
            let weeks = Int(ceil(absD / weeklyRate))
            return WeightGoalRecommendation(direction: .lose, weeklyRateKg: weeklyRate,
                                            dailyCalorieAdjustment: -deficit,
                                            estimatedWeeks: weeks,
                                            suggestDietBreak: weeksInDeficit >= 8)
        } else {
            // Lean bulk: conservative 200 kcal/day surplus → ~0.18 kg/week
            let surplus = 200
            let weeklyRate = Double(surplus) * 7.0 / 7700.0
            let weeks = Int(ceil(absD / weeklyRate))
            return WeightGoalRecommendation(direction: .gain, weeklyRateKg: weeklyRate,
                                            dailyCalorieAdjustment: surplus,
                                            estimatedWeeks: weeks,
                                            suggestDietBreak: false)
        }
    }
}

private extension String {
    var trimmingTrailingZeros: String {
        var value = self
        while value.last == "0" { value.removeLast() }
        if value.last == "." { value.removeLast() }
        return value
    }
}
