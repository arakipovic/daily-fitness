import SwiftUI
import FoundationModels

// MARK: - Structured extraction schema

@Generable
private struct NLFoodExtraction {
    @Guide(description: "The food name only, e.g. 'banana', 'chicken breast', 'oatmeal'")
    var foodName: String
    @Guide(description: "The numeric quantity as a decimal, e.g. 1.0, 2.0, 0.5, 150.0")
    var quantity: Double
    @Guide(description: "The unit — one of: g, oz, cup, tbsp, tsp, ml, serving, piece, kg. Default to 'serving' when unclear.")
    var unit: String
}

// MARK: - View

struct NLFoodEntryView: View {
    let date: Date
    let onAdded: () -> Void

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var inputText = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var confirming: ScannedFoodResult?
    @FocusState private var isFocused: Bool

    private var canSubmit: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isProcessing
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 10) {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.accentColor)
                    Text("Describe what you ate")
                        .font(.title2.weight(.semibold))
                    Text("Describe what you ate in plain language.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(alignment: .leading, spacing: 6) {
                    TextField("e.g. 2 scrambled eggs, bowl of oatmeal with banana", text: $inputText, axis: .vertical)
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .lineLimit(3)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .disabled(isProcessing)
                        .onSubmit {
                            if canSubmit { Task { await findFood() } }
                        }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 24)

                Button {
                    Task { await findFood() }
                } label: {
                    Group {
                        if isProcessing {
                            HStack(spacing: 10) {
                                ProgressView().tint(.white)
                                Text("Finding...")
                            }
                        } else {
                            Text("Find Food")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(canSubmit ? Color.accentColor : Color.secondary)
                    .foregroundStyle(.white)
                    .fontWeight(.semibold)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canSubmit)
                .padding(.horizontal, 24)
                .animation(.easeInOut(duration: 0.15), value: canSubmit)

                Spacer()
                Spacer()
            }
            .navigationTitle("Log by Description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { isFocused = true }
            .navigationDestination(isPresented: Binding(
                get: { confirming != nil },
                set: { if !$0 { confirming = nil } }
            )) {
                if let result = confirming {
                    ScannedFoodConfirmView(result: result, date: date) { entry in
                        store.addFoodEntry(entry)
                        dismiss()
                        onAdded()
                    }
                }
            }
        }
    }

    // MARK: - Logic

    private func findFood() async {
        let query = inputText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        do {
            let session = LanguageModelSession(
                instructions: Instructions(
                    "Extract the food name, quantity and unit from the user's description of what they ate. Be concise — foodName should be the item only (no quantity words). Default quantity to 1.0 and unit to 'serving' when not specified."
                )
            )
            let response = try await session.respond(
                to: Prompt(query),
                generating: NLFoodExtraction.self
            )
            let extraction = response.content

            guard let resolved = NutritionLogic.resolveNLFood(
                name: extraction.foodName,
                quantity: max(0.1, extraction.quantity),
                unit: extraction.unit
            ) else {
                errorMessage = "\"\(extraction.foodName)\" isn't in the food database. Try scanning a barcode instead."
                return
            }

            let m = resolved.template.macros(forGrams: resolved.grams)
            confirming = ScannedFoodResult(
                name: resolved.template.name,
                calories: m.kcal,
                protein: m.p,
                carbs: m.c,
                fat: m.f,
                fiber: m.fiber,
                sugar: m.sugar,
                saturatedFat: m.saturatedFat,
                sodium: m.sodium,
                cholesterol: m.cholesterol,
                servingSize: resolved.template.amountDescription(forGrams: resolved.grams)
            )
        } catch {
            errorMessage = "Couldn't understand the description. Try again."
        }
    }
}
