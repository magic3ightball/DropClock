import Foundation

/// One step of a prescription, e.g. "4 times a day for 7 days".
/// `days == 0` means "keep going until the user stops it" (typical for glaucoma).
struct TaperPhase: Codable, Hashable, Identifiable {
    var id = UUID()
    var timesPerDay: Int
    var days: Int
}

enum EyeSide: String, Codable, CaseIterable, Identifiable {
    case left, right, both
    var id: String { rawValue }
}

/// Plain value the engine works with, so it stays free of SwiftData and easy to test.
struct MedicationSpec: Hashable {
    var id: String
    var name: String
    var eye: EyeSide
    var startDate: Date
    var phases: [TaperPhase]
    /// Lower number wins when two drops land on the same minute.
    var sortOrder: Int = 0
}

struct PlannedDose: Hashable, Identifiable {
    var medicationID: String
    var time: Date
    var id: String { "\(medicationID)@\(Int(time.timeIntervalSince1970))" }
}

struct ScheduleSettings: Hashable {
    /// Minutes after midnight.
    var wakeMinutes: Int = 8 * 60
    var bedMinutes: Int = 22 * 60
    /// Doctors usually ask for ~5 minutes between different drops.
    var spacingMinutes: Int = 5
}

enum ScheduleEngine {

    /// Which phase is active on `day`, or nil if the medication has not started or has finished.
    static func activePhase(for spec: MedicationSpec, on day: Date, calendar: Calendar = .current) -> TaperPhase? {
        let start = calendar.startOfDay(for: spec.startDate)
        let target = calendar.startOfDay(for: day)
        guard let dayIndex = calendar.dateComponents([.day], from: start, to: target).day, dayIndex >= 0 else { return nil }
        var cursor = 0
        for phase in spec.phases {
            if phase.days <= 0 { return phase.timesPerDay > 0 ? phase : nil }
            if dayIndex < cursor + phase.days { return phase.timesPerDay > 0 ? phase : nil }
            cursor += phase.days
        }
        return nil
    }

    /// Last day the medication is used, or nil if it is open-ended.
    static func endDate(for spec: MedicationSpec, calendar: Calendar = .current) -> Date? {
        guard !spec.phases.contains(where: { $0.days <= 0 }) else { return nil }
        let total = spec.phases.reduce(0) { $0 + $1.days }
        guard total > 0 else { return nil }
        return calendar.date(byAdding: .day, value: total - 1, to: calendar.startOfDay(for: spec.startDate))
    }

    /// Evenly spreads `count` doses between wake and bed time.
    static func baseMinutes(count: Int, settings: ScheduleSettings) -> [Int] {
        guard count > 0 else { return [] }
        if count == 1 { return [settings.wakeMinutes] }
        let span = max(settings.bedMinutes - settings.wakeMinutes, 0)
        return (0..<count).map { i in
            settings.wakeMinutes + Int((Double(span) * Double(i) / Double(count - 1)).rounded())
        }
    }

    /// All doses for one calendar day, sorted, with different medications pushed apart by `spacingMinutes`.
    static func doses(on day: Date, specs: [MedicationSpec], settings: ScheduleSettings = .init(), calendar: Calendar = .current) -> [PlannedDose] {
        let midnight = calendar.startOfDay(for: day)
        var raw: [(minutes: Int, order: Int, id: String)] = []
        for spec in specs {
            guard let phase = activePhase(for: spec, on: day, calendar: calendar) else { continue }
            for m in baseMinutes(count: phase.timesPerDay, settings: settings) {
                raw.append((m, spec.sortOrder, spec.id))
            }
        }
        raw.sort { ($0.minutes, $0.order, $0.id) < ($1.minutes, $1.order, $1.id) }

        var result: [PlannedDose] = []
        var lastMinutes: Int? = nil
        for item in raw {
            var m = item.minutes
            if let last = lastMinutes, m < last + settings.spacingMinutes {
                m = last + settings.spacingMinutes
            }
            lastMinutes = m
            if let time = calendar.date(byAdding: .minute, value: m, to: midnight) {
                result.append(PlannedDose(medicationID: item.id, time: time))
            }
        }
        return result
    }

    /// Upcoming doses from `now`, capped so we stay under iOS's 64 pending-notification limit.
    static func upcoming(from now: Date, days: Int = 7, limit: Int = 60, specs: [MedicationSpec], settings: ScheduleSettings = .init(), calendar: Calendar = .current) -> [PlannedDose] {
        var out: [PlannedDose] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            out += doses(on: day, specs: specs, settings: settings, calendar: calendar).filter { $0.time > now }
            if out.count >= limit { break }
        }
        return Array(out.prefix(limit))
    }
}
