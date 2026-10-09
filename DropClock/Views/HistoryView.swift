import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    enum Mode: Hashable { case doses, pressure }

    @EnvironmentObject private var store: UnlockStore
    @Query(sort: \DoseLog.scheduledAt, order: .reverse) private var logs: [DoseLog]
    @Query(filter: #Predicate<Medication> { !$0.isArchived }, sort: \Medication.sortOrder) private var meds: [Medication]
    @Query(sort: \EyePressureReading.date) private var readings: [EyePressureReading]

    @State private var mode: Mode = .doses
    @State private var report: ReportFile?
    @State private var showingPaywall = false
    @State private var addingReading = false

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .doses: DoseHistoryList(logs: logs)
                case .pressure: PressureList(readings: readings)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                Picker("View", selection: $mode) {
                    Text("Doses").tag(Mode.doses)
                    Text("Eye pressure").tag(Mode.pressure)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 6)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if mode == .pressure {
                        Button { addingReading = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel(Text("Add reading"))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard store.isUnlocked else { showingPaywall = true; return }
                        report = ReportFile(url: ReportBuilder.makePDF(meds: meds, logs: logs, readings: readings, settings: AppData.settings))
                    } label: {
                        Label("PDF report", systemImage: "doc.richtext")
                    }
                    .disabled(logs.isEmpty && readings.isEmpty)
                }
            }
            .sheet(item: $report) { file in ShareSheet(items: [file.url]) }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .sheet(isPresented: $addingReading) { AddPressureView() }
        }
    }
}

private struct ReportFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct DoseHistoryList: View {
    let logs: [DoseLog]

    private var grouped: [(day: Date, items: [DoseLog])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: logs) { cal.startOfDay(for: $0.scheduledAt) }
        return dict.keys.sorted(by: >).map { ($0, dict[$0] ?? []) }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.day) { group in
                Section {
                    ForEach(group.items) { log in
                        HStack(spacing: 12) {
                            CapDot(color: log.medication?.capColor ?? .white, size: 16)
                            Text(log.medication?.name ?? "-")
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
    }
}

private struct PressureList: View {
    @Environment(\.modelContext) private var context
    let readings: [EyePressureReading]

    private var newestFirst: [EyePressureReading] { readings.reversed() }
    private var leftLabel: String { String(localized: "Left eye") }
    private var rightLabel: String { String(localized: "Right eye") }

    var body: some View {
        List {
            if readings.count >= 2 {
                Section {
                    Chart {
                        ForEach(readings) { r in
                            if let l = r.left {
                                LineMark(x: .value("Date", r.date), y: .value("mmHg", l), series: .value("Eye", leftLabel))
                                    .foregroundStyle(by: .value("Eye", leftLabel))
                                PointMark(x: .value("Date", r.date), y: .value("mmHg", l))
                                    .foregroundStyle(by: .value("Eye", leftLabel))
                            }
                            if let rr = r.right {
                                LineMark(x: .value("Date", r.date), y: .value("mmHg", rr), series: .value("Eye", rightLabel))
                                    .foregroundStyle(by: .value("Eye", rightLabel))
                                PointMark(x: .value("Date", r.date), y: .value("mmHg", rr))
                                    .foregroundStyle(by: .value("Eye", rightLabel))
                            }
                        }
                    }
                    .chartYAxisLabel("mmHg")
                    .frame(height: 180)
                    .padding(.vertical, 6)
                }
            }
            Section {
                ForEach(newestFirst) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(r.date, format: .dateTime.year().month().day())
                            Spacer()
                            Text("L \(format(r.left))  R \(format(r.right))").monospacedDigit()
                        }
                        if !r.note.isEmpty {
                            Text(r.note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    idx.map { newestFirst[$0] }.forEach(context.delete)
                    try? context.save()
                }
            }
        }
        .overlay {
            if readings.isEmpty {
                ContentUnavailableView("No pressure readings", systemImage: "gauge.with.dots.needle.33percent", description: Text("Record the eye pressure (IOP) measured at your clinic."))
            }
        }
    }

    private func format(_ v: Double?) -> String { v.map { String(format: "%.0f", $0) } ?? "-" }
}

struct AddPressureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var left = ""
    @State private var right = ""
    @State private var note = ""

    private func parse(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Section("mmHg") {
                    TextField("Left eye", text: $left).keyboardType(.decimalPad)
                    TextField("Right eye", text: $right).keyboardType(.decimalPad)
                }
                TextField("Note", text: $note)
            }
            .navigationTitle("Eye pressure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.insert(EyePressureReading(date: date, left: parse(left), right: parse(right), note: note))
                        try? context.save()
                        dismiss()
                    }
                    .disabled(parse(left) == nil && parse(right) == nil)
                }
            }
        }
    }
}
