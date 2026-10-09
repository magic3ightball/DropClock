import Foundation
import UserNotifications

/// Keeps a rolling window of local notifications in sync with the schedule.
///
/// Why this exists: the #1 complaint about competing apps is "the alarm did not ring".
/// iOS only keeps 64 pending notifications per app, so apps that schedule weeks ahead silently
/// lose alarms. We schedule the next 60 and refresh every time the app opens or data changes.
///
/// TODO(v1.1): on iOS 26+, offer AlarmKit alarms that break through Silent / Focus mode.
enum NotificationScheduler {
    static let categoryID = "DOSE"
    static let takenActionID = "TAKEN"
    static let snoozeActionID = "SNOOZE"
    static let prefix = "dose-"

    static func registerCategories() {
        let taken = UNNotificationAction(identifier: takenActionID, title: String(localized: "Mark as taken"), options: [])
        let snooze = UNNotificationAction(identifier: snoozeActionID, title: String(localized: "Remind me in 5 min"), options: [])
        let category = UNNotificationCategory(identifier: categoryID, actions: [taken, snooze], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func identifier(for dose: PlannedDose) -> String { prefix + dose.id }

    /// Replaces every pending dose notification with a fresh window.
    static func reschedule(specs: [MedicationSpec], takenIDs: Set<String>, settings: ScheduleSettings, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        let names = Dictionary(uniqueKeysWithValues: specs.map { ($0.id, $0) })
        let doses = ScheduleEngine.upcoming(from: now, specs: specs, settings: settings)
            .filter { !takenIDs.contains($0.id) }

        for dose in doses {
            guard let spec = names[dose.medicationID] else { continue }
            let content = UNMutableNotificationContent()
            content.title = spec.name
            content.body = bodyText(for: spec.eye)
            content.sound = .default
            content.categoryIdentifier = categoryID
            content.userInfo = ["medicationID": dose.medicationID, "scheduledAt": dose.time.timeIntervalSince1970]
            if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dose.time)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: identifier(for: dose), content: content, trigger: trigger))
        }
    }

    static func cancel(_ dose: PlannedDose) {
        let id = identifier(for: dose)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    static func snooze(from content: UNNotificationContent, minutes: Int = 5) async {
        guard let copy = content.mutableCopy() as? UNMutableNotificationContent else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "snooze-" + UUID().uuidString, content: copy, trigger: trigger))
    }

    private static func bodyText(for eye: EyeSide) -> String {
        switch eye {
        case .left: return String(localized: "Time for your drop · Left eye")
        case .right: return String(localized: "Time for your drop · Right eye")
        case .both: return String(localized: "Time for your drop · Both eyes")
        }
    }
}
