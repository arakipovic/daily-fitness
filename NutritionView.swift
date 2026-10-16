import SwiftUI
import FoundationModels

struct NutritionView: View {
    @Environment(Store.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(GlobalActions.self) private var global

    @State private var selectedDate: Date = Date()
    @State private var showingAddFood = false
    @State private var showingScanner = false
    @State private var showingNLEntry = false
    @State private var showingRecipeImport = false
    @State private var addDefaultMeal: MealType = .breakfast
    @State private var editingEntry: FoodEntry? = nil
    @State private var editingMealEntry: FoodEntry? = nil
    @State private var editingEntryGroup: MealEntryGroup? = nil
    @State private var copyingMeal: MealType? = nil
    @State private var dbFoodCount = 0
    @State private var historicalActiveCalories: Double = 0

    // Cached day-level entries — recomputed only when date or food log count changes,
    // not on every Store mutation (e.g. session saves, weight updates).
    @State private var dayEntries: [FoodEntry] = []
    @State private var grouped: [MealType: [FoodEntry]] = [:]
    @State private var sortedGrouped: [MealType: [FoodEntry]] = [:]
    @State private var totalCalories: Int = 0
    @State private var totalProtein: Double = 0
    @State private var totalCarbs: Double = 0
    @State private var totalFiber: Double = 0

    private var aiAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    private var activeCaloriesEarned: Int {
        // 30% discount applied — wearable calorie counts are systematically high
        let raw = isToday ? healthKit.activeEnergyToday : historicalActiveCalories
        return max(0, Int(raw * 0.7))
    }

    private var calorieBudget: Int {
        NutritionLogic.calorieBudget(target: store.logbook.calorieTarget, activeCalories: activeCaloriesEarned)
    }

    private var carbsTarget: Double {
        NutritionLogic.defaultCarbsTarget(calorieTarget: store.logbook.calorieTarget)
    }

    private var dayKey: String { "\(selectedDate.timeIntervalSince1970)-\(store.logbook.foodLog.count)" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 0) {
                        Button {
                            selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                        } label: {
                            Image(systemName: "chevron.left").frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)

                        DatePicker("", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.compact).labelsHidden().frame(maxWidth: .infinity)

                        Button {
                            selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                        } label: {
                            Image(systemName: "chevron.right").frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }

                Section("Progress") {
                    MacroProgressBar(
                        label: activeCaloriesEarned > 0 ? "Calories (+\(activeCaloriesEarned) active, adj.)" : "Calories",
                        current: Double(totalCalories),
                        target: Double(calorieBudget),
                        unit: "kcal",
                        color: .orange
                    )
                    MacroProgressBar(label: "Protein", current: totalProtein, target: store.logbook.proteinTarget, unit: "g", color: .blue)
                    MacroProgressBar(label: "Carbs", current: totalCarbs, target: carbsTarget, unit: "g", color: .cyan)
                    MacroProgressBar(label: "Fiber", current: totalFiber, target: store.logbook.fiberTarget, unit: "g", color: .green)
                    NavigationLink { TargetsEditorView() } label: {
                        Label("Edit Daily Targets", systemImage: "slider.horizontal.3")
                    }
                }

                ForEach(MealType.allCases) { meal in
                    mealSection(meal: meal)
                }

                Section {
                    NavigationLink {
                        FoodDatabaseBrowserView(defaultDate: selectedDate, defaultMeal: addDefaultMeal)
                    } label: {
                        Label("Food Database (\(dbFoodCount) foods)", systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink { RecipesView(logDate: selectedDate) } label: {
                        Label("Recipes", systemImage: "fork.knife.circle")
                    }
                    NavigationLink { NutritionGuideView() } label: {
                        Label("Nutrition Guide", systemImage: "book.pages")
                    }
                    NavigationLink { MacroCalculatorView() } label: {
                        Label("Meal Macro Calculator", systemImage: "scalemass")
                    }
                    NavigationLink { AlcoholCalculatorView() } label: {
                        Label("Alcohol Macro Adjuster", systemImage: "wineglass")
                    }
                } header: {
                    Label("Tools", systemImage: "wrench.and.screwdriver")
                }
            }
            .task {
                await FoodStore.shared.setup()
                dbFoodCount = await FoodStore.shared.count
            }
            .task(id: dayKey) {
                let entries = NutritionLogic.entries(store.logbook.foodLog, on: selectedDate)
                let g = NutritionLogic.groupedByMeal(entries)
                var sg: [MealType: [FoodEntry]] = [:]
                for meal in MealType.allCases {
                    sg[meal] = (g[meal] ?? []).sorted { $0.date < $1.date }
                }
                dayEntries = entries
                grouped = g
                sortedGrouped = sg
                totalCalories = NutritionLogic.totalCalories(entries)
                totalProtein = NutritionLogic.totalProtein(entries)
                totalCarbs = NutritionLogic.totalCarbs(entries)
                totalFiber = NutritionLogic.totalFiber(entries)
                guard !Calendar.current.isDateInToday(selectedDate) else {
                    historicalActiveCalories = 0; return
                }
                let calories = await healthKit.activeEnergy(on: selectedDate)
                guard !Task.isCancelled else { return }
                historicalActiveCalories = calories
            }
            .navigationTitle("Nutrition")
            .trackScreen("nutrition")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button { showingScanner = true } label: {
                            Label("Scan Food", systemImage: "barcode.viewfinder")
                        }
                        if aiAvailable {
                            Button { showingNLEntry = true } label: {
                                Label("Describe What You Ate", systemImage: "text.bubble")
                            }
                            Button { showingRecipeImport = true } label: {
                                Label("Import Recipe", systemImage: "list.bullet.clipboard")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button { global.showingHistory = true } label: {
                        Image(systemName: "chart.bar.xaxis")
                    }
                    Button { global.showingSettings = true } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingAddFood) {
                AddFoodView(defaultDate: selectedDate, defaultMeal: addDefaultMeal)
            }
            .sheet(isPresented: $showingScanner) {
                FoodScannerView(date: selectedDate) { showingScanner = false }
            }
            .sheet(isPresented: $showingNLEntry) {
                NLFoodEntryView(date: selectedDate) { showingNLEntry = false }
            }
            .sheet(isPresented: $showingRecipeImport) {
                RecipeImportView(date: selectedDate, meal: addDefaultMeal) { showingRecipeImport = false }
            }
            .sheet(item: $editingEntry) { entry in
                FoodEntryEditView(entry: entry)
            }
            .sheet(item: $editingMealEntry) { entry in
                if let mealID = entry.savedMealID,
                   let savedMeal = store.logbook.savedMeals.first(where: { $0.id == mealID }) {
                    MealBuilderView(
                        date: entry.date,
                        existingMeal: savedMeal,
                        defaultMeal: entry.meal,
                        replacingEntries: [entry],
                        onAdded: {}
                    )
                }
            }
            .sheet(item: $copyingMeal) { meal in
                CopyMealSheet(meal: meal, targetDate: selectedDate)
            }
            .sheet(item: $editingEntryGroup) { group in
                SeparatelyLoggedMealEditView(group: group)
            }
        }
    }

    private func partitionEntries(_ entries: [FoodEntry]) -> (singles: [FoodEntry], groups: [MealEntryGroup]) {
        let byBase = Dictionary(grouping: entries, by: { NutritionLogic.separatelyLoggedMealName($0.name) })
        let singles = byBase[nil] ?? []
        let namedGroups = byBase.filter { $0.key != nil }
        let groups = namedGroups
            .compactMap { key, grpEntries -> MealEntryGroup? in
                guard let name = key, grpEntries.count >= 2 else { return nil }
                return MealEntryGroup(name: name, entries: grpEntries)
            }
            .sorted { $0.name < $1.name }
        let orphans = namedGroups.values.filter { $0.count < 2 }.flatMap { $0 }
        let allSingles = (singles + orphans).sorted { $0.date < $1.date }
        return (allSingles, groups)
    }

    @ViewBuilder
    private func mealSection(meal: MealType) -> some View {
        let entries = sortedGrouped[meal] ?? []
        let mealCalories = NutritionLogic.totalCalories(entries)

        let (allSingles, entryGroups) = partitionEntries(entries)

        Section {
            ForEach(allSingles) { entry in
                FoodEntryRow(entry: entry)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let mealID = entry.savedMealID,
                           store.logbook.savedMeals.contains(where: { $0.id == mealID }) {
                            editingMealEntry = entry
                        } else {
                            editingEntry = entry
                        }
                    }
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
                store.deleteFoodEntries(at: offsets, from: allSingles)
            }
            ForEach(entryGroups) { group in
                MealGroupRow(name: group.name, entries: group.entries)
                    .contentShape(Rectangle())
                    .onTapGesture { editingEntryGroup = group }
            }
            .onDelete { offsets in
                offsets.map { entryGroups[$0] }.forEach { group in
                    group.entries.forEach { store.deleteFoodEntry(id: $0.id) }
                }
            }
            Button {
                addDefaultMeal = meal
                showingAddFood = true
            } label: {
                Label("Add to \(meal.rawValue)", systemImage: "plus.circle")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: meal.icon).foregroundStyle(.secondary)
                Text(meal.rawValue).textCase(nil).font(.subheadline.weight(.semibold))
                Spacer()
                if mealCalories > 0 {
                    Text("\(mealCalories) kcal").font(.caption).foregroundStyle(.secondary).textCase(nil)
                }
                Menu {
                    Button {
                        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                        // Defer past menu dismissal to avoid UIContextMenuInteraction warning
                        // and premature cancellation of the dayKey task.
                        Task { @MainActor in
                            store.copyMeal(meal, from: yesterday, to: selectedDate)
                        }
                    } label: {
                        Label("Copy from Yesterday", systemImage: "doc.on.doc")
                    }
                    Button { copyingMeal = meal } label: {
                        Label("Choose Another Date…", systemImage: "calendar")
                    }
                } label: {
                    Image(systemName: "doc.on.doc").font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(.blue).textCase(nil)
            }
        }
    }
}

// MARK: - Food Database Browser

struct FoodDatabaseBrowserView: View {
    @Environment(Store.self) private var store

    var defaultDate: Date = Date()
    var defaultMeal: MealType = MealType.guess(from: Date())
    var onAdded: (() -> Void)? = nil

    @State private var searchText = ""
    @State private var browseFoods: [FoodCategory: [FoodTemplate]] = [:]
    @State private var dbSearchResults: [FoodTemplate] = []
    @State private var showingCreateCustomFood = false
    @State private var browseRefreshID = 0

    private var grouped: [(FoodCategory, [FoodTemplate])] {
        let source: [FoodTemplate] = searchText.isEmpty
            ? FoodCategory.allCases.flatMap { browseFoods[$0] ?? [] }
            : dbSearchResults
        return FoodCategory.allCases.compactMap { category in
            let foods = source.filter { $0.category == category }
            return foods.isEmpty ? nil : (category, foods)
        }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.0) { category, foods in
                Section(category.rawValue) {
                    ForEach(foods) { food in
                        NavigationLink {
                            FoodAmountView(food: food, date: defaultDate, defaultMeal: defaultMeal) {
                                onAdded?()
                            }
                        } label: {
                            FoodDatabaseFoodRow(food: food)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search foods...")
        .navigationTitle("Food Database")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreateCustomFood = true
                } label: {
                    Label("New Custom Food", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateCustomFood) {
            CreateCustomFoodView {
                browseRefreshID += 1
            }
        }
        .task(id: browseRefreshID) {
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
}

// MARK: - Meal Entry Group (separately-logged entries collapsed into one row)

struct MealEntryGroup: Identifiable {
    var id: String { name }
    let name: String
    let entries: [FoodEntry]
}

struct MealGroupRow: View {
    let name: String
    let entries: [FoodEntry]

    private var totalKcal: Int    { entries.reduce(0) { $0 + $1.calories } }
    private var totalProtein: Double { entries.reduce(0.0) { $0 + $1.protein } }
    private var totalCarbs: Double   { entries.reduce(0.0) { $0 + $1.carbs } }
    private var totalFat: Double     { entries.reduce(0.0) { $0 + $1.fat } }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(totalKcal) kcal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("\(entries.count) ingredients")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("P \(String(format: "%.0f", totalProtein))g · C \(String(format: "%.0f", totalCarbs))g · F \(String(format: "%.0f", totalFat))g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Separately Logged Meal Edit View

struct SeparatelyLoggedMealEditView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let group: MealEntryGroup
    @State private var showingMealBuilder = false
    @State private var entries: [FoodEntry] = []

    private var totalKcal: Int       { entries.reduce(0) { $0 + $1.calories } }
    private var totalProtein: Double { entries.reduce(0.0) { $0 + $1.protein } }
    private var totalCarbs: Double   { entries.reduce(0.0) { $0 + $1.carbs } }
    private var totalFat: Double     { entries.reduce(0.0) { $0 + $1.fat } }
    private var totalFiber: Double   { entries.reduce(0.0) { $0 + $1.fiber } }
    private var totalSugar: Double   { entries.reduce(0.0) { $0 + $1.sugar } }
    private var totalSatFat: Double  { entries.reduce(0.0) { $0 + $1.saturatedFat } }
    private var totalSodium: Double  { entries.reduce(0.0) { $0 + $1.sodium } }
    private var totalChol: Double    { entries.reduce(0.0) { $0 + $1.cholesterol } }

    private var matchingSavedMeal: SavedMeal? {
        store.logbook.savedMeals.first { $0.name == group.name }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Combined Macros") {
                    LabeledContent("Calories",  value: "\(totalKcal) kcal")
                    LabeledContent("Protein",   value: "\(String(format: "%.1f", totalProtein))g")
                    LabeledContent("Carbs",     value: "\(String(format: "%.1f", totalCarbs))g")
                    LabeledContent("Fat",       value: "\(String(format: "%.1f", totalFat))g")
                    if totalFiber > 0 {
                        LabeledContent("Fiber", value: "\(String(format: "%.1f", totalFiber))g")
                    }
                }

                Section("Ingredients (\(entries.count))") {
                    ForEach(entries) { entry in
                        ingredientRow(for: entry)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { entries[$0].id }
                        ids.forEach { store.deleteFoodEntry(id: $0) }
                        entries.remove(atOffsets: offsets)
                        if entries.isEmpty { dismiss() }
                    }
                }

                Section {
                    Button("Merge into one entry") { merge() }

                    if matchingSavedMeal != nil {
                        Button("Edit ingredients") { showingMealBuilder = true }
                    }

                    Button("Delete all", role: .destructive) {
                        entries.forEach { store.deleteFoodEntry(id: $0.id) }
                        dismiss()
                    }
                }
            }
            .navigationTitle(group.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingMealBuilder) {
                if let meal = matchingSavedMeal {
                    MealBuilderView(
                        date: entries.first?.date ?? Date(),
                        existingMeal: meal,
                        defaultMeal: entries.first?.meal ?? .breakfast,
                        replacingEntries: entries,
                        onAdded: { dismiss() }
                    )
                }
            }
        }
        .onAppear { entries = group.entries }
    }

    @ViewBuilder
    private func ingredientRow(for entry: FoodEntry) -> some View {
        let label = ingredientLabel(entry.name)
        let grams = NutritionLogic.gramsFromEntryName(entry.name)
        let displayName = grams != nil ? ingredientBaseName(label) : label
        let step = stepSize(for: grams ?? 0)

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.subheadline)
                HStack(spacing: 6) {
                    Text("\(entry.calories) kcal")
                    Text("·").foregroundStyle(.tertiary)
                    Text("P \(String(format: "%.0f", entry.protein))g").foregroundStyle(.blue)
                    Text("·").foregroundStyle(.tertiary)
                    Text("C \(String(format: "%.0f", entry.carbs))g").foregroundStyle(.cyan)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let g = grams {
                HStack(spacing: 2) {
                    Button {
                        adjustGrams(entryID: entry.id, delta: -step)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Text("\(Int(g.rounded()))g")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .frame(minWidth: 40)
                        .multilineTextAlignment(.center)

                    Button {
                        adjustGrams(entryID: entry.id, delta: step)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func ingredientLabel(_ name: String) -> String {
        guard let range = name.range(of: " · ") else { return name }
        return String(name[range.upperBound...])
    }

    private func ingredientBaseName(_ label: String) -> String {
        guard label.hasSuffix("g)"),
              let parenIdx = label.lastIndex(of: "(") else { return label }
        return String(label[label.startIndex..<parenIdx]).trimmingCharacters(in: .whitespaces)
    }

    private func stepSize(for grams: Double) -> Int {
        switch Int(grams) {
        case ..<20:   return 1
        case 20..<100: return 5
        default:      return 10
        }
    }

    private func adjustGrams(entryID: UUID, delta: Int) {
        guard let idx = entries.firstIndex(where: { $0.id == entryID }) else { return }
        var entry = entries[idx]
        guard let currentGrams = NutritionLogic.gramsFromEntryName(entry.name),
              currentGrams > 0 else { return }
        let newGrams = max(1.0, currentGrams + Double(delta))
        let scale = newGrams / currentGrams

        let oldTag = "(\(Int(currentGrams.rounded()))g)"
        let newTag = "(\(Int(newGrams.rounded()))g)"
        if entry.name.hasSuffix(oldTag) {
            entry.name = String(entry.name.dropLast(oldTag.count)) + newTag
        }
        entry.calories = max(0, Int((Double(entry.calories) * scale).rounded()))
        entry.protein = max(0, (entry.protein * scale * 10).rounded() / 10)
        entry.carbs = max(0, (entry.carbs * scale * 10).rounded() / 10)
        entry.fat = max(0, (entry.fat * scale * 10).rounded() / 10)
        entry.fiber = max(0, (entry.fiber * scale * 10).rounded() / 10)
        entry.sugar = max(0, (entry.sugar * scale * 10).rounded() / 10)
        entry.saturatedFat = max(0, (entry.saturatedFat * scale * 10).rounded() / 10)
        entry.sodium = max(0, (entry.sodium * scale).rounded())
        entry.cholesterol = max(0, (entry.cholesterol * scale).rounded())

        entries[idx] = entry
        store.updateFoodEntry(entry)
    }

    private func merge() {
        let date = entries.first?.date ?? Date()
        let meal = entries.first?.meal ?? .breakfast
        entries.forEach { store.deleteFoodEntry(id: $0.id) }
        store.addFoodEntry(FoodEntry(
            name: group.name,
            calories: totalKcal,
            protein: totalProtein,
            carbs: totalCarbs,
            fat: totalFat,
            fiber: totalFiber,
            sugar: totalSugar,
            saturatedFat: totalSatFat,
            sodium: totalSodium,
            cholesterol: totalChol,
            date: date,
            meal: meal,
            savedMealID: matchingSavedMeal?.id
        ))
        dismiss()
    }
}

// MARK: - Create Custom Food

struct CreateCustomFoodView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var onCreated: () -> Void

    @State private var name = ""
    @State private var category: FoodCategory = .meals
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var fiber = ""
    @State private var servingG = "100"
    @State private var servingLabel = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (Int(kcal) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name (e.g. Greek Yogurt – Full Fat)", text: $name)
                    Picker("Category", selection: $category) {
                        ForEach(FoodCategory.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                }
                Section {
                    LabeledContent("Calories (kcal)") {
                        TextField("0", text: $kcal)
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
                } header: {
                    Text("Macros per 100g")
                }
                Section("Serving") {
                    LabeledContent("Size (g)") {
                        TextField("100", text: $servingG)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Label") {
                        TextField("e.g. 1 cup, 1 medium", text: $servingLabel)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("New Custom Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        let label = servingLabel.trimmingCharacters(in: .whitespaces)
        let template = FoodTemplate(
            name: name.trimmingCharacters(in: .whitespaces),
            category: category,
            kcal: Double(kcal) ?? 0,
            protein: Double(protein.replacingOccurrences(of: ",", with: ".")) ?? 0,
            carbs: Double(carbs.replacingOccurrences(of: ",", with: ".")) ?? 0,
            fat: Double(fat.replacingOccurrences(of: ",", with: ".")) ?? 0,
            fiber: Double(fiber.replacingOccurrences(of: ",", with: ".")) ?? 0,
            defaultServingG: Int(servingG) ?? 100,
            servingLabel: label.isEmpty ? nil : label,
            isCustom: true,
            customFoodID: UUID()
        )
        let profileID = store.profileID
        Task { await FoodStore.shared.insertCustomFood(template, userID: profileID) }
        onCreated()
        dismiss()
    }
}

private struct FoodDatabaseFoodRow: View {
    let food: FoodTemplate

    private var macros: (
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
            HStack(spacing: 8) {
                Text(food.defaultServingSummary)
                Text("\(macros.kcal) kcal")
                Text("P \(String(format: "%.0f", macros.p))g")
                if macros.fiber > 0 {
                    Text("Fiber \(String(format: "%.1f", macros.fiber))g")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Macro Calculator

struct MacroCalculatorView: View {
    @State private var protein: String = "150"
    @State private var carbs: String = "200"
    @State private var fat: String = "50"
    @State private var meals: String = "3"

    var proteinNum: Double { Double(protein) ?? 0 }
    var carbsNum: Double { Double(carbs) ?? 0 }
    var fatNum: Double { Double(fat) ?? 0 }
    var mealsNum: Int { max(1, Int(meals) ?? 3) }

    var totalCalories: Double { proteinNum * 4 + carbsNum * 4 + fatNum * 9 }
    var perMealProtein: Double { proteinNum / Double(mealsNum) }
    var perMealCarbs: Double { carbsNum / Double(mealsNum) }
    var perMealFat: Double { fatNum / Double(mealsNum) }
    var perMealCalories: Double { totalCalories / Double(mealsNum) }

    var leanProteinPerMeal: Double { perMealProtein * 4 }
    var ricePerMeal: Double { perMealCarbs / 0.78 }
    var potatoPerMeal: Double { perMealCarbs / 0.15 }
    var oilPerMeal: Double { perMealFat }

    var body: some View {
        Form {
            Section("Your Daily Targets") {
                LabeledContent("Protein (g)") {
                    TextField("150", text: $protein)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Carbs (g)") {
                    TextField("200", text: $carbs)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Fat (g)") {
                    TextField("50", text: $fat)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Meals per day") {
                    TextField("3", text: $meals)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Daily Total") {
                MacroRow(label: "Calories", value: String(format: "%.0f kcal", totalCalories))
                MacroRow(label: "Protein", value: String(format: "%.0f g", proteinNum))
                MacroRow(label: "Carbs", value: String(format: "%.0f g", carbsNum))
                MacroRow(label: "Fat", value: String(format: "%.0f g", fatNum))
            }

            Section("Per Meal (\(mealsNum) meals)") {
                MacroRow(label: "Calories", value: String(format: "%.0f kcal", perMealCalories))
                MacroRow(label: "Protein", value: String(format: "%.0f g", perMealProtein))
                MacroRow(label: "Carbs", value: String(format: "%.0f g", perMealCarbs))
                MacroRow(label: "Fat", value: String(format: "%.0f g", perMealFat))
            }

            Section("Food Amounts Per Meal (rough guide)") {
                MacroRow(label: "Lean protein (raw)", value: String(format: "%.0f g", leanProteinPerMeal))
                MacroRow(label: "Rice, uncooked", value: String(format: "%.0f g", ricePerMeal))
                MacroRow(label: "Potatoes, raw", value: String(format: "%.0f g", potatoPerMeal))
                MacroRow(label: "Healthy oil", value: String(format: "%.0f g", oilPerMeal))
                Text("These are estimates. Use your calorie app for accuracy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Macro Calculator")
    }
}

// MARK: - Alcohol Calculator

enum AlcoholSwapMode: String, CaseIterable, Identifiable {
    case carbs = "All Carbs"
    case fats = "All Fats"
    case mixed = "50/50 Mix"
    var id: String { rawValue }
}

enum DrinkType: String, CaseIterable, Identifiable {
    case regularBeer = "Beer (regular)"
    case lightBeer = "Beer (light)"
    case wine = "Wine (red/white)"
    case spirits = "Spirits (1 shot)"
    case cocktail = "Cocktail (mixed)"

    var id: String { rawValue }

    var kcalPerServing: Double {
        switch self {
        case .regularBeer: return 153
        case .lightBeer: return 103
        case .wine: return 123
        case .spirits: return 97
        case .cocktail: return 200
        }
    }
}

struct AlcoholCalculatorView: View {
    @State private var protein: String = "150"
    @State private var carbs: String = "200"
    @State private var fat: String = "65"
    @State private var drink1: DrinkType = .regularBeer
    @State private var drinks1Count: String = "2"
    @State private var drink2: DrinkType = .wine
    @State private var drinks2Count: String = "0"
    @State private var swapMode: AlcoholSwapMode = .mixed

    var totalAlcoholKcal: Double {
        (Double(drinks1Count) ?? 0) * drink1.kcalPerServing +
        (Double(drinks2Count) ?? 0) * drink2.kcalPerServing
    }

    var proteinNum: Double { Double(protein) ?? 0 }
    var carbsNum: Double { Double(carbs) ?? 0 }
    var fatNum: Double { Double(fat) ?? 0 }

    var adjustedCarbs: Double {
        switch swapMode {
        case .carbs: return max(0, carbsNum - totalAlcoholKcal / 4)
        case .fats: return carbsNum
        case .mixed: return max(0, carbsNum - (totalAlcoholKcal * 0.5) / 4)
        }
    }

    var adjustedFat: Double {
        switch swapMode {
        case .carbs: return fatNum
        case .fats: return max(0, fatNum - totalAlcoholKcal / 9)
        case .mixed: return max(0, fatNum - (totalAlcoholKcal * 0.5) / 9)
        }
    }

    var adjustedCalories: Double {
        proteinNum * 4 + adjustedCarbs * 4 + adjustedFat * 9
    }

    var body: some View {
        Form {
            Section("Your Current Macros") {
                LabeledContent("Protein (g)") {
                    TextField("150", text: $protein)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Carbs (g)") {
                    TextField("200", text: $carbs)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Fat (g)") {
                    TextField("65", text: $fat)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Drinks") {
                Picker("Drink 1", selection: $drink1) {
                    ForEach(DrinkType.allCases) { d in Text(d.rawValue).tag(d) }
                }
                LabeledContent("Quantity") {
                    TextField("0", text: $drinks1Count)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Drink 2", selection: $drink2) {
                    ForEach(DrinkType.allCases) { d in Text(d.rawValue).tag(d) }
                }
                LabeledContent("Quantity") {
                    TextField("0", text: $drinks2Count)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                MacroRow(label: "Alcohol calories", value: String(format: "%.0f kcal", totalAlcoholKcal))
            }

            Section("Swap Strategy") {
                Picker("Swap from", selection: $swapMode) {
                    ForEach(AlcoholSwapMode.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.segmented)
            }

            Section("Adjusted Macros") {
                MacroRow(label: "Calories", value: String(format: "%.0f kcal", adjustedCalories))
                MacroRow(label: "Protein", value: String(format: "%.0f g", proteinNum))
                MacroRow(label: "Carbs", value: String(format: "%.0f g", adjustedCarbs), highlighted: adjustedCarbs < carbsNum)
                MacroRow(label: "Fat", value: String(format: "%.0f g", adjustedFat), highlighted: adjustedFat < fatNum)
            }
        }
        .navigationTitle("Alcohol Calculator")
    }
}

private struct MacroRow: View {
    let label: String
    let value: String
    var highlighted: Bool = false

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .fontWeight(highlighted ? .semibold : .regular)
                .foregroundStyle(highlighted ? .orange : .primary)
        }
    }
}

// MARK: - Recipe Import

@Generable
private struct ParsedIngredient {
    @Guide(description: "Ingredient name, e.g. 'chicken breast', 'olive oil', 'rolled oats'")
    var name: String
    @Guide(description: "Estimated calories for this ingredient at the given quantity")
    var calories: Int
    @Guide(description: "Estimated protein in grams")
    var proteinG: Double
    @Guide(description: "Estimated carbohydrates in grams")
    var carbsG: Double
    @Guide(description: "Estimated fat in grams")
    var fatG: Double
}

@Generable
private struct RecipeExtraction {
    @Guide(description: "Short recipe or dish name")
    var recipeName: String
    @Guide(description: "Number of servings the recipe makes in total. Use 1 if unknown.")
    var totalServings: Int
    @Guide(description: "Each ingredient with its estimated macros for the stated amount")
    var ingredients: [ParsedIngredient]
}

struct RecipeImportView: View {
    let date: Date
    let meal: MealType
    let onAdded: () -> Void

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var recipeText = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var parsed: RecipeExtraction?
    @State private var servings: Double = 1
    @FocusState private var isFocused: Bool

    private var canParse: Bool {
        !recipeText.trimmingCharacters(in: .whitespaces).isEmpty && !isProcessing
    }

    private var totalCalories: Int {
        guard let p = parsed, p.totalServings > 0 else { return 0 }
        let sum = p.ingredients.reduce(0) { $0 + $1.calories }
        return Int((Double(sum) / Double(p.totalServings) * servings).rounded())
    }
    private var totalProtein: Double {
        guard let p = parsed, p.totalServings > 0 else { return 0 }
        let sum = p.ingredients.reduce(0.0) { $0 + $1.proteinG }
        return (sum / Double(p.totalServings) * servings * 10).rounded() / 10
    }
    private var totalCarbs: Double {
        guard let p = parsed, p.totalServings > 0 else { return 0 }
        let sum = p.ingredients.reduce(0.0) { $0 + $1.carbsG }
        return (sum / Double(p.totalServings) * servings * 10).rounded() / 10
    }
    private var totalFat: Double {
        guard let p = parsed, p.totalServings > 0 else { return 0 }
        let sum = p.ingredients.reduce(0.0) { $0 + $1.fatG }
        return (sum / Double(p.totalServings) * servings * 10).rounded() / 10
    }

    var body: some View {
        NavigationStack {
            if let p = parsed {
                resultView(p)
            } else {
                inputView
            }
        }
    }

    private var inputView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "list.bullet.clipboard.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.accentColor)
                            .padding(.top, 32)
                        Text("Paste a Recipe")
                            .font(.title2.weight(.semibold))
                        Text("Paste the ingredients list. The AI will estimate macros for each ingredient and create a meal entry.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        TextField(
                            "e.g.\n200g chicken breast\n1 cup rice\n1 tbsp olive oil\n1 avocado",
                            text: $recipeText,
                            axis: .vertical
                        )
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .lineLimit(8...20)
                        .focused($isFocused)
                        .disabled(isProcessing)

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 20)

                    Button {
                        Task { await parseRecipe() }
                    } label: {
                        Group {
                            if isProcessing {
                                HStack(spacing: 10) {
                                    ProgressView().tint(.white)
                                    Text("Analysing...")
                                }
                            } else {
                                Text("Analyse Recipe")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(canParse ? Color.accentColor : Color.secondary)
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!canParse)
                    .padding(.horizontal, 20)
                    .animation(.easeInOut(duration: 0.15), value: canParse)
                }
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Recipe Import")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear { isFocused = true }
    }

    private func resultView(_ p: RecipeExtraction) -> some View {
        List {
            Section {
                HStack {
                    Text("Servings")
                    Spacer()
                    Stepper(
                        value: $servings, in: 0.5...10, step: 0.5,
                        label: { Text(servings == servings.rounded() ? "\(Int(servings))" : String(format: "%.1f", servings)) }
                    )
                }
            } header: {
                Text(p.recipeName)
                    .font(.headline)
                    .textCase(nil)
            }

            Section("Macros per \(servings == 1 ? "serving" : String(format: "%.1f servings", servings))") {
                LabeledContent("Calories") { Text("\(totalCalories) kcal").foregroundStyle(.secondary) }
                LabeledContent("Protein")  { Text(String(format: "%.1fg", totalProtein)).foregroundStyle(.secondary) }
                LabeledContent("Carbs")    { Text(String(format: "%.1fg", totalCarbs)).foregroundStyle(.secondary) }
                LabeledContent("Fat")      { Text(String(format: "%.1fg", totalFat)).foregroundStyle(.secondary) }
            }

            Section("Ingredients (\(p.totalServings) total serving\(p.totalServings == 1 ? "" : "s"))") {
                ForEach(p.ingredients, id: \.name) { ing in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ing.name).font(.subheadline)
                        Text("\(ing.calories) kcal · \(String(format: "%.0fg", ing.proteinG))p · \(String(format: "%.0fg", ing.carbsG))c · \(String(format: "%.0fg", ing.fatG))f")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Recipe Preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { parsed = nil }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Log Meal") { logMeal(p) }
                    .fontWeight(.semibold)
                    .disabled(totalCalories == 0)
            }
        }
    }

    private func parseRecipe() async {
        let text = recipeText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        do {
            let session = LanguageModelSession(
                instructions: Instructions(
                    "You are a nutrition expert. Parse the recipe or ingredient list provided. For each ingredient estimate realistic macros (calories, protein, carbs, fat) based on the given quantity. If no quantity is stated, assume a typical single serving. Keep ingredient names short and clean."
                )
            )
            let response = try await session.respond(
                to: Prompt(text),
                generating: RecipeExtraction.self
            )
            parsed = response.content
            servings = 1
        } catch {
            errorMessage = "Couldn't parse the recipe. Check your connection and try again."
        }
    }

    private func logMeal(_ p: RecipeExtraction) {
        let name = p.recipeName.isEmpty ? "Recipe" : p.recipeName
        let entry = FoodEntry(
            name: name,
            calories: totalCalories,
            protein: totalProtein,
            carbs: totalCarbs,
            fat: totalFat,
            date: date,
            meal: meal
        )
        store.addFoodEntry(entry)
        onAdded()
        dismiss()
    }
}
