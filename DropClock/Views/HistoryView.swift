import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \DoseLog.scheduledAt, order: .reverse) private var logs: [DoseLog]

    private var grouped: [(day: Date, items: [DoseLog])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: logs) { cal.startOfDay(for: $0.scheduledAt) }
        return dict.keys.sorted(by: >).map { ($0, dict[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.day) { group in
                    Section {
                        ForEach(group.items) { log in
                            HStack(spacing: 12) {
                                CapDot(color: log.medication?.capColor ?? .white, size: 16)
                                Text(log.medication?.name ?? "—")
                                Spacer()
                                Text(log.takenAt, style: .time).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    } header: {
                        Text(group.day, format: .dateTime.month().day().weekday())
                    }
                }
            }
            .overlay {
                if logs.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: "calendar", description: Text("Doses you check off will show up here."))
                }
            }
            .navigationTitle("History")
            .toolbar {
                // TODO(v1): replace with a PDF report for the eye doctor (ImageRenderer).
                ShareLink(item: csv) { Image(systemName: "square.and.arrow.up") }
                    .disabled(logs.isEmpty)
            }
        }
    }

    private var csv: String {
        let f = ISO8601DateFormatter()
        let rows = logs.map { "\(f.string(from: $0.scheduledAt)),\(f.string(from: $0.takenAt)),\($0.medication?.name ?? "")" }
        return (["scheduled,taken,drop"] + rows).joined(separator: "\n")
    }
}
