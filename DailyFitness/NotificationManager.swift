import Foundation
import UserNotifications

// MARK: - Settings model (stored in UserDefaults — device-level, not per-profile)

struct NotificationSettings: Codable {
    var workoutEnabled: Bool = false
    var workoutHour: Int = 19
    var workoutMinute: Int = 0

    var foodEnabled: Bool = false
    var foodHour: Int = 13
    var foodMinute: Int = 0

    var measurementEnabled: Bool = false
    var measurementDayOfWeek: Int = 1  // 1 = Sunday … 7 = Saturday
    var measurementHour: Int = 9
    var measurementMinute: Int = 0

    private static let key = "com.dailyfitness.notificationSettings"

    static func load() -> NotificationSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(NotificationSettings.self, from: data)
        else { return NotificationSettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Manager

@MainActor
@Observable
final class NotificationManager {

    static let shared = NotificationManager()

    var settings: NotificationSettings = .load()
    var permissionStatus: UNAuthorizationStatus = .notDetermined

    private init() {}

    // MARK: - Permission

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            permissionStatus = granted ? .authorized : .denied
            if granted { reschedule() }
        } catch {
            permissionStatus = .denied
        }
    }

    func refreshStatus() async {
        permissionStatus = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
    }

    // MARK: - Schedule

    func saveAndReschedule() {
        settings.save()
        reschedule()
    }

    func reschedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(
            withIdentifiers: ["daily_workout", "daily_food", "weekly_measurement"]
        )
        guard permissionStatus == .authorized else { return }

        if settings.workoutEnabled {
            scheduleDaily(
                id: "daily_workout",
                title: "Time to Train",
                body: "Your workout is scheduled for today. Let's go!",
                hour: settings.workoutHour,
                minute: settings.workoutMinute
            )
        }
        if settings.foodEnabled {
            scheduleDaily(
                id: "daily_food",
                title: "Log Your Meals",
                body: "Don't forget to track what you've eaten today.",
                hour: settings.foodHour,
                minute: settings.foodMinute
            )
        }
        if settings.measurementEnabled {
            scheduleWeekly(
                id: "weekly_measurement",
                title: "Weekly Check-In",
                body: "Time to log your body measurements and track your progress.",
                dayOfWeek: settings.measurementDayOfWeek,
                hour: settings.measurementHour,
                minute: settings.measurementMinute
            )
        }
    }

    // MARK: - Private

    private func scheduleDaily(id: String, title: String, body: String, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        )
    }

    private func scheduleWeekly(id: String, title: String, body: String, dayOfWeek: Int, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var comps = DateComponents()
        comps.weekday = dayOfWeek
        comps.hour = hour
        comps.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        )
    }
}
