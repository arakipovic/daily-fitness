import SwiftUI
import FoundationModels

// MARK: - Structured extraction schema

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

// MARK: - View

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

    // Totals for one serving
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

    // MARK: - Input

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

    // MARK: - Result

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

    // MARK: - Logic

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
