import SwiftUI
import UserNotifications
import AlarmKit

/// Horario semanal local con avisos opcionales. Las alarmas permanecen desactivadas por defecto.
struct ReminderSchedule: Codable, Equatable {
    var enabled = false
    var hour: Int
    var minute = 0
    var weekdays = [1, 2, 3, 4, 5, 6, 7]
    var alarmEnabled = false

    init(hour: Int) { self.hour = hour }
    private enum CodingKeys: String, CodingKey { case enabled, hour, minute, weekdays, alarmEnabled }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        hour = try values.decode(Int.self, forKey: .hour)
        minute = try values.decode(Int.self, forKey: .minute)
        weekdays = try values.decode([Int].self, forKey: .weekdays)
        alarmEnabled = try values.decodeIfPresent(Bool.self, forKey: .alarmEnabled) ?? false
    }

    var time: Date {
        get { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date() }
        set {
            hour = Calendar.current.component(.hour, from: newValue)
            minute = Calendar.current.component(.minute, from: newValue)
        }
    }
}

/// Preferencias persistidas para mañana y noche, separadas de las mediciones.
struct ReminderConfiguration: Codable, Equatable {
    var morning = ReminderSchedule(hour: 8)
    var evening = ReminderSchedule(hour: 21)
    static func load(preferences: UserDefaults = .standard) -> Self {
        guard let data = preferences.data(forKey: "localReminderConfiguration"),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
}

/// Plan de segundo aviso único a los 30 minutos cuando falta una toma del día y periodo.
struct FollowupReminder: Equatable {
    let id: String
    let date: Date
    let period: DayPeriod
    static let prefix = "mi-tension.followup."

    /// Planifica 21 días y contempla el día anterior para avisos que cruzan medianoche.
    static func planned(configuration: ReminderConfiguration, readings: [BloodPressureReading], now: Date = Date(), calendar: Calendar = .current) -> [Self] {
        var result: [Self] = []
        let start = calendar.startOfDay(for: now)
        for offset in -1..<21 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            for (period, schedule) in [(DayPeriod.morning, configuration.morning), (.evening, configuration.evening)] where schedule.enabled {
                guard schedule.weekdays.contains(calendar.component(.weekday, from: day)),
                      let original = calendar.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: day),
                      let followup = calendar.date(byAdding: .minute, value: 30, to: original), followup > now,
                      !readings.contains(where: { calendar.isDate($0.measuredAt, inSameDayAs: day) && DayPeriod.suggested(for: $0.measuredAt, calendar: calendar) == period }) else { continue }
                let parts = calendar.dateComponents([.year, .month, .day], from: day)
                let id = prefix + "\(parts.year!)-\(parts.month!)-\(parts.day!).\(period.rawValue)"
                result.append(Self(id: id, date: followup, period: period))
            }
        }
        return result.sorted { $0.date < $1.date }
    }
}

@MainActor
/// Sincroniza segundos avisos serializando tareas; una revisión evita reintroducir avisos ya cancelados.
final class FollowupReminders: ObservableObject {
    static let shared = FollowupReminders()
    @Published private(set) var errorMessage: String?
    private let client: any ReminderNotificationClient
    private var currentTask: Task<Void, Error>?
    private var revision = 0

    init(client: any ReminderNotificationClient = SystemReminderNotificationClient()) { self.client = client }

    /// Cancela inmediatamente los avisos satisfechos tras guardar, sin tocar los avisos principales.
    func cancelSatisfied(readings: [BloodPressureReading], calendar: Calendar = .current) {
        revision += 1
        let ids = Set(readings.map { reading in
            let parts = calendar.dateComponents([.year, .month, .day], from: reading.measuredAt)
            let period = DayPeriod.suggested(for: reading.measuredAt, calendar: calendar)
            return FollowupReminder.prefix + "\(parts.year!)-\(parts.month!)-\(parts.day!).\(period.rawValue)"
        })
        client.removeRequests(Array(ids))
    }

    /// Reconcilia solo su espacio de IDs. Reabrir la app renueva el horizonte limitado de avisos.
    func synchronize(configuration: ReminderConfiguration, readings: [BloodPressureReading], now: Date = Date(), calendar: Calendar = .current) async throws {
        revision += 1
        let version = revision
        let previous = currentTask
        let task = Task { @MainActor in
            let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "MiTension.followups", expirationHandler: nil)
            defer { if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) } }
            _ = try? await previous?.value
            guard version == revision else { return }
            do {
                let desired = FollowupReminder.planned(configuration: configuration, readings: readings, now: now, calendar: calendar)
                let old = await client.requests().filter { $0.identifier.hasPrefix(FollowupReminder.prefix) }
                guard version == revision else { return }
                let desiredIDs = Set(desired.map(\.id))
                // Cancel missing/completed slots first, and leave primary reminders untouched.
                client.removeRequests(old.filter { !desiredIDs.contains($0.identifier) }.map(\.identifier))
                for plan in desired {
                    guard version == revision else { return }
                    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plan.date)
                    var datedComponents = components
                    datedComponents.calendar = calendar
                    datedComponents.timeZone = calendar.timeZone
                    let content = UNMutableNotificationContent()
                    content.title = NSString.localizedUserNotificationString(forKey: "Hora de tomar la tensión", arguments: nil)
                    content.body = NSString.localizedUserNotificationString(forKey: "Han pasado 30 minutos y no has guardado la toma de este periodo. Regístrala cuando puedas.", arguments: nil)
                    content.sound = .default
                    let trigger = UNCalendarNotificationTrigger(dateMatching: datedComponents, repeats: false)
                    try await client.addRequest(UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger))
                    if version != revision { client.removeRequests([plan.id]); return }
                }
                errorMessage = nil
            } catch {
                errorMessage = L10n.text("No se pudo actualizar el segundo aviso. Revisa los permisos de notificaciones y vuelve a abrir Alertas.")
                throw error
            }
        }
        currentTask = task
        try await task.value
    }
}

/// Abstracción inyectable de notificaciones para probar permisos y errores sin cambiar el dispositivo real.
protocol ReminderNotificationClient {
    func permission() async throws -> Bool
    func requests() async -> [UNNotificationRequest]
    func addRequest(_ request: UNNotificationRequest) async throws
    func removeRequests(_ identifiers: [String])
}

/// Adaptador del centro de notificaciones de iOS; no utiliza servicios remotos.
struct SystemReminderNotificationClient: ReminderNotificationClient {
    func permission() async throws -> Bool { try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    func requests() async -> [UNNotificationRequest] { await UNUserNotificationCenter.current().pendingNotificationRequests() }
    func addRequest(_ request: UNNotificationRequest) async throws { try await UNUserNotificationCenter.current().add(request) }
    func removeRequests(_ identifiers: [String]) { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers) }
}

/// Avisos semanales principales. Guarda preferencias incluso cuando el permiso es denegado.
final class LocalReminders: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LocalReminders()
    private let prefix = "mi-tension.reminder."
    private let preferences: UserDefaults
    private let client: any ReminderNotificationClient

    init(preferences: UserDefaults = .standard, client: any ReminderNotificationClient = SystemReminderNotificationClient()) {
        self.preferences = preferences
        self.client = client
        super.init()
    }

    func testNotification() async throws {
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else {
            throw NSError(domain: "Reminders", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.text("Activa las notificaciones en Ajustes para recibir avisos.")])
        }
        let content = UNMutableNotificationContent()
        content.title = NSString.localizedUserNotificationString(forKey: "Hora de tomar la tensión", arguments: nil)
        content.body = NSString.localizedUserNotificationString(forKey: "Descansa unos minutos y registra tu toma en Mi Tensión.", arguments: nil)
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        try await center.add(UNNotificationRequest(identifier: prefix + "test", content: content, trigger: trigger))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    @discardableResult func save(_ configuration: ReminderConfiguration) async throws -> Bool {
        let schedules = [configuration.morning, configuration.evening]
        guard schedules.allSatisfy({ !$0.enabled || !$0.weekdays.isEmpty }) else {
            throw NSError(domain: "Reminders", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.text("Selecciona al menos un día.")])
        }
        let data = try JSONEncoder().encode(configuration)
        // Keep the user's valid configuration even when permission or scheduling fails.
        preferences.set(data, forKey: "localReminderConfiguration")
        if schedules.contains(where: { $0.enabled }) {
            guard try await client.permission() else { return false }
        }
        let old = await client.requests().filter { $0.identifier.hasPrefix(prefix) }
        let generation = UUID().uuidString
        var added: [String] = []
        do {
            for (index, schedule) in schedules.enumerated() where schedule.enabled {
                for weekday in schedule.weekdays {
                    let id = prefix + generation + ".\(index).\(weekday)"
                    let content = UNMutableNotificationContent()
                    content.title = NSString.localizedUserNotificationString(forKey: "Hora de tomar la tensión", arguments: nil)
                    content.body = NSString.localizedUserNotificationString(forKey: "Descansa unos minutos y registra tu toma en Mi Tensión.", arguments: nil)
                    content.sound = .default
                    let components = DateComponents(hour: schedule.hour, minute: schedule.minute, weekday: weekday)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    try await client.addRequest(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                    added.append(id)
                }
            }
        } catch {
            client.removeRequests(added)
            throw error
        }
        client.removeRequests(old.map(\.identifier))
        return true
    }
}

/// Interfaz inyectable de alarmas, independiente de los permisos de notificaciones.
protocol ReminderAlarmClient {
    func permission() async throws -> Bool
    func activeIDs() throws -> Set<UUID>
    func add(id: UUID, schedule: ReminderSchedule) async throws
    func cancel(id: UUID) throws
}

/// Adaptador AlarmKit disponible desde iOS 26; versiones anteriores conservan las notificaciones.
struct SystemReminderAlarmClient: ReminderAlarmClient {
    func permission() async throws -> Bool {
        if #available(iOS 26.0, *) { return try await AlarmManager.shared.requestAuthorization() == .authorized }
        return false
    }
    func activeIDs() throws -> Set<UUID> {
        if #available(iOS 26.0, *) { return Set(try AlarmManager.shared.alarms.map(\.id)) }
        return []
    }
    func add(id: UUID, schedule: ReminderSchedule) async throws {
        if #available(iOS 26.0, *) {
            let weekdays: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
            let recurrence = schedule.weekdays.map { weekdays[$0 - 1] }
            let relative = Alarm.Schedule.Relative(time: .init(hour: schedule.hour, minute: schedule.minute), repeats: .weekly(recurrence))
            try await scheduleAlarm(id: id, schedule: .relative(relative))
        } else {
            throw NSError(domain: "Reminders", code: 3, userInfo: [NSLocalizedDescriptionKey: L10n.text("La alarma sonora está disponible desde iOS 26.")])
        }
    }
    @available(iOS 26.0, *)
    func scheduleAlarm(id: UUID, schedule: Alarm.Schedule) async throws {
            let alert: AlarmPresentation.Alert
            if #available(iOS 26.1, *) {
                alert = AlarmPresentation.Alert(title: "Hora de tomar la tensión")
            } else {
                alert = AlarmPresentation.Alert(title: "Hora de tomar la tensión", stopButton: AlarmButton(text: "Cerrar", textColor: .white, systemImageName: "stop.circle"))
            }
            let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert), metadata: TensionAlarmMetadata(), tintColor: Color.aquaDark)
            let configuration = AlarmManager.AlarmConfiguration.alarm(schedule: schedule, attributes: attributes)
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }
    func cancel(id: UUID) throws {
        if #available(iOS 26.0, *) { try AlarmManager.shared.cancel(id: id) }
    }
}

@available(iOS 26.0, *)
/// Metadatos vacíos de AlarmKit: no incluyen mediciones ni medicamentos.
private struct TensionAlarmMetadata: AlarmMetadata {}

/// Administra únicamente los UUID de alarmas propios y revierte altas si falla una actualización.
final class LocalAlarmReminders {
    static let shared = LocalAlarmReminders()
    private let preferences: UserDefaults
    private let client: any ReminderAlarmClient
    private let key = "MiTension.ownedAlarmIDs"

    init(preferences: UserDefaults = .standard, client: any ReminderAlarmClient = SystemReminderAlarmClient()) {
        self.preferences = preferences
        self.client = client
    }

    @available(iOS 26.0, *)
    func testAlarm() async throws {
        guard try await client.permission() else {
            throw NSError(domain: "Reminders", code: 4, userInfo: [NSLocalizedDescriptionKey: L10n.text("Configuración guardada. Permite las alarmas en Ajustes para que suenen.")])
        }
        let testKey = "MiTension.testAlarmID"
        if let value = preferences.string(forKey: testKey), let previous = UUID(uuidString: value), try client.activeIDs().contains(previous) {
            try client.cancel(id: previous)
        }
        let id = UUID()
        preferences.set(id.uuidString, forKey: testKey)
        try await SystemReminderAlarmClient().scheduleAlarm(id: id, schedule: .fixed(Date().addingTimeInterval(10)))
    }

    @discardableResult func save(_ configuration: ReminderConfiguration) async throws -> Bool {
        let schedules = [configuration.morning, configuration.evening].filter { $0.enabled && $0.alarmEnabled }
        guard schedules.allSatisfy({ !$0.weekdays.isEmpty && $0.weekdays.allSatisfy { (1...7).contains($0) } && (0...23).contains($0.hour) && (0...59).contains($0.minute) }) else {
            throw NSError(domain: "Reminders", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.text("Selecciona al menos un día.")])
        }
        if !schedules.isEmpty, try await !client.permission() { return false }
        let old = Set((preferences.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:)))
        let active = try client.activeIDs()
        var added: [UUID] = []
        do {
            for schedule in schedules {
                let id = UUID()
                // Track before scheduling so a failed cleanup can be retried on the next save.
                added.append(id)
                preferences.set(Array(old.union(added)).map(\.uuidString), forKey: key)
                try await client.add(id: id, schedule: schedule)
            }
            for id in old.intersection(active) { try client.cancel(id: id) }
            preferences.set(added.map(\.uuidString), forKey: key)
            return true
        } catch {
            var remaining = old
            for id in added {
                do { try client.cancel(id: id) } catch { remaining.insert(id) }
            }
            preferences.set(remaining.map(\.uuidString), forKey: key)
            throw error
        }
    }
}

/// Configuración de horarios, días y permisos, con prueba voluntaria de avisos y alarmas.
struct ReminderSettingsView: View {
    @EnvironmentObject private var store: ReadingStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var configuration = ReminderConfiguration.load()
    @State private var savedConfiguration = ReminderConfiguration.load()
    @State private var saving = false
    @State private var message: String?
    @State private var denied = false
    @State private var alarmsDenied = false
    @State private var saved = false
    @State private var pendingCount = 0
    @State private var pendingFollowupCount = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(L10n.text("Recordatorios para tus tomas"), systemImage: "bell.badge")
                    Text(L10n.text("Elige horarios y días para la mañana y la noche. Los avisos están desactivados inicialmente."))
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let message {
                        Label(message, systemImage: saved ? "checkmark.circle" : "exclamationmark.circle")
                            .foregroundStyle(saved ? Color.aquaDark : Color.primary)
                    }
                    if denied {
                        Button(L10n.text("Abrir ajustes de notificaciones")) {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                    if alarmsDenied {
                        Button(L10n.text("Abrir ajustes de alarmas")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }
                scheduleSection(DayPeriod.morning.title, schedule: $configuration.morning)
                scheduleSection(DayPeriod.evening.title, schedule: $configuration.evening)
                Section {
                    Text(L10n.format("Avisos programados: %ld", pendingCount))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(L10n.format("Segundos avisos programados: %ld", pendingFollowupCount))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button { applySettings() } label: {
                        HStack {
                            Text(L10n.text("Guardar alertas"))
                            Spacer()
                            if saving { ProgressView() }
                        }
                    }
                    .disabled(saving)
                    Button(L10n.text("Probar aviso en 10 segundos")) {
                        saving = true
                        Task { @MainActor in
                            do {
                                try await LocalReminders.shared.testNotification()
                                saved = true
                                message = L10n.text("Aviso de prueba programado.")
                            } catch {
                                saved = false
                                message = error.localizedDescription
                            }
                            saving = false
                            await refreshPermission()
                        }
                    }
                    if #available(iOS 26.0, *) {
                        Button(L10n.text("Probar alarma en 10 segundos")) {
                            saving = true
                            Task { @MainActor in
                                do {
                                    try await LocalAlarmReminders.shared.testAlarm()
                                    saved = true
                                    message = L10n.text("Alarma de prueba programada.")
                                } catch {
                                    saved = false
                                    message = error.localizedDescription
                                }
                                saving = false
                                await refreshPermission()
                            }
                        }
                    }
                }
                Section(L10n.text("Información")) {
                    Text(L10n.text("Si no guardas una toma de ese día y periodo, recibirás una segunda notificación con sonido 30 minutos después. Solo se repite una vez. Se preparan los próximos 21 días y se renuevan al abrir la app; abre Mi Tensión al menos cada tres semanas. La alarma del sistema no se repite."))
                    Text(L10n.text("La alarma sonora requiere iOS 26 y permiso de alarmas. Puede sonar en silencio o con Concentración, aunque la app esté cerrada. Desactívala si prefieres solo la notificación."))
                    Text(L10n.text("Los avisos se programan en este iPhone, sin enviar datos a servidores. Funcionan aunque la app esté cerrada."))
                    Text(L10n.text("Debes permitir las notificaciones. El modo Concentración y los ajustes de sonido pueden silenciar o retrasar los avisos."))
                Text(L10n.text("Son recordatorios, no alarmas médicas: no detectan valores de tensión ni sustituyen las indicaciones de tu médico."))
                    Text(L10n.text("Guardar aplica los cambios. Cerrar también guarda los cambios pendientes. Sin permiso de notificaciones, la configuración se conserva pero los avisos no se mostrarán."))
                }.font(.footnote)
            }
            .disabled(saving)
            .navigationTitle(L10n.text("Alertas"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("Cerrar")) {
                        if configuration != savedConfiguration { applySettings(close: true) } else { dismiss() }
                    }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Guardar")) { applySettings() }.disabled(saving) }
            }
            .interactiveDismissDisabled(saving || configuration != savedConfiguration)
            .task {
                configuration = ReminderConfiguration.load()
                savedConfiguration = configuration
                await refreshPermission()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refreshPermission() } }
            }
        }
    }

    private func applySettings(close: Bool = false) {
        guard !saving else { return }
        saving = true
        saved = false
        message = nil
        Task { @MainActor in
            do {
                let scheduled = try await LocalReminders.shared.save(configuration)
                try await FollowupReminders.shared.synchronize(configuration: configuration, readings: store.readings)
                let alarmsScheduled = try await LocalAlarmReminders.shared.save(configuration)
                savedConfiguration = configuration
                saved = scheduled && alarmsScheduled
                message = L10n.text(!alarmsScheduled ? "Configuración guardada. Permite las alarmas en Ajustes para que suenen." : scheduled ? "Alertas guardadas." : "Configuración guardada. Activa las notificaciones en Ajustes para recibir avisos.")
                if close && saved { dismiss() }
            } catch {
                savedConfiguration = ReminderConfiguration.load()
                message = error.localizedDescription
            }
            saving = false
            await refreshPermission()
        }
    }

    private func scheduleSection(_ title: String, schedule: Binding<ReminderSchedule>) -> some View {
        Section(title) {
            Toggle(L10n.text("Activar aviso"), isOn: schedule.enabled)
            if schedule.wrappedValue.enabled {
                DatePicker(L10n.text("Hora"), selection: schedule.time, displayedComponents: .hourAndMinute)
                if #available(iOS 26.0, *) {
                    Toggle(L10n.text("Alarma sonora además de la notificación"), isOn: schedule.alarmEnabled)
                } else {
                    Text(L10n.text("La alarma sonora está disponible desde iOS 26."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(L10n.text("Días de la semana")).font(.subheadline).foregroundStyle(.secondary)
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                    Toggle(Calendar.current.weekdaySymbols[weekday - 1].capitalized, isOn: Binding(
                        get: { schedule.wrappedValue.weekdays.contains(weekday) },
                        set: { enabled in
                            schedule.wrappedValue.weekdays.removeAll { $0 == weekday }
                            if enabled { schedule.wrappedValue.weekdays.append(weekday) }
                        }
                    ))
                }
            }
        }
    }

    @MainActor private func refreshPermission() async {
        denied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
        if #available(iOS 26.0, *) { alarmsDenied = AlarmManager.shared.authorizationState == .denied }
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        pendingCount = requests.filter { $0.identifier.hasPrefix("mi-tension.reminder.") && ($0.trigger?.repeats ?? false) }.count
        pendingFollowupCount = requests.filter { $0.identifier.hasPrefix(FollowupReminder.prefix) }.count
    }
}

/// Navegación horizontal principal y renovación de periodos/avisos al activar la app.
struct RootView: View {
    @EnvironmentObject private var store: ReadingStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingAddReading = false
    @State private var selectedPage = 0
    @State private var showingMore = false
    @StateObject private var followups = FollowupReminders.shared
    @Environment(\.layoutDirection) private var layoutDirection
    private let sections = [L10n.text("Resumen"), L10n.text("Histórico"), L10n.text("Gráficas"), L10n.text("Médico")]
    private let symbols = ["square.grid.2x2.fill", "clock.arrow.circlepath", "chart.xyaxis.line", "doc.text"]

    var body: some View {
        TabView(selection: $selectedPage) {
            NavigationStack {
                DashboardView(showingAddReading: $showingAddReading, showingMore: $showingMore)
            }
            .tag(0)

            NavigationStack { HistoryView().toolbar { moreButton } }.tag(1)

            NavigationStack { TrendsView().toolbar { moreButton } }
                .tag(2)

            NavigationStack { MedicalReportView().toolbar { moreButton } }.tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .top) {
            if let error = store.persistenceError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(Color.primary)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.coral.opacity(0.12))
            }
            if let error = followups.errorMessage {
                Label(error, systemImage: "bell.badge")
                    .font(.footnote).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.coral.opacity(0.12))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(sections.indices, id: \.self) { index in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { selectedPage = index }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: symbols[index]).font(.system(size: 19))
                            Text(sections[index]).font(.system(size: 11, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(selectedPage == index ? Color.aquaDark : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(selectedPage == index ? Color.aquaDark.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedPage == index ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .simultaneousGesture(horizontalNavigation)
        }
        .sheet(isPresented: $showingAddReading) { AddReadingView() }
        .sheet(isPresented: $showingMore) { MoreToolsView() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshPeriods(); refreshFollowups() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in store.refreshPeriods(); refreshFollowups() }
        .onChange(of: store.readings) { _, _ in refreshFollowups() }
        .task { refreshFollowups() }
    }

    private func refreshFollowups() {
        let readings = store.readings
        let configuration = ReminderConfiguration.load()
        Task { try? await followups.synchronize(configuration: configuration, readings: readings) }
    }

    private var moreButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingMore = true } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel(L10n.text("Más"))
        }
    }

    private var horizontalNavigation: some Gesture {
        DragGesture(minimumDistance: 35).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
            let direction = (value.translation.width < 0 ? 1 : -1) * (layoutDirection == .rightToLeft ? -1 : 1)
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedPage = min(max(selectedPage + direction, 0), sections.count - 1)
            }
        }
    }
}

/// Histórico por día y periodo con eliminación confirmada de tomas individuales.
private struct HistoryView: View {
    @EnvironmentObject private var store: ReadingStore
    @State private var days: Int? = nil
    @State private var period: DayPeriod?
    @State private var readingToDelete: BloodPressureReading?

    private var readings: [BloodPressureReading] {
        store.readings(inLastDays: days).filter {
            period == nil || $0.period == period
        }
    }
    private var dayGroups: [ReadingDayGroup] {
        ReadingDayGroup.grouped(readings)
    }

    var body: some View {
        List {
            Section {
                Picker(L10n.text("Periodo"), selection: $days) {
                    Text(L10n.text("7 días")).tag(Optional(7))
                    Text(L10n.text("30 días")).tag(Optional(30))
                    Text(L10n.text("Todo")).tag(Optional<Int>.none)
                }.pickerStyle(.segmented)
                Picker(L10n.text("Momento"), selection: $period) {
                    Text(L10n.text("Todas")).tag(Optional<DayPeriod>.none)
                    ForEach(DayPeriod.allCases) { Text($0.title).tag(Optional($0)) }
                }.pickerStyle(.segmented)
                Text(L10n.format("Tomas guardadas en este iPhone: %ld", readings.count))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if readings.isEmpty {
                ContentUnavailableView(L10n.text("Sin tomas en este periodo"), systemImage: "clock.arrow.circlepath")
            }
            ForEach(dayGroups) { day in
                Section(day.date.formatted(date: .complete, time: .omitted)) {
                    ForEach(DayPeriod.allCases.filter { period == nil || $0 == period }) { dayPeriod in
                        ReadingPeriodGroupView(period: dayPeriod, readings: day.readings(in: dayPeriod)) {
                            readingToDelete = $0
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .navigationTitle(L10n.text("Histórico"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(L10n.text("¿Eliminar esta toma?"), isPresented: Binding(get: { readingToDelete != nil }, set: { if !$0 { readingToDelete = nil } }), titleVisibility: .visible) {
            Button(L10n.text("Eliminar definitivamente"), role: .destructive) {
                if let readingToDelete { store.delete(id: readingToDelete.id) }
                readingToDelete = nil
            }
            Button(L10n.text("Cancelar"), role: .cancel) { readingToDelete = nil }
        } message: { Text(L10n.text("La toma se borrará del almacenamiento local del iPhone.")) }
    }
}

/// Recursos sin texto incrustado; los títulos y controles se traducen con el dispositivo.
private enum GuideIllustration: String, Identifiable {
    case posture = "GuidePosture"
    case cuff = "GuideCuff"
    var id: String { rawValue }
    var title: String { L10n.text(self == .posture ? "Descansa 5 minutos" : "Coloca el brazo") }
}

/// Visor desplazable de imágenes con zoom acotado entre 1× y 4×.
private struct GuideImageZoomView: View {
    let asset: String
    let title: String
    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                Image(asset).resizable().scaledToFit()
                    .frame(width: max(1, geometry.size.width - 32) * zoom)
                    .accessibilityLabel(title)
                    .clipShape(RoundedRectangle(cornerRadius: 18)).padding(16)
            }
            .simultaneousGesture(MagnificationGesture()
                .onChanged { value in zoom = min(4, max(1, settledZoom * value)) }
                .onEnded { _ in settledZoom = zoom })
            .onTapGesture(count: 2) {
                zoom = zoom > 1 ? 1 : 2
                settledZoom = zoom
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text(L10n.text("Pellizca o toca dos veces para ampliar."))
                .font(.caption).foregroundStyle(.secondary).padding(12)
                .frame(maxWidth: .infinity).background(Color.cardBackground)
        }
    }
}

/// Guía orientativa con fuente médica y explicación explícita del almacenamiento local.
struct MeasurementGuideView: View {
    @State private var enlargedIllustration: GuideIllustration?
    var body: some View {
        List {
            Section(L10n.text("Cómo tomar la tensión")) {
                step("1", L10n.text("Prepara el tensiómetro"), L10n.text("Usa un tensiómetro validado de brazo y un manguito de tu talla. La app registra las lecturas del aparato."))
                step("2", L10n.text("Antes de medir"), L10n.text("Evita ejercicio, tabaco y cafeína durante los 30 minutos previos. Vacía la vejiga."))
                step("3", L10n.text("Descansa 5 minutos"), L10n.text("Siéntate en silencio, con la espalda apoyada, los pies en el suelo y las piernas sin cruzar."), illustration: .posture)
                step("4", L10n.text("Coloca el brazo"), L10n.text("Pon el manguito sobre la piel, siguiendo las instrucciones del aparato. Apoya el brazo a la altura del corazón."), illustration: .cuff)
                step("5", L10n.text("Haz dos tomas"), L10n.text("No hables ni te muevas. Espera al menos 1 minuto entre las dos mediciones y guarda cada una por separado."))
                step("6", L10n.text("Sigue tu pauta"), L10n.text("Mide en los horarios indicados por tu profesional sanitario y lleva el informe a la consulta."))
                Link(L10n.text("Fuente: American Heart Association"), destination: URL(string: "https://www.heart.org/en/health-topics/high-blood-pressure/understanding-blood-pressure-readings/monitoring-your-blood-pressure-at-home")!)
                    .font(.footnote)
            }
            Section(L10n.text("Tu privacidad")) {
                Label(L10n.text("No guardamos datos en servidores"), systemImage: "lock.shield.fill").font(.headline)
                Text(L10n.text("Tus tomas y notas se guardan únicamente en el almacenamiento local de este iPhone para que puedas consultar el histórico. La app no exige una cuenta ni envía tus mediciones a nuestros servidores."))
                Text(L10n.text("Solo tú decides si exportas o compartes un informe o una copia. Las copias del dispositivo pueden incluir los datos de la app según tus ajustes de iOS."))
                Text(L10n.text("Eliminar la app puede borrar el histórico local. Exporta una copia si quieres conservarlo."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L10n.text("Guía y privacidad"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $enlargedIllustration) { illustration in
            NavigationStack {
                GuideImageZoomView(asset: illustration.rawValue, title: illustration.title)
                .background(Color.appBackground)
                .navigationTitle(illustration.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Cerrar")) { enlargedIllustration = nil } } }
            }
            .presentationDragIndicator(.visible)
        }
    }

    /// Paso accesible de la guía, con ilustración ampliable opcional.
    private func step(_ number: String, _ title: String, _ text: String, illustration: GuideIllustration? = nil) -> some View {
        VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.headline).foregroundStyle(Color.aquaDark)
                .frame(width: 30, height: 30)
                .background(Color.aquaDark.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text(title)).font(.headline)
                Text(L10n.text(text)).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        if let illustration {
            Button { enlargedIllustration = illustration } label: {
                VStack(spacing: 6) {
                    Image(illustration.rawValue).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityHidden(true)
                    Text(L10n.text("Toca para ampliar la imagen.")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title + ". " + text)
            .accessibilityHint(L10n.text("Toca para ampliar la imagen."))
        }
        }.padding(.vertical, 5)
    }
}
