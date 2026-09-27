import XCTest
import PDFKit
import UserNotifications
import SwiftUI
import UIKit
@testable import MiTension

/// Regresiones con datos sintéticos: aíslan almacenamiento y permisos del histórico real del usuario.
/// Los tests de contratos también leen el código fuente para detectar cambios de navegación y seguridad.
final class ProductionTests: XCTestCase {
    func testExcelImportsOneTwoOrThreeReadingsForEachDayPeriod() throws {
        for count in 1...3 {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            var readings: [BloodPressureReading] = []
            for hour in [8, 20] {
                for minute in 0..<count {
                    let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: hour, minute: minute)))
                    readings.append(BloodPressureReading(systolic: 120 + minute, diastolic: 80, measuredAt: date, period: hour == 8 ? .morning : .evening))
                }
            }
            let file = try ExcelExport.make(readings: readings)
            defer { try? FileManager.default.removeItem(at: file) }
            let imported = try ExcelImport.read(url: file)
            XCTAssertEqual(imported.count, count * 2)
            XCTAssertEqual(imported.filter { $0.period == .morning }.count, count)
            XCTAssertEqual(imported.filter { $0.period == .evening }.count, count)
            XCTAssertEqual(Set(imported.map(\.id)), Set(readings.map(\.id)))
        }
    }
    @MainActor func testGuideIllustrationsAreBundledAndViewBuilds() throws {
        for name in ["GuidePosture", "GuideCuff"] {
            let image = try XCTUnwrap(UIImage(named: name))
            XCTAssertGreaterThan(image.size.width, 900)
            XCTAssertGreaterThan(image.size.height, 500)
        }
        let host = UIHostingController(rootView: NavigationStack { MeasurementGuideView() })
        host.loadViewIfNeeded()
        host.view.frame = CGRect(x: 0, y: 0, width: 375, height: 812)
        host.view.layoutIfNeeded()
        XCTAssertNotNil(host.view)
    }

    private final class SuspendedNotificationClient: ReminderNotificationClient {
        var pending: [UNNotificationRequest] = []
        var continuation: CheckedContinuation<Void, Never>?
        var suspendNext = true
        func permission() async throws -> Bool { true }
        func requests() async -> [UNNotificationRequest] { pending }
        func addRequest(_ request: UNNotificationRequest) async throws {
            if suspendNext {
                suspendNext = false
                await withCheckedContinuation { continuation = $0 }
            }
            pending.removeAll { $0.identifier == request.identifier }
            pending.append(request)
        }
        func removeRequests(_ identifiers: [String]) { pending.removeAll { identifiers.contains($0.identifier) } }
    }

    @MainActor func testSavingWhileSchedulingDoesNotRecreateCancelledFollowup() async throws {
        let client = SuspendedNotificationClient()
        let service = FollowupReminders(client: client)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 8))!
        var config = ReminderConfiguration(); config.morning.enabled = true
        let initial = Task { try await service.synchronize(configuration: config, readings: [], now: now, calendar: calendar) }
        for _ in 0..<1000 {
            if client.continuation != nil { break }
            await Task.yield()
        }
        let continuation = try XCTUnwrap(client.continuation)
        let reading = BloodPressureReading(systolic: 120, diastolic: 80, measuredAt: now, period: .morning)
        service.cancelSatisfied(readings: [reading], calendar: calendar)
        let updated = Task { try await service.synchronize(configuration: config, readings: [reading], now: now, calendar: calendar) }
        continuation.resume()
        try await initial.value
        try await updated.value
        XCTAssertEqual(client.pending.count, 20)
        XCTAssertFalse(client.pending.contains { $0.identifier == "mi-tension.followup.2026-9-27.morning" })
    }

    private final class AlarmClient: ReminderAlarmClient {
        var allowed = true
        var active = Set<UUID>()
        var schedules: [UUID: ReminderSchedule] = [:]
        var failNext = false
        func permission() async throws -> Bool { allowed }
        func activeIDs() throws -> Set<UUID> { active }
        func add(id: UUID, schedule: ReminderSchedule) async throws {
            if failNext { failNext = false; throw NSError(domain: "QA", code: 1) }
            active.insert(id); schedules[id] = schedule
        }
        func cancel(id: UUID) throws { active.remove(id); schedules[id] = nil }
    }

    func testOldReminderConfigurationDoesNotEnableAlarms() throws {
        let data = Data(#"{"morning":{"enabled":true,"hour":8,"minute":0,"weekdays":[2,3]},"evening":{"enabled":false,"hour":21,"minute":0,"weekdays":[1]}}"#.utf8)
        let configuration = try JSONDecoder().decode(ReminderConfiguration.self, from: data)
        XCTAssertFalse(configuration.morning.alarmEnabled)
        XCTAssertFalse(configuration.evening.alarmEnabled)
        XCTAssertTrue(configuration.morning.enabled)
    }

    func testAlarmsReplaceWithoutDuplicatesAndCancelOnlyOwnedAlarms() async throws {
        let suite = "AlarmTests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let client = AlarmClient()
        let other = UUID(); client.active.insert(other)
        let alarms = LocalAlarmReminders(preferences: preferences, client: client)
        var config = ReminderConfiguration()
        config.morning.enabled = true; config.morning.alarmEnabled = true
        config.morning.weekdays = [2, 4]; config.morning.hour = 9
        try await alarms.save(config)
        XCTAssertEqual(client.active.count, 2)
        XCTAssertEqual(client.schedules.values.first?.weekdays, [2, 4])
        try await alarms.save(config)
        XCTAssertEqual(client.active.count, 2)
        config.morning.alarmEnabled = false
        try await alarms.save(config)
        XCTAssertEqual(client.active, [other])
    }

    func testDeniedAndFailedAlarmSchedulingPreserveExistingAlarms() async throws {
        let suite = "AlarmTests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let client = AlarmClient()
        let alarms = LocalAlarmReminders(preferences: preferences, client: client)
        var config = ReminderConfiguration()
        config.evening.enabled = true; config.evening.alarmEnabled = true
        try await alarms.save(config)
        let original = client.active
        client.allowed = false
        let result = try await alarms.save(config)
        XCTAssertFalse(result)
        XCTAssertEqual(client.active, original)
        client.allowed = true; client.failNext = true
        do { try await alarms.save(config); XCTFail("Must report failure") } catch {}
        XCTAssertEqual(client.active, original)
        let encoded = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(ReminderConfiguration.self, from: encoded), config)
    }

    func testHistoryGroupsMorningAndNightEvenWithSingleReading() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7200)!
        func date(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
        }
        let morning = BloodPressureReading(systolic: 120, diastolic: 80, measuredAt: date(27, 8), period: .morning)
        let evening = BloodPressureReading(systolic: 125, diastolic: 82, measuredAt: date(27, 21), period: .evening)
        let single = BloodPressureReading(systolic: 122, diastolic: 81, measuredAt: date(26, 20), period: .evening)
        let groups = ReadingDayGroup.grouped([single, morning, evening], calendar: calendar)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].readings(in: .morning).map(\.id), [morning.id])
        XCTAssertEqual(groups[0].readings(in: .evening).map(\.id), [evening.id])
        XCTAssertTrue(groups[1].readings(in: .morning).isEmpty)
        XCTAssertEqual(groups[1].readings(in: .evening).map(\.id), [single.id])
        XCTAssertEqual(Set(groups.flatMap(\.readings).map(\.id)).count, 3)
    }

    private final class ReminderClient: ReminderNotificationClient {
        var allowed = true
        var pending: [UNNotificationRequest] = []
        var failNext = false
        func permission() async throws -> Bool { allowed }
        func requests() async -> [UNNotificationRequest] { pending }
        func addRequest(_ request: UNNotificationRequest) async throws {
            if failNext { throw NSError(domain:"QA",code:1) }
            pending.removeAll { $0.identifier == request.identifier }
            pending.append(request)
        }
        func removeRequests(_ identifiers: [String]) { pending.removeAll { identifiers.contains($0.identifier) } }
    }

    func testFollowupThirtyMinutesOnceAndCancelOnlyRecordedPeriod() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7200)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 7))!
        var config = ReminderConfiguration()
        config.morning.enabled = true; config.evening.enabled = true
        let plans = FollowupReminder.planned(configuration: config, readings: [], now: now, calendar: calendar)
        XCTAssertEqual(plans.count, 42)
        XCTAssertEqual(Set(plans.map(\.id)).count, 42)
        XCTAssertEqual(calendar.component(.hour, from: plans[0].date), 8)
        XCTAssertEqual(calendar.component(.minute, from: plans[0].date), 30)
        let reading = BloodPressureReading(systolic: 120, diastolic: 80, measuredAt: now, period: .morning)
        let completed = FollowupReminder.planned(configuration: config, readings: [reading], now: now, calendar: calendar)
        XCTAssertEqual(completed.count, 41)
        XCTAssertFalse(completed.contains { calendar.isDate($0.date, inSameDayAs: now) && $0.period == .morning })
        XCTAssertTrue(completed.contains { calendar.isDate($0.date, inSameDayAs: now) && $0.period == .evening })
    }

    func testFollowupCrossesMidnightAndHonorsWeekdays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 23))!
        var config = ReminderConfiguration()
        config.evening.enabled = true; config.evening.hour = 23; config.evening.minute = 50
        config.evening.weekdays = [1]
        let plans = FollowupReminder.planned(configuration: config, readings: [], now: now, calendar: calendar)
        XCTAssertEqual(plans.count, 3)
        XCTAssertEqual(calendar.component(.day, from: plans[0].date), 28)
        XCTAssertEqual(calendar.component(.hour, from: plans[0].date), 0)
        XCTAssertEqual(calendar.component(.minute, from: plans[0].date), 20)
        let afterMidnight = calendar.date(byAdding: .minute, value: 65, to: now)!
        XCTAssertEqual(FollowupReminder.planned(configuration: config, readings: [], now: afterMidnight, calendar: calendar).first, plans.first)
        let morning = BloodPressureReading(systolic: 120, diastolic: 80, measuredAt: calendar.startOfDay(for: now), period: .morning)
        XCTAssertEqual(FollowupReminder.planned(configuration: config, readings: [morning], now: now, calendar: calendar), plans)
    }

    @MainActor func testFollowupSaveCancelsAndDisableRemovesOnlyFollowups() async throws {
        let client = ReminderClient()
        let service = FollowupReminders(client: client)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 8))!
        var config = ReminderConfiguration(); config.morning.enabled = true
        let primary = UNNotificationRequest(identifier: "mi-tension.reminder.primary", content: UNMutableNotificationContent(), trigger: nil)
        client.pending = [primary]
        try await service.synchronize(configuration: config, readings: [], now: now, calendar: calendar)
        XCTAssertEqual(client.pending.count, 22)
        let reading = BloodPressureReading(systolic: 120, diastolic: 80, measuredAt: now, period: .morning)
        service.cancelSatisfied(readings: [reading], calendar: calendar)
        XCTAssertEqual(client.pending.count, 21)
        try await service.synchronize(configuration: config, readings: [reading], now: now, calendar: calendar)
        XCTAssertEqual(client.pending.count, 21)
        config.morning.enabled = false
        try await service.synchronize(configuration: config, readings: [], now: now, calendar: calendar)
        XCTAssertEqual(client.pending.map(\.identifier), [primary.identifier])
    }

    func testFollowupExpiredDoesNotRepeatAndDSTUsesLocalTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 9))!
        var config = ReminderConfiguration(); config.morning.enabled = true
        let plans = FollowupReminder.planned(configuration: config, readings: [], now: now, calendar: calendar)
        XCTAssertFalse(plans.contains { calendar.isDate($0.date, inSameDayAs: now) })
        XCTAssertTrue(plans.allSatisfy { calendar.component(.hour, from: $0.date) == 8 && calendar.component(.minute, from: $0.date) == 30 })
        XCTAssertEqual(plans.count, 20)
    }

    func testReminderSettingsPersistWhenPermissionIsDenied() async throws {
        let suite = "ReminderTests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { preferences.removePersistentDomain(forName:suite) }
        let client = ReminderClient(); client.allowed = false
        let reminders = LocalReminders(preferences:preferences,client:client)
        var config = ReminderConfiguration(); config.morning.enabled = true
        config.morning.hour = 9; config.morning.minute = 35; config.morning.weekdays = [2,4]
        let scheduled = try await reminders.save(config)
        XCTAssertFalse(scheduled)
        XCTAssertEqual(ReminderConfiguration.load(preferences:preferences),config)
        XCTAssertTrue(client.pending.isEmpty)
        client.allowed = true
        let retried = try await reminders.save(config)
        XCTAssertTrue(retried)
        XCTAssertEqual(client.pending.count,2)
    }

    func testReminderResaveReplacesRequestsAndDisablePersists() async throws {
        let suite = "ReminderTests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { preferences.removePersistentDomain(forName:suite) }
        let client = ReminderClient(); let reminders = LocalReminders(preferences:preferences,client:client)
        var config = ReminderConfiguration(); config.evening.enabled = true
        config.evening.hour = 20; config.evening.minute = 55; config.evening.weekdays = [2,3,4,5,6]
        _ = try await reminders.save(config); _ = try await reminders.save(config)
        XCTAssertEqual(client.pending.count,5)
        XCTAssertEqual(ReminderConfiguration.load(preferences:preferences),config)
        config.evening.enabled = false
        _ = try await reminders.save(config)
        XCTAssertTrue(client.pending.isEmpty)
        XCTAssertEqual(ReminderConfiguration.load(preferences:preferences),config)
    }

    func testInvalidReminderDaysKeepPreviousConfiguration() async throws {
        let suite = "ReminderTests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { preferences.removePersistentDomain(forName:suite) }
        let client = ReminderClient(); let reminders = LocalReminders(preferences:preferences,client:client)
        var config = ReminderConfiguration(); config.morning.enabled = true
        _ = try await reminders.save(config)
        var invalid = config; invalid.morning.weekdays = []
        do { _ = try await reminders.save(invalid); XCTFail("Empty days accepted") } catch { }
        XCTAssertEqual(ReminderConfiguration.load(preferences:preferences),config)
        XCTAssertEqual(client.pending.count,7)
    }

    func testReminderSchedulingFailureKeepsSettingsAndPriorRequests() async throws {
        let suite = "ReminderTests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { preferences.removePersistentDomain(forName:suite) }
        let client = ReminderClient(); let reminders = LocalReminders(preferences:preferences,client:client)
        var config = ReminderConfiguration(); config.morning.enabled = true
        _ = try await reminders.save(config)
        let old = client.pending.map(\.identifier)
        config.morning.hour = 10; client.failNext = true
        do { _ = try await reminders.save(config); XCTFail("Scheduling failure ignored") } catch { }
        XCTAssertEqual(ReminderConfiguration.load(preferences:preferences),config)
        XCTAssertEqual(client.pending.map(\.identifier),old)
    }
    private func sample(note: String = "QA", medications: [ReadingMedication] = []) -> BloodPressureReading {
        BloodPressureReading(systolic: 120, diastolic: 80, pulse: 65, measuredAt: Date(timeIntervalSince1970: 1_790_400_000), period: .morning, note: note, medications: medications)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ProductionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func backup(_ readings: [BloodPressureReading], at url: URL, version: Int = 1) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(ReadingsBackup(version: version, exportedAt: Date(), readings: readings)).write(to: url)
    }

    func testLegacyReadingAndMedicationRoundTrip() throws {
        let r = sample(medications: [ReadingMedication(name: "QA MED", dose: "QA", note: "日本語 العربية")])
        let encoded = try JSONEncoder().encode(r)
        XCTAssertEqual(try JSONDecoder().decode(BloodPressureReading.self, from: encoded), r)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "medications")
        let old = try JSONDecoder().decode(BloodPressureReading.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.id, r.id); XCTAssertTrue(old.medications.isEmpty)
    }

    func testIndependentPressureBoundaries() {
        for (sys,dia,s,d,u) in [(134,84,false,false,false),(135,84,true,false,false),(120,85,false,true,false),(135,85,true,true,false),(179,119,true,true,false),(180,80,true,false,true),(150,120,true,true,true)] {
            let r = BloodPressureReading(systolic: sys, diastolic: dia, measuredAt: Date(), period: .evening)
            XCTAssertEqual(r.systolicAboveReference,s); XCTAssertEqual(r.diastolicAboveReference,d); XCTAssertEqual(r.needsPromptAssessment,u)
        }
    }

    func testLocalizedDigitsAndInvalidNumericInput() {
        for value in ["120", "١٢٠", "۱۲۰", "１２０", " 120 "] { XCTAssertEqual(L10n.integer(value),120) }
        for value in ["", "abc", "12.5", "12 0", "-80", "1e2", "999999999999999999999999999999"] { XCTAssertNil(L10n.integer(value)) }
    }

    func testAutomaticPeriodUsesLocalTimeAndFourteenHourBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 2 * 3600))
        let formatter = ISO8601DateFormatter()
        let before = try XCTUnwrap(formatter.date(from:"2026-09-27T11:59:59Z"))
        let boundary = try XCTUnwrap(formatter.date(from:"2026-09-27T12:00:00Z"))
        XCTAssertEqual(DayPeriod.suggested(for:before,calendar:calendar),.morning)
        XCTAssertEqual(DayPeriod.suggested(for:boundary,calendar:calendar),.evening)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: -6 * 3600))
        XCTAssertEqual(DayPeriod.suggested(for:boundary,calendar:calendar),.morning)
    }

    @MainActor func testOld2055ReadingIsReclassifiedWithoutChangingItsValues() async throws {
        var r = sample()
        r.measuredAt = try XCTUnwrap(Calendar.current.date(bySettingHour:20,minute:55,second:0,of:Date()))
        r.period = .morning
        let url = try directory().appendingPathComponent("readings.json")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([r]).write(to:url)
        let store = ReadingStore(storageURL:url)
        XCTAssertEqual(store.readings[0].period,.evening)
        XCTAssertEqual(store.readings[0].id,r.id)
        XCTAssertEqual(store.readings[0].measuredAt,r.measuredAt)
        XCTAssertEqual(store.readings[0].systolic,r.systolic)
        XCTAssertEqual(ReadingStore(storageURL:url).readings[0].period,.evening)
    }

    @MainActor func testThreeReadingsAreSeparateAndSavedAtomically() async throws {
        let url = try directory().appendingPathComponent("readings.json")
        let store = ReadingStore(storageURL:url)
        let readings = [sample(note:"ONE"),sample(note:"TWO"),sample(note:"THREE")]
        try store.add(readings)
        XCTAssertEqual(store.readings.count,3)
        XCTAssertEqual(Set(store.readings.map(\.id)).count,3)
        XCTAssertEqual(ReadingStore(storageURL:url).readings.count,3)
        let previous = try Data(contentsOf:url)
        var invalid = sample(); invalid.diastolic = 0
        XCTAssertThrowsError(try store.add([sample(),sample(),invalid]))
        XCTAssertEqual(try Data(contentsOf:url),previous)
        XCTAssertEqual(store.readings.count,3)
    }

    @MainActor func testSavedMedicationSurvivesColdLoadWithoutChangingReading() async throws {
        let url = try directory().appendingPathComponent("readings.json")
        let store = ReadingStore(storageURL: url)
        let meds = [ReadingMedication(name: "QA MED", dose: "QA DOSE")]
        let reading = sample(medications: meds); try store.add(reading)
        let reopened = ReadingStore(storageURL: url)
        XCTAssertEqual(reopened.readings.count,1)
        XCTAssertEqual(reopened.readings[0].id,reading.id)
        XCTAssertEqual(reopened.readings[0].systolic,reading.systolic)
        XCTAssertEqual(reopened.readings[0].measuredAt,reading.measuredAt)
        XCTAssertEqual(reopened.readings[0].medications,meds)
    }

    @MainActor func testRestoreDeduplicatesAcrossAndWithinBackups() async throws {
        let dir = try directory(); let store = ReadingStore(storageURL: dir.appendingPathComponent("data.json"))
        let first = sample(); let second = sample(note: "SECOND")
        try store.add(first)
        let file = dir.appendingPathComponent("backup.json"); try backup([first,second,second],at:file)
        XCTAssertEqual(try store.restore(from:file),1)
        XCTAssertEqual(try store.restore(from:file),0)
        XCTAssertEqual(Set(store.readings.map(\.id)).count,2)
    }

    @MainActor func testUnsupportedOrInvalidBackupLeavesOriginalUnchanged() async throws {
        let dir = try directory(); let url = dir.appendingPathComponent("data.json")
        let store = ReadingStore(storageURL:url); try store.add(sample())
        let original = try Data(contentsOf:url)
        let file = dir.appendingPathComponent("backup.json")
        try backup([sample()],at:file,version:99)
        XCTAssertThrowsError(try store.restore(from:file))
        var invalid = sample(); invalid.pulse = 0
        try backup([invalid],at:file)
        XCTAssertThrowsError(try store.restore(from:file))
        XCTAssertEqual(try Data(contentsOf:url),original)
        XCTAssertEqual(store.readings.count,1)
    }

    @MainActor func testCorruptHistoryCannotBeOverwritten() async throws {
        let url = try directory().appendingPathComponent("readings.json")
        let damaged = Data("incomplete JSON".utf8); try damaged.write(to:url)
        let store = ReadingStore(storageURL:url)
        XCTAssertNotNil(store.persistenceError)
        XCTAssertThrowsError(try store.add(sample()))
        XCTAssertThrowsError(try store.backupFile())
        XCTAssertEqual(try Data(contentsOf:url),damaged)
    }

    @MainActor func testFailedWriteAndDuplicateAddDoNotMutateMemory() async throws {
        let dir = try directory()
        let missing = ReadingStore(storageURL:dir.appendingPathComponent("missing/data.json"))
        XCTAssertThrowsError(try missing.add(sample())); XCTAssertTrue(missing.readings.isEmpty)
        let store = ReadingStore(storageURL:dir.appendingPathComponent("data.json")); let r = sample()
        try store.add(r); XCTAssertThrowsError(try store.add(r)); XCTAssertEqual(store.readings.count,1)
    }

    func testExcelRoundTripPreservesIDsDatesAndStructuredMedications() throws {
        let reading = sample(note: "=1+1 & <texto> 中文", medications: [ReadingMedication(name: "Medicamento de prueba", dose: "dosis de prueba", note: "Primera línea\nSegunda línea")])
        let file = try ExcelExport.make(readings: [reading])
        let restored = try ExcelImport.read(url: file)
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.id, reading.id)
        XCTAssertEqual(restored.first?.systolic, reading.systolic)
        XCTAssertEqual(restored.first?.diastolic, reading.diastolic)
        XCTAssertEqual(restored.first?.pulse, reading.pulse)
        XCTAssertEqual(restored.first?.note, reading.note)
        XCTAssertEqual(restored.first?.medications, reading.medications)
        XCTAssertEqual(try XCTUnwrap(restored.first).measuredAt.timeIntervalSince1970, reading.measuredAt.timeIntervalSince1970, accuracy: 0.001)
    }

    @MainActor func testExcelImportIsAtomicAndDoesNotDuplicateOrOverwriteExistingReadings() throws {
        let dir = try directory()
        let first = sample(), second = sample(note: "Segundo registro")
        let store = ReadingStore(storageURL: dir.appendingPathComponent("readings.json"))
        try store.add(first)
        let file = try ExcelExport.make(readings: [first, second])
        XCTAssertEqual(try store.importExcel(from: file), 1)
        XCTAssertEqual(try store.importExcel(from: file), 0)
        XCTAssertEqual(store.readings.count, 2)
        var invalid = sample(); invalid.diastolic = 200
        let malformed = try ExcelExport.make(readings: [sample(), invalid])
        XCTAssertThrowsError(try store.importExcel(from: malformed))
        XCTAssertEqual(store.readings.count, 2)
        let reopened = ReadingStore(storageURL: dir.appendingPathComponent("readings.json"))
        XCTAssertEqual(Set(reopened.readings.map(\.id)), [first.id, second.id])
    }

    func testExcelImportSupportsDeflateAndSharedStringsAndRejectsFormulas() throws {
        let dir = try directory()
        let id = UUID()
        func fixture(formula: String = "") -> Data {
            let sheet = """
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="G1" t="s"><v>0</v></c></row><row r="2"><c r="A2"><v>46000</v></c><c r="C2">\(formula)<v>120</v></c><c r="D2"><v>80</v></c><c r="F2" t="s"><v>1</v></c><c r="G2" t="inlineStr"><is><t>\(id.uuidString)</t></is></c></row></sheetData></worksheet>
            """
            return ExcelExport.archive([("xl/worksheets/sheet1.xml", sheet), ("xl/sharedStrings.xml", "<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><si><t>ID</t></si><si><r><t>Texto </t></r><r><t>中文 &amp; prueba</t></r></si></sst>")], compress: true)
        }
        let file = dir.appendingPathComponent("compressed.xlsx")
        try fixture().write(to: file)
        let readings = try ExcelImport.read(url: file)
        XCTAssertEqual(readings.first?.id, id)
        XCTAssertEqual(readings.first?.note, "Texto 中文 & prueba")
        try fixture(formula: "<f>100+20</f>").write(to: file)
        XCTAssertThrowsError(try ExcelImport.read(url: file))
    }

    func testExcelImportRejectsCorruptAndTruncatedArchives() throws {
        let file = try ExcelExport.make(readings: [sample()])
        var data = try Data(contentsOf: file)
        let range = try XCTUnwrap(data.range(of: Data("<worksheet".utf8)))
        data[range.lowerBound] ^= 1
        try data.write(to: file)
        XCTAssertThrowsError(try ExcelImport.read(url: file))
        try Data(data.prefix(40)).write(to: file)
        XCTAssertThrowsError(try ExcelImport.read(url: file))
    }

    func testExcelEscapesUserContentAndRetainsMedicationColumn() throws {
        let r = sample(note:"=1+1 & <QA>",medications:[ReadingMedication(name:"QA & <MED>",dose:"=SUM(1,2)")])
        let file = try ExcelExport.make(readings:[r])
        let bytes = try Data(contentsOf:file)
        XCTAssertEqual(Array(bytes.prefix(2)),[0x50,0x4b])
        let xml = String(decoding:bytes,as:UTF8.self)
        XCTAssertTrue(xml.contains("r=\"H2\""))
        XCTAssertTrue(xml.contains("&amp; &lt;MED&gt;"))
        XCTAssertFalse(xml.contains("<f>"))
        XCTAssertTrue(xml.contains(r.id.uuidString))
        let second = try ExcelExport.make(readings:[r]); XCTAssertNotEqual(file,second)
        XCTAssertThrowsError(try ExcelExport.make(readings:[sample(note:String(repeating:"a",count:32_768))]))
    }

    @MainActor func testBackupRoundTripAndDeletionArePersisted() async throws {
        let dir = try directory()
        let suite = "MiTensionTests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { preferences.removePersistentDomain(forName:suite) }
        let original = ReadingStore(storageURL:dir.appendingPathComponent("original.json"),preferences:preferences)
        let r = sample(medications:[ReadingMedication(name:"QA MED")]); try original.add(r)
        let copy = try original.backupFile(); XCTAssertNotNil(original.lastBackupDate)
        let destination = dir.appendingPathComponent("destination.json")
        let restored = ReadingStore(storageURL:destination,preferences:preferences)
        XCTAssertEqual(try restored.restore(from:copy),1); XCTAssertEqual(restored.readings,[r])
        restored.delete(id:r.id)
        XCTAssertTrue(ReadingStore(storageURL:destination,preferences:preferences).readings.isEmpty)
    }

    func testPDFPaginatesBusyDayAndOneVeryLongMedication() throws {
        var readings = (0..<40).map { sample(note:"QA-ROW-\($0)-END") }
        readings[0].medications = [ReadingMedication(name:"QA MED",note:(0..<180).map { "QA-LINE-\($0)-END" }.joined(separator:"\n"))]
        let url = try ReportPDFGenerator.make(readings:readings,periodTitle:"QA")
        let pdf = try XCTUnwrap(PDFDocument(url:url))
        XCTAssertGreaterThan(pdf.pageCount,3)
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at:$0)?.string }.joined(separator:"\n")
        for i in 0..<40 { XCTAssertTrue(text.contains("QA-ROW-\(i)-END"),"Missing reading \(i)") }
        for i in 0..<180 { XCTAssertTrue(text.contains("QA-LINE-\(i)-END"),"Missing medication line \(i)") }
        for page in 0..<pdf.pageCount {
            let p = try XCTUnwrap(pdf.page(at:page))
            let selection = p.selection(for: p.bounds(for:.mediaBox))
            XCTAssertFalse(selection?.string?.isEmpty ?? true)
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("production-qa-report.pdf")
        try Data(contentsOf:url).write(to:output)
        print("QA_PDF_PATH: \(output.path)")
    }

    func testMoreToolsCatalogListsTheFourLeadingRows() {
        XCTAssertEqual(MoreToolsRow.allCases.map(\.rawValue), ["alerts", "guide", "excel", "backup"])
        XCTAssertEqual(MoreToolsRow.allCases.map(\.titleKey), [
            "Alertas", "Guía y privacidad", "Exportar a Excel", "Importar registros de Excel",
        ])
        XCTAssertEqual(MoreToolsCopy.titleKey, "Cuida tu rutina")
        XCTAssertEqual(MoreToolsCopy.leadKey, "Guía, avisos y tus datos, en un solo lugar.")
        XCTAssertEqual(MoreToolsCopy.storedKey, "Guardado en este iPhone")
    }

    func testMoreToolsCopyExistsInTheStringCatalog() throws {
        let keys = [MoreToolsCopy.titleKey, MoreToolsCopy.leadKey, MoreToolsCopy.storedKey]
            + MoreToolsRow.allCases.flatMap { [$0.titleKey, $0.subtitleKey] }
        let catalog = try String(contentsOf: moreToolsCatalogURL(), encoding: .utf8)
        for key in keys {
            XCTAssertTrue(catalog.contains("\"\(key)\""), "Falta la clave «\(key)» en Localizable.xcstrings")
            let needle = "\"\(key)\":"
            let start = try XCTUnwrap(catalog.range(of: needle), "No se pudo abrir «\(key)»")
            let rest = catalog[start.upperBound...]
            let chunk = String(rest.prefix(900))
            XCTAssertTrue(chunk.contains("\"es\""), "«\(key)» no tiene español")
            XCTAssertTrue(chunk.contains("\"en\""), "«\(key)» no tiene inglés")
        }
    }

    func testMoreToolsViewSourceKeepsLeadingLayoutAndPlainButtons() throws {
        let source = try moreToolsViewSource()
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertTrue(source.contains(".multilineTextAlignment(.leading)"))
        XCTAssertGreaterThanOrEqual(source.components(separatedBy: ".buttonStyle(.plain)").count - 1, 4)
        XCTAssertFalse(source.contains("VStack(alignment: .center"))
        XCTAssertFalse(source.contains(".multilineTextAlignment(.center)"))
        let buttons = source.components(separatedBy: "Button {").count - 1
        let links = source.components(separatedBy: "NavigationLink {").count - 1
        XCTAssertEqual(buttons, 1, "Alertas es el único Button de la lista")
        XCTAssertEqual(links, 3, "Guía, Excel y copia son NavigationLink")
    }

    @MainActor func testMoreToolsViewBuildsWithoutCrashing() {
        let view = MoreToolsView().environmentObject(ReadingStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("more-tools-\(UUID().uuidString).json")))
        let host = UIHostingController(rootView: view)
        host.loadViewIfNeeded()
        XCTAssertNotNil(host.view)
    }

    private func moreToolsViewSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MiTension/Views/FeaturesView.swift")
        let all = try String(contentsOf: url, encoding: .utf8)
        let start = try XCTUnwrap(all.range(of: "struct MoreToolsView: View {")?.lowerBound)
        let end = try XCTUnwrap(all.range(of: "struct ExcelExportView: View {")?.lowerBound)
        return String(all[start..<end])
    }

    private func moreToolsCatalogURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MiTension/Localizable.xcstrings")
    }
}
