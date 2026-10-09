import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: UnlockStore
    @AppStorage(SettingsKey.wake) private var wake = 8 * 60
    @AppStorage(SettingsKey.bed) private var bed = 22 * 60
    @AppStorage(SettingsKey.spacing) private var spacing = 5
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("First drop", selection: minutesBinding($wake), displayedComponents: .hourAndMinute)
                    DatePicker("Last drop", selection: minutesBinding($bed), displayedComponents: .hourAndMinute)
                    Stepper("\(spacing) min between different drops", value: $spacing, in: 1...30)
                } header: {
                    Text("Daily window")
                } footer: {
                    Text("Doses are spread evenly between your first and last drop.")
                }
                if UnlockStore.monetizationEnabled {
                Section {
                    if store.isUnlocked {
                        Label("DropClock Full unlocked", systemImage: "checkmark.seal.fill")
                    } else {
                        Button("Unlock all features") { showingPaywall = true }
                    }
                    Button("Restore purchase") { Task { await store.restore() } }
                }
                }
                Section {
                    Text("DropClock is a reminder tool. Always follow your doctor's instructions.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onChange(of: wake) { _, _ in Task { await AppData.refreshNotifications() } }
            .onChange(of: bed) { _, _ in Task { await AppData.refreshNotifications() } }
            .onChange(of: spacing) { _, _ in Task { await AppData.refreshNotifications() } }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
        }
    }

    private func minutesBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(byAdding: .minute, value: minutes.wrappedValue, to: Calendar.current.startOfDay(for: Date())) ?? Date() },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}

struct PaywallView: View {
    @EnvironmentObject private var store: UnlockStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("DropClock Full").font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 12) {
                    Label("Unlimited drops and both eyes", systemImage: "drop.fill")
                    Label("Taper schedules (4× → 3× → 2×)", systemImage: "chart.line.downtrend.xyaxis")
                    Label("History you can share with your doctor", systemImage: "doc.text")
                    Label("One-time purchase. No subscription.", systemImage: "checkmark.seal")
                }
                .font(.body)
                Spacer()
                Button {
                    Task { await store.purchase(); if store.isUnlocked { dismiss() } }
                } label: {
                    Text(store.product.map { String(localized: "Unlock for \($0.displayPrice)") } ?? String(localized: "Unlock"))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.product == nil || store.isPurchasing)
                Button("Restore purchase") { Task { await store.restore(); if store.isUnlocked { dismiss() } } }
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
            .toolbar { Button("Close") { dismiss() } }
        }
    }
}

struct OnboardingView: View {
    var onDone: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Image(systemName: "drop.circle.fill").font(.system(size: 64)).foregroundStyle(Color.accentColor)
            Text("Never miss an eye drop").font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 14) {
                Label("Reminders that actually ring", systemImage: "bell.badge")
                Label("Drops spaced 5 minutes apart automatically", systemImage: "timer")
                Label("Taper schedules after surgery", systemImage: "chart.line.downtrend.xyaxis")
                Label("Your data stays on this iPhone", systemImage: "lock")
            }
            Spacer()
            Button {
                Task { await NotificationScheduler.requestPermission(); onDone() }
            } label: {
                Text("Turn on reminders").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(28)
    }
}
