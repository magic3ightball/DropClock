import SwiftUI
import SwiftData
import UserNotifications

@main
struct DropClockApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UnlockStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task { await store.start() }
        }
        .modelContainer(AppData.container)
    }
}

/// Single shared container so the notification delegate can log doses too.
enum AppData {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Medication.self, DoseLog.self, EyePressureReading.self)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    static var settings: ScheduleSettings {
        let d = UserDefaults.standard
        var s = ScheduleSettings()
        if d.object(forKey: SettingsKey.wake) != nil { s.wakeMinutes = d.integer(forKey: SettingsKey.wake) }
        if d.object(forKey: SettingsKey.bed) != nil { s.bedMinutes = d.integer(forKey: SettingsKey.bed) }
        if d.object(forKey: SettingsKey.spacing) != nil { s.spacingMinutes = d.integer(forKey: SettingsKey.spacing) }
        return s
    }

    /// Recompute the notification window from the database.
    @MainActor
    static func refreshNotifications() async {
        let context = container.mainContext
        let meds = (try? context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { !$0.isArchived }))) ?? []
        let logs = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
        let taken = Set(logs.compactMap { log -> String? in
            guard let m = log.medication else { return nil }
            return PlannedDose(medicationID: m.uid, time: log.scheduledAt).id
        })
        await NotificationScheduler.reschedule(specs: meds.map(\.spec), takenIDs: taken, settings: settings)
    }

    @MainActor
    static func markTaken(medicationID: String, scheduledAt: Date) {
        let context = container.mainContext
        let meds = (try? context.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.uid == medicationID }))) ?? []
        guard let med = meds.first else { return }
        if med.logs.contains(where: { $0.scheduledAt == scheduledAt }) { return }
        context.insert(DoseLog(scheduledAt: scheduledAt, medication: med))
        try? context.save()
        NotificationScheduler.cancel(PlannedDose(medicationID: medicationID, time: scheduledAt))
    }
}

enum SettingsKey {
    static let wake = "wakeMinutes"
    static let bed = "bedMinutes"
    static let spacing = "spacingMinutes"
    static let onboarded = "didOnboard"
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationScheduler.registerCategories()
        return true
    }

    // Show the banner and play sound even when the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        switch response.actionIdentifier {
        case NotificationScheduler.takenActionID:
            guard let id = content.userInfo["medicationID"] as? String,
                  let ts = content.userInfo["scheduledAt"] as? TimeInterval else { return }
            await MainActor.run { AppData.markTaken(medicationID: id, scheduledAt: Date(timeIntervalSince1970: ts)) }
        case NotificationScheduler.snoozeActionID:
            await NotificationScheduler.snooze(from: content)
        default:
            break
        }
    }
}
