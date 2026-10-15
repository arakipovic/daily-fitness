import SwiftUI
import FoundationModels

struct FoodLogView: View {
    @Environment(Store.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    @State private var showingAdd = false
    @State private var showingScanner = false
    @State private var showingRecipes = false
    @State private var showingNLEntry = false
    @State private var selectedDate: Date

    private var aiAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }
    @State private var addDefaultMeal: MealType = .breakfast
    @State private var editingEntry: FoodEntry? = nil
    @State private var copyingMeal: MealType? = nil
    @State private var historicalActiveCalories: Double = 0

    init(initialDate: Date = Date()) {
        _selectedDate = State(initialValue: initialDate)
    }

    @State private var dayEntries: [FoodEntry] = []
    @State private var grouped: [MealType: [FoodEntry]] = [:]
    @State private var totalCalories: Int = 0
    @State private var totalProtein: Double = 0
    @State private var totalCarbs: Double = 0
    @State private var totalFiber: Double = 0

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }
    private var activeCaloriesEarned: Int {
        isToday ? Int(healthKit.activeEnergyToday) : Int(historicalActiveCalories)
    }
    private var calorieBudget: Int {
        NutritionLogic.calorieBudget(
            target: store.logbook.calorieTarget,
            activeCalories: activeCaloriesEarned
        )
    }
    private var carbsTarget: Double {
        NutritionLogic.defaultCarbsTarget(calorieTarget: store.logbook.calorieTarget)
    }

    private var dayKey: String { "\(selectedDate.timeIntervalSince1970)-\(store.logbook.foodLog.count)" }

    var body: some View {
        List {
            Section {
                HStack(spacing: 0) {
                    Button {
                        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                    Button {
                        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Progress") {
                MacroProgressBar(
                    label: activeCaloriesEarned > 0
                        ? "Calories (incl. +\(activeCaloriesEarned) active)"
                        : "Calories",
                    current: Double(totalCalories),
                    target: Double(calorieBudget),
                    unit: "kcal",
                    color: .orange
                )
                MacroProgressBar(
                    label: "Protein",
                    current: totalProtein,
                    target: store.logbook.proteinTarget,
                    unit: "g",
                    color: .blue
                )
                MacroProgressBar(
                    label: "Carbs",
                    current: totalCarbs,
                    target: carbsTarget,
                    unit: "g",
                    color: .cyan
                )
                MacroProgressBar(
                    label: "Fiber",
                    current: totalFiber,
                    target: store.logbook.fiberTarget,
                    unit: "g",
                    color: .green
                )
                NavigationLink {
                    TargetsEditorView()
                } label: {
                    Label("Edit Daily Targets", systemImage: "slider.horizontal.3")
                }
            }

            ForEach(MealType.allCases) { meal in
                mealSection(meal: meal)
            }
        }
        .task(id: dayKey) {
            let entries = NutritionLogic.entries(store.logbook.foodLog, on: selectedDate)
            dayEntries = entries
            grouped = NutritionLogic.groupedByMeal(entries)
            totalCalories = NutritionLogic.totalCalories(entries)
            totalProtein = NutritionLogic.totalProtein(entries)
            totalCarbs = NutritionLogic.totalCarbs(entries)
            totalFiber = NutritionLogic.totalFiber(entries)
            guard !Calendar.current.isDateInToday(selectedDate) else {
                historicalActiveCalories = 0; return
            }
            historicalActiveCalories = await healthKit.activeEnergy(on: selectedDate)
        }
        .navigationTitle("Food Log")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        showingScanner = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                    Menu {
                        Button {
                            addDefaultMeal = MealType.guess(from: Date())
                            showingAdd = true
                        } label: {
                            Label("Search Food", systemImage: "magnifyingglass")
                        }
                        if aiAvailable {
                            Button {
                                showingNLEntry = true
                            } label: {
                                Label("Describe What You Ate", systemImage: "text.bubble")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    Menu {
                        Button {
                            showingRecipes = true
                        } label: {
                            Label("From Recipes", systemImage: "fork.knife.circle")
                        }
                        Button {
                            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                            store.copyFoodLog(from: yesterday, to: selectedDate)
                        } label: {
                            Label("Copy from Yesterday", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddFoodView(defaultDate: selectedDate, defaultMeal: addDefaultMeal)
        }
        .sheet(isPresented: $showingScanner) {
            FoodScannerView(date: selectedDate) { showingScanner = false }
        }
        .sheet(isPresented: $showingRecipes) {
            NavigationStack {
                RecipesView(logDate: selectedDate)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingRecipes = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingNLEntry) {
            NLFoodEntryView(date: selectedDate) { showingNLEntry = false }
        }
        .sheet(item: $editingEntry) { entry in
            FoodEntryEditView(entry: entry)
        }
        .sheet(item: $copyingMeal) { meal in
            CopyMealSheet(meal: meal, targetDate: selectedDate)
        }
    }

    @ViewBuilder
    private func mealSection(meal: MealType) -> some View {
        let entries = (grouped[meal] ?? []).sorted { $0.date < $1.date }
        let mealCalories = NutritionLogic.totalCalories(entries)

        Section {
            ForEach(entries) { entry in
                FoodEntryRow(entry: entry)
                    .contentShape(Rectangle())
                    .onTapGesture { editingEntry = entry }
                    .contextMenu {
                        if !isToday {
                            Button {
                                store.copyFoodEntry(entry, to: Date())
                            } label: {
                                Label("Copy to Today", systemImage: "doc.on.doc")
                            }
                        }
                    }
            }
            .onDelete { offsets in
                store.deleteFoodEntries(at: offsets, from: entries)
            }

            Button {
                addDefaultMeal = meal
                showingAdd = true
            } label: {
                Label("Add to \(meal.rawValue)", systemImage: "plus.circle")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: meal.icon)
                    .foregroundStyle(.secondary)
                Text(meal.rawValue)
                    .textCase(nil)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if mealCalories > 0 {
                    Text("\(mealCalories) kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
                Menu {
                    Button {
                        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                        Task { @MainActor in
                            store.copyMeal(meal, from: yesterday, to: selectedDate)
                        }
                    } label: {
                        Label("Copy from Yesterday", systemImage: "doc.on.doc")
                    }
                    Button {
                        copyingMeal = meal
                    } label: {
                        Label("Choose Another Date…", systemImage: "calendar")
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .textCase(nil)
            }
        }
    }
}

// MARK: - Food Entry Row

struct FoodEntryRow: View {
    let entry: FoodEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(entry.calories) kcal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Text("P \(String(format: "%.0f", entry.protein))g").foregroundStyle(.blue)
                Text("C \(String(format: "%.0f", entry.carbs))g").foregroundStyle(.cyan)
                Text("F \(String(format: "%.1f", entry.fat))g").foregroundStyle(.secondary)
            }
            .font(.caption)

            if !nutrientDetails.isEmpty {
                Text(nutrientDetails.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var nutrientDetails: [String] {
        var details: [String] = []
        if entry.fiber > 0 { details.append("Fiber \(String(format: "%.1f", entry.fiber))g") }
        if entry.sugar > 0 { details.append("Sugar \(String(format: "%.1f", entry.sugar))g") }
        if entry.saturatedFat > 0 { details.append("Sat fat \(String(format: "%.1f", entry.saturatedFat))g") }
        if entry.sodium > 0 { details.append("Sodium \(String(format: "%.0f", entry.sodium))mg") }
        if entry.cholesterol > 0 { details.append("Chol \(String(format: "%.0f", entry.cholesterol))mg") }
        return details
    }
}

// MARK: - Food Entry Edit View

struct FoodEntryEditView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var entry: FoodEntry
    @State private var servings: Double
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var fiber: String
    @State private var selectedMeal: MealType

    init(entry: FoodEntry) {
        _entry = State(initialValue: entry)
        let parsed = NutritionLogic.parseServingsFromEntryName(entry.name) ?? 1
        let base = parsed > 1 ? (1.0 / parsed) : 1.0
        _servings = State(initialValue: parsed)
        _calories = State(initialValue: "\(Int((Double(entry.calories) * base).rounded()))")
        _protein = State(initialValue: String(format: "%.1f", entry.protein * base))
        _carbs = State(initialValue: String(format: "%.1f", entry.carbs * base))
        _fat = State(initialValue: String(format: "%.1f", entry.fat * base))
        let backfilled = NutritionLogic.backfilledFiber(for: entry)
        _fiber = State(initialValue: String(format: "%.1f", backfilled * base))
        _selectedMeal = State(initialValue: entry.meal)
    }

    private var baseCaloriesInt: Int { Int(calories) ?? 0 }
    private var baseProtein: Double { Double(protein.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var baseCarbs: Double { Double(carbs.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var baseFat: Double { Double(fat.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var baseFiber: Double { Double(fiber.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    private var scaledCalories: Int { Int((Double(baseCaloriesInt) * servings).rounded()) }
    private var scaledProtein: Double { (baseProtein * servings * 10).rounded() / 10 }
    private var scaledCarbs: Double { (baseCarbs * servings * 10).rounded() / 10 }
    private var scaledFat: Double { (baseFat * servings * 10).rounded() / 10 }

    private func formatted(_ n: Double) -> String {
        n == n.rounded() ? "\(Int(n))" : String(format: "%.1f", n)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    Picker("Meal", selection: $selectedMeal) {
                        ForEach(MealType.allCases) { meal in
                            Label(meal.rawValue, systemImage: meal.icon).tag(meal)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    HStack {
                        TextField("", value: $servings, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.semibold))
                            .frame(maxWidth: 70)
                        Text(servings == 1 ? "serving" : "servings")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Stepper("", onIncrement: {
                            servings = min(99, servings + 0.5)
                        }, onDecrement: {
                            servings = max(0.5, servings - 0.5)
                        }).labelsHidden()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([0.5, 1.0, 1.5, 2.0, 3.0], id: \.self) { n in
                                Button("\(formatted(n))×") { servings = n }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .tint(servings == n ? .accentColor : .secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Quantity")
                }

                Section("Macros per serving") {
                    LabeledContent("Calories (kcal)") {
                        TextField("0", text: $calories)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Protein (g)") {
                        TextField("0", text: $protein)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Carbs (g)") {
                        TextField("0", text: $carbs)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Fat (g)") {
                        TextField("0", text: $fat)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Fiber (g)") {
                        TextField("0", text: $fiber)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if servings != 1 {
                    Section("Total (\(formatted(servings))×)") {
                        LabeledContent("Calories", value: "\(scaledCalories) kcal")
                        LabeledContent("Protein", value: "\(String(format: "%.1f", scaledProtein))g")
                        LabeledContent("Carbs", value: "\(String(format: "%.1f", scaledCarbs))g")
                        LabeledContent("Fat", value: "\(String(format: "%.1f", scaledFat))g")
                    }
                    .foregroundStyle(.secondary)
                }

                Section {
                    Button("Delete Entry", role: .destructive) {
                        store.deleteFoodEntry(id: entry.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let s = max(0.1, servings)
                        var updated = entry
                        updated.calories = scaledCalories
                        updated.protein = (baseProtein * s * 10).rounded() / 10
                        updated.carbs = (baseCarbs * s * 10).rounded() / 10
                        updated.fat = (baseFat * s * 10).rounded() / 10
                        updated.fiber = (baseFiber * s * 10).rounded() / 10
                        updated.meal = selectedMeal
                        let base = NutritionLogic.baseNameFromEntryName(entry.name)
                        updated.name = s == 1 ? base : "\(base) (\(formatted(s))×)"
                        store.updateFoodEntry(updated)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Macro Progress Bar

struct MacroProgressBar: View {
    let label: String
    let current: Double
    let target: Double
    let unit: String
    let color: Color

    var fraction: Double { target > 0 ? min(current / target, 1.0) : 0 }
    var over: Bool { current > target }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(formatValue(current)) / \(formatValue(target)) \(unit)")
                    .font(.caption)
                    .foregroundStyle(over ? .red : .secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(over ? Color.red : color)
                        .frame(width: geo.size.width * fraction, height: 8)
                        .animation(.spring(duration: 0.4), value: fraction)
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 2)
    }

    private func formatValue(_ v: Double) -> String {
        String(format: "%.0f", v)
    }
}

// MARK: - Add Food Sheet

struct AddFoodView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let defaultDate: Date
    let defaultMeal: MealType

    @State private var searchText = ""
    @State private var showingCustomEntry = false
    @State private var showingMealBuilder = false
    @State private var searchResults: [FoodTemplate] = []
    @State private var foodCount = 0

    init(defaultDate: Date, defaultMeal: MealType = MealType.guess(from: Date())) {
        self.defaultDate = defaultDate
        self.defaultMeal = defaultMeal
    }

    // MARK: - Computed

    private var recentEntries: [FoodEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        var seen = Set<String>()
        return store.logbook.foodLog
            .filter { $0.date >= cutoff }
            .sorted { $0.date > $1.date }
            .filter { seen.insert($0.name).inserted }
            .prefix(10)
            .map { $0 }
    }

    private var savedMeals: [SavedMeal] {
        store.logbook.savedMeals.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var savedMealSearchResults: [SavedMeal] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return savedMeals.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    Section {
                        Button { showingMealBuilder = true } label: {
                            Label("Create saved meal", systemImage: "list.bullet.rectangle.portrait")
                        }
                        Button { showingCustomEntry = true } label: {
                            Label("Enter custom food", systemImage: "square.and.pencil")
                        }
                        NavigationLink {
                            FoodDatabaseBrowserView(defaultDate: defaultDate, defaultMeal: defaultMeal) { dismiss() }
                        } label: {
                            Label("Browse all \(foodCount) foods", systemImage: "list.bullet")
                        }
                    }

                    if !recentEntries.isEmpty {
                        Section("Recents") {
                            ForEach(recentEntries) { entry in
                                RecentFoodRow(
                                    entry: entry,
                                    template: matchingTemplate(for: entry),
                                    date: defaultDate,
                                    defaultMeal: defaultMeal,
                                    onLogged: { dismiss() }
                                )
                            }
                        }
                    }

                    if !savedMeals.isEmpty {
                        Section("Saved Meals") {
                            ForEach(savedMeals) { meal in
                                NavigationLink {
                                    MealBuilderView(date: defaultDate, existingMeal: meal, defaultMeal: defaultMeal) { dismiss() }
                                } label: {
                                    SavedMealRow(meal: meal)
                                }
                            }
                            .onDelete { offsets in
                                let meals = savedMeals
                                offsets.map { meals[$0].id }.forEach(store.deleteSavedMeal)
                            }
                        }
                    }

                } else {
                    if !savedMealSearchResults.isEmpty {
                        Section("Saved Meals") {
                            ForEach(savedMealSearchResults) { meal in
                                NavigationLink {
                                    MealBuilderView(date: defaultDate, existingMeal: meal, defaultMeal: defaultMeal) { dismiss() }
                                } label: {
                                    SavedMealRow(meal: meal)
                                }
                            }
                        }
                    }
                    if searchResults.isEmpty && savedMealSearchResults.isEmpty {
                        Section {
                            Text("No foods matched \"\(searchText)\"")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                            Button { showingCustomEntry = true } label: {
                                Label("Enter \"\(searchText)\" manually", systemImage: "square.and.pencil")
                            }
                        }
                    } else if !searchResults.isEmpty {
                        Section("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s")") {
                            ForEach(searchResults) { food in
                                NavigationLink {
                                    FoodAmountView(food: food, date: defaultDate, defaultMeal: defaultMeal) { dismiss() }
                                } label: {
                                    FoodTemplateRow(food: food)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search \(foodCount) foods…")
            .navigationTitle("Add Food")
            .task {
                await FoodStore.shared.setup()
                foodCount = await FoodStore.shared.count
            }
            .task(id: searchText) {
                guard !searchText.isEmpty else { searchResults = []; return }
                searchResults = await FoodStore.shared.search(searchText, userID: store.profileID)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCustomEntry) {
                CustomFoodEntryView(date: defaultDate, defaultMeal: defaultMeal) { dismiss() }
            }
            .sheet(isPresented: $showingMealBuilder) {
                MealBuilderView(date: defaultDate, defaultMeal: defaultMeal) { dismiss() }
            }
        }
    }

    private func matchingTemplate(for entry: FoodEntry) -> FoodTemplate? {
        foodDatabase.first { entry.name.hasPrefix($0.name + " (") || entry.name == $0.name }
    }
}

private struct SavedMealRow: View {
    let meal: SavedMeal

    private var totals: (
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
        NutritionLogic.macros(for: meal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meal.name)
                .font(.subheadline.weight(.medium))
            HStack(spacing: 10) {
                Text("\(meal.ingredients.count) parts")
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(totals.kcal) kcal")
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("P \(String(format: "%.0f", totals.protein))g")
                    .foregroundStyle(.blue)
                if totals.fiber > 0 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("Fiber \(String(format: "%.1f", totals.fiber))g")
                        .foregroundStyle(.green)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }
}

// MARK: Recent Food Row

private struct RecentFoodRow: View {
    let entry: FoodEntry
    let template: FoodTemplate?
    let date: Date
    let defaultMeal: MealType
    let onLogged: () -> Void

    var body: some View {
        if let template {
            NavigationLink {
                FoodAmountView(food: template, date: date, defaultMeal: defaultMeal) { onLogged() }
            } label: {
                rowLabel
            }
        } else {
            NavigationLink {
                FoodEntryAmountView(entry: entry, date: date, defaultMeal: defaultMeal) { onLogged() }
            } label: {
                rowLabel
            }
        }
    }

    private var rowLabel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.name)
                .font(.subheadline)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text("\(entry.calories) kcal")
                Text("·").foregroundStyle(.tertiary)
                Text("P \(String(format: "%.0f", entry.protein))g").foregroundStyle(.blue)
                Text("·").foregroundStyle(.tertiary)
                Text("C \(String(format: "%.0f", entry.carbs))g").foregroundStyle(.cyan)
                if entry.fiber > 0 {
                    Text("·").foregroundStyle(.tertiary)
                    Text("Fiber \(String(format: "%.1f", entry.fiber))g").foregroundStyle(.green)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: Food Template Row

private struct FoodTemplateRow: View {
    let food: FoodTemplate

    var m: (
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
        food.macros(forGrams: Double(food.defaultServingG))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(food.name)
                .font(.subheadline)
            HStack(spacing: 10) {
                Text(food.defaultServingSummary)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(m.kcal) kcal")
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("P \(String(format: "%.0f", m.p))g")
                    .foregroundStyle(.blue)
                if m.fiber > 0 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("Fiber \(String(format: "%.1f", m.fiber))g")
                        .foregroundStyle(.green)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }
}

// MARK: Food Amount View (for database items)

struct FoodAmountView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let food: FoodTemplate
    let date: Date
    let onAdded: () -> Void

    @State private var gramsText: String
    @State private var selectedMeal: MealType
    @FocusState private var focused: Bool

    init(food: FoodTemplate, date: Date, defaultMeal: MealType = MealType.guess(from: Date()), onAdded: @escaping () -> Void) {
        self.food = food
        self.date = date
        self.onAdded = onAdded
        _gramsText = State(initialValue: "\(food.defaultServingG)")
        _selectedMeal = State(initialValue: defaultMeal)
    }

    var grams: Double { max(0, Double(gramsText) ?? Double(food.defaultServingG)) }
    var m: (
        kcal: Int,
        p: Double,
        c: Double,
        f: Double,
        fiber: Double,
        sugar: Double,
        saturatedFat: Double,
        sodium: Double,
        cholesterol: Double
    ) { food.macros(forGrams: grams) }

    // Adaptive stepper: finer steps for small amounts, coarser for large ones.
    private var stepSize: Int {
        switch Int(grams) {
        case ..<20:   return 1
        case 20..<100: return 5
        case 100..<500: return 10
        default: return 25
        }
    }

    private var lastLoggedGrams: Double? {
        NutritionLogic.lastLoggedGrams(forFood: food, in: store.logbook.foodLog)
    }

    var body: some View {
        Form {
            Section("Meal") {
                Picker("Meal", selection: $selectedMeal) {
                    ForEach(MealType.allCases) { meal in
                        Label(meal.rawValue, systemImage: meal.icon).tag(meal)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Serving size") {
                HStack {
                    TextField("Grams", text: $gramsText)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .font(.title2.weight(.semibold))
                    Text("g")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Stepper("", onIncrement: { adjust(by: stepSize) }, onDecrement: { adjust(by: -stepSize) })
                        .labelsHidden()
                }
                // Quick-select chips: common portions + last logged amount
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        portionChip(grams: food.defaultServingG, label: food.defaultServingDescription, isHighlighted: true)
                        if food.defaultServingG >= 20 {
                            portionChip(grams: food.defaultServingG / 2, label: "\(food.defaultServingG / 2)g")
                        }
                        portionChip(grams: food.defaultServingG * 2, label: "\(food.defaultServingG * 2)g")
                        if let last = lastLoggedGrams, Int(last) != food.defaultServingG {
                            portionChip(grams: Int(last), label: "Last: \(Int(last))g")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Macros for \(food.macroHeading(forGrams: grams))") {
                MacroResultRow(label: "Calories", value: "\(m.kcal) kcal", color: .primary)
                MacroResultRow(label: "Protein",  value: "\(String(format: "%.1f", m.p))g", color: .blue)
                MacroResultRow(label: "Carbs",    value: "\(String(format: "%.1f", m.c))g", color: .cyan)
                MacroResultRow(label: "Fat",      value: "\(String(format: "%.1f", m.f))g", color: .yellow)
                MacroResultRow(label: "Fiber",    value: "\(String(format: "%.1f", m.fiber))g", color: .green)
                if m.sugar > 0 {
                    MacroResultRow(label: "Sugar", value: "\(String(format: "%.1f", m.sugar))g", color: .gray)
                }
                if m.saturatedFat > 0 {
                    MacroResultRow(label: "Saturated Fat", value: "\(String(format: "%.1f", m.saturatedFat))g", color: .gray)
                }
                if m.sodium > 0 {
                    MacroResultRow(label: "Sodium", value: "\(String(format: "%.0f", m.sodium))mg", color: .gray)
                }
                if m.cholesterol > 0 {
                    MacroResultRow(label: "Cholesterol", value: "\(String(format: "%.0f", m.cholesterol))mg", color: .gray)
                }
            }

            Section {
                Button {
                    store.addFoodEntry(FoodEntry(
                        name: food.logName(forGrams: grams),
                        calories: m.kcal,
                        protein: m.p,
                        carbs: m.c,
                        fat: m.f,
                        fiber: m.fiber,
                        sugar: m.sugar,
                        saturatedFat: m.saturatedFat,
                        sodium: m.sodium,
                        cholesterol: m.cholesterol,
                        date: date,
                        meal: selectedMeal
                    ))
                    onAdded()
                    dismiss()
                } label: {
                    Text("Add to Log")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
            }
        }
        .navigationTitle(food.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
    }

    private func adjust(by delta: Int) {
        let current = Int(Double(gramsText) ?? Double(food.defaultServingG))
        gramsText = "\(max(1, current + delta))"
    }

    @ViewBuilder
    private func portionChip(grams: Int, label: String, isHighlighted: Bool = false) -> some View {
        Button(label) { gramsText = "\(grams)" }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(isHighlighted ? .accentColor : .secondary)
    }
}

// MARK: Food Entry Amount View (for re-logging custom/recent entries)

struct FoodEntryAmountView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let entry: FoodEntry
    let date: Date
    let onAdded: () -> Void

    @State private var multiplierText = "1"
    @State private var selectedMeal: MealType
    @FocusState private var focused: Bool

    init(entry: FoodEntry, date: Date, defaultMeal: MealType = MealType.guess(from: Date()), onAdded: @escaping () -> Void) {
        self.entry = entry
        self.date = date
        self.onAdded = onAdded
        _selectedMeal = State(initialValue: defaultMeal)
    }

    private var multiplier: Double {
        max(0.1, Double(multiplierText.replacingOccurrences(of: ",", with: ".")) ?? 1)
    }

    private var scaledCalories: Int { Int((Double(entry.calories) * multiplier).rounded()) }
    private var scaledProtein: Double { (entry.protein * multiplier * 10).rounded() / 10 }
    private var scaledCarbs: Double { (entry.carbs * multiplier * 10).rounded() / 10 }
    private var scaledFat: Double { (entry.fat * multiplier * 10).rounded() / 10 }
    private var scaledFiber: Double { (entry.fiber * multiplier * 10).rounded() / 10 }

    var body: some View {
        Form {
            Section("Meal") {
                Picker("Meal", selection: $selectedMeal) {
                    ForEach(MealType.allCases) { meal in
                        Label(meal.rawValue, systemImage: meal.icon).tag(meal)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Servings") {
                HStack {
                    TextField("1", text: $multiplierText)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .font(.title2.weight(.semibold))
                    Text("× serving")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Stepper("", onIncrement: { adjustMultiplier(by: 0.5) }, onDecrement: { adjustMultiplier(by: -0.5) })
                        .labelsHidden()
                }
                Button("Reset to 1 serving") { multiplierText = "1" }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Macros for \(String(format: "%g", multiplier))× serving") {
                MacroResultRow(label: "Calories", value: "\(scaledCalories) kcal", color: .primary)
                MacroResultRow(label: "Protein",  value: "\(String(format: "%.1f", scaledProtein))g", color: .blue)
                MacroResultRow(label: "Carbs",    value: "\(String(format: "%.1f", scaledCarbs))g", color: .cyan)
                MacroResultRow(label: "Fat",      value: "\(String(format: "%.1f", scaledFat))g", color: .yellow)
                if entry.fiber > 0 {
                    MacroResultRow(label: "Fiber", value: "\(String(format: "%.1f", scaledFiber))g", color: .green)
                }
            }

            Section {
                Button {
                    store.addFoodEntry(FoodEntry(
                        name: entry.name,
                        calories: scaledCalories,
                        protein: scaledProtein,
                        carbs: scaledCarbs,
                        fat: scaledFat,
                        fiber: scaledFiber,
                        sugar: (entry.sugar * multiplier * 10).rounded() / 10,
                        saturatedFat: (entry.saturatedFat * multiplier * 10).rounded() / 10,
                        sodium: (entry.sodium * multiplier).rounded(),
                        cholesterol: (entry.cholesterol * multiplier).rounded(),
                        date: date,
                        meal: selectedMeal
                    ))
                    onAdded()
                    dismiss()
                } label: {
                    Text("Add to Log")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
            }
        }
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
    }

    private func adjustMultiplier(by delta: Double) {
        let current = Double(multiplierText.replacingOccurrences(of: ",", with: ".")) ?? 1
        let next = max(0.5, (current + delta * 2).rounded() / 2)
        multiplierText = String(format: "%g", next)
    }
}

private struct MacroResultRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(color == .primary ? Color.primary : color)
        }
    }
}

// MARK: Custom Food Entry

struct CustomFoodEntryView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let date: Date
    let onAdded: () -> Void

    @State private var selectedMeal: MealType
    @State private var name = ""
    @State private var useIngredients = false
    @State private var ingredients: [SavedMealIngredient] = []
    @State private var showingPicker = false

    // Manual macro fields
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var fiber = ""
    @State private var sugar = ""
    @State private var saturatedFat = ""
    @State private var sodium = ""
    @State private var cholesterol = ""

    init(date: Date, defaultMeal: MealType = MealType.guess(from: Date()), onAdded: @escaping () -> Void) {
        self.date = date
        self.onAdded = onAdded
        _selectedMeal = State(initialValue: defaultMeal)
    }

    private var tempMeal: SavedMeal {
        SavedMeal(name: name, ingredients: ingredients)
    }

    private var ingredientTotals: (kcal: Int, protein: Double, carbs: Double, fat: Double, fiber: Double, sugar: Double, saturatedFat: Double, sodium: Double, cholesterol: Double) {
        NutritionLogic.macros(for: tempMeal)
    }

    var isValid: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        if useIngredients { return hasName && !ingredients.isEmpty }
        return hasName && Int(calories) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    Picker("Meal", selection: $selectedMeal) {
                        ForEach(MealType.allCases) { meal in
                            Label(meal.rawValue, systemImage: meal.icon).tag(meal)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Picker("Entry method", selection: $useIngredients) {
                        Text("Enter macros").tag(false)
                        Text("From ingredients").tag(true)
                    }
                    .pickerStyle(.segmented)
                    TextField("Name (e.g. Morning Protein Shake)", text: $name)
                }

                if useIngredients {
                    Section {
                        ForEach($ingredients) { $ing in
                            MealIngredientRow(ingredient: $ing)
                        }
                        .onDelete { ingredients.remove(atOffsets: $0) }
                        Button {
                            showingPicker = true
                        } label: {
                            Label("Add Ingredient", systemImage: "plus.circle")
                        }
                    } header: {
                        Text("Ingredients (\(ingredients.count))")
                    }

                    if !ingredients.isEmpty {
                        let t = ingredientTotals
                        Section("Computed Macros") {
                            MacroResultRow(label: "Calories",     value: "\(t.kcal) kcal",                              color: .primary)
                            MacroResultRow(label: "Protein",      value: "\(String(format: "%.1f", t.protein))g",       color: .blue)
                            MacroResultRow(label: "Carbs",        value: "\(String(format: "%.1f", t.carbs))g",         color: .cyan)
                            MacroResultRow(label: "Fat",          value: "\(String(format: "%.1f", t.fat))g",           color: .yellow)
                            MacroResultRow(label: "Fiber",        value: "\(String(format: "%.1f", t.fiber))g",         color: .green)
                            if t.sugar > 0 { MacroResultRow(label: "Sugar",         value: "\(String(format: "%.1f", t.sugar))g",         color: .gray) }
                            if t.saturatedFat > 0 { MacroResultRow(label: "Sat Fat", value: "\(String(format: "%.1f", t.saturatedFat))g", color: .gray) }
                            if t.sodium > 0 { MacroResultRow(label: "Sodium",        value: "\(String(format: "%.0f", t.sodium))mg",       color: .gray) }
                        }

                        Section {
                            Button {
                                store.saveMeal(tempMeal)
                            } label: {
                                Label("Save as reusable meal", systemImage: "bookmark")
                            }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        } footer: {
                            Text("Saves this ingredient combination to your meal library for future use.")
                        }
                    }
                } else {
                    Section("Food") {
                        LabeledContent("Calories") {
                            TextField("0", text: $calories)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    Section("Macros (optional)") {
                        LabeledContent("Protein (g)") {
                            TextField("0", text: $protein)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Carbs (g)") {
                            TextField("0", text: $carbs)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Fat (g)") {
                            TextField("0", text: $fat)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Fiber (g)") {
                            TextField("0", text: $fiber)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Sugar (g)") {
                            TextField("0", text: $sugar)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Saturated Fat (g)") {
                            TextField("0", text: $saturatedFat)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Sodium (mg)") {
                            TextField("0", text: $sodium)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Cholesterol (mg)") {
                            TextField("0", text: $cholesterol)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            .navigationTitle("Custom Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { logEntry() }
                        .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showingPicker) {
                IngredientPickerView { ingredient in
                    ingredients.append(ingredient)
                }
            }
        }
    }

    private func logEntry() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let entry: FoodEntry
        if useIngredients {
            let t = ingredientTotals
            entry = FoodEntry(
                name: trimmedName,
                calories: t.kcal,
                protein: t.protein,
                carbs: t.carbs,
                fat: t.fat,
                fiber: t.fiber,
                sugar: t.sugar,
                saturatedFat: t.saturatedFat,
                sodium: t.sodium,
                cholesterol: t.cholesterol,
                date: date,
                meal: selectedMeal
            )
        } else {
            let kcal  = Double(Int(calories) ?? 0)
            let prot  = Double(protein.replacingOccurrences(of: ",", with: ".")) ?? 0
            let crb   = Double(carbs.replacingOccurrences(of: ",", with: ".")) ?? 0
            let ft    = Double(fat.replacingOccurrences(of: ",", with: ".")) ?? 0
            let fib   = Double(fiber.replacingOccurrences(of: ",", with: ".")) ?? 0
            let sug   = Double(sugar.replacingOccurrences(of: ",", with: ".")) ?? 0
            let satFt = Double(saturatedFat.replacingOccurrences(of: ",", with: ".")) ?? 0
            let sod   = Double(sodium.replacingOccurrences(of: ",", with: ".")) ?? 0
            let chol  = Double(cholesterol.replacingOccurrences(of: ",", with: ".")) ?? 0
            entry = FoodEntry(
                name: trimmedName,
                calories: Int(kcal),
                protein: prot,
                carbs: crb,
                fat: ft,
                fiber: fib,
                sugar: sug,
                saturatedFat: satFt,
                sodium: sod,
                cholesterol: chol,
                date: date,
                meal: selectedMeal
            )
            // Save to the food database so the user can find it in future searches.
            // Macros are stored as-entered (one serving = 100g unit for scaling).
            let template = FoodTemplate(
                name: trimmedName,
                category: .meals,
                kcal: kcal,
                protein: prot,
                carbs: crb,
                fat: ft,
                fiber: fib,
                sugar: sug,
                saturatedFat: satFt,
                sodium: sod,
                cholesterol: chol,
                defaultServingG: 100,
                servingLabel: "1 serving"
            )
            Task { await FoodStore.shared.insertCustomFood(template, userID: store.profileID) }
        }
        store.addFoodEntry(entry)
        onAdded()
        dismiss()
    }
}

// MARK: - Meal Builder

struct MealBuilderView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let existingMeal: SavedMeal?
    private let replacingEntries: [FoodEntry]
    let date: Date
    let onAdded: () -> Void

    @State private var mealID: UUID
    @State private var createdAt: Date
    @State private var mealName = ""
    @State private var ingredients: [SavedMealIngredient] = []
    @State private var logDate: Date
    @State private var servingsText = "1"
    @State private var showingPicker = false
    @State private var selectedMealType: MealType

    init(date: Date, existingMeal: SavedMeal? = nil, defaultMeal: MealType = MealType.guess(from: Date()), replacingEntry: FoodEntry? = nil, replacingEntries: [FoodEntry] = [], onAdded: @escaping () -> Void) {
        self.date = date
        self.existingMeal = existingMeal
        let allReplacing = replacingEntry.map { [$0] } ?? replacingEntries
        self.replacingEntries = allReplacing
        self.onAdded = onAdded
        _mealID = State(initialValue: existingMeal?.id ?? UUID())
        _createdAt = State(initialValue: existingMeal?.createdAt ?? Date())
        _mealName = State(initialValue: existingMeal?.name ?? "")
        _ingredients = State(initialValue: existingMeal?.ingredients ?? [])
        _logDate = State(initialValue: allReplacing.first?.date ?? date)
        _selectedMealType = State(initialValue: allReplacing.first?.meal ?? defaultMeal)
    }

    var servings: Double {
        max(0, Double(servingsText) ?? 1)
    }

    var meal: SavedMeal {
        SavedMeal(
            id: mealID,
            name: mealName.trimmingCharacters(in: .whitespaces),
            ingredients: ingredients,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }

    var totals: (
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
        NutritionLogic.macros(for: meal, servings: servings)
    }

    var isValid: Bool {
        !mealName.trimmingCharacters(in: .whitespaces).isEmpty && !ingredients.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal Name") {
                    TextField("e.g. Morning Protein Shake", text: $mealName)
                }

                Section("Log") {
                    DatePicker("Date", selection: $logDate, displayedComponents: .date)
                    Picker("Meal", selection: $selectedMealType) {
                        ForEach(MealType.allCases) { m in
                            Label(m.rawValue, systemImage: m.icon).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    LabeledContent("Servings") {
                        TextField("1", text: $servingsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    ForEach($ingredients) { $ing in
                        MealIngredientRow(ingredient: $ing)
                    }
                    .onDelete { ingredients.remove(atOffsets: $0) }

                    Button {
                        showingPicker = true
                    } label: {
                        Label("Add Ingredient", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Ingredients (\(ingredients.count))")
                }

                if !ingredients.isEmpty {
                    Section(servings == 1 ? "Total Nutrients" : "Total Nutrients for \(NutritionLogic.servingText(servings))") {
                        nutrientRows(totals)
                    }

                    Section {
                        if replacingEntries.isEmpty {
                            Button {
                                store.saveMeal(meal)
                            } label: {
                                Text("Save Meal")
                                    .frame(maxWidth: .infinity)
                                    .fontWeight(.semibold)
                            }
                            .disabled(!isValid)
                        }

                        Button {
                            let meal = meal
                            if !replacingEntries.isEmpty {
                                replacingEntries.forEach { store.deleteFoodEntry(id: $0.id) }
                            } else {
                                store.saveMeal(meal)
                            }
                            store.logMeal(
                                meal,
                                date: logDate,
                                servings: servings,
                                logIngredientsSeparately: false,
                                mealType: selectedMealType
                            )
                            onAdded()
                            dismiss()
                        } label: {
                            Text(!replacingEntries.isEmpty ? "Update" : (existingMeal == nil ? "Save & Log Meal" : "Log Meal"))
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                        .disabled(!isValid || servings <= 0)
                    }
                }
            }
            .navigationTitle(!replacingEntries.isEmpty ? "Edit Logged Meal" : (existingMeal == nil ? "Create Meal" : "Edit Meal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPicker) {
                IngredientPickerView { ingredient in
                    ingredients.append(ingredient)
                }
            }
        }
    }

    @ViewBuilder
    private func nutrientRows(_ values: (
        kcal: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double,
        sugar: Double,
        saturatedFat: Double,
        sodium: Double,
        cholesterol: Double
    )) -> some View {
        MacroResultRow(label: "Calories", value: "\(values.kcal) kcal", color: .primary)
        MacroResultRow(label: "Protein", value: "\(String(format: "%.1f", values.protein))g", color: .blue)
        MacroResultRow(label: "Carbs", value: "\(String(format: "%.1f", values.carbs))g", color: .cyan)
        MacroResultRow(label: "Fat", value: "\(String(format: "%.1f", values.fat))g", color: .yellow)
        MacroResultRow(label: "Fiber", value: "\(String(format: "%.1f", values.fiber))g", color: .green)
        if values.sugar > 0 {
            MacroResultRow(label: "Sugar", value: "\(String(format: "%.1f", values.sugar))g", color: .gray)
        }
        if values.saturatedFat > 0 {
            MacroResultRow(label: "Saturated Fat", value: "\(String(format: "%.1f", values.saturatedFat))g", color: .gray)
        }
        if values.sodium > 0 {
            MacroResultRow(label: "Sodium", value: "\(String(format: "%.0f", values.sodium))mg", color: .gray)
        }
        if values.cholesterol > 0 {
            MacroResultRow(label: "Cholesterol", value: "\(String(format: "%.0f", values.cholesterol))mg", color: .gray)
        }
    }
}

private struct MealIngredientRow: View {
    @Binding var ingredient: SavedMealIngredient

    var m: (
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
        NutritionLogic.macros(for: ingredient)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(ingredient.name)
                    .font(.subheadline)
                Spacer()
                Text("\(m.kcal) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                TextField("g", value: $ingredient.grams, format: .number)
                    .keyboardType(.decimalPad)
                    .font(.caption)
                    .frame(width: 50)
                    .textFieldStyle(.roundedBorder)
                Text("g · P \(String(format: "%.0f", m.protein))  C \(String(format: "%.0f", m.carbs))  F \(String(format: "%.0f", m.fat))  Fiber \(String(format: "%.1f", m.fiber))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct IngredientPickerView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let onSelected: (SavedMealIngredient) -> Void

    @State private var searchText = ""
    @State private var selectedTemplate: FoodTemplate?
    @State private var selectedSavedMeal: SavedMeal?
    @State private var gramsText = ""
    @State private var servingsText = "1"
    @State private var dbSearchResults: [FoodTemplate] = []
    @State private var browseFoods: [FoodCategory: [FoodTemplate]] = [:]

    private var savedMeals: [SavedMeal] {
        store.logbook.savedMeals.sorted { $0.name < $1.name }
    }

    var grouped: [(FoodCategory, [FoodTemplate])] {
        let source: [FoodTemplate] = searchText.isEmpty
            ? FoodCategory.allCases.flatMap { browseFoods[$0] ?? [] }
            : dbSearchResults
        return FoodCategory.allCases.compactMap { cat in
            let items = source.filter { $0.category == cat }
            return items.isEmpty ? nil : (cat, items)
        }
    }

    var body: some View {
        NavigationStack {
            if let template = selectedTemplate {
                templateAmountView(template: template)
            } else if let meal = selectedSavedMeal {
                savedMealServingsView(meal: meal)
            } else {
                pickerList
            }
        }
    }

    @ViewBuilder
    private func templateAmountView(template: FoodTemplate) -> some View {
        let grams = max(0.1, Double(gramsText) ?? Double(template.defaultServingG))
        let m = template.macros(forGrams: grams)
        Form {
            Section(template.name) {
                HStack {
                    TextField("Grams", text: $gramsText)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                    Text("g")
                        .foregroundStyle(.secondary)
                }
                Button("Default (\(template.defaultServingDescription))") {
                    gramsText = "\(template.defaultServingG)"
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section("Macros") {
                MacroResultRow(label: "Calories", value: "\(m.kcal) kcal", color: .primary)
                MacroResultRow(label: "Protein",  value: "\(String(format: "%.1f", m.p))g", color: .blue)
                MacroResultRow(label: "Carbs",    value: "\(String(format: "%.1f", m.c))g", color: .cyan)
                MacroResultRow(label: "Fat",      value: "\(String(format: "%.1f", m.f))g", color: .yellow)
                MacroResultRow(label: "Fiber",    value: "\(String(format: "%.1f", m.fiber))g", color: .green)
                if m.sugar > 0 { MacroResultRow(label: "Sugar", value: "\(String(format: "%.1f", m.sugar))g", color: .gray) }
                if m.saturatedFat > 0 { MacroResultRow(label: "Saturated Fat", value: "\(String(format: "%.1f", m.saturatedFat))g", color: .gray) }
                if m.sodium > 0 { MacroResultRow(label: "Sodium", value: "\(String(format: "%.0f", m.sodium))mg", color: .gray) }
                if m.cholesterol > 0 { MacroResultRow(label: "Cholesterol", value: "\(String(format: "%.0f", m.cholesterol))mg", color: .gray) }
            }
            Section {
                Button {
                    onSelected(SavedMealIngredient(template: template, grams: grams))
                    dismiss()
                } label: {
                    Text("Add to Meal").frame(maxWidth: .infinity).fontWeight(.semibold)
                }
            }
        }
        .navigationTitle("Set Amount")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { selectedTemplate = nil }
            }
        }
        .onAppear { gramsText = "\(template.defaultServingG)" }
    }

    @ViewBuilder
    private func savedMealServingsView(meal: SavedMeal) -> some View {
        let servings = max(0.1, Double(servingsText.replacingOccurrences(of: ",", with: ".")) ?? 1)
        let ingredient = SavedMealIngredient(meal: meal, servings: servings)
        let m = NutritionLogic.macros(for: ingredient)
        Form {
            Section(meal.name) {
                HStack {
                    TextField("1", text: $servingsText)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                    Text("serving\(servings == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Stepper("", onIncrement: { adjustServings(by: 0.5) }, onDecrement: { adjustServings(by: -0.5) })
                        .labelsHidden()
                }
                Button("Reset to 1 serving") { servingsText = "1" }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Macros") {
                MacroResultRow(label: "Calories", value: "\(m.kcal) kcal", color: .primary)
                MacroResultRow(label: "Protein",  value: "\(String(format: "%.1f", m.protein))g", color: .blue)
                MacroResultRow(label: "Carbs",    value: "\(String(format: "%.1f", m.carbs))g", color: .cyan)
                MacroResultRow(label: "Fat",      value: "\(String(format: "%.1f", m.fat))g", color: .yellow)
                if m.fiber > 0 { MacroResultRow(label: "Fiber", value: "\(String(format: "%.1f", m.fiber))g", color: .green) }
            }
            Section {
                Button {
                    onSelected(SavedMealIngredient(meal: meal, servings: servings))
                    dismiss()
                } label: {
                    Text("Add to Meal").frame(maxWidth: .infinity).fontWeight(.semibold)
                }
            }
        }
        .navigationTitle("Set Amount")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { selectedSavedMeal = nil }
            }
        }
    }

    private var pickerList: some View {
        List {
            if !savedMeals.isEmpty && searchText.isEmpty {
                Section("Saved Meals") {
                    ForEach(savedMeals) { meal in
                        Button {
                            selectedSavedMeal = meal
                        } label: {
                            SavedMealRow(meal: meal)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            ForEach(grouped, id: \.0) { category, foods in
                Section(category.rawValue) {
                    ForEach(foods) { food in
                        Button {
                            selectedTemplate = food
                        } label: {
                            FoodTemplateRow(food: food)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search foods…")
        .navigationTitle("Pick Ingredient")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .task {
            await FoodStore.shared.setup()
            for category in FoodCategory.allCases {
                let loaded = await FoodStore.shared.foods(in: category, userID: store.profileID)
                browseFoods[category] = loaded
            }
        }
        .task(id: searchText) {
            guard !searchText.isEmpty else { dbSearchResults = []; return }
            dbSearchResults = await FoodStore.shared.search(searchText, userID: store.profileID)
        }
    }

    private func adjustServings(by delta: Double) {
        let current = Double(servingsText.replacingOccurrences(of: ",", with: ".")) ?? 1
        let next = max(0.5, (current + delta * 2).rounded() / 2)
        servingsText = String(format: "%g", next)
    }
}

// MARK: - Copy Meal Sheet

struct CopyMealSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let meal: MealType
    let targetDate: Date

    @State private var sourceDate: Date

    init(meal: MealType, targetDate: Date) {
        self.meal = meal
        self.targetDate = targetDate
        _sourceDate = State(initialValue: Calendar.current.date(byAdding: .day, value: -1, to: targetDate) ?? targetDate)
    }

    private var sourceEntries: [FoodEntry] {
        NutritionLogic.entries(store.logbook.foodLog, on: sourceDate)
            .filter { $0.meal == meal }
            .sorted { $0.date < $1.date }
    }

    private var targetLabel: String {
        if Calendar.current.isDateInToday(targetDate) { return "Today" }
        if Calendar.current.isDateInYesterday(targetDate) { return "Yesterday" }
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        return fmt.string(from: targetDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Copy from") {
                    DatePicker("Date", selection: $sourceDate, in: ...targetDate, displayedComponents: .date)
                }

                if sourceEntries.isEmpty {
                    Section {
                        Text("No \(meal.rawValue) entries on this date.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    Section("\(meal.rawValue) — \(NutritionLogic.totalCalories(sourceEntries)) kcal") {
                        ForEach(sourceEntries) { entry in
                            FoodEntryRow(entry: entry)
                        }
                    }

                    Section {
                        Button {
                            store.copyMeal(meal, from: sourceDate, to: targetDate)
                            dismiss()
                        } label: {
                            Text("Copy \(sourceEntries.count) item\(sourceEntries.count == 1 ? "" : "s") to \(targetLabel)")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .navigationTitle("Copy \(meal.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Targets Editor

struct TargetsEditorView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showingTDEE = false

    @State private var calories: String
    @State private var protein: String
    @State private var fiber: String

    init() {
        _calories = State(initialValue: "")
        _protein = State(initialValue: "")
        _fiber = State(initialValue: "")
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Calories (kcal)") {
                    TextField("2000", text: $calories)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Protein (g)") {
                    TextField("150", text: $protein)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Fiber (g)") {
                    TextField("30", text: $fiber)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Daily Targets")
            } footer: {
                let cal = Int(calories) ?? 2000
                let carbsEst = Int(NutritionLogic.defaultCarbsTarget(calorieTarget: cal))
                Text("Carbs target is auto-calculated (~\(carbsEst)g for \(cal) kcal). Focus on calories, protein, and fiber — carbs and fats will fall into place.")
            }

            Section {
                Button("Use Nutrition Calculator") {
                    showingTDEE = true
                }
            } footer: {
                Text("Calculate your personalised starting targets from your stats and activity level.")
            }

            Section {
                Button("Save Targets") {
                    store.updateTargets(
                        calories: Int(calories) ?? 2000,
                        protein: Double(protein) ?? 150,
                        fiber: Double(fiber) ?? 30
                    )
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .fontWeight(.semibold)
            }
        }
        .navigationTitle("Edit Targets")
        .onAppear {
            calories = "\(store.logbook.calorieTarget)"
            protein = String(format: "%.0f", store.logbook.proteinTarget)
            fiber = String(format: "%.0f", store.logbook.fiberTarget)
        }
        .sheet(isPresented: $showingTDEE) {
            TDEECalculatorView { cal, p, fib in
                calories = "\(cal)"
                protein = String(format: "%.0f", p)
                fiber = String(format: "%.0f", fib)
            }
        }
    }
}
