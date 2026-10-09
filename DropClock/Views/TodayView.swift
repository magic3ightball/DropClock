import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Medication> { !$0.isArchived }, sort: \Medication.sortOrder) private var meds: [Medication]
    @Query private var logs: [DoseLog]

    @AppStorage(SettingsKey.wake) private var wake = 8 * 60
    @AppStorage(SettingsKey.bed) private var bed = 22 * 60
    @AppStorage(SettingsKey.spacing) private var spacing = 5

    private var settings: ScheduleSettings { .init(wakeMinutes: wake, bedMinutes: bed, spacingMinutes: spacing) }
    private var byID: [String: Medication] { Dictionary(uniqueKeysWithValues: meds.map { ($0.uid, $0) }) }
    private var doses: [PlannedDose] { ScheduleEngine.doses(on: Date(), specs: meds.map(\.spec), settings: settings) }
    private var takenIDs: Set<String> {
        Set(logs.compactMap { log in log.medication.map { PlannedDose(medicationID: $0.uid, time: log.scheduledAt).id } })
    }

    var body: some View {
        NavigationStack {
            Group {
                if meds.isEmpty {
                    ContentUnavailableView("No drops yet", systemImage: "drop", description: Text("Add the eye drops your doctor prescribed in the Drops tab."))
                } else if doses.isEmpty {
                    ContentUnavailableView("Nothing scheduled today", systemImage: "checkmark.circle")
                } else {
                    List {
                        Section {
                            ProgressView(value: Double(doses.filter { takenIDs.contains($0.id) }.count), total: Double(max(doses.count, 1)))
                            Text("\(doses.filter { takenIDs.contains($0.id) }.count) of \(doses.count) done")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Section {
                            ForEach(doses) { dose in
                                if let med = byID[dose.medicationID] {
                                    DoseRow(med: med, dose: dose, taken: takenIDs.contains(dose.id)) { toggle(dose, med: med) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Today")
        }
    }

    private func toggle(_ dose: PlannedDose, med: Medication) {
        if let existing = med.logs.first(where: { $0.scheduledAt == dose.time }) {
            context.delete(existing)
        } else {
            context.insert(DoseLog(scheduledAt: dose.time, medication: med))
            NotificationScheduler.cancel(dose)
        }
        try? context.save()
        Task { await AppData.refreshNotifications() }
    }
}

private struct DoseRow: View {
    let med: Medication
    let dose: PlannedDose
    let taken: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Text(dose.time, style: .time)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .frame(width: 84, alignment: .leading)
                CapDot(color: med.capColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(med.name).font(.body.weight(.medium))
                    Text(med.eye.label).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: taken ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(taken ? Color.accentColor : Color.secondary)
            }
            .padding(.vertical, 6)
            .opacity(taken ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(med.name))
        .accessibilityValue(taken ? Text("Taken") : Text("Not taken"))
    }
}
