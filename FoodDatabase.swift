import Foundation

enum FoodCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case protein      = "Protein"
    case grains       = "Carbs & Grains"
    case dairy        = "Dairy"
    case fruit        = "Fruit"
    case vegetables   = "Vegetables"
    case fats         = "Fats & Oils"
    case extras       = "Condiments & Extras"
    case meals        = "Meals & Prepared Foods"
    case supplements  = "Supplements"
    case restaurants  = "Restaurants"
    case drinks       = "Drinks"
    var id: String { rawValue }
}

struct FoodTemplate: Identifiable {
    let id = UUID()
    let name: String
    let category: FoodCategory
    // Per 100g
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let sugar: Double
    let saturatedFat: Double
    let sodium: Double      // mg per 100g
    let cholesterol: Double // mg per 100g
    let defaultServingG: Int // suggested serving in grams
    let servingLabel: String?
    // Custom food metadata — nil for shared/bundled foods
    let isCustom: Bool
    let customFoodID: UUID?

    init(
        name: String,
        category: FoodCategory,
        kcal: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double = 0,
        sugar: Double = 0,
        saturatedFat: Double = 0,
        sodium: Double = 0,
        cholesterol: Double = 0,
        defaultServingG: Int,
        servingLabel: String? = nil,
        isCustom: Bool = false,
        customFoodID: UUID? = nil
    ) {
        self.name = name
        self.category = category
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
        self.saturatedFat = saturatedFat
        self.sodium = sodium
        self.cholesterol = cholesterol
        self.defaultServingG = defaultServingG
        self.servingLabel = servingLabel
        self.isCustom = isCustom
        self.customFoodID = customFoodID
    }

    var defaultServingDescription: String {
        servingLabel ?? "\(defaultServingG)g"
    }

    var defaultServingSummary: String {
        guard let servingLabel else { return "\(defaultServingG)g" }
        return "\(servingLabel) (\(defaultServingG)g)"
    }

    func macros(forGrams g: Double) -> (
        kcal: Int,
        p: Double,
        c: Double,
        f: Double,
        fiber: Double,
        sugar: Double,
        saturatedFat: Double,
        sodium: Double,
        cholesterol: Double
    ) {
        let ratio = g / 100
        return (
            Int((kcal * ratio).rounded()),
            (protein * ratio * 10).rounded() / 10,
            (carbs   * ratio * 10).rounded() / 10,
            (fat     * ratio * 10).rounded() / 10,
            (fiber   * ratio * 10).rounded() / 10,
            (sugar   * ratio * 10).rounded() / 10,
            (saturatedFat * ratio * 10).rounded() / 10,
            (sodium * ratio).rounded(),
            (cholesterol * ratio).rounded()
        )
    }

    func amountDescription(forGrams grams: Double) -> String {
        let rounded = Int(grams.rounded())
        if abs(grams - Double(defaultServingG)) < 0.1, let servingLabel {
            return servingLabel
        }
        return "\(rounded)g"
    }

    func macroHeading(forGrams grams: Double) -> String {
        let amount = amountDescription(forGrams: grams)
        if amount == "\(Int(grams.rounded()))g" {
            return amount
        }
        return "\(amount) (\(Int(grams.rounded()))g)"
    }

    func logName(forGrams grams: Double) -> String {
        "\(name) (\(amountDescription(forGrams: grams)))"
    }
}

extension SavedMealIngredient {
    init(template: FoodTemplate, grams: Double) {
        self.init(
            name: template.name,
            category: template.category,
            grams: grams,
            kcalPer100g: template.kcal,
            proteinPer100g: template.protein,
            carbsPer100g: template.carbs,
            fatPer100g: template.fat,
            fiberPer100g: template.fiber,
            sugarPer100g: template.sugar,
            saturatedFatPer100g: template.saturatedFat,
            sodiumPer100g: template.sodium,
            cholesterolPer100g: template.cholesterol,
            servingLabel: template.servingLabel
        )
    }

    // Snapshot a SavedMeal's per-100g values so it can be used as an ingredient in another meal.
    // Macros are computed at the time of addition; later edits to the source meal do not propagate.
    init(meal: SavedMeal, servings: Double = 1) {
        let totals = NutritionLogic.macros(for: meal, servings: servings)
        let totalGrams = meal.ingredients.reduce(0.0) { $0 + $1.grams } * max(0.01, servings)
        let factor = totalGrams > 0 ? 100.0 / totalGrams : 0
        self.init(
            name: meal.name,
            category: .meals,
            grams: totalGrams,
            kcalPer100g: Double(totals.kcal) * factor,
            proteinPer100g: totals.protein * factor,
            carbsPer100g: totals.carbs * factor,
            fatPer100g: totals.fat * factor,
            fiberPer100g: totals.fiber * factor,
            sugarPer100g: totals.sugar * factor,
            saturatedFatPer100g: totals.saturatedFat * factor,
            sodiumPer100g: totals.sodium * factor,
            cholesterolPer100g: totals.cholesterol * factor,
            servingLabel: "\(Int(totalGrams.rounded()))g serving"
        )
    }
}

let foodDatabase: [FoodTemplate] = [

    // MARK: - Protein — Poultry
    FoodTemplate(name: "Chicken breast (cooked)",      category: .protein, kcal: 165, protein: 31,   carbs: 0,    fat: 3.6,  saturatedFat: 1, sodium: 74, cholesterol: 85, defaultServingG: 150),
    FoodTemplate(name: "Chicken breast (raw)",         category: .protein, kcal: 110, protein: 23,   carbs: 0,    fat: 1.2,  defaultServingG: 180),
    FoodTemplate(name: "Chicken thigh (cooked)",       category: .protein, kcal: 209, protein: 26,   carbs: 0,    fat: 11,   defaultServingG: 120),
    FoodTemplate(name: "Chicken thigh (raw, boneless)",category: .protein, kcal: 153, protein: 18,   carbs: 0,    fat: 9,    defaultServingG: 150),
    FoodTemplate(name: "Chicken drumstick (cooked)",   category: .protein, kcal: 172, protein: 28,   carbs: 0,    fat: 5.7,  defaultServingG: 100),
    FoodTemplate(name: "Chicken liver",                category: .protein, kcal: 172, protein: 27,   carbs: 0.9,  fat: 6.5,  defaultServingG: 100),
    FoodTemplate(name: "Turkey breast (cooked)",       category: .protein, kcal: 135, protein: 30,   carbs: 0,    fat: 1,    defaultServingG: 150),
    FoodTemplate(name: "Turkey mince (lean)",          category: .protein, kcal: 160, protein: 21,   carbs: 0,    fat: 8,    defaultServingG: 150),
    FoodTemplate(name: "Turkey slices (deli)",         category: .protein, kcal: 100, protein: 20,   carbs: 1,    fat: 1.5,  defaultServingG: 80),
    FoodTemplate(name: "Chicken sausages",             category: .protein, kcal: 175, protein: 15,   carbs: 6,    fat: 10,   defaultServingG: 120),

    // MARK: - Protein — Beef & Pork
    FoodTemplate(name: "Beef mince 5% fat",            category: .protein, kcal: 137, protein: 21,   carbs: 0,    fat: 5,    defaultServingG: 150),
    FoodTemplate(name: "Beef mince 10% fat",           category: .protein, kcal: 175, protein: 19,   carbs: 0,    fat: 10,   defaultServingG: 150),
    FoodTemplate(name: "Beef mince 20% fat",           category: .protein, kcal: 254, protein: 17,   carbs: 0,    fat: 20,   defaultServingG: 150),
    FoodTemplate(name: "Beef sirloin steak (grilled)", category: .protein, kcal: 210, protein: 26,   carbs: 0,    fat: 11,   defaultServingG: 200),
    FoodTemplate(name: "Beef ribeye steak (grilled)",  category: .protein, kcal: 291, protein: 25,   carbs: 0,    fat: 20,   defaultServingG: 200),
    FoodTemplate(name: "Beef fillet steak",            category: .protein, kcal: 179, protein: 28,   carbs: 0,    fat: 6.5,  defaultServingG: 180),
    FoodTemplate(name: "Beef jerky",                   category: .protein, kcal: 338, protein: 33,   carbs: 22,   fat: 7,    defaultServingG: 40),
    FoodTemplate(name: "Lamb leg (roasted)",           category: .protein, kcal: 218, protein: 28,   carbs: 0,    fat: 11,   defaultServingG: 150),
    FoodTemplate(name: "Lamb mince",                   category: .protein, kcal: 282, protein: 17,   carbs: 0,    fat: 23,   defaultServingG: 150),
    FoodTemplate(name: "Pork tenderloin (cooked)",     category: .protein, kcal: 166, protein: 29,   carbs: 0,    fat: 4.5,  defaultServingG: 150),
    FoodTemplate(name: "Pork loin chop (grilled)",     category: .protein, kcal: 214, protein: 26,   carbs: 0,    fat: 12,   defaultServingG: 180),
    FoodTemplate(name: "Pork sausage",                 category: .protein, kcal: 301, protein: 12,   carbs: 3,    fat: 26,   defaultServingG: 100),
    FoodTemplate(name: "Ham (deli, lean)",             category: .protein, kcal: 107, protein: 17,   carbs: 1.5,  fat: 3.5,  defaultServingG: 80),
    FoodTemplate(name: "Bacon (back, grilled)",        category: .protein, kcal: 215, protein: 25,   carbs: 0,    fat: 12,   defaultServingG: 60),

    // MARK: - Protein — Fish & Seafood
    FoodTemplate(name: "Salmon fillet (cooked)",       category: .protein, kcal: 208, protein: 20,   carbs: 0,    fat: 13,   saturatedFat: 3.1, sodium: 59, cholesterol: 55, defaultServingG: 130),
    FoodTemplate(name: "Smoked salmon",                category: .protein, kcal: 179, protein: 20,   carbs: 0,    fat: 10,   defaultServingG: 80),
    FoodTemplate(name: "Cod fillet (cooked)",          category: .protein, kcal: 105, protein: 23,   carbs: 0,    fat: 0.9,  defaultServingG: 150),
    FoodTemplate(name: "Tuna (canned, in water)",      category: .protein, kcal: 116, protein: 26,   carbs: 0,    fat: 0.5,  defaultServingG: 120),
    FoodTemplate(name: "Tuna (canned, in oil)",        category: .protein, kcal: 198, protein: 29,   carbs: 0,    fat: 9,    defaultServingG: 120),
    FoodTemplate(name: "Mackerel fillet",              category: .protein, kcal: 305, protein: 19,   carbs: 0,    fat: 25,   defaultServingG: 130),
    FoodTemplate(name: "Sardines (canned in oil)",     category: .protein, kcal: 208, protein: 25,   carbs: 0,    fat: 11,   defaultServingG: 100),
    FoodTemplate(name: "Tilapia (cooked)",             category: .protein, kcal: 128, protein: 26,   carbs: 0,    fat: 2.7,  defaultServingG: 150),
    FoodTemplate(name: "Sea bass (cooked)",            category: .protein, kcal: 124, protein: 24,   carbs: 0,    fat: 2.5,  defaultServingG: 150),
    FoodTemplate(name: "Prawns / Shrimp (cooked)",     category: .protein, kcal: 99,  protein: 24,   carbs: 0,    fat: 0.3,  defaultServingG: 150),
    FoodTemplate(name: "Scallops (cooked)",            category: .protein, kcal: 111, protein: 20,   carbs: 5,    fat: 1,    defaultServingG: 120),
    FoodTemplate(name: "Mussels (cooked)",             category: .protein, kcal: 172, protein: 24,   carbs: 7,    fat: 4.5,  defaultServingG: 150),
    FoodTemplate(name: "Anchovies (canned)",           category: .protein, kcal: 210, protein: 29,   carbs: 0,    fat: 10,   defaultServingG: 20),

    // MARK: - Protein — Eggs
    FoodTemplate(name: "Eggs (whole, large)",          category: .protein, kcal: 155, protein: 13,   carbs: 1.1,  fat: 11,   sugar: 1.1, saturatedFat: 3.3, sodium: 124, cholesterol: 373, defaultServingG: 60, servingLabel: "1 large egg"),
    FoodTemplate(name: "Egg whites (liquid)",          category: .protein, kcal: 52,  protein: 11,   carbs: 0.7,  fat: 0.2,  defaultServingG: 200, servingLabel: "200ml egg whites"),
    FoodTemplate(name: "Scrambled eggs (cooked)",      category: .protein, kcal: 149, protein: 10,   carbs: 1.4,  fat: 11,   defaultServingG: 150),

    // MARK: - Protein — Plant
    FoodTemplate(name: "Tofu (firm)",                  category: .protein, kcal: 144, protein: 17,   carbs: 3,    fat: 8,    fiber: 0.3, defaultServingG: 150),
    FoodTemplate(name: "Tofu (silken)",                category: .protein, kcal: 55,  protein: 6,    carbs: 2,    fat: 2.7,  fiber: 0.2, defaultServingG: 150),
    FoodTemplate(name: "Tempeh",                       category: .protein, kcal: 193, protein: 19,   carbs: 9,    fat: 11,   fiber: 9.0, defaultServingG: 100),
    FoodTemplate(name: "Seitan (wheat protein)",       category: .protein, kcal: 370, protein: 75,   carbs: 14,   fat: 1.9,  fiber: 0.6, defaultServingG: 100),
    FoodTemplate(name: "Edamame (shelled)",            category: .protein, kcal: 122, protein: 11,   carbs: 10,   fat: 5,    fiber: 5.0, defaultServingG: 150),

    // MARK: - Protein — Supplements & Bars
    FoodTemplate(name: "Whey protein powder",          category: .protein, kcal: 370, protein: 75,   carbs: 8,    fat: 6,    defaultServingG: 30),
    FoodTemplate(name: "Casein protein powder",        category: .protein, kcal: 360, protein: 78,   carbs: 6,    fat: 2,    defaultServingG: 30),
    FoodTemplate(name: "Protein bar (generic ~200kcal)",category: .protein, kcal: 320, protein: 25,  carbs: 26,   fat: 9,    defaultServingG: 60),
    FoodTemplate(name: "Grenade Carb Killa bar",       category: .protein, kcal: 325, protein: 21,   carbs: 28,   fat: 12,   defaultServingG: 60),

    // MARK: - Carbs & Grains — Rice & Potato
    FoodTemplate(name: "White rice (cooked)",          category: .grains, kcal: 130, protein: 2.7,  carbs: 28,   fat: 0.3,  fiber: 0.4, defaultServingG: 200, servingLabel: "1 cup cooked rice"),
    FoodTemplate(name: "Brown rice (cooked)",          category: .grains, kcal: 123, protein: 2.7,  carbs: 25,   fat: 1,    fiber: 1.8, defaultServingG: 200, servingLabel: "1 cup cooked rice"),
    FoodTemplate(name: "Basmati rice (cooked)",        category: .grains, kcal: 138, protein: 3,    carbs: 30,   fat: 0.5,  fiber: 0.6, defaultServingG: 200, servingLabel: "1 cup cooked rice"),
    FoodTemplate(name: "Jasmine rice (cooked)",        category: .grains, kcal: 132, protein: 2.5,  carbs: 29,   fat: 0.3,  fiber: 0.4, defaultServingG: 200, servingLabel: "1 cup cooked rice"),
    FoodTemplate(name: "White potato (boiled)",        category: .grains, kcal: 77,  protein: 2,    carbs: 17,   fat: 0.1,  fiber: 2.2, sugar: 0.8, defaultServingG: 200, servingLabel: "1 medium potato"),
    FoodTemplate(name: "White potato (baked)",         category: .grains, kcal: 93,  protein: 2.5,  carbs: 21,   fat: 0.1,  fiber: 2.2, sugar: 1.2, defaultServingG: 200, servingLabel: "1 medium potato"),
    FoodTemplate(name: "Sweet potato (boiled)",        category: .grains, kcal: 86,  protein: 1.6,  carbs: 20,   fat: 0.1,  fiber: 3, sugar: 4.2, defaultServingG: 200, servingLabel: "1 medium sweet potato"),
    FoodTemplate(name: "Sweet potato (baked)",         category: .grains, kcal: 90,  protein: 2,    carbs: 21,   fat: 0.1,  fiber: 3.3, sugar: 6.5, defaultServingG: 200, servingLabel: "1 medium sweet potato"),

    // MARK: - Carbs & Grains — Pasta & Noodles
    FoodTemplate(name: "Pasta (white, cooked)",        category: .grains, kcal: 131, protein: 5,    carbs: 25,   fat: 1.1,  fiber: 1.8, defaultServingG: 200),
    FoodTemplate(name: "Pasta (wholemeal, cooked)",    category: .grains, kcal: 124, protein: 5,    carbs: 23,   fat: 1.3,  fiber: 3.9, defaultServingG: 200),
    FoodTemplate(name: "Chickpea pasta (cooked)",      category: .grains, kcal: 160, protein: 9,    carbs: 26,   fat: 2.5,  fiber: 4.5, defaultServingG: 200),
    FoodTemplate(name: "Egg noodles (cooked)",         category: .grains, kcal: 138, protein: 4.5,  carbs: 27,   fat: 2,    fiber: 1.7, defaultServingG: 200),
    FoodTemplate(name: "Rice noodles (cooked)",        category: .grains, kcal: 109, protein: 1.5,  carbs: 25,   fat: 0.2,  fiber: 0.9, defaultServingG: 200),
    FoodTemplate(name: "Soba noodles (cooked)",        category: .grains, kcal: 99,  protein: 5,    carbs: 21,   fat: 0.1,  fiber: 1.9, defaultServingG: 200),
    FoodTemplate(name: "Udon noodles (cooked)",        category: .grains, kcal: 138, protein: 4,    carbs: 30,   fat: 0.6,  fiber: 1.4, defaultServingG: 200),

    // MARK: - Carbs & Grains — Bread
    FoodTemplate(name: "White bread",                  category: .grains, kcal: 265, protein: 9,    carbs: 49,   fat: 3.2,  fiber: 2.7, sugar: 5, sodium: 491, defaultServingG: 35, servingLabel: "1 slice"),
    FoodTemplate(name: "Wholemeal bread",              category: .grains, kcal: 247, protein: 12,   carbs: 42,   fat: 3.4,  fiber: 6.8, sugar: 5.6, sodium: 430, defaultServingG: 35, servingLabel: "1 slice"),
    FoodTemplate(name: "Sourdough bread",              category: .grains, kcal: 289, protein: 9,    carbs: 55,   fat: 2.5,  fiber: 2.2, defaultServingG: 50, servingLabel: "1 slice"),
    FoodTemplate(name: "Rye bread",                    category: .grains, kcal: 259, protein: 9,    carbs: 48,   fat: 3.3,  fiber: 5.8, defaultServingG: 35, servingLabel: "1 slice"),
    FoodTemplate(name: "Pita bread (large)",           category: .grains, kcal: 275, protein: 9.5,  carbs: 55,   fat: 1.2,  fiber: 2.7, defaultServingG: 60, servingLabel: "1 large pita"),
    FoodTemplate(name: "Bagel (plain)",                category: .grains, kcal: 270, protein: 10,   carbs: 53,   fat: 1.5,  fiber: 2.1, defaultServingG: 90, servingLabel: "1 bagel"),
    FoodTemplate(name: "English muffin",               category: .grains, kcal: 223, protein: 8,    carbs: 44,   fat: 2,    fiber: 2.5, defaultServingG: 55, servingLabel: "1 muffin"),
    FoodTemplate(name: "Tortilla wrap (medium)",       category: .grains, kcal: 300, protein: 7,    carbs: 48,   fat: 8,    fiber: 2.9, defaultServingG: 45, servingLabel: "1 medium wrap"),
    FoodTemplate(name: "Corn tortilla",                category: .grains, kcal: 218, protein: 6,    carbs: 44,   fat: 3,    fiber: 4.1, defaultServingG: 30, servingLabel: "1 tortilla"),

    // MARK: - Carbs & Grains — Other grains
    FoodTemplate(name: "Oats (dry / rolled)",          category: .grains, kcal: 379, protein: 13,   carbs: 67,   fat: 7,    fiber: 10.1, sugar: 1, saturatedFat: 1.2, defaultServingG: 60, servingLabel: "1/2 cup dry oats"),
    FoodTemplate(name: "Porridge (made with water)",   category: .grains, kcal: 55,  protein: 2,    carbs: 10,   fat: 1.1,  fiber: 1.5, defaultServingG: 300),
    FoodTemplate(name: "Quinoa (cooked)",              category: .grains, kcal: 120, protein: 4.4,  carbs: 22,   fat: 1.9,  fiber: 2.8, defaultServingG: 180),
    FoodTemplate(name: "Couscous (cooked)",            category: .grains, kcal: 112, protein: 3.8,  carbs: 23,   fat: 0.2,  fiber: 1.4, defaultServingG: 180),
    FoodTemplate(name: "Bulgur wheat (cooked)",        category: .grains, kcal: 83,  protein: 3,    carbs: 18,   fat: 0.2,  fiber: 4.5, defaultServingG: 180),
    FoodTemplate(name: "Polenta (cooked)",             category: .grains, kcal: 71,  protein: 1.5,  carbs: 15,   fat: 0.4,  fiber: 1.0, defaultServingG: 200),
    FoodTemplate(name: "Granola (plain)",              category: .grains, kcal: 471, protein: 10,   carbs: 64,   fat: 20,   fiber: 6.3, defaultServingG: 45),
    FoodTemplate(name: "Muesli (unsweetened)",         category: .grains, kcal: 355, protein: 9.5,  carbs: 62,   fat: 7.5,  fiber: 6.5, defaultServingG: 60),
    FoodTemplate(name: "Rice cakes (plain)",           category: .grains, kcal: 387, protein: 7.5,  carbs: 80,   fat: 3,    fiber: 3.5, defaultServingG: 20),

    // MARK: - Carbs & Grains — Legumes as carb source
    FoodTemplate(name: "Red lentils (cooked)",         category: .grains, kcal: 116, protein: 9,    carbs: 20,   fat: 0.4,  fiber: 7.9, sugar: 1.8, defaultServingG: 200),
    FoodTemplate(name: "Green lentils (cooked)",       category: .grains, kcal: 116, protein: 9,    carbs: 20,   fat: 0.4,  fiber: 7.9, sugar: 1.8, defaultServingG: 200),

    // MARK: - Dairy — Yogurt & Skyr
    FoodTemplate(name: "Greek yogurt 0% (Fage)",       category: .dairy, kcal: 57,  protein: 10,   carbs: 3.6,  fat: 0.2,  sugar: 3.6, sodium: 36, cholesterol: 5, defaultServingG: 200, servingLabel: "1 cup"),
    FoodTemplate(name: "Greek yogurt 2%",              category: .dairy, kcal: 73,  protein: 10,   carbs: 4,    fat: 2,    sugar: 4, saturatedFat: 1.3, sodium: 36, cholesterol: 8, defaultServingG: 200, servingLabel: "1 cup"),
    FoodTemplate(name: "Greek yogurt full fat",        category: .dairy, kcal: 100, protein: 9,    carbs: 4,    fat: 5,    sugar: 4, saturatedFat: 3.3, sodium: 36, cholesterol: 15, defaultServingG: 200, servingLabel: "1 cup"),
    FoodTemplate(name: "Skyr (0% fat)",                category: .dairy, kcal: 63,  protein: 11,   carbs: 4,    fat: 0.2,  defaultServingG: 200, servingLabel: "1 cup"),
    FoodTemplate(name: "Protein yogurt (Arla 25g)",    category: .dairy, kcal: 62,  protein: 10,   carbs: 4.5,  fat: 0.2,  defaultServingG: 150, servingLabel: "1 pot"),
    FoodTemplate(name: "Plain yogurt (low fat)",       category: .dairy, kcal: 56,  protein: 5.7,  carbs: 7.7,  fat: 0.7,  defaultServingG: 200),

    // MARK: - Dairy — Cheese
    FoodTemplate(name: "Cheddar cheese",               category: .dairy, kcal: 402, protein: 25,   carbs: 0.1,  fat: 33,   defaultServingG: 30),
    FoodTemplate(name: "Low-fat cheddar (grated)",     category: .dairy, kcal: 275, protein: 25,   carbs: 0.1,  fat: 20,   defaultServingG: 30),
    FoodTemplate(name: "Mozzarella (light)",           category: .dairy, kcal: 190, protein: 18,   carbs: 2,    fat: 12,   defaultServingG: 60),
    FoodTemplate(name: "Mozzarella (full fat)",        category: .dairy, kcal: 300, protein: 22,   carbs: 2.2,  fat: 22,   defaultServingG: 60),
    FoodTemplate(name: "Parmesan",                     category: .dairy, kcal: 392, protein: 36,   carbs: 0,    fat: 26,   defaultServingG: 15),
    FoodTemplate(name: "Ricotta",                      category: .dairy, kcal: 174, protein: 11,   carbs: 3,    fat: 13,   defaultServingG: 100),
    FoodTemplate(name: "Cottage cheese 0%",            category: .dairy, kcal: 84,  protein: 12,   carbs: 3.4,  fat: 0.1,  defaultServingG: 200),
    FoodTemplate(name: "Cottage cheese 4%",            category: .dairy, kcal: 103, protein: 11,   carbs: 3.4,  fat: 4.3,  defaultServingG: 200),
    FoodTemplate(name: "Cream cheese (regular)",       category: .dairy, kcal: 342, protein: 6,    carbs: 4.1,  fat: 34,   defaultServingG: 30),
    FoodTemplate(name: "Cream cheese (light)",         category: .dairy, kcal: 167, protein: 7,    carbs: 4.5,  fat: 14,   defaultServingG: 30),
    FoodTemplate(name: "Quark (0%)",                   category: .dairy, kcal: 65,  protein: 12,   carbs: 4,    fat: 0.2,  defaultServingG: 150),
    FoodTemplate(name: "Feta cheese",                  category: .dairy, kcal: 264, protein: 14,   carbs: 4.1,  fat: 21,   defaultServingG: 30),

    // MARK: - Dairy — Milk & Cream
    FoodTemplate(name: "Milk (whole)",                 category: .dairy, kcal: 61,  protein: 3.2,  carbs: 4.8,  fat: 3.3,  defaultServingG: 250, servingLabel: "1 cup"),
    FoodTemplate(name: "Milk (semi-skimmed)",          category: .dairy, kcal: 50,  protein: 3.6,  carbs: 4.8,  fat: 1.8,  defaultServingG: 250, servingLabel: "1 cup"),
    FoodTemplate(name: "Milk (skimmed)",               category: .dairy, kcal: 35,  protein: 3.4,  carbs: 5,    fat: 0.1,  defaultServingG: 250, servingLabel: "1 cup"),
    FoodTemplate(name: "Oat milk (unsweetened)",       category: .dairy, kcal: 40,  protein: 1,    carbs: 7.5,  fat: 0.75, defaultServingG: 250, servingLabel: "1 cup"),
    FoodTemplate(name: "Almond milk (unsweetened)",    category: .dairy, kcal: 17,  protein: 0.6,  carbs: 1.5,  fat: 1.1,  defaultServingG: 250, servingLabel: "1 cup"),
    FoodTemplate(name: "Soy milk (unsweetened)",       category: .dairy, kcal: 33,  protein: 3.3,  carbs: 1.8,  fat: 1.8,  defaultServingG: 250, servingLabel: "1 cup"),

    // MARK: - Fruit
    FoodTemplate(name: "Apple",                        category: .fruit, kcal: 52,  protein: 0.3,  carbs: 14,   fat: 0.2,  fiber: 2.4, sugar: 10.4, defaultServingG: 150, servingLabel: "1 apple"),
    FoodTemplate(name: "Banana",                       category: .fruit, kcal: 89,  protein: 1.1,  carbs: 23,   fat: 0.3,  fiber: 2.6, sugar: 12.2, defaultServingG: 120, servingLabel: "1 banana"),
    FoodTemplate(name: "Orange",                       category: .fruit, kcal: 47,  protein: 0.9,  carbs: 12,   fat: 0.1,  fiber: 2.4, sugar: 9.4, defaultServingG: 150, servingLabel: "1 orange"),
    FoodTemplate(name: "Pear",                         category: .fruit, kcal: 57,  protein: 0.4,  carbs: 15,   fat: 0.1,  fiber: 3.1, sugar: 9.8, defaultServingG: 160, servingLabel: "1 pear"),
    FoodTemplate(name: "Peach",                        category: .fruit, kcal: 39,  protein: 0.9,  carbs: 10,   fat: 0.3,  fiber: 1.5, sugar: 8.4, defaultServingG: 150, servingLabel: "1 peach"),
    FoodTemplate(name: "Nectarine",                    category: .fruit, kcal: 44,  protein: 1.1,  carbs: 11,   fat: 0.3,  fiber: 1.7, sugar: 7.9, defaultServingG: 150, servingLabel: "1 nectarine"),
    FoodTemplate(name: "Plum",                         category: .fruit, kcal: 46,  protein: 0.7,  carbs: 11,   fat: 0.3,  fiber: 1.4, sugar: 9.9, defaultServingG: 80, servingLabel: "1 plum"),
    FoodTemplate(name: "Grapefruit",                   category: .fruit, kcal: 42,  protein: 0.8,  carbs: 11,   fat: 0.1,  fiber: 1.6, sugar: 7, defaultServingG: 200, servingLabel: "1 grapefruit"),
    FoodTemplate(name: "Kiwi",                         category: .fruit, kcal: 61,  protein: 1.1,  carbs: 15,   fat: 0.5,  fiber: 3, sugar: 9, defaultServingG: 100, servingLabel: "2 kiwi"),
    FoodTemplate(name: "Mango",                        category: .fruit, kcal: 60,  protein: 0.8,  carbs: 15,   fat: 0.4,  fiber: 1.6, sugar: 13.7, defaultServingG: 150, servingLabel: "1 cup mango"),
    FoodTemplate(name: "Pineapple",                    category: .fruit, kcal: 50,  protein: 0.5,  carbs: 13,   fat: 0.1,  fiber: 1.4, sugar: 9.9, defaultServingG: 150, servingLabel: "1 cup pineapple"),
    FoodTemplate(name: "Watermelon",                   category: .fruit, kcal: 30,  protein: 0.6,  carbs: 7.6,  fat: 0.2,  fiber: 0.4, sugar: 6.2, defaultServingG: 300, servingLabel: "2 cups watermelon"),
    FoodTemplate(name: "Cantaloupe melon",             category: .fruit, kcal: 34,  protein: 0.8,  carbs: 8,    fat: 0.2,  fiber: 0.9, sugar: 7.9, defaultServingG: 200, servingLabel: "1 cup melon"),
    FoodTemplate(name: "Grapes",                       category: .fruit, kcal: 69,  protein: 0.7,  carbs: 18,   fat: 0.2,  fiber: 0.9, sugar: 15.5, defaultServingG: 150, servingLabel: "1 cup grapes"),
    FoodTemplate(name: "Cherries",                     category: .fruit, kcal: 63,  protein: 1.1,  carbs: 16,   fat: 0.2,  fiber: 2.1, sugar: 12.8, defaultServingG: 100, servingLabel: "1 cup cherries"),
    FoodTemplate(name: "Blueberries",                  category: .fruit, kcal: 57,  protein: 0.7,  carbs: 14,   fat: 0.3,  fiber: 2.4, sugar: 10, defaultServingG: 100, servingLabel: "1 cup blueberries"),
    FoodTemplate(name: "Strawberries",                 category: .fruit, kcal: 32,  protein: 0.7,  carbs: 7.7,  fat: 0.3,  fiber: 2, sugar: 4.9, defaultServingG: 150, servingLabel: "1 cup strawberries"),
    FoodTemplate(name: "Raspberries",                  category: .fruit, kcal: 52,  protein: 1.2,  carbs: 12,   fat: 0.7,  fiber: 6.5, sugar: 4.4, defaultServingG: 100, servingLabel: "1 cup raspberries"),
    FoodTemplate(name: "Blackberries",                 category: .fruit, kcal: 43,  protein: 1.4,  carbs: 10,   fat: 0.5,  fiber: 5.3, sugar: 4.9, defaultServingG: 100, servingLabel: "1 cup blackberries"),
    FoodTemplate(name: "Dates (Medjool)",              category: .fruit, kcal: 277, protein: 1.8,  carbs: 75,   fat: 0.2,  fiber: 6.7, sugar: 66.5, defaultServingG: 30, servingLabel: "1 Medjool date"),
    FoodTemplate(name: "Dried figs",                   category: .fruit, kcal: 249, protein: 3.3,  carbs: 64,   fat: 0.9,  fiber: 9.8, sugar: 47.9, defaultServingG: 40, servingLabel: "2 dried figs"),
    FoodTemplate(name: "Raisins",                      category: .fruit, kcal: 299, protein: 3.1,  carbs: 79,   fat: 0.5,  fiber: 3.7, sugar: 59.2, defaultServingG: 30, servingLabel: "1 small handful"),

    // MARK: - Vegetables
    FoodTemplate(name: "Broccoli (raw)",               category: .vegetables, kcal: 34,  protein: 2.8,  carbs: 7,    fat: 0.4,  fiber: 2.6, sugar: 1.7, defaultServingG: 200),
    FoodTemplate(name: "Spinach (raw)",                category: .vegetables, kcal: 23,  protein: 2.9,  carbs: 3.6,  fat: 0.4,  fiber: 2.2, sugar: 0.4, defaultServingG: 80),
    FoodTemplate(name: "Kale (raw)",                   category: .vegetables, kcal: 49,  protein: 4.3,  carbs: 9,    fat: 0.9,  fiber: 3.6, defaultServingG: 80),
    FoodTemplate(name: "Rocket / Arugula",             category: .vegetables, kcal: 25,  protein: 2.6,  carbs: 3.7,  fat: 0.7,  fiber: 1.6, defaultServingG: 60),
    FoodTemplate(name: "Mixed salad leaves",           category: .vegetables, kcal: 17,  protein: 1.3,  carbs: 2.5,  fat: 0.4,  fiber: 1.6, sugar: 0.8, defaultServingG: 80),
    FoodTemplate(name: "Cauliflower",                  category: .vegetables, kcal: 25,  protein: 1.9,  carbs: 5,    fat: 0.3,  fiber: 2, sugar: 1.9, defaultServingG: 200),
    FoodTemplate(name: "Cabbage (white)",              category: .vegetables, kcal: 25,  protein: 1.3,  carbs: 6,    fat: 0.1,  fiber: 2.5, defaultServingG: 150),
    FoodTemplate(name: "Mushrooms (white)",            category: .vegetables, kcal: 22,  protein: 3.1,  carbs: 3.3,  fat: 0.3,  fiber: 1.0, defaultServingG: 100),
    FoodTemplate(name: "Red pepper",                   category: .vegetables, kcal: 31,  protein: 1,    carbs: 6,    fat: 0.3,  fiber: 2.1, defaultServingG: 150),
    FoodTemplate(name: "Yellow pepper",                category: .vegetables, kcal: 27,  protein: 1,    carbs: 6.3,  fat: 0.2,  fiber: 1.7, defaultServingG: 150),
    FoodTemplate(name: "Cucumber",                     category: .vegetables, kcal: 15,  protein: 0.7,  carbs: 3.6,  fat: 0.1,  fiber: 0.5, sugar: 1.7, defaultServingG: 150),
    FoodTemplate(name: "Tomatoes",                     category: .vegetables, kcal: 18,  protein: 0.9,  carbs: 3.9,  fat: 0.2,  fiber: 1.2, sugar: 2.6, defaultServingG: 150),
    FoodTemplate(name: "Cherry tomatoes",              category: .vegetables, kcal: 18,  protein: 0.9,  carbs: 3.9,  fat: 0.2,  fiber: 1.2, defaultServingG: 100),
    FoodTemplate(name: "Carrot (raw)",                 category: .vegetables, kcal: 41,  protein: 0.9,  carbs: 10,   fat: 0.2,  fiber: 2.8, sugar: 4.7, defaultServingG: 120),
    FoodTemplate(name: "Celery",                       category: .vegetables, kcal: 16,  protein: 0.7,  carbs: 3,    fat: 0.2,  fiber: 1.6, defaultServingG: 100),
    FoodTemplate(name: "Onion",                        category: .vegetables, kcal: 40,  protein: 1.1,  carbs: 9.3,  fat: 0.1,  fiber: 1.7, defaultServingG: 100),
    FoodTemplate(name: "Red onion",                    category: .vegetables, kcal: 40,  protein: 1,    carbs: 9,    fat: 0.1,  fiber: 1.8, defaultServingG: 80),
    FoodTemplate(name: "Garlic (raw)",                 category: .vegetables, kcal: 149, protein: 6.4,  carbs: 33,   fat: 0.5,  fiber: 2.1, defaultServingG: 5),
    FoodTemplate(name: "Courgette / Zucchini",         category: .vegetables, kcal: 17,  protein: 1.2,  carbs: 3.1,  fat: 0.3,  fiber: 1.0, defaultServingG: 200),
    FoodTemplate(name: "Green beans",                  category: .vegetables, kcal: 31,  protein: 1.8,  carbs: 7,    fat: 0.1,  fiber: 2.7, defaultServingG: 150),
    FoodTemplate(name: "Asparagus",                    category: .vegetables, kcal: 20,  protein: 2.2,  carbs: 3.9,  fat: 0.1,  fiber: 2.1, defaultServingG: 150),
    FoodTemplate(name: "Leek",                         category: .vegetables, kcal: 61,  protein: 1.5,  carbs: 14,   fat: 0.3,  fiber: 1.8, defaultServingG: 120),
    FoodTemplate(name: "Beetroot (cooked)",            category: .vegetables, kcal: 44,  protein: 1.7,  carbs: 10,   fat: 0.2,  fiber: 2.0, defaultServingG: 100),
    FoodTemplate(name: "Frozen peas",                  category: .vegetables, kcal: 81,  protein: 5.4,  carbs: 14,   fat: 0.4,  fiber: 5.1, defaultServingG: 80),
    FoodTemplate(name: "Sweetcorn (canned)",           category: .vegetables, kcal: 86,  protein: 2.6,  carbs: 18,   fat: 0.9,  fiber: 1.5, defaultServingG: 100),
    FoodTemplate(name: "Butternut squash",             category: .vegetables, kcal: 45,  protein: 1,    carbs: 12,   fat: 0.1,  fiber: 2.0, defaultServingG: 200),
    FoodTemplate(name: "Beansprouts",                  category: .vegetables, kcal: 30,  protein: 3,    carbs: 5.9,  fat: 0.2,  fiber: 1.8, defaultServingG: 100),

    // MARK: - Fats & Oils
    FoodTemplate(name: "Olive oil",                    category: .fats, kcal: 884, protein: 0,    carbs: 0,    fat: 100,  saturatedFat: 13.8, defaultServingG: 10, servingLabel: "1 tbsp"),
    FoodTemplate(name: "Coconut oil",                  category: .fats, kcal: 862, protein: 0,    carbs: 0,    fat: 100,  saturatedFat: 82.5, defaultServingG: 10, servingLabel: "1 tbsp"),
    FoodTemplate(name: "Butter",                       category: .fats, kcal: 717, protein: 0.9,  carbs: 0.1,  fat: 81,   saturatedFat: 51, sodium: 11, cholesterol: 215, defaultServingG: 10, servingLabel: "1 pat"),
    FoodTemplate(name: "Haas avocado (large)",         category: .fats, kcal: 160, protein: 2,    carbs: 9,    fat: 15,   fiber: 6.7, sugar: 0.7, saturatedFat: 2.1, defaultServingG: 200, servingLabel: "1 large Haas avocado"),
    FoodTemplate(name: "Almonds",                      category: .fats, kcal: 579, protein: 21,   carbs: 22,   fat: 50,   fiber: 12.5, sugar: 4.4, saturatedFat: 3.8, defaultServingG: 30, servingLabel: "1 handful"),
    FoodTemplate(name: "Walnuts",                      category: .fats, kcal: 654, protein: 15,   carbs: 14,   fat: 65,   fiber: 6.7, sugar: 2.6, saturatedFat: 6.1, defaultServingG: 30, servingLabel: "1 handful"),
    FoodTemplate(name: "Cashews",                      category: .fats, kcal: 553, protein: 18,   carbs: 30,   fat: 44,   fiber: 3.3, sugar: 5.9, saturatedFat: 7.8, defaultServingG: 30, servingLabel: "1 handful"),
    FoodTemplate(name: "Pistachios (shelled)",         category: .fats, kcal: 562, protein: 20,   carbs: 28,   fat: 45,   fiber: 10.6, defaultServingG: 30, servingLabel: "1 handful"),
    FoodTemplate(name: "Peanuts",                      category: .fats, kcal: 567, protein: 26,   carbs: 16,   fat: 49,   fiber: 8.5, defaultServingG: 30, servingLabel: "1 handful"),
    FoodTemplate(name: "Mixed nuts",                   category: .fats, kcal: 607, protein: 18,   carbs: 21,   fat: 55,   fiber: 6.4, defaultServingG: 30, servingLabel: "1 handful"),
    FoodTemplate(name: "Peanut butter (smooth)",       category: .fats, kcal: 588, protein: 25,   carbs: 20,   fat: 50,   fiber: 6, sugar: 9, saturatedFat: 10, sodium: 17, defaultServingG: 30, servingLabel: "2 tbsp"),
    FoodTemplate(name: "Almond butter",                category: .fats, kcal: 614, protein: 21,   carbs: 19,   fat: 56,   fiber: 10.3, defaultServingG: 30, servingLabel: "2 tbsp"),
    FoodTemplate(name: "Sunflower seeds",              category: .fats, kcal: 584, protein: 21,   carbs: 20,   fat: 51,   fiber: 8.6, defaultServingG: 20),
    FoodTemplate(name: "Pumpkin seeds",                category: .fats, kcal: 559, protein: 30,   carbs: 11,   fat: 49,   fiber: 6.0, defaultServingG: 20),
    FoodTemplate(name: "Flaxseeds / Linseeds",         category: .fats, kcal: 534, protein: 18,   carbs: 29,   fat: 42,   fiber: 27.3, defaultServingG: 15),
    FoodTemplate(name: "Chia seeds",                   category: .fats, kcal: 486, protein: 17,   carbs: 42,   fat: 31,   fiber: 34.4, defaultServingG: 15),
    FoodTemplate(name: "Dark chocolate 70–85%",        category: .fats, kcal: 598, protein: 8,    carbs: 46,   fat: 43,   fiber: 10.9, defaultServingG: 25),

    // MARK: - Condiments & Extras — Legumes
    FoodTemplate(name: "Red kidney beans (canned)",    category: .extras, kcal: 127, protein: 8.7,  carbs: 22,   fat: 0.5,  fiber: 6.4, sugar: 0.3, sodium: 240, defaultServingG: 150),
    FoodTemplate(name: "Black beans (canned)",         category: .extras, kcal: 130, protein: 9,    carbs: 23,   fat: 0.5,  fiber: 8.7, sugar: 0.3, sodium: 240, defaultServingG: 150),
    FoodTemplate(name: "Chickpeas (canned)",           category: .extras, kcal: 164, protein: 8.9,  carbs: 27,   fat: 2.6,  fiber: 7.6, sugar: 4.8, sodium: 240, defaultServingG: 150),
    FoodTemplate(name: "Baked beans (Heinz)",          category: .extras, kcal: 84,  protein: 4.8,  carbs: 14,   fat: 0.4,  fiber: 3.7, sugar: 4.8, sodium: 280, defaultServingG: 200),

    // MARK: - Condiments & Extras — Sauces & Spreads
    FoodTemplate(name: "Hummus",                       category: .extras, kcal: 177, protein: 4.9,  carbs: 16,   fat: 10,   fiber: 6.0, defaultServingG: 50),
    FoodTemplate(name: "Chopped tomatoes (canned)",    category: .extras, kcal: 24,  protein: 1.2,  carbs: 4.8,  fat: 0.2,  fiber: 1.2, defaultServingG: 200),
    FoodTemplate(name: "Tomato purée",                 category: .extras, kcal: 68,  protein: 3.8,  carbs: 13,   fat: 0.4,  fiber: 2.0, defaultServingG: 30),
    FoodTemplate(name: "Passata",                      category: .extras, kcal: 30,  protein: 1.5,  carbs: 5.8,  fat: 0.2,  fiber: 1.2, defaultServingG: 200),
    FoodTemplate(name: "Salsa (shop-bought)",          category: .extras, kcal: 25,  protein: 1,    carbs: 5,    fat: 0.1,  fiber: 1.2, defaultServingG: 50),
    FoodTemplate(name: "Pesto (green, jarred)",        category: .extras, kcal: 362, protein: 8,    carbs: 5,    fat: 35,   fiber: 1.3, defaultServingG: 30),
    FoodTemplate(name: "Soy sauce (regular)",          category: .extras, kcal: 60,  protein: 8,    carbs: 5,    fat: 0.1,  defaultServingG: 15),
    FoodTemplate(name: "Sriracha",                     category: .extras, kcal: 93,  protein: 1.9,  carbs: 18,   fat: 0.8,  defaultServingG: 10),
    FoodTemplate(name: "Ketchup",                      category: .extras, kcal: 101, protein: 1.3,  carbs: 26,   fat: 0.2,  fiber: 0.5, defaultServingG: 20),
    FoodTemplate(name: "Mustard (yellow)",             category: .extras, kcal: 66,  protein: 4,    carbs: 6,    fat: 3.3,  defaultServingG: 10),
    FoodTemplate(name: "Mayonnaise (full fat)",        category: .extras, kcal: 680, protein: 1,    carbs: 1,    fat: 75,   defaultServingG: 15),
    FoodTemplate(name: "Light mayonnaise",             category: .extras, kcal: 270, protein: 1,    carbs: 5,    fat: 27,   defaultServingG: 15),
    FoodTemplate(name: "Honey",                        category: .extras, kcal: 304, protein: 0.3,  carbs: 82,   fat: 0,    defaultServingG: 15),
    FoodTemplate(name: "Maple syrup",                  category: .extras, kcal: 260, protein: 0,    carbs: 67,   fat: 0.1,  defaultServingG: 15),
    FoodTemplate(name: "Jam / Jelly",                  category: .extras, kcal: 250, protein: 0.4,  carbs: 65,   fat: 0,    defaultServingG: 15),

    // MARK: - Meals & Prepared Foods
    FoodTemplate(name: "Chicken rice bowl",             category: .meals, kcal: 150, protein: 13,   carbs: 17,   fat: 3.2,  fiber: 1.2, sugar: 1.5, saturatedFat: 0.8, sodium: 260, cholesterol: 35, defaultServingG: 450, servingLabel: "1 bowl"),
    FoodTemplate(name: "Salmon rice bowl",              category: .meals, kcal: 170, protein: 11,   carbs: 16,   fat: 6.5,  fiber: 1.1, sugar: 1.4, saturatedFat: 1.3, sodium: 240, cholesterol: 28, defaultServingG: 450, servingLabel: "1 bowl"),
    FoodTemplate(name: "Beef burrito bowl",             category: .meals, kcal: 168, protein: 11,   carbs: 19,   fat: 5.5,  fiber: 3.8, sugar: 2.3, saturatedFat: 1.8, sodium: 360, cholesterol: 28, defaultServingG: 500, servingLabel: "1 bowl"),
    FoodTemplate(name: "Tofu veggie grain bowl",        category: .meals, kcal: 132, protein: 7,    carbs: 16,   fat: 4.2,  fiber: 3.1, sugar: 2.6, saturatedFat: 0.7, sodium: 220, defaultServingG: 450, servingLabel: "1 bowl"),
    FoodTemplate(name: "Turkey sandwich",               category: .meals, kcal: 210, protein: 14,   carbs: 24,   fat: 6.5,  fiber: 2.5, sugar: 4, saturatedFat: 1.8, sodium: 520, cholesterol: 25, defaultServingG: 220, servingLabel: "1 sandwich"),
    FoodTemplate(name: "Chicken Caesar wrap",           category: .meals, kcal: 230, protein: 16,   carbs: 22,   fat: 9,    fiber: 2.2, sugar: 2.5, saturatedFat: 2.5, sodium: 590, cholesterol: 45, defaultServingG: 260, servingLabel: "1 wrap"),
    FoodTemplate(name: "Egg breakfast sandwich",        category: .meals, kcal: 235, protein: 13,   carbs: 23,   fat: 10,   fiber: 1.8, sugar: 3.5, saturatedFat: 3.2, sodium: 520, cholesterol: 150, defaultServingG: 180, servingLabel: "1 sandwich"),
    FoodTemplate(name: "Overnight oats with berries",   category: .meals, kcal: 132, protein: 6,    carbs: 21,   fat: 3.2,  fiber: 3.4, sugar: 8, saturatedFat: 0.8, sodium: 55, cholesterol: 4, defaultServingG: 300, servingLabel: "1 jar"),
    FoodTemplate(name: "Greek yogurt parfait",          category: .meals, kcal: 118, protein: 8,    carbs: 17,   fat: 2,    fiber: 2.1, sugar: 11, saturatedFat: 0.8, sodium: 45, cholesterol: 4, defaultServingG: 300, servingLabel: "1 bowl"),
    FoodTemplate(name: "Protein shake with banana",     category: .meals, kcal: 100, protein: 11,   carbs: 12,   fat: 1.5,  fiber: 1.2, sugar: 6.5, saturatedFat: 0.4, sodium: 75, cholesterol: 15, defaultServingG: 400, servingLabel: "1 shake"),
    FoodTemplate(name: "Chicken pasta meal",            category: .meals, kcal: 165, protein: 12,   carbs: 22,   fat: 3.5,  fiber: 2.1, sugar: 3.5, saturatedFat: 0.9, sodium: 310, cholesterol: 28, defaultServingG: 450, servingLabel: "1 plate"),
    FoodTemplate(name: "Spaghetti bolognese",           category: .meals, kcal: 170, protein: 9,    carbs: 22,   fat: 5.2,  fiber: 2.4, sugar: 4.2, saturatedFat: 1.7, sodium: 330, cholesterol: 25, defaultServingG: 450, servingLabel: "1 plate"),
    FoodTemplate(name: "Chicken salad meal",            category: .meals, kcal: 115, protein: 13,   carbs: 7,    fat: 4.2,  fiber: 2.5, sugar: 3.5, saturatedFat: 0.9, sodium: 260, cholesterol: 40, defaultServingG: 400, servingLabel: "1 salad"),
    FoodTemplate(name: "Tuna mayo sandwich",            category: .meals, kcal: 225, protein: 13,   carbs: 23,   fat: 9,    fiber: 2.2, sugar: 3.8, saturatedFat: 1.5, sodium: 520, cholesterol: 28, defaultServingG: 220, servingLabel: "1 sandwich"),
    FoodTemplate(name: "Bean chili with rice",          category: .meals, kcal: 132, protein: 6.5,  carbs: 23,   fat: 1.8,  fiber: 5.5, sugar: 3.2, saturatedFat: 0.3, sodium: 330, defaultServingG: 500, servingLabel: "1 bowl"),
    FoodTemplate(name: "Chicken burrito",               category: .meals, kcal: 190, protein: 12,   carbs: 24,   fat: 5.5,  fiber: 3.2, sugar: 2.5, saturatedFat: 1.8, sodium: 440, cholesterol: 28, defaultServingG: 350, servingLabel: "1 burrito"),
    FoodTemplate(name: "Sushi salmon avocado roll",     category: .meals, kcal: 160, protein: 7,    carbs: 24,   fat: 4.5,  fiber: 1.5, sugar: 3, saturatedFat: 0.9, sodium: 360, cholesterol: 12, defaultServingG: 250, servingLabel: "1 roll"),
    FoodTemplate(name: "Chicken noodle soup",           category: .meals, kcal: 65,  protein: 5,    carbs: 8,    fat: 1.5,  fiber: 0.9, sugar: 1.6, saturatedFat: 0.4, sodium: 360, cholesterol: 12, defaultServingG: 400, servingLabel: "1 bowl"),
    FoodTemplate(name: "Lentil soup",                   category: .meals, kcal: 82,  protein: 5,    carbs: 14,   fat: 1,    fiber: 4.8, sugar: 2, saturatedFat: 0.2, sodium: 300, defaultServingG: 400, servingLabel: "1 bowl"),

    // MARK: - Restaurants — Din Tai Fung
    // Calories sourced from dintaifungmenu.us; macros estimated from ingredient composition.
    // XLB / dumplings listed per piece; plates listed per full serving.

    // Appetizers & Salads
    FoodTemplate(name: "DTF · Cucumber Salad",                      category: .restaurants, kcal: 60,  protein: 1,   carbs: 10,  fat: 2,   defaultServingG: 200),
    FoodTemplate(name: "DTF · Seaweed & Bean Curd Salad",           category: .restaurants, kcal: 89,  protein: 5,   carbs: 9,   fat: 4,   defaultServingG: 180),
    FoodTemplate(name: "DTF · Soy Noodle Salad",                    category: .restaurants, kcal: 90,  protein: 4,   carbs: 15,  fat: 2,   defaultServingG: 200),
    FoodTemplate(name: "DTF · Wood Ear Mushrooms",                   category: .restaurants, kcal: 61,  protein: 2,   carbs: 10,  fat: 2,   defaultServingG: 180),
    FoodTemplate(name: "DTF · Sweet & Sour Baby Back Ribs",          category: .restaurants, kcal: 143, protein: 18,  carbs: 12,  fat: 6,   defaultServingG: 300),

    // Soups
    FoodTemplate(name: "DTF · Hot & Sour Soup",                     category: .restaurants, kcal: 50,  protein: 6,   carbs: 8,   fat: 1.5, defaultServingG: 400),
    FoodTemplate(name: "DTF · Steamed Soup w/ Chicken",             category: .restaurants, kcal: 52,  protein: 7,   carbs: 4,   fat: 1.5, defaultServingG: 500),
    FoodTemplate(name: "DTF · Steamed Soup w/ Beef Short Ribs",     category: .restaurants, kcal: 64,  protein: 8,   carbs: 4,   fat: 3,   defaultServingG: 500),

    // Xiao Long Bao (per piece; 1 order = 10 pieces)
    FoodTemplate(name: "DTF · Pork XLB (1 piece)",                  category: .restaurants, kcal: 110, protein: 7,   carbs: 12,  fat: 3,   defaultServingG: 40),
    FoodTemplate(name: "DTF · Crab & Pork XLB (1 piece)",           category: .restaurants, kcal: 115, protein: 7,   carbs: 12,  fat: 3.5, defaultServingG: 40),
    FoodTemplate(name: "DTF · Chicken XLB (1 piece)",               category: .restaurants, kcal: 97,  protein: 7,   carbs: 11,  fat: 2,   defaultServingG: 40),
    FoodTemplate(name: "DTF · Truffle & Pork XLB (1 piece)",        category: .restaurants, kcal: 118, protein: 7,   carbs: 12,  fat: 4,   defaultServingG: 40),

    // Dumplings (per piece; 1 order = 10 pieces)
    FoodTemplate(name: "DTF · Chicken Dumplings (1 piece)",         category: .restaurants, kcal: 109, protein: 7,   carbs: 12,  fat: 2.5, defaultServingG: 35),
    FoodTemplate(name: "DTF · Vegan Dumplings (1 piece)",           category: .restaurants, kcal: 97,  protein: 3,   carbs: 16,  fat: 2,   defaultServingG: 35),
    FoodTemplate(name: "DTF · Cod Dumplings (1 piece)",             category: .restaurants, kcal: 103, protein: 8,   carbs: 11,  fat: 2,   defaultServingG: 35),
    FoodTemplate(name: "DTF · Shrimp & Pork Dumplings (1 piece)",   category: .restaurants, kcal: 103, protein: 8,   carbs: 12,  fat: 3,   defaultServingG: 40),
    FoodTemplate(name: "DTF · Kimchi & Pork Dumplings (1 piece)",   category: .restaurants, kcal: 105, protein: 7,   carbs: 13,  fat: 3.5, defaultServingG: 40),

    // Shao Mai & Buns (per piece; 1 order = 4 pieces)
    FoodTemplate(name: "DTF · Shrimp & Pork Shao Mai (1 piece)",    category: .restaurants, kcal: 120, protein: 8,   carbs: 11,  fat: 4,   defaultServingG: 60),
    FoodTemplate(name: "DTF · Sticky Rice Shao Mai (1 piece)",      category: .restaurants, kcal: 123, protein: 6,   carbs: 16,  fat: 4,   defaultServingG: 65),
    FoodTemplate(name: "DTF · Pork Buns (1 piece)",                 category: .restaurants, kcal: 107, protein: 6,   carbs: 15,  fat: 3,   defaultServingG: 70),
    FoodTemplate(name: "DTF · Chicken & Mushroom Buns (1 piece)",   category: .restaurants, kcal: 100, protein: 5,   carbs: 16,  fat: 2.5, defaultServingG: 70),
    FoodTemplate(name: "DTF · Vegan Buns (1 piece)",                category: .restaurants, kcal: 93,  protein: 3,   carbs: 17,  fat: 2,   defaultServingG: 70),

    // Wontons — Spicy (per piece; 1 order = 5 pieces)
    FoodTemplate(name: "DTF · Shrimp & Pork Spicy Wontons (1 pc)", category: .restaurants, kcal: 152, protein: 7,   carbs: 15,  fat: 6,   defaultServingG: 50),
    FoodTemplate(name: "DTF · Chicken Spicy Wontons (1 piece)",    category: .restaurants, kcal: 140, protein: 7,   carbs: 15,  fat: 5,   defaultServingG: 50),
    FoodTemplate(name: "DTF · Vegan Spicy Wontons (1 piece)",      category: .restaurants, kcal: 120, protein: 3,   carbs: 18,  fat: 3,   defaultServingG: 50),

    // Wontons — Soup (full bowl)
    FoodTemplate(name: "DTF · Shrimp & Pork Wonton Soup",          category: .restaurants, kcal: 73,  protein: 8,   carbs: 10,  fat: 2.5, defaultServingG: 450),
    FoodTemplate(name: "DTF · Chicken Wonton Soup",                category: .restaurants, kcal: 67,  protein: 7,   carbs: 10,  fat: 2,   defaultServingG: 450),
    FoodTemplate(name: "DTF · Vegan Wonton Soup",                  category: .restaurants, kcal: 56,  protein: 3,   carbs: 11,  fat: 1,   defaultServingG: 450),

    // Vegetable Sides (full plate)
    FoodTemplate(name: "DTF · String Beans w/ Garlic",             category: .restaurants, kcal: 64,  protein: 2.5, carbs: 9,   fat: 2,   defaultServingG: 250),
    FoodTemplate(name: "DTF · Broccoli w/ Garlic",                 category: .restaurants, kcal: 60,  protein: 3,   carbs: 8,   fat: 2,   defaultServingG: 250),
    FoodTemplate(name: "DTF · Bok Choy w/ Scallion Oil",           category: .restaurants, kcal: 60,  protein: 1.5, carbs: 6,   fat: 3,   defaultServingG: 200),
    FoodTemplate(name: "DTF · Spinach w/ Garlic",                  category: .restaurants, kcal: 55,  protein: 3,   carbs: 6,   fat: 2,   defaultServingG: 200),
    FoodTemplate(name: "DTF · Taiwanese Cabbage w/ Garlic",        category: .restaurants, kcal: 56,  protein: 2,   carbs: 8,   fat: 2,   defaultServingG: 250),
    FoodTemplate(name: "DTF · Kale w/ Garlic",                     category: .restaurants, kcal: 65,  protein: 3,   carbs: 8,   fat: 2,   defaultServingG: 200),

    // Specialties
    FoodTemplate(name: "DTF · Shrimp & Pork Pot Stickers (1 pc)", category: .restaurants, kcal: 95,  protein: 7,   carbs: 11,  fat: 3,   defaultServingG: 55),
    FoodTemplate(name: "DTF · Black Pepper Beef Tenderloin",       category: .restaurants, kcal: 173, protein: 20,  carbs: 8,   fat: 9,   defaultServingG: 300),

    // Noodle Dishes (full plate)
    FoodTemplate(name: "DTF · Noodles w/ Sesame Sauce",           category: .restaurants, kcal: 160, protein: 11,  carbs: 23,  fat: 6,   defaultServingG: 350),
    FoodTemplate(name: "DTF · Vegan Sesame Noodles",              category: .restaurants, kcal: 154, protein: 7,   carbs: 25,  fat: 5.5, defaultServingG: 350),
    FoodTemplate(name: "DTF · Noodles w/ Spicy Sauce",            category: .restaurants, kcal: 149, protein: 10,  carbs: 22,  fat: 5,   defaultServingG: 350),
    FoodTemplate(name: "DTF · Noodles w/ Minced Pork",            category: .restaurants, kcal: 145, protein: 14,  carbs: 22,  fat: 5,   defaultServingG: 400),
    FoodTemplate(name: "DTF · Noodles w/ Diced Beef",             category: .restaurants, kcal: 150, protein: 16,  carbs: 20,  fat: 6,   defaultServingG: 400),

    // Noodle Soups (full bowl)
    FoodTemplate(name: "DTF · Braised Beef Noodle Soup",          category: .restaurants, kcal: 108, protein: 15,  carbs: 16,  fat: 3.5, defaultServingG: 600),
    FoodTemplate(name: "DTF · Sliced Chicken Noodle Soup",        category: .restaurants, kcal: 87,  protein: 14,  carbs: 13,  fat: 1.5, defaultServingG: 600),
    FoodTemplate(name: "DTF · Fried Pork Chop Noodle Soup",       category: .restaurants, kcal: 113, protein: 14,  carbs: 16,  fat: 4,   defaultServingG: 600),
    FoodTemplate(name: "DTF · Tofu Puff & Glass Noodle Soup",     category: .restaurants, kcal: 76,  protein: 7,   carbs: 13,  fat: 2,   defaultServingG: 500),

    // Fried Rice (full plate ~400g)
    FoodTemplate(name: "DTF · Chicken Fried Rice",                category: .restaurants, kcal: 155, protein: 16,  carbs: 22,  fat: 5,   defaultServingG: 400),
    FoodTemplate(name: "DTF · Shrimp Fried Rice",                 category: .restaurants, kcal: 160, protein: 17,  carbs: 22,  fat: 5.5, defaultServingG: 400),
    FoodTemplate(name: "DTF · Shredded Pork Fried Rice",          category: .restaurants, kcal: 157, protein: 16,  carbs: 22,  fat: 5.5, defaultServingG: 400),
    FoodTemplate(name: "DTF · Pork Chop Fried Rice",              category: .restaurants, kcal: 160, protein: 18,  carbs: 22,  fat: 6,   defaultServingG: 450),
    FoodTemplate(name: "DTF · Veg & Mushroom Fried Rice",         category: .restaurants, kcal: 135, protein: 7,   carbs: 24,  fat: 4,   defaultServingG: 400),

    // Fried Noodles (full plate ~400g)
    FoodTemplate(name: "DTF · Chicken Fried Noodles",             category: .restaurants, kcal: 160, protein: 17,  carbs: 22,  fat: 6,   defaultServingG: 400),
    FoodTemplate(name: "DTF · Shrimp Fried Noodles",              category: .restaurants, kcal: 165, protein: 16,  carbs: 22,  fat: 6.5, defaultServingG: 400),
    FoodTemplate(name: "DTF · Shredded Pork Fried Noodles",       category: .restaurants, kcal: 162, protein: 16,  carbs: 22,  fat: 6,   defaultServingG: 400),
    FoodTemplate(name: "DTF · Veg Fried Noodles",                 category: .restaurants, kcal: 140, protein: 6,   carbs: 25,  fat: 5,   defaultServingG: 400),

    // Shanghai Rice Cakes (full plate ~400g)
    FoodTemplate(name: "DTF · Shanghai Rice Cakes w/ Chicken",    category: .restaurants, kcal: 147, protein: 14,  carbs: 24,  fat: 4,   defaultServingG: 400),
    FoodTemplate(name: "DTF · Shanghai Rice Cakes w/ Shrimp",     category: .restaurants, kcal: 150, protein: 14,  carbs: 25,  fat: 4,   defaultServingG: 400),
    FoodTemplate(name: "DTF · Shanghai Rice Cakes w/ Pork",       category: .restaurants, kcal: 149, protein: 14,  carbs: 24,  fat: 4.5, defaultServingG: 400),
    FoodTemplate(name: "DTF · Vegan Shanghai Rice Cakes",         category: .restaurants, kcal: 130, protein: 4,   carbs: 26,  fat: 3,   defaultServingG: 400),

    // À La Carte
    FoodTemplate(name: "DTF · Fried Pork Chop",                   category: .restaurants, kcal: 210, protein: 22,  carbs: 8,   fat: 12,  defaultServingG: 200),
    FoodTemplate(name: "DTF · Pork Sticky Rice Wrap",             category: .restaurants, kcal: 192, protein: 10,  carbs: 28,  fat: 7,   defaultServingG: 250),

    // Desserts (per piece where noted)
    FoodTemplate(name: "DTF · Shaved Snow w/ Mango",              category: .restaurants, kcal: 74,  protein: 1,   carbs: 18,  fat: 0.5, defaultServingG: 350),
    FoodTemplate(name: "DTF · Chocolate & Mochi XLB (1 piece)",   category: .restaurants, kcal: 183, protein: 2,   carbs: 28,  fat: 6,   defaultServingG: 35),
    FoodTemplate(name: "DTF · Red Bean & Mochi XLB (1 piece)",    category: .restaurants, kcal: 171, protein: 3,   carbs: 27,  fat: 5,   defaultServingG: 35),
    FoodTemplate(name: "DTF · Sweet Taro XLB (1 piece)",          category: .restaurants, kcal: 166, protein: 2,   carbs: 27,  fat: 5,   defaultServingG: 35),
    FoodTemplate(name: "DTF · Sesame & Mochi XLB (1 piece)",      category: .restaurants, kcal: 177, protein: 2,   carbs: 28,  fat: 6,   defaultServingG: 35),
    FoodTemplate(name: "DTF · Chocolate Buns (1 piece)",          category: .restaurants, kcal: 117, protein: 3,   carbs: 19,  fat: 4,   defaultServingG: 70),
    FoodTemplate(name: "DTF · Red Bean Buns (1 piece)",           category: .restaurants, kcal: 107, protein: 3,   carbs: 18,  fat: 3,   defaultServingG: 70),
    FoodTemplate(name: "DTF · Sweet Taro Buns (1 piece)",         category: .restaurants, kcal: 103, protein: 2,   carbs: 18,  fat: 3,   defaultServingG: 70),
    FoodTemplate(name: "DTF · Sesame Buns (1 piece)",             category: .restaurants, kcal: 110, protein: 3,   carbs: 18,  fat: 4,   defaultServingG: 70),
    FoodTemplate(name: "DTF · Red Bean Sticky Rice Wrap",         category: .restaurants, kcal: 180, protein: 4,   carbs: 35,  fat: 4,   defaultServingG: 200),

    // DTF Beverages (per 350 ml serving)
    FoodTemplate(name: "DTF · Milk Tea",                          category: .restaurants, kcal: 63,  protein: 1,   carbs: 15,  fat: 1,   defaultServingG: 350),
    FoodTemplate(name: "DTF · Green Milk Tea",                    category: .restaurants, kcal: 60,  protein: 1,   carbs: 14,  fat: 1,   defaultServingG: 350),
    FoodTemplate(name: "DTF · Honey Milk Tea",                    category: .restaurants, kcal: 66,  protein: 1,   carbs: 16,  fat: 1,   defaultServingG: 350),
    FoodTemplate(name: "DTF · Matcha Jasmine Latte",              category: .restaurants, kcal: 69,  protein: 2,   carbs: 14,  fat: 2,   defaultServingG: 350),
    FoodTemplate(name: "DTF · Iced Green / Black Tea",            category: .restaurants, kcal: 26,  protein: 0,   carbs: 7,   fat: 0,   defaultServingG: 350),
    FoodTemplate(name: "DTF · Sea Salt Cream Tea",                category: .restaurants, kcal: 46,  protein: 1,   carbs: 9,   fat: 2,   defaultServingG: 350),
    FoodTemplate(name: "DTF · Honey Lemonade",                    category: .restaurants, kcal: 43,  protein: 0,   carbs: 11,  fat: 0,   defaultServingG: 350),
    FoodTemplate(name: "DTF · Fresh Squeezed Orange Juice",       category: .restaurants, kcal: 46,  protein: 1,   carbs: 11,  fat: 0,   defaultServingG: 350),

    // MARK: - Restaurants — Joe & The Juice
    FoodTemplate(name: "J&J · Tunacado",                  category: .restaurants, kcal: 218, protein: 13,  carbs: 18,  fat: 12,  defaultServingG: 220),
    FoodTemplate(name: "J&J · Chicken Avocado",           category: .restaurants, kcal: 195, protein: 15,  carbs: 14,  fat: 10,  defaultServingG: 220),
    FoodTemplate(name: "J&J · The Club",                  category: .restaurants, kcal: 217, protein: 18,  carbs: 24,  fat: 10,  defaultServingG: 240),
    FoodTemplate(name: "J&J · Buff (protein shake)",      category: .restaurants, kcal: 109, protein: 8,   carbs: 14,  fat: 3,   defaultServingG: 350),
    FoodTemplate(name: "J&J · Chocolate Milkshake",       category: .restaurants, kcal: 120, protein: 5,   carbs: 18,  fat: 4,   defaultServingG: 350),
    FoodTemplate(name: "J&J · Matcha Shake",              category: .restaurants, kcal: 74,  protein: 4,   carbs: 12,  fat: 1.5, defaultServingG: 350),
    FoodTemplate(name: "J&J · Orange Juice",              category: .restaurants, kcal: 46,  protein: 0.7, carbs: 10,  fat: 0.2, defaultServingG: 250),
    FoodTemplate(name: "J&J · Joe Juice (Apple/Ginger)",  category: .restaurants, kcal: 48,  protein: 0.5, carbs: 11,  fat: 0.1, defaultServingG: 250),
    FoodTemplate(name: "J&J · Acai Bowl",                 category: .restaurants, kcal: 127, protein: 4,   carbs: 22,  fat: 4,   defaultServingG: 300),
    FoodTemplate(name: "J&J · Power Shake (Banana)",      category: .restaurants, kcal: 100, protein: 10,  carbs: 13,  fat: 2,   defaultServingG: 350),

    // MARK: - Restaurants — Baldi at Waldorf Astoria Beverly Hills
    // Baldi does not publish nutrition data; macros estimated from luxury hotel breakfast standards.
    FoodTemplate(name: "Baldi · Eggs Benedict w/ Ham",     category: .restaurants, kcal: 186, protein: 9,   carbs: 9,   fat: 11,  defaultServingG: 350),
    FoodTemplate(name: "Baldi · French Toast (full)",      category: .restaurants, kcal: 300, protein: 10,  carbs: 67,  fat: 30,  defaultServingG: 150),
    FoodTemplate(name: "Baldi · French Toast (half)",      category: .restaurants, kcal: 300, protein: 10,  carbs: 67,  fat: 30,  defaultServingG: 75),
    FoodTemplate(name: "Baldi · Energy Smoothie",          category: .restaurants, kcal: 75,  protein: 2,   carbs: 14,  fat: 1.25,defaultServingG: 400),
    FoodTemplate(name: "Baldi · Avocado Toast",            category: .restaurants, kcal: 183, protein: 6,   carbs: 20,  fat: 9,   defaultServingG: 200),
    FoodTemplate(name: "Baldi · Granola w/ Berries & Yogurt",category: .restaurants, kcal: 140,protein: 6,  carbs: 22,  fat: 4,   defaultServingG: 250),
    FoodTemplate(name: "Baldi · Omelette (3 egg, veg)",    category: .restaurants, kcal: 135, protein: 13,  carbs: 4,   fat: 8,   defaultServingG: 250),
    FoodTemplate(name: "Baldi · Acai Bowl",                category: .restaurants, kcal: 130, protein: 5,   carbs: 25,  fat: 4,   defaultServingG: 300),

    // MARK: - Restaurants — Thai
    // Macros estimated from standard Thai restaurant recipes; serving = typical plate weight.
    FoodTemplate(name: "Thai · Pad See Ew (chicken)",         category: .restaurants, kcal: 148, protein: 12,  carbs: 18,  fat: 4,   defaultServingG: 350),
    FoodTemplate(name: "Thai · Pad See Ew (beef)",            category: .restaurants, kcal: 155, protein: 13,  carbs: 18,  fat: 5,   defaultServingG: 350),
    FoodTemplate(name: "Thai · Pad See Ew (tofu)",            category: .restaurants, kcal: 130, protein: 7,   carbs: 20,  fat: 4,   defaultServingG: 350),
    FoodTemplate(name: "Thai · Pad Thai (chicken)",           category: .restaurants, kcal: 160, protein: 13,  carbs: 20,  fat: 4.5, defaultServingG: 320),
    FoodTemplate(name: "Thai · Pad Thai (shrimp)",            category: .restaurants, kcal: 155, protein: 14,  carbs: 20,  fat: 4,   defaultServingG: 320),
    FoodTemplate(name: "Thai · Pad Krapow (Thai Basil Chicken)", category: .restaurants, kcal: 175, protein: 18, carbs: 6,  fat: 9,   defaultServingG: 300),
    FoodTemplate(name: "Thai · Pad Krapow w/ Fried Egg",      category: .restaurants, kcal: 187, protein: 19,  carbs: 6,   fat: 11,  defaultServingG: 330),
    FoodTemplate(name: "Thai · Green Curry (chicken)",        category: .restaurants, kcal: 133, protein: 10,  carbs: 7,   fat: 8,   defaultServingG: 350),
    FoodTemplate(name: "Thai · Red Curry (chicken)",          category: .restaurants, kcal: 128, protein: 10,  carbs: 7,   fat: 8,   defaultServingG: 350),
    FoodTemplate(name: "Thai · Massaman Curry (chicken)",     category: .restaurants, kcal: 135, protein: 10,  carbs: 9,   fat: 8,   defaultServingG: 350),
    FoodTemplate(name: "Thai · Yellow Curry (chicken)",       category: .restaurants, kcal: 127, protein: 10,  carbs: 8,   fat: 7,   defaultServingG: 350),
    FoodTemplate(name: "Thai · Tom Yum Soup",                 category: .restaurants, kcal: 50,  protein: 5,   carbs: 5,   fat: 2,   defaultServingG: 300),
    FoodTemplate(name: "Thai · Tom Kha Soup (coconut)",       category: .restaurants, kcal: 70,  protein: 5,   carbs: 5,   fat: 4.5, defaultServingG: 300),
    FoodTemplate(name: "Thai · Som Tum (Papaya Salad)",       category: .restaurants, kcal: 53,  protein: 2,   carbs: 11,  fat: 1,   defaultServingG: 250),
    FoodTemplate(name: "Thai · Larb Gai (Chicken Salad)",     category: .restaurants, kcal: 105, protein: 14,  carbs: 6,   fat: 3.5, defaultServingG: 200),
    FoodTemplate(name: "Thai · Khao Man Gai",                 category: .restaurants, kcal: 145, protein: 12,  carbs: 18,  fat: 3,   defaultServingG: 350),
    FoodTemplate(name: "Thai · Khao Pad (Egg Fried Rice)",    category: .restaurants, kcal: 178, protein: 7,   carbs: 28,  fat: 6,   defaultServingG: 300),
    FoodTemplate(name: "Thai · Fresh Spring Rolls (2 pcs)",   category: .restaurants, kcal: 88,  protein: 5,   carbs: 14,  fat: 1.5, defaultServingG: 170),
    FoodTemplate(name: "Thai · Fried Spring Rolls (2 pcs)",   category: .restaurants, kcal: 175, protein: 6,   carbs: 18,  fat: 9,   defaultServingG: 140),
    FoodTemplate(name: "Thai · Mango Sticky Rice",            category: .restaurants, kcal: 183, protein: 3,   carbs: 38,  fat: 3,   defaultServingG: 200),
    FoodTemplate(name: "Thai · Jasmine Rice (side)",          category: .restaurants, kcal: 130, protein: 2.7, carbs: 28,  fat: 0.3, defaultServingG: 200),
    FoodTemplate(name: "Thai · Roti (1 piece)",               category: .restaurants, kcal: 220, protein: 4,   carbs: 32,  fat: 9,   defaultServingG: 80),

    // MARK: - Restaurants — Whole Foods Market
    // Breads: 365 brand + in-store bakery. Values per 100g; serving = 1 slice or 1 piece.
    FoodTemplate(name: "WF · 365 Whole Wheat Bread",          category: .restaurants, kcal: 250, protein: 10.7, carbs: 42.9, fat: 3.6,  fiber: 7.1, sodium: 482, defaultServingG: 28, servingLabel: "1 slice"),
    FoodTemplate(name: "WF · 365 Multigrain Bread",           category: .restaurants, kcal: 267, protein: 10.0, carbs: 46.7, fat: 5.0,  fiber: 6.7, sodium: 500, defaultServingG: 30, servingLabel: "1 slice"),
    FoodTemplate(name: "WF · 365 White Sandwich Bread",       category: .restaurants, kcal: 286, protein: 10.7, carbs: 53.6, fat: 3.6,  fiber: 3.6, sodium: 571, defaultServingG: 28, servingLabel: "1 slice"),
    FoodTemplate(name: "WF · 365 Sourdough Bread",            category: .restaurants, kcal: 263, protein: 10.5, carbs: 52.6, fat: 1.3,  fiber: 2.6, sodium: 474, defaultServingG: 38, servingLabel: "1 slice"),
    FoodTemplate(name: "WF · Bakery Everything Bagel",        category: .restaurants, kcal: 257, protein: 9.5,  carbs: 50.5, fat: 1.9,  fiber: 1.9, sodium: 467, defaultServingG: 105, servingLabel: "1 bagel"),
    FoodTemplate(name: "WF · Bakery Plain Bagel",             category: .restaurants, kcal: 248, protein: 8.6,  carbs: 51.4, fat: 1.0,  fiber: 1.9, sodium: 400, defaultServingG: 105, servingLabel: "1 bagel"),
    FoodTemplate(name: "WF · Bakery Seeded Sourdough",        category: .restaurants, kcal: 275, protein: 10.0, carbs: 52.5, fat: 3.75, fiber: 5.0, sodium: 550, defaultServingG: 40, servingLabel: "1 slice"),

    // Hot Food Bar — values per 100g; serving = typical hot bar scoop/portion
    FoodTemplate(name: "WF · Hot Bar Rotisserie Chicken",     category: .restaurants, kcal: 189, protein: 25.0, carbs: 1.0,  fat: 9.0,  sodium: 480, cholesterol: 85, defaultServingG: 200, servingLabel: "~200g"),
    FoodTemplate(name: "WF · Hot Bar Mac & Cheese",           category: .restaurants, kcal: 195, protein: 7.0,  carbs: 24.0, fat: 8.0,  sodium: 450, defaultServingG: 250, servingLabel: "1 cup"),
    FoodTemplate(name: "WF · Hot Bar Chicken Tikka Masala",   category: .restaurants, kcal: 130, protein: 11.0, carbs: 7.0,  fat: 6.0,  sodium: 380, cholesterol: 45, defaultServingG: 300, servingLabel: "~300g"),
    FoodTemplate(name: "WF · Hot Bar Chana Masala",           category: .restaurants, kcal: 115, protein: 5.0,  carbs: 18.0, fat: 3.0,  fiber: 4.0, sodium: 320, defaultServingG: 300, servingLabel: "~300g"),
    FoodTemplate(name: "WF · Hot Bar Lemon Herb Salmon",      category: .restaurants, kcal: 185, protein: 24.0, carbs: 0.0,  fat: 10.0, sodium: 310, cholesterol: 75, defaultServingG: 170, servingLabel: "~170g fillet"),
    FoodTemplate(name: "WF · Hot Bar BBQ Pulled Pork",        category: .restaurants, kcal: 190, protein: 19.0, carbs: 10.0, fat: 8.0,  sodium: 430, cholesterol: 60, defaultServingG: 200, servingLabel: "~200g"),
    FoodTemplate(name: "WF · Hot Bar Beef Chili",             category: .restaurants, kcal: 120, protein: 9.0,  carbs: 8.0,  fat: 6.0,  fiber: 2.0, sodium: 380, cholesterol: 30, defaultServingG: 350, servingLabel: "1 cup"),
    FoodTemplate(name: "WF · Hot Bar Roasted Vegetables",     category: .restaurants, kcal: 75,  protein: 2.0,  carbs: 12.0, fat: 3.0,  fiber: 3.0, sodium: 180, defaultServingG: 200, servingLabel: "~200g"),
    FoodTemplate(name: "WF · Hot Bar Mashed Potatoes",        category: .restaurants, kcal: 110, protein: 2.0,  carbs: 16.0, fat: 4.5,  sodium: 320, defaultServingG: 230, servingLabel: "1 cup"),
    FoodTemplate(name: "WF · Hot Bar Brown Rice",             category: .restaurants, kcal: 150, protein: 3.0,  carbs: 32.0, fat: 1.0,  fiber: 1.5, sodium: 5, defaultServingG: 185, servingLabel: "1 cup"),
    FoodTemplate(name: "WF · Hot Bar Chicken Tenders",        category: .restaurants, kcal: 220, protein: 21.0, carbs: 11.0, fat: 10.0, sodium: 500, cholesterol: 70, defaultServingG: 150, servingLabel: "~150g"),
    FoodTemplate(name: "WF · Hot Bar Veggie Curry",           category: .restaurants, kcal: 95,  protein: 3.0,  carbs: 14.0, fat: 3.0,  fiber: 3.0, sodium: 280, defaultServingG: 300, servingLabel: "~300g"),

    // Cold Prepared Foods & Salad Bar — values per 100g
    FoodTemplate(name: "WF · Prepared Chicken Caesar Salad",  category: .restaurants, kcal: 155, protein: 12.0, carbs: 6.0,  fat: 9.0,  sodium: 380, cholesterol: 40, defaultServingG: 300, servingLabel: "1 container"),
    FoodTemplate(name: "WF · Prepared Tuna Salad",            category: .restaurants, kcal: 210, protein: 14.0, carbs: 3.0,  fat: 16.0, sodium: 420, cholesterol: 55, defaultServingG: 200, servingLabel: "~200g"),
    FoodTemplate(name: "WF · Prepared Chicken Salad",         category: .restaurants, kcal: 210, protein: 14.0, carbs: 4.0,  fat: 15.0, sodium: 400, cholesterol: 55, defaultServingG: 200, servingLabel: "~200g"),
    FoodTemplate(name: "WF · Prepared Greek Salad",           category: .restaurants, kcal: 100, protein: 3.0,  carbs: 8.0,  fat: 6.0,  fiber: 2.0, sodium: 350, defaultServingG: 250, servingLabel: "1 container"),
    FoodTemplate(name: "WF · Prepared Quinoa Salad",          category: .restaurants, kcal: 145, protein: 5.0,  carbs: 20.0, fat: 5.0,  fiber: 3.0, sodium: 280, defaultServingG: 250, servingLabel: "1 container"),
    FoodTemplate(name: "WF · Prepared Pasta Salad",           category: .restaurants, kcal: 175, protein: 5.0,  carbs: 27.0, fat: 6.0,  fiber: 2.0, sodium: 290, defaultServingG: 250, servingLabel: "1 container"),
    FoodTemplate(name: "WF · California Roll",                category: .restaurants, kcal: 150, protein: 5.0,  carbs: 25.0, fat: 4.0,  sodium: 340, defaultServingG: 200, servingLabel: "1 roll (8 pcs)"),
    FoodTemplate(name: "WF · Spicy Tuna Roll",                category: .restaurants, kcal: 165, protein: 8.0,  carbs: 23.0, fat: 5.0,  sodium: 380, cholesterol: 20, defaultServingG: 200, servingLabel: "1 roll (8 pcs)"),
    FoodTemplate(name: "WF · Turkey & Havarti Sandwich",      category: .restaurants, kcal: 200, protein: 12.0, carbs: 22.0, fat: 7.0,  sodium: 520, cholesterol: 35, defaultServingG: 250, servingLabel: "1 sandwich"),
    FoodTemplate(name: "WF · Acai Bowl",                      category: .restaurants, kcal: 160, protein: 4.0,  carbs: 27.0, fat: 5.0,  fiber: 4.0, sugar: 15.0, defaultServingG: 350, servingLabel: "1 bowl"),

    // MARK: - Supplements — Fibre
    // Psyllium husk: very high soluble fibre; per 100g values; typical dose 5g in water
    FoodTemplate(name: "Psyllium Husk (powder)",     category: .supplements, kcal: 200, protein: 2,  carbs: 80, fat: 1, fiber: 78, defaultServingG: 5),
    FoodTemplate(name: "Psyllium Husk Capsules (6)", category: .supplements, kcal: 200, protein: 2,  carbs: 80, fat: 1, fiber: 78, defaultServingG: 5),

    // MARK: - Supplements — Minerals
    // Note: these are supplement doses; calories come from binders/fillers only.
    // defaultServingG represents a typical dose unit (≈ 1–2 tablets).
    FoodTemplate(name: "Magnesium Glycinate 400 mg", category: .supplements, kcal: 3, protein: 0, carbs: 0.5, fat: 0, defaultServingG: 2),
    FoodTemplate(name: "Magnesium Citrate 400 mg",   category: .supplements, kcal: 3, protein: 0, carbs: 0.5, fat: 0, defaultServingG: 2),
    FoodTemplate(name: "Magnesium Malate 400 mg",    category: .supplements, kcal: 3, protein: 0, carbs: 0.5, fat: 0, defaultServingG: 2),
    FoodTemplate(name: "Zinc 15 mg (tablet)",        category: .supplements, kcal: 1, protein: 0, carbs: 0.2, fat: 0, defaultServingG: 1),
    FoodTemplate(name: "Zinc 25 mg (tablet)",        category: .supplements, kcal: 1, protein: 0, carbs: 0.2, fat: 0, defaultServingG: 1),
    FoodTemplate(name: "Zinc 50 mg (tablet)",        category: .supplements, kcal: 2, protein: 0, carbs: 0.3, fat: 0, defaultServingG: 1),
    FoodTemplate(name: "Calcium Carbonate 500 mg",   category: .supplements, kcal: 2, protein: 0, carbs: 0.5, fat: 0, defaultServingG: 1),
    FoodTemplate(name: "Calcium Citrate 500 mg",     category: .supplements, kcal: 2, protein: 0, carbs: 0.5, fat: 0, defaultServingG: 1),
    FoodTemplate(name: "Calcium + D3 (tablet)",      category: .supplements, kcal: 3, protein: 0, carbs: 0.5, fat: 0, defaultServingG: 1),
    FoodTemplate(name: "Vitamin D3 1000 IU",         category: .supplements, kcal: 1, protein: 0, carbs: 0,   fat: 0, defaultServingG: 1),
    FoodTemplate(name: "Vitamin D3 5000 IU",         category: .supplements, kcal: 5, protein: 0, carbs: 0,   fat: 0.5, defaultServingG: 1),
    FoodTemplate(name: "Omega-3 Fish Oil 1000 mg",   category: .supplements, kcal: 9, protein: 0, carbs: 0,   fat: 1, defaultServingG: 1),
    FoodTemplate(name: "Omega-3 Fish Oil 2000 mg",   category: .supplements, kcal: 18, protein: 0, carbs: 0,  fat: 2, defaultServingG: 2),

    // MARK: - Supplements — Optimum Nutrition
    // Values per 100g; defaultServingG = typical scoop/serving in grams.
    // Source: ON product labels (US versions).
    FoodTemplate(name: "ON Gold Standard Whey (1 scoop)",        category: .supplements, kcal: 400, protein: 80,   carbs: 10,  fat: 3.3, defaultServingG: 30),
    FoodTemplate(name: "ON Gold Standard Casein (1 scoop)",      category: .supplements, kcal: 353, protein: 70.6, carbs: 8.8, fat: 2.9, defaultServingG: 34),
    FoodTemplate(name: "ON Serious Mass (2-scoop serving)",      category: .supplements, kcal: 374, protein: 15,   carbs: 76,  fat: 1.3, defaultServingG: 334),
    FoodTemplate(name: "ON Natural Whey (1 scoop)",              category: .supplements, kcal: 400, protein: 73.3, carbs: 13.3,fat: 5,   defaultServingG: 30),
    FoodTemplate(name: "ON Platinum Hydrowhey (1 scoop)",        category: .supplements, kcal: 387, protein: 83.9, carbs: 3.2, fat: 1.6, defaultServingG: 31),
    FoodTemplate(name: "ON Amino Energy (1 serving)",            category: .supplements, kcal: 56,  protein: 0,    carbs: 11,  fat: 0,   defaultServingG: 9),
    FoodTemplate(name: "ON Creatine Monohydrate (1 serving)",    category: .supplements, kcal: 0,   protein: 0,    carbs: 0,   fat: 0,   defaultServingG: 5),
    FoodTemplate(name: "ON ZMA (3 capsules)",                    category: .supplements, kcal: 5,   protein: 0.5,  carbs: 0.3, fat: 0,   defaultServingG: 3),
    FoodTemplate(name: "ON Pre-Workout (1 serving)",             category: .supplements, kcal: 20,  protein: 0,    carbs: 4,   fat: 0,   defaultServingG: 10),
    FoodTemplate(name: "ON BCAA 5000 Powder (1 serving)",        category: .supplements, kcal: 25,  protein: 5,    carbs: 0,   fat: 0,   defaultServingG: 10),

    // MARK: - Supplements — Other Brands
    FoodTemplate(name: "MyProtein Impact Whey (1 scoop)",        category: .supplements, kcal: 412, protein: 80,   carbs: 7.6, fat: 7.6, defaultServingG: 25),
    FoodTemplate(name: "MyProtein Clear Whey (1 scoop)",         category: .supplements, kcal: 420, protein: 86,   carbs: 4.3, fat: 0.7, defaultServingG: 35),
    FoodTemplate(name: "MyProtein Creatine Monohydrate",         category: .supplements, kcal: 0,   protein: 0,    carbs: 0,   fat: 0,   defaultServingG: 5),
    FoodTemplate(name: "Creatine Monohydrate (generic, 5g)",     category: .supplements, kcal: 0,   protein: 0,    carbs: 0,   fat: 0,   defaultServingG: 5),
    FoodTemplate(name: "Collagen Peptides (generic, 1 scoop)",   category: .supplements, kcal: 364, protein: 90.9, carbs: 0,   fat: 0,   defaultServingG: 11),
    FoodTemplate(name: "Matcha Powder (ceremonial grade, 1 tsp)",category: .supplements, kcal: 324, protein: 24,   carbs: 38,  fat: 5,   defaultServingG: 3),
    FoodTemplate(name: "Spirulina Powder (1 tbsp)",              category: .supplements, kcal: 290, protein: 57,   carbs: 24,  fat: 8,   defaultServingG: 7),
    FoodTemplate(name: "Ashwagandha (600mg capsule)",            category: .supplements, kcal: 3,   protein: 0.1,  carbs: 0.5, fat: 0,   defaultServingG: 1),
    FoodTemplate(name: "L-Glutamine Powder (1 scoop 5g)",        category: .supplements, kcal: 20,  protein: 5,    carbs: 0,   fat: 0,   defaultServingG: 5),
    FoodTemplate(name: "Pre-Workout Generic (1 scoop 10g)",      category: .supplements, kcal: 200, protein: 0,    carbs: 40,  fat: 0,   defaultServingG: 10),
    FoodTemplate(name: "BCAA 2:1:1 Powder (1 scoop 10g)",        category: .supplements, kcal: 250, protein: 50,   carbs: 0,   fat: 0,   defaultServingG: 10),
    FoodTemplate(name: "Vitamin C 1000mg (tablet)",              category: .supplements, kcal: 2,   protein: 0,    carbs: 0.5, fat: 0,   defaultServingG: 1),
    FoodTemplate(name: "Multivitamin (tablet)",                  category: .supplements, kcal: 5,   protein: 0,    carbs: 1,   fat: 0,   defaultServingG: 1),
    FoodTemplate(name: "NMN 500mg (capsule)",                    category: .supplements, kcal: 2,   protein: 0,    carbs: 0.5, fat: 0,   defaultServingG: 1),
    FoodTemplate(name: "Resveratrol 500mg (capsule)",            category: .supplements, kcal: 2,   protein: 0,    carbs: 0.5, fat: 0,   defaultServingG: 1),
    FoodTemplate(name: "Berberine 500mg (capsule)",              category: .supplements, kcal: 2,   protein: 0,    carbs: 0.5, fat: 0,   defaultServingG: 1),
    FoodTemplate(name: "CoQ10 100mg (softgel)",                  category: .supplements, kcal: 5,   protein: 0,    carbs: 0,   fat: 0.5, defaultServingG: 1),
    FoodTemplate(name: "Melatonin 0.3mg (tablet)",               category: .supplements, kcal: 1,   protein: 0,    carbs: 0.2, fat: 0,   defaultServingG: 1),

    // MARK: - Supplements — Blueprint by Bryan Johnson
    // Blueprint EVOO — extra virgin olive oil, unflavoured, same macros as standard EVOO
    FoodTemplate(name: "Blueprint EVOO",                     category: .supplements, kcal: 884, protein: 0,    carbs: 0,    fat: 100,  defaultServingG: 30),
    // Blueprint Protein — plant-based (pea/rice), per serving ~30g powder
    FoodTemplate(name: "Blueprint Protein Powder (1 scoop)", category: .supplements, kcal: 120, protein: 24,   carbs: 5,    fat: 2,    defaultServingG: 30),
    // Blueprint Nutty Pudding — oat/nut/seed base mix; approximate per 100g prepared
    FoodTemplate(name: "Blueprint Nutty Pudding (100g)",     category: .supplements, kcal: 230, protein: 9,    carbs: 25,   fat: 11,   fiber: 3.0, defaultServingG: 200),
    // Blueprint Super Veggie — broccoli + cauliflower + black lentil bowl; per 100g
    FoodTemplate(name: "Blueprint Super Veggie (100g)",      category: .supplements, kcal: 75,  protein: 5,    carbs: 12,   fat: 1,    fiber: 3.5, defaultServingG: 300),
    // Blueprint Longevity Mix — green/berry powder supplement, ~11g scoop
    FoodTemplate(name: "Blueprint Longevity Mix (1 scoop)",  category: .supplements, kcal: 45,  protein: 2,    carbs: 8,    fat: 0.5,  defaultServingG: 11),
    // Blueprint Collagen Protein — per scoop ~10g
    FoodTemplate(name: "Blueprint Collagen Protein (1 scoop)",category: .supplements, kcal: 40, protein: 10,   carbs: 0,    fat: 0,    defaultServingG: 10),
    // Blueprint Blueberry Nut Mix — blueberry + mixed nuts blend, estimated per 100g
    FoodTemplate(name: "Blueprint Blueberry Nut Mix (100g)", category: .supplements, kcal: 430, protein: 10,   carbs: 35,   fat: 28,   fiber: 4.0, defaultServingG: 50),
]
