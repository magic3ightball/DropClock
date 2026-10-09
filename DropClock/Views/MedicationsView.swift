import SwiftUI
import SwiftData

struct MedicationsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var store: UnlockStore
    @Query(filter: #Predicate<Medication> { !$0.isArchived }, sort: \Medication.sortOrder) private var meds: [Medication]

    @State private var editing: Medication?
    @State private var showingNew = false
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(meds) { med in
                    Button { editing = med } label: {
                        HStack(spacing: 12) {
                            CapDot(color: med.capColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(med.name).foregroundStyle(.primary)
                                Text(summary(med)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { idx in
                    idx.map { meds[$0] }.forEach(context.delete)
                    try? context.save()
                    Task { await AppData.refreshNotifications() }
                }
            }
            .overlay {
                if meds.isEmpty {
                    ContentUnavailableView("No drops yet", systemImage: "drop", description: Text("Tap + to add your first eye drop."))
                }
            }
            .navigationTitle("Drops")
            .toolbar {
                Button {
                    if store.canAddMedication(currentCount: meds.count) { showingNew = true } else { showingPaywall = true }
                } label: { Image(systemName: "plus") }
                .accessibilityLabel(Text("Add drop"))
            }
            .sheet(isPresented: $showingNew) {
                MedicationEditView(medication: nil, nextSortOrder: meds.count,
                                   allowSplitEyes: store.canAddMedication(currentCount: meds.count + 1))
            }
            .sheet(item: $editing) { MedicationEditView(medication: $0, nextSortOrder: meds.count, allowSplitEyes: false) }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
        }
    }

    private func summary(_ med: Medication) -> String {
        let phases = med.phases.map { p in
            p.days > 0
            ? String(localized: "\(p.timesPerDay)×/day for \(p.days)d")
            : String(localized: "\(p.timesPerDay)×/day ongoing")
        }
        return phases.joined(separator: " → ")
    }
}

struct MedicationEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let medication: Medication?
    let nextSortOrder: Int
    /// Splitting creates two entries, so free users at the limit cannot use it.
    let allowSplitEyes: Bool

    @State private var name = ""
    @State private var cap: CapColor = .white
    @State private var eye: EyeSide = .both
    @State private var start = Date()
    @State private var phases: [TaperPhase] = [TaperPhase(timesPerDay: 4, days: 7)]
    @State private var splitEyes = false
    @State private var firstEye: EyeSide = .right
    @State private var secondStart = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Drop") {
                    TextField("Name (e.g. Prednisolone)", text: $name)
                    Picker("Eye", selection: $eye) {
                        ForEach(EyeSide.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if medication == nil && eye == .both {
                    Section {
                        Toggle("Second eye starts on a different date", isOn: $splitEyes)
                            .disabled(!allowSplitEyes)
                        if splitEyes {
                            Picker("First eye", selection: $firstEye) {
                                Text(EyeSide.right.label).tag(EyeSide.right)
                                Text(EyeSide.left.label).tag(EyeSide.left)
                            }
                            .pickerStyle(.segmented)
                            DatePicker("Second eye starts", selection: $secondStart, in: start..., displayedComponents: .date)
                        }
                    } footer: {
                        if allowSplitEyes {
                            Text("For surgery on one eye first and the other a few weeks later. The same schedule restarts for the second eye.")
                        } else {
                            Text("Unlock DropClock Full to schedule each eye separately.")
                        }
                    }
                }
                Section("Cap color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(CapColor.allCases) { c in
                            CapDot(color: c, size: 32)
                                .overlay(Circle().stroke(Color.accentColor, lineWidth: cap == c ? 3 : 0).padding(-4))
                                .onTapGesture { cap = c }
                                .accessibilityLabel(Text(c.label))
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    DatePicker("Start date", selection: $start, displayedComponents: .date)
                    ForEach($phases) { $phase in
                        VStack(alignment: .leading) {
                            Stepper("\(phase.timesPerDay) times a day", value: $phase.timesPerDay, in: 1...12)
                            Stepper(phase.days == 0 ? String(localized: "Ongoing") : String(localized: "for \(phase.days) days"),
                                    value: $phase.days, in: 0...120)
                        }
                    }
                    .onDelete { phases.remove(atOffsets: $0) }
                    Button("Add next step (taper)") {
                        let last = phases.last
                        phases.append(TaperPhase(timesPerDay: max((last?.timesPerDay ?? 2) - 1, 1), days: 7))
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    Text("Enter exactly what your doctor prescribed. DropClock does not give medical advice.")
                }
            }
            .navigationTitle(medication == nil ? Text("New drop") : Text("Edit drop"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || phases.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let m = medication else { return }
        name = m.name; cap = m.capColor; eye = m.eye; start = m.startDate; phases = m.phases
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let m = medication {
            m.name = trimmed; m.capColor = cap; m.eye = eye; m.startDate = start; m.phases = phases
        } else if eye == .both && splitEyes && allowSplitEyes {
            let secondEye: EyeSide = firstEye == .right ? .left : .right
            context.insert(Medication(name: trimmed, capColor: cap, eye: firstEye, startDate: start, phases: phases, sortOrder: nextSortOrder))
            context.insert(Medication(name: trimmed, capColor: cap, eye: secondEye, startDate: secondStart, phases: phases, sortOrder: nextSortOrder + 1))
        } else {
            context.insert(Medication(name: trimmed, capColor: cap, eye: eye, startDate: start, phases: phases, sortOrder: nextSortOrder))
        }
        try? context.save()
        Task {
            await NotificationScheduler.requestPermission()
            await AppData.refreshNotifications()
        }
        dismiss()
    }
}
