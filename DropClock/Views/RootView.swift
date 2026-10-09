import SwiftUI
import SwiftData

struct RootView: View {
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "clock") }
            MedicationsView()
                .tabItem { Label("Drops", systemImage: "drop") }
            HistoryView()
                .tabItem { Label("History", systemImage: "calendar") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { onboarded = !$0 })) {
            OnboardingView { onboarded = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await AppData.refreshNotifications() } }
        }
    }
}

/// Small colored circle that mirrors the bottle cap, the way older users recognise their drops.
struct CapDot: View {
    var color: CapColor
    var size: CGFloat = 22
    var body: some View {
        Circle()
            .fill(color.color)
            .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
