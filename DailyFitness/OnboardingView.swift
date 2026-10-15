import SwiftUI

struct OnboardingView: View {
    @Environment(Store.self) private var store
    @State private var selectedProgramID: String = ""
    @State private var startDate: Date = Date()
    @State private var unit: Unit = .kg

    var body: some View {
        NavigationStack {
            Form {
                Section("Select Program") {
                    Picker("Program", selection: $selectedProgramID) {
                        ForEach(store.catalog.programs) { program in
                            Text(program.name).tag(program.id)
                        }
                    }
                }
                Section("Start Date") {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
                Section("Units") {
                    Picker("Units", selection: $unit) {
                        ForEach(Unit.allCases) { u in
                            Text(u.rawValue.uppercased()).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Text("Training 2x/week? Pick the 3-day program and do any two workouts.")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
                Section {
                    Button("Continue") {
                        store.logbook.selectedProgramID = selectedProgramID.isEmpty
                            ? (store.catalog.programs.first?.id ?? "")
                            : selectedProgramID
                        store.logbook.startDate = startDate
                        store.logbook.unit = unit
                        store.saveImmediately()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.catalog.programs.isEmpty)
                }
            }
            .navigationTitle("Get Started")
        }
        .onAppear {
            if selectedProgramID.isEmpty {
                selectedProgramID = store.catalog.programs.first?.id ?? ""
            }
        }
    }
}
