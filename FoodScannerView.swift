import SwiftUI
import Vision
import VisionKit
import FoundationModels

// MARK: - Shared result

struct ScannedFoodResult {
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
    var servingSize: String
}

// MARK: - Entry point

struct FoodScannerView: View {
    let date: Date
    let onAdded: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var showingBarcode = false
    @State private var showingLabel = false

    private var labelScanAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "viewfinder")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                Text("Scan a barcode or nutrition label\nto quickly log food.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
                VStack(spacing: 12) {
                    ScanOptionButton(
                        title: "Scan Barcode",
                        subtitle: "Packaged foods & products",
                        icon: "barcode.viewfinder",
                        disabled: false
                    ) { showingBarcode = true }

                    ScanOptionButton(
                        title: "Scan Nutrition Label",
                        subtitle: labelScanAvailable ? "Reads label with Apple Intelligence" : "Requires Apple Intelligence",
                        icon: "text.viewfinder",
                        disabled: !labelScanAvailable
                    ) { showingLabel = true }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .navigationTitle("Scan Food")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen("food_scanner")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showingBarcode) {
                BarcodeScannerView(date: date) {
                    dismiss()
                    onAdded()
                }
            }
            .fullScreenCover(isPresented: $showingLabel) {
                LabelScannerView(date: date) {
                    dismiss()
                    onAdded()
                }
            }
        }
    }
}

private struct ScanOptionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 36)
                    .foregroundStyle(disabled ? Color.secondary : Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(disabled ? .secondary : .primary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Barcode scanner

struct BarcodeScannerView: View {
    let date: Date
    let onAdded: () -> Void

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .scanning
    @State private var confirming: ScannedFoodResult? = nil

    enum Phase { case scanning, loading, error(String) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                scannerContent
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black.opacity(0.6), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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

    @ViewBuilder
    private var scannerContent: some View {
        switch phase {
        case .scanning:
            BarcodeDataScannerRepresentable { barcode in
                guard case .scanning = phase else { return }
                phase = .loading
                Task { await fetchProduct(barcode: barcode) }
            }
            .ignoresSafeArea()
            VStack {
                Spacer()
                Text("Point at barcode")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 60)
            }

        case .loading:
            VStack(spacing: 16) {
                ProgressView().tint(.white)
                Text("Looking up product…").foregroundStyle(.white).font(.subheadline)
            }

        case .error(let msg):
            VStack(spacing: 20) {
                Image(systemName: "barcode").font(.system(size: 48)).foregroundStyle(.orange)
                Text(msg)
                    .foregroundStyle(.white)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Scan Again") { phase = .scanning }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func fetchProduct(barcode: String) async {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v0/product/\(barcode).json") else {
            phase = .error("Invalid barcode."); return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(OFFResponse.self, from: data)
            guard decoded.status == 1, let product = decoded.product else {
                phase = .error("Product not found in database.\nTry scanning the nutrition label instead.")
                return
            }
            let n = product.nutriments
            let name = [product.productName, product.productNameEn]
                .compactMap { $0 }.first(where: { !$0.isEmpty }) ?? "Unknown Product"
            confirming = ScannedFoodResult(
                name: name,
                calories: Int(n.energyKcalServing ?? n.energyKcal100g ?? 0),
                protein: n.proteinsServing ?? n.proteins100g ?? 0,
                carbs: n.carbohydratesServing ?? n.carbohydrates100g ?? 0,
                fat: n.fatServing ?? n.fat100g ?? 0,
                fiber: n.fiberServing ?? n.fiber100g ?? 0,
                sugar: n.sugarsServing ?? n.sugars100g ?? 0,
                saturatedFat: n.saturatedFatServing ?? n.saturatedFat100g ?? 0,
                sodium: (n.sodiumServing ?? n.sodium100g ?? 0) * 1000,
                cholesterol: (n.cholesterolServing ?? n.cholesterol100g ?? 0) * 1000,
                servingSize: product.servingSize ?? "1 serving"
            )
        } catch {
            phase = .error("Couldn't fetch product data.\nCheck your connection and try again.")
        }
    }
}

// MARK: - Label scanner (Apple Intelligence)

struct LabelScannerView: View {
    let date: Date
    let onAdded: () -> Void

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var texts: [String] = []
    @State private var isAnalyzing = false
    @State private var errorMessage: String? = nil
    @State private var confirming: ScannedFoodResult? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                LabelDataScannerRepresentable(texts: $texts)
                    .ignoresSafeArea()
                VStack {
                    Spacer()
                    bottomBar
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .principal) {
                    Text("Point at Nutrition Label")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black.opacity(0.6), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            if !texts.isEmpty {
                Text("\(texts.count) text region\(texts.count == 1 ? "" : "s") detected")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Button {
                errorMessage = nil
                Task { await analyze() }
            } label: {
                Group {
                    if isAnalyzing {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text("Analyzing with Apple Intelligence…")
                        }
                    } else {
                        Text("Extract Nutrition Facts")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(texts.isEmpty || isAnalyzing)
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 20)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    private func analyze() async {
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let session = LanguageModelSession(
                instructions: Instructions(
                    "You are a nutrition label parser. Extract nutrition facts from raw OCR text of a food label. Use per-serving values, not per-100g. Return 0 for any missing numeric field."
                )
            )
            let response = try await session.respond(
                to: Prompt(texts.joined(separator: "\n")),
                generating: ExtractedNutrition.self
            )
            let extracted = response.content
            confirming = ScannedFoodResult(
                name: extracted.name.isEmpty ? "Scanned Food" : extracted.name,
                calories: extracted.calories,
                protein: extracted.proteinGrams,
                carbs: extracted.carbsGrams,
                fat: extracted.fatGrams,
                fiber: extracted.fiberGrams,
                sugar: extracted.sugarGrams,
                saturatedFat: extracted.saturatedFatGrams,
                sodium: extracted.sodiumMg,
                cholesterol: extracted.cholesterolMg,
                servingSize: extracted.servingSize.isEmpty ? "1 serving" : extracted.servingSize
            )
        } catch {
            errorMessage = "Could not extract data. Point the camera closer to the label and try again."
        }
    }
}

@Generable
private struct ExtractedNutrition {
    @Guide(description: "Product or food name from the label")
    var name: String
    @Guide(description: "Calories per serving as a whole number")
    var calories: Int
    @Guide(description: "Protein in grams per serving")
    var proteinGrams: Double
    @Guide(description: "Total carbohydrates in grams per serving")
    var carbsGrams: Double
    @Guide(description: "Total fat in grams per serving")
    var fatGrams: Double
    @Guide(description: "Dietary fiber in grams per serving, 0 if not listed")
    var fiberGrams: Double
    @Guide(description: "Total sugars in grams per serving, 0 if not listed")
    var sugarGrams: Double
    @Guide(description: "Saturated fat in grams per serving, 0 if not listed")
    var saturatedFatGrams: Double
    @Guide(description: "Sodium in milligrams per serving, 0 if not listed")
    var sodiumMg: Double
    @Guide(description: "Cholesterol in milligrams per serving, 0 if not listed")
    var cholesterolMg: Double
    @Guide(description: "Serving size description such as 30g or 1 cup")
    var servingSize: String
}

// MARK: - Confirm view

struct ScannedFoodConfirmView: View {
    @State var result: ScannedFoodResult
    @State private var servings: Double = 1
    let date: Date
    let onAdd: (FoodEntry) -> Void

    private var scaledCalories: Int { Int((Double(result.calories) * servings).rounded()) }
    private var scaledProtein: Double { (result.protein * servings * 10).rounded() / 10 }
    private var scaledCarbs: Double { (result.carbs * servings * 10).rounded() / 10 }
    private var scaledFat: Double { (result.fat * servings * 10).rounded() / 10 }
    private var scaledFiber: Double { (result.fiber * servings * 10).rounded() / 10 }
    private var scaledSugar: Double { (result.sugar * servings * 10).rounded() / 10 }
    private var scaledSaturatedFat: Double { (result.saturatedFat * servings * 10).rounded() / 10 }
    private var scaledSodium: Double { (result.sodium * servings).rounded() }
    private var scaledCholesterol: Double { (result.cholesterol * servings).rounded() }

    private var entryBaseName: String {
        result.name.isEmpty ? "Scanned Food" : result.name
    }

    private var entryName: String {
        servings == 1 ? entryBaseName : "\(entryBaseName) (\(formatted(servings))×)"
    }

    private func formatted(_ n: Double) -> String {
        n == n.rounded() ? "\(Int(n))" : String(format: "%.1f", n)
    }

    var body: some View {
        Form {
            Section("Product") {
                TextField("Name", text: $result.name)
                LabeledContent("Serving size") {
                    TextField("e.g. 30g", text: $result.servingSize)
                        .multilineTextAlignment(.trailing)
                }
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
                numericRow("Calories", value: $result.calories)
                decimalRow("Protein (g)", value: $result.protein)
                decimalRow("Carbs (g)", value: $result.carbs)
                decimalRow("Fat (g)", value: $result.fat)
            }
            Section("Details per serving") {
                decimalRow("Fiber (g)", value: $result.fiber)
                decimalRow("Sugar (g)", value: $result.sugar)
                decimalRow("Saturated Fat (g)", value: $result.saturatedFat)
                decimalRow("Sodium (mg)", value: $result.sodium)
                decimalRow("Cholesterol (mg)", value: $result.cholesterol)
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
                Button {
                    onAdd(FoodEntry(
                        name: entryName,
                        calories: scaledCalories,
                        protein: scaledProtein,
                        carbs: scaledCarbs,
                        fat: scaledFat,
                        fiber: scaledFiber,
                        sugar: scaledSugar,
                        saturatedFat: scaledSaturatedFat,
                        sodium: scaledSodium,
                        cholesterol: scaledCholesterol,
                        date: date
                    ))
                } label: {
                    Text(servings == 1 ? "Add to Log" : "Add to Log — \(scaledCalories) kcal")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
            }
        }
        .navigationTitle("Confirm")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func numericRow(_ label: String, value: Binding<Int>) -> some View {
        LabeledContent(label) {
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func decimalRow(_ label: String, value: Binding<Double>) -> some View {
        LabeledContent(label) {
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - UIKit scanner wrappers

private struct BarcodeDataScannerRepresentable: UIViewControllerRepresentable {
    let onBarcode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onBarcode: onBarcode) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .code39])],
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        context.coordinator.onBarcode = onBarcode
        if !vc.isScanning { try? vc.startScanning() }
    }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onBarcode: (String) -> Void
        init(onBarcode: @escaping (String) -> Void) { self.onBarcode = onBarcode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard let payload = addedItems.lazy.compactMap({
                if case .barcode(let b) = $0 { return b.payloadStringValue } else { return nil }
            }).first else { return }
            DispatchQueue.main.async { self.onBarcode(payload) }
        }
    }
}

private struct LabelDataScannerRepresentable: UIViewControllerRepresentable {
    @Binding var texts: [String]

    func makeCoordinator() -> Coordinator { Coordinator(texts: $texts) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
    }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        @Binding var texts: [String]
        init(texts: Binding<[String]>) { self._texts = texts }

        func dataScanner(_ scanner: DataScannerViewController, didAdd: [RecognizedItem], allItems: [RecognizedItem]) {
            syncTexts(from: allItems)
        }
        func dataScanner(_ scanner: DataScannerViewController, didUpdate: [RecognizedItem], allItems: [RecognizedItem]) {
            syncTexts(from: allItems)
        }
        func dataScanner(_ scanner: DataScannerViewController, didRemove: [RecognizedItem], allItems: [RecognizedItem]) {
            syncTexts(from: allItems)
        }

        private func syncTexts(from items: [RecognizedItem]) {
            let latest = items.compactMap { item -> String? in
                guard case .text(let t) = item else { return nil }
                return t.transcript
            }
            DispatchQueue.main.async { self.texts = latest }
        }
    }
}

// MARK: - OpenFoodFacts models

private struct OFFResponse: Decodable {
    let status: Int
    let product: OFFProduct?
}

private struct OFFProduct: Decodable {
    let productName: String?
    let productNameEn: String?
    let servingSize: String?
    let nutriments: OFFNutriments
    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case productNameEn = "product_name_en"
        case servingSize = "serving_size"
        case nutriments
    }
}

private struct OFFNutriments: Decodable {
    let energyKcal100g: Double?
    let energyKcalServing: Double?
    let proteins100g: Double?
    let proteinsServing: Double?
    let carbohydrates100g: Double?
    let carbohydratesServing: Double?
    let fat100g: Double?
    let fatServing: Double?
    let fiber100g: Double?
    let fiberServing: Double?
    let sugars100g: Double?
    let sugarsServing: Double?
    let saturatedFat100g: Double?
    let saturatedFatServing: Double?
    // OFF stores sodium and cholesterol in grams; multiply by 1000 at call site for mg
    let sodium100g: Double?
    let sodiumServing: Double?
    let cholesterol100g: Double?
    let cholesterolServing: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case energyKcalServing = "energy-kcal_serving"
        case proteins100g = "proteins_100g"
        case proteinsServing = "proteins_serving"
        case carbohydrates100g = "carbohydrates_100g"
        case carbohydratesServing = "carbohydrates_serving"
        case fat100g = "fat_100g"
        case fatServing = "fat_serving"
        case fiber100g = "fiber_100g"
        case fiberServing = "fiber_serving"
        case sugars100g = "sugars_100g"
        case sugarsServing = "sugars_serving"
        case saturatedFat100g = "saturated-fat_100g"
        case saturatedFatServing = "saturated-fat_serving"
        case sodium100g = "sodium_100g"
        case sodiumServing = "sodium_serving"
        case cholesterol100g = "cholesterol_100g"
        case cholesterolServing = "cholesterol_serving"
    }
}
