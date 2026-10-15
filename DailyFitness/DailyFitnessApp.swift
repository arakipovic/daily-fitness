import SwiftUI

@main
struct DailyFitnessApp: App {
    @State private var profileManager = ProfileManager.shared
    @State private var healthKit = HealthKitManager.shared
    @State private var notificationManager = NotificationManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(profileManager.activeProfileID)
                .environment(profileManager.activeStore)
                .environment(healthKit)
                .environment(profileManager)
                .environment(notificationManager)
                .task {
                    async let food: () = FoodStore.shared.setup()
                    async let auth: () = healthKit.requestAuthorization()
                    async let notif: () = notificationManager.refreshStatus()
                    _ = await (food, auth, notif)
                    notificationManager.reschedule()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                profileManager.activeStore.saveImmediately()
            }
            if phase == .active {
                Task { await notificationManager.refreshStatus() }
            }
        }
    }
}
