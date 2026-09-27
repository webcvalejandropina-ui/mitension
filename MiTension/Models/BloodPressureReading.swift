import Foundation

/// Periodo automático de la hora local del dispositivo; no es un campo editable por el usuario.
enum DayPeriod: String, Codable, CaseIterable, Identifiable {
    case morning
    case evening

    var id: String { rawValue }
    var title: String { self == .morning ? L10n.text("Mañana") : L10n.text("Noche") }
    var symbol: String { self == .morning ? "sun.max.fill" : "moon.stars.fill" }

    /// Clasifica antes de las 14:00 como mañana y desde las 14:00 como noche.
    static func suggested(for date: Date, calendar: Calendar = .current) -> DayPeriod {
        calendar.component(.hour, from: date) < 14 ? .morning : .evening
    }
}

/// Medicamento asociado a una toma concreta. La dosis es texto libre, no una recomendación médica.
struct ReadingMedication: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var dose = ""
    var note = ""

    var description: String {
        name + (dose.isEmpty ? "" : " · " + dose) + (note.isEmpty ? "" : " — " + note)
    }
}

/// Una medición individual identificada por UUID. No se fusionan ni se promedian los registros guardados.
struct BloodPressureReading: Identifiable, Codable, Hashable {
    let id: UUID
    var systolic: Int
    var diastolic: Int
    var pulse: Int?
    var measuredAt: Date
    var period: DayPeriod
    var note: String
    var medications: [ReadingMedication]
    var medicationSummary: String { medications.map(\.description).joined(separator: "\n") }
    // Adult home-reading reference, not a diagnosis or an individual treatment target.
    var systolicAboveReference: Bool { systolic >= 135 }
    var diastolicAboveReference: Bool { diastolic >= 85 }
    var needsPromptAssessment: Bool { systolic >= 180 || diastolic >= 120 }
    /// Validación estructural compartida por guardado e importación; no determina un diagnóstico.
    var isValid: Bool {
        (40...300).contains(systolic) && (30...200).contains(diastolic) && diastolic < systolic
            && (pulse.map { (20...250).contains($0) } ?? true)
            && measuredAt.timeIntervalSinceReferenceDate.isFinite
            && medications.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && Set(medications.map(\.id)).count == medications.count
    }

    init(
        id: UUID = UUID(),
        systolic: Int,
        diastolic: Int,
        pulse: Int? = nil,
        measuredAt: Date,
        period: DayPeriod,
        note: String = "",
        medications: [ReadingMedication] = []
    ) {
        self.id = id
        self.systolic = systolic
        self.diastolic = diastolic
        self.pulse = pulse
        self.measuredAt = measuredAt
        self.period = period
        self.note = note
        self.medications = medications
    }

    private enum CodingKeys: String, CodingKey {
        case id, systolic, diastolic, pulse, measuredAt, period, note, medications
    }

    /// Compatibilidad con históricos antiguos: notas y medicamentos ausentes reciben valores vacíos.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        systolic = try values.decode(Int.self, forKey: .systolic)
        diastolic = try values.decode(Int.self, forKey: .diastolic)
        pulse = try values.decodeIfPresent(Int.self, forKey: .pulse)
        measuredAt = try values.decode(Date.self, forKey: .measuredAt)
        period = try values.decode(DayPeriod.self, forKey: .period)
        note = try values.decodeIfPresent(String.self, forKey: .note) ?? ""
        medications = try values.decodeIfPresent([ReadingMedication].self, forKey: .medications) ?? []
    }
}

/// Formato JSON heredado interno; la interfaz pública de intercambio utiliza Excel.
struct ReadingsBackup: Codable {
    let version: Int
    let exportedAt: Date
    let readings: [BloodPressureReading]
}

/// Agrupación por inicio de día local que conserva cada toma y su identidad.
struct ReadingDayGroup: Identifiable {
    let date: Date
    let readings: [BloodPressureReading]
    var id: Date { date }

    func readings(in period: DayPeriod) -> [BloodPressureReading] {
        readings.filter { $0.period == period }
    }

    static func grouped(_ readings: [BloodPressureReading], calendar: Calendar = .current) -> [ReadingDayGroup] {
        Dictionary(grouping: readings, by: { calendar.startOfDay(for: $0.measuredAt) })
            .map { ReadingDayGroup(date: $0.key, readings: $0.value.sorted { $0.measuredAt > $1.measuredAt }) }
            .sorted { $0.date > $1.date }
    }
}

/// Acceso al catálogo de idiomas del dispositivo y normalización segura de enteros Unicode.
enum L10n {
    static func integer(_ text: String) -> Int? {
        let characters = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !characters.isEmpty, characters.allSatisfy({
            $0.unicodeScalars.count == 1 && $0.unicodeScalars.first?.properties.generalCategory == .decimalNumber
        }) else { return nil }
        return Int(characters.compactMap(\.wholeNumberValue).map(String.init).joined())
    }
    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: .main, comment: "")
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}
