import SwiftUI

@Observable
final class GlobalActions {
    var showingScanner = false
    var showingCustomWorkout = false
    var showingHistory = false
    var showingSettings = false
}

struct ContentView: View {
    @Environment(Store.self) private var store
    @State private var global = GlobalActions()

    var body: some View {
        Group {
            if store.logbook.selectedProgramID.isEmpty {
                OnboardingView()
            } else {
                TabView {
                    HealthView()
                        .tabItem { Label("Health", systemImage: "heart.fill") }
                    TrainView()
                        .tabItem { Label("Train", systemImage: "figure.strengthtraining.traditional") }
                    NutritionView()
                        .tabItem { Label("Nutrition", systemImage: "fork.knife") }
                }
            }
        }
        .environment(global)
        .sheet(isPresented: $global.showingScanner) {
            FoodScannerView(date: Date()) { global.showingScanner = false }
                .environment(global)
        }
        .sheet(isPresented: $global.showingHistory) {
            WorkoutHistoryView()
                .environment(global)
        }
        .sheet(isPresented: $global.showingSettings) {
            SettingsView()
                .environment(global)
        }
        .fullScreenCover(isPresented: $global.showingCustomWorkout) {
            CustomWorkoutPickerView()
                .environment(global)
        }
    }
}
