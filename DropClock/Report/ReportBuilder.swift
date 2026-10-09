import SwiftUI
import UIKit

/// Builds an A4 PDF the user can show or send to their eye doctor:
/// current drops and schedules, day-by-day adherence, and eye pressure readings.
@MainActor
enum ReportBuilder {
    static let pageSize = CGSize(width: 595, height: 842) // A4 in points
    static let rowsPerPage = 32

    struct DayRow: Identifiable {
        var day: Date
        var planned: Int
        var taken: Int
        var id: Date { day }
    }

    static func dayRows(meds: [Medication], logs: [DoseLog], settings: ScheduleSettings, days: Int = 60, now: Date = Date()) -> [DayRow] {
        let cal = Calendar.current
        let specs = meds.map(\.spec)
        let earliest = (meds.map(\.startDate) + logs.map(\.scheduledAt)).min() ?? now
        let today = cal.startOfDay(for: now)
        let firstDay = max(cal.startOfDay(for: earliest), cal.date(byAdding: .day, value: -(days - 1), to: today) ?? today)
        let takenByDay = Dictionary(grouping: logs) { cal.startOfDay(for: $0.scheduledAt) }.mapValues(\.count)

        var rows: [DayRow] = []
        var day = today
        while day >= firstDay {
            let planned = ScheduleEngine.doses(on: day, specs: specs, settings: settings, calendar: cal).count
            let taken = takenByDay[day] ?? 0
            if planned > 0 || taken > 0 { rows.append(DayRow(day: day, planned: planned, taken: taken)) }
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return rows
    }

    static func makePDF(meds: [Medication], logs: [DoseLog], readings: [EyePressureReading], settings: ScheduleSettings) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DropClock-Report.pdf")
        let rows = dayRows(meds: meds, logs: logs, settings: settings)
        let sortedReadings = readings.sorted { $0.date > $1.date }

        // First page carries the drug list, so it fits fewer day rows.
        var chunks: [[DayRow]] = []
        let firstCount = max(rowsPerPage - meds.count * 2 - 6, 8)
        chunks.append(Array(rows.prefix(firstCount)))
        var rest = Array(rows.dropFirst(firstCount))
        while !rest.isEmpty {
            chunks.append(Array(rest.prefix(rowsPerPage)))
            rest = Array(rest.dropFirst(rowsPerPage))
        }

        var box = CGRect(origin: .zero, size: pageSize)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return url }
        let totalPages = chunks.count + (sortedReadings.isEmpty ? 0 : 1)

        for (i, chunk) in chunks.enumerated() {
            let page = ReportPage(index: i + 1, total: totalPages, meds: i == 0 ? meds : [], rows: chunk, readings: [])
            draw(page, into: ctx)
        }
        if !sortedReadings.isEmpty {
            let page = ReportPage(index: totalPages, total: totalPages, meds: [], rows: [], readings: Array(sortedReadings.prefix(rowsPerPage)))
            draw(page, into: ctx)
        }
        ctx.closePDF()
        return url
    }

    private static func draw<V: View>(_ view: V, into ctx: CGContext) {
        let renderer = ImageRenderer(content: view.frame(width: pageSize.width, height: pageSize.height))
        renderer.render { _, render in
            ctx.beginPDFPage(nil)
            render(ctx)
            ctx.endPDFPage()
        }
    }
}

private struct ReportPage: View {
    let index: Int
    let total: Int
    let meds: [Medication]
    let rows: [ReportBuilder.DayRow]
    let readings: [EyePressureReading]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DropClock report").font(.system(size: 18, weight: .bold))
                Spacer()
                Text(Date(), format: .dateTime.year().month().day()).font(.system(size: 10))
            }
            Divider()

            if !meds.isEmpty {
                Text("Current drops").font(.system(size: 12, weight: .semibold))
                ForEach(meds) { med in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(med.name) · \(String(localized: med.eye.labelResource))").font(.system(size: 10, weight: .medium))
                        Text(med.scheduleSummary).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Divider()
            }

            if !rows.isEmpty {
                Text("Daily adherence").font(.system(size: 12, weight: .semibold))
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 3) {
                    GridRow {
                        Text("Date"); Text("Planned"); Text("Taken"); Text("%")
                    }
                    .font(.system(size: 9, weight: .semibold))
                    ForEach(rows) { r in
                        GridRow {
                            Text(r.day, format: .dateTime.year().month().day().weekday(.abbreviated))
                            Text("\(r.planned)")
                            Text("\(r.taken)")
                            Text(r.planned > 0 ? "\(Int((Double(r.taken) / Double(r.planned) * 100).rounded()))%" : "-")
                        }
                        .font(.system(size: 9).monospacedDigit())
                    }
                }
            }

            if !readings.isEmpty {
                Text("Eye pressure (mmHg)").font(.system(size: 12, weight: .semibold))
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 3) {
                    GridRow {
                        Text("Date"); Text("Left eye"); Text("Right eye"); Text("Note")
                    }
                    .font(.system(size: 9, weight: .semibold))
                    ForEach(readings) { r in
                        GridRow {
                            Text(r.date, format: .dateTime.year().month().day())
                            Text(r.left.map { String(format: "%.0f", $0) } ?? "-")
                            Text(r.right.map { String(format: "%.0f", $0) } ?? "-")
                            Text(r.note).lineLimit(1)
                        }
                        .font(.system(size: 9).monospacedDigit())
                    }
                }
            }

            Spacer()
            HStack {
                Text("Recorded by the patient in DropClock. Not a medical record.").font(.system(size: 8)).foregroundStyle(.secondary)
                Spacer()
                Text("\(index) / \(total)").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
        .padding(36)
        .foregroundStyle(.black)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

extension EyeSide {
    var labelResource: LocalizedStringResource {
        switch self {
        case .left: return "Left eye"
        case .right: return "Right eye"
        case .both: return "Both eyes"
        }
    }
}

extension Medication {
    var scheduleSummary: String {
        let df = DateFormatter()
        df.dateStyle = .medium
        let steps = phases.map { p in
            p.days > 0
            ? String(localized: "\(p.timesPerDay)×/day for \(p.days)d")
            : String(localized: "\(p.timesPerDay)×/day ongoing")
        }
        return String(localized: "From \(df.string(from: startDate)): ") + steps.joined(separator: " → ")
    }
}

/// Minimal wrapper so we can hand a freshly generated file to the system share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
