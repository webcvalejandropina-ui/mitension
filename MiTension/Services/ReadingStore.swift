import Combine
import Foundation

/// Errores de persistencia mostrados con mensajes localizados.
enum ReadingStoreError: LocalizedError {
    case couldNotSave

    var errorDescription: String? {
        L10n.text("No se pudo guardar la toma en este iPhone. Inténtalo de nuevo.")
    }
}

@MainActor
/// Almacén local observable. Publica cambios solo después de escribir el archivo protegido.
final class ReadingStore: ObservableObject {
    @Published private(set) var readings: [BloodPressureReading] = []
    @Published private(set) var lastBackupDate: Date?
    @Published private(set) var persistenceError: String?

    private let lastBackupDateKey = "MiTension.lastBackupDate"
    private let customStorageURL: URL?
    private let preferences: UserDefaults
    private var loadFailed = false

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var storageURL: URL {
        if let customStorageURL { return customStorageURL }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MiTension", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("readings.json")
    }

    /// Permite inyectar almacenamiento y preferencias aislados para los tests.
    init(storageURL: URL? = nil, preferences: UserDefaults = .standard) {
        customStorageURL = storageURL
        self.preferences = preferences
        lastBackupDate = preferences.object(forKey: lastBackupDateKey) as? Date
        load()
    }

    func add(_ reading: BloodPressureReading) throws {
        try add([reading])
    }

    /// Guarda el lote completo de forma atómica: si una toma falla, no se guarda ninguna.
    func add(_ newReadings: [BloodPressureReading]) throws {
        let existingIDs = Set(readings.map(\.id))
        guard !newReadings.isEmpty, newReadings.allSatisfy(\.isValid),
              Set(newReadings.map(\.id)).count == newReadings.count,
              newReadings.allSatisfy({ !existingIDs.contains($0.id) }) else { throw ReadingStoreError.couldNotSave }
        var updated = readings
        updated.append(contentsOf: normalizedPeriods(newReadings))
        updated.sort { $0.measuredAt > $1.measuredAt }
        try persist(updated)
        readings = updated
        persistenceError = nil
        if customStorageURL == nil { FollowupReminders.shared.cancelSatisfied(readings: newReadings) }
    }


    func delete(at offsets: IndexSet, from visibleReadings: [BloodPressureReading]) {
        let ids = Set(offsets.map { visibleReadings[$0].id })
        updateReadings { $0.removeAll { ids.contains($0.id) } }
    }

    func delete(id: UUID) {
        updateReadings { $0.removeAll { $0.id == id } }
    }

    func readings(inLastDays days: Int?) -> [BloodPressureReading] {
        guard let days else { return readings }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return readings.filter { $0.measuredAt >= cutoff }
    }

    /// Compatibilidad técnica con copias JSON antiguas; no se ofrece en las pantallas de exportación.
    func backupFile() throws -> URL {
        guard !loadFailed else { throw ReadingStoreError.couldNotSave }
        let backupDate = Date()
        let backup = ReadingsBackup(version: 1, exportedAt: backupDate, readings: readings)
        let data = try encoder.encode(backup)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mi-Tension-\(formatter.string(from: backupDate))-\(UUID().uuidString).json")
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        lastBackupDate = backupDate
        preferences.set(backupDate, forKey: lastBackupDateKey)
        return url
    }

    /// Restaura el formato heredado sin sustituir registros existentes con el mismo UUID.
    func restore(from url: URL) throws -> Int {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 32 * 1_024 * 1_024 + 1) ?? Data()
        guard data.count <= 32 * 1_024 * 1_024 else { throw ReadingStoreError.couldNotSave }
        let backup = try decoder.decode(ReadingsBackup.self, from: data)
        guard backup.version == 1, backup.readings.allSatisfy(\.isValid) else { throw ReadingStoreError.couldNotSave }
        var seenIDs = Set(readings.map(\.id))
        let newItems = normalizedPeriods(backup.readings.filter { seenIDs.insert($0.id).inserted })
        var updated = readings + newItems
        updated.sort { $0.measuredAt > $1.measuredAt }
        try persist(updated)
        readings = updated
        persistenceError = nil
        return newItems.count
    }

    /// Valida el Excel completo, descarta IDs ya presentes y guarda las filas nuevas en una sola operación.
    func importExcel(from url: URL) throws -> Int {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let imported = try ExcelImport.read(url: url)
        var seen = Set(readings.map(\.id))
        let newItems = imported.filter { seen.insert($0.id).inserted }
        guard !newItems.isEmpty else { return 0 }
        try add(newItems)
        return newItems.count
    }

    /// Conserva el archivo original si está corrupto; bloquea escrituras para no perder el histórico.
    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let stored = try decoder.decode([BloodPressureReading].self, from: Data(contentsOf: storageURL))
            guard stored.allSatisfy(\.isValid), Set(stored.map(\.id)).count == stored.count else { throw ReadingStoreError.couldNotSave }
            let normalized = normalizedPeriods(stored)
            readings = normalized.sorted { $0.measuredAt > $1.measuredAt }
            if normalized != stored {
                do { try persist(normalized) }
                catch { persistenceError = ReadingStoreError.couldNotSave.localizedDescription }
            }
        } catch {
            loadFailed = true
            persistenceError = L10n.text("No se pudo leer el histórico. Se conserva el archivo original; no guardes nuevas tomas hasta recuperarlo.")
        }
    }

    private func updateReadings(_ mutation: (inout [BloodPressureReading]) -> Void) {
        var updated = readings
        mutation(&updated)
        do {
            try persist(updated)
            readings = updated
            persistenceError = nil
        } catch {
            persistenceError = ReadingStoreError.couldNotSave.localizedDescription
        }
    }

    private func normalizedPeriods(_ items: [BloodPressureReading]) -> [BloodPressureReading] {
        items.map { reading in
            var reading = reading
            reading.period = DayPeriod.suggested(for: reading.measuredAt)
            return reading
        }
    }

    /// Recalcula mañana/noche al volver a la app o cambiar de zona horaria, manteniendo la fecha original.
    func refreshPeriods() {
        guard !loadFailed else { return }
        let normalized = normalizedPeriods(readings)
        guard normalized != readings else { return }
        do {
            try persist(normalized)
            readings = normalized
            persistenceError = nil
        } catch { persistenceError = ReadingStoreError.couldNotSave.localizedDescription }
    }

    /// Escritura atómica con protección de iOS; los errores no modifican el estado publicado.
    private func persist(_ readings: [BloodPressureReading]) throws {
        guard !loadFailed else { throw ReadingStoreError.couldNotSave }
        do {
            let data = try encoder.encode(readings)
            let url = storageURL
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            throw ReadingStoreError.couldNotSave
        }
    }
}
