import Foundation
import SwiftData
import SwiftUI

enum CapColor: String, Codable, CaseIterable, Identifiable {
    case white, gray, tan, pink, red, orange, yellow, green, teal, blue, purple
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .white: return Color(white: 0.95)
        case .gray: return .gray
        case .tan: return Color(red: 0.82, green: 0.71, blue: 0.55)
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .blue: return .blue
        case .purple: return .purple
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .white: return "White"
        case .gray: return "Gray"
        case .tan: return "Tan"
        case .pink: return "Pink"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .teal: return "Teal"
        case .blue: return "Blue"
        case .purple: return "Purple"
        }
    }
}

extension EyeSide {
    var label: LocalizedStringKey {
        switch self {
        case .left: return "Left eye"
        case .right: return "Right eye"
        case .both: return "Both eyes"
        }
    }
}

@Model
final class Medication {
    var uid: String = UUID().uuidString
    var name: String = ""
    var capColorRaw: String = CapColor.white.rawValue
    var eyeRaw: String = EyeSide.both.rawValue
    var startDate: Date = Date()
    /// Stored as JSON so SwiftData on iOS 17 does not have to handle arrays of structs.
    var phasesData: Data = Data()
    var sortOrder: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \DoseLog.medication)
    var logs: [DoseLog] = []

    init(name: String, capColor: CapColor, eye: EyeSide, startDate: Date, phases: [TaperPhase], sortOrder: Int = 0) {
        self.name = name
        self.capColorRaw = capColor.rawValue
        self.eyeRaw = eye.rawValue
        self.startDate = startDate
        self.sortOrder = sortOrder
        self.phases = phases
    }

    var capColor: CapColor {
        get { CapColor(rawValue: capColorRaw) ?? .white }
        set { capColorRaw = newValue.rawValue }
    }

    var eye: EyeSide {
        get { EyeSide(rawValue: eyeRaw) ?? .both }
        set { eyeRaw = newValue.rawValue }
    }

    var phases: [TaperPhase] {
        get { (try? JSONDecoder().decode([TaperPhase].self, from: phasesData)) ?? [] }
        set { phasesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var spec: MedicationSpec {
        MedicationSpec(id: uid, name: name, eye: eye, startDate: startDate, phases: phases, sortOrder: sortOrder)
    }
}

/// Eye pressure (IOP) measured at the clinic, in mmHg. Mostly used by glaucoma patients.
@Model
final class EyePressureReading {
    var date: Date = Date()
    var left: Double?
    var right: Double?
    var note: String = ""

    init(date: Date, left: Double?, right: Double?, note: String = "") {
        self.date = date
        self.left = left
        self.right = right
        self.note = note
    }
}

@Model
final class DoseLog {
    /// The planned time this log answers. Lets us match a log to a dose in the schedule.
    var scheduledAt: Date = Date()
    var takenAt: Date = Date()
    var medication: Medication?

    init(scheduledAt: Date, takenAt: Date = Date(), medication: Medication) {
        self.scheduledAt = scheduledAt
        self.takenAt = takenAt
        self.medication = medication
    }
}
