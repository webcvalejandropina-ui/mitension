import Charts
import SwiftUI
import UIKit

/// Resumen de la última toma y medias del periodo, separado del registro individual por día.
struct DashboardView: View {
    @EnvironmentObject private var store: ReadingStore
    @Binding var showingAddReading: Bool
    @Binding var showingMore: Bool
    @State private var filterDays: Int? = 7
    @State private var readingToDelete: BloodPressureReading?
    @State private var showingReminders = false
    @AppStorage("MiTension.storageNoticeDismissed") private var storageNoticeDismissed = false

    private var visibleReadings: [BloodPressureReading] { store.readings(inLastDays: filterDays) }
    private var weekReadings: [BloodPressureReading] { store.readings(inLastDays: 7) }
    private var average: (Int, Int)? {
        guard !weekReadings.isEmpty else { return nil }
        return (
            weekReadings.map(\.systolic).reduce(0, +) / weekReadings.count,
            weekReadings.map(\.diastolic).reduce(0, +) / weekReadings.count
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                header
                if !storageNoticeDismissed { localStorageBanner }
                latestReading
                weeklySummary
                history
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(Color.appBackground)
        .navigationBarHidden(true)
        .sheet(isPresented: $showingReminders) { ReminderSettingsView() }
        .safeAreaInset(edge: .bottom) {
            Button { showingAddReading = true } label: {
                Label(L10n.text("Guardar nueva toma"), systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Color.ink, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .background(.ultraThinMaterial)
        }
        .confirmationDialog(
            L10n.text("¿Eliminar esta toma?"),
            isPresented: Binding(
                get: { readingToDelete != nil },
                set: { if !$0 { readingToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.text("Eliminar definitivamente"), role: .destructive) {
                if let readingToDelete { store.delete(id: readingToDelete.id) }
                readingToDelete = nil
            }
            Button(L10n.text("Cancelar"), role: .cancel) { readingToDelete = nil }
        } message: {
            Text(L10n.text("La toma se borrará del almacenamiento local del iPhone."))
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image("PineappleMark")
                .resizable().scaledToFit()
                .frame(width: 48, height: 56)
                .accessibilityHidden(true)
                Text(L10n.text("Mis mediciones"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .tracking(-0.5)
                    .layoutPriority(1)
            Spacer(minLength: 0)
            Button { showingReminders = true } label: {
                Image(systemName: "bell.badge.fill")
                .font(.system(size: 25))
                .foregroundStyle(Color.aqua)
                .frame(width: 40, height: 46)
                .background(Color.ink, in: RoundedRectangle(cornerRadius: 15))
            }
            .accessibilityLabel(L10n.text("Alertas"))
            Button { showingMore = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.aquaDark)
                    .frame(width: 40, height: 46)
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 15))
            }
            .accessibilityLabel(L10n.text("Más"))
        }
        .padding(.top, 14)
    }

    private var localStorageBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone.gen3")
                .font(.title3)
                .foregroundStyle(Color.aquaDark)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("Guardado en este iPhone")).font(.subheadline.weight(.semibold))
                Text(store.readings.isEmpty ? L10n.text("Aún no hay tomas guardadas") : L10n.format("Tomas disponibles sin conexión: %ld", store.readings.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { storageNoticeDismissed = true }
            } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 20))
                    .foregroundStyle(.secondary).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("Ocultar este aviso"))
            .accessibilityHint(L10n.text("No volverá a mostrarse en este iPhone. Tus tomas se conservan."))
        }
        .padding(14)
        .background(Color.aquaDark.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.aquaDark.opacity(0.16)))
    }

    private var latestReading: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(L10n.text("ÚLTIMA TOMA")).font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(.white.opacity(0.68))
                Spacer()
                Image(systemName: "waveform.path.ecg").foregroundStyle(Color.aqua)
            }

            if let latest = store.readings.first {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(latest.systolic)").font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("/").font(.title).foregroundStyle(Color.aqua)
                    Text("\(latest.diastolic)").font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("mmHg").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.64))
                }
                HStack {
                    Label(latest.period.title, systemImage: latest.period.symbol)
                    Spacer()
                    Text(latest.measuredAt.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
                PressureInterpretationView(reading: latest)
            } else {
                Text("— / —").font(.system(size: 48, weight: .bold, design: .rounded))
                Text(L10n.text("Pulsa “Guardar nueva toma” para empezar.")).font(.subheadline).foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .foregroundStyle(.white)
        .background(
            LinearGradient(colors: [Color.ink, Color(red: 12/255, green: 52/255, blue: 65/255)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .shadow(color: Color.ink.opacity(0.14), radius: 18, y: 8)
    }

    private var weeklySummary: some View {
        HStack(spacing: 12) {
            SmallMetric(
                title: L10n.text("MEDIA 7 DÍAS"),
                value: average.map { "\($0.0) / \($0.1)" } ?? "— / —",
                note: "mmHg",
                color: .coral,
                symbol: "chart.line.uptrend.xyaxis"
            )
            SmallMetric(
                title: L10n.text("ESTA SEMANA"),
                value: "\(weekReadings.count)",
                note: L10n.text("tomas"),
                color: .blue,
                symbol: "calendar.badge.clock"
            )
        }
    }

    @ViewBuilder private var trend: some View {
        let data = Array(store.readings.prefix(10).reversed())
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text("EVOLUCIÓN")).font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(Color.aquaDark)
                Text(L10n.text("Últimas mediciones")).font(.title3.bold())
            }
            if data.count > 1 {
                Chart {
                    ForEach(data) { item in
                        LineMark(x: .value(L10n.text("Fecha"), item.measuredAt), y: .value(L10n.text("Sistólica"), item.systolic), series: .value(L10n.text("Serie"), L10n.text("Sistólica")))
                            .foregroundStyle(Color.aquaDark).interpolationMethod(.catmullRom)
                        PointMark(x: .value(L10n.text("Fecha"), item.measuredAt), y: .value(L10n.text("Sistólica"), item.systolic)).foregroundStyle(Color.aquaDark)
                        LineMark(x: .value(L10n.text("Fecha"), item.measuredAt), y: .value(L10n.text("Diastólica"), item.diastolic), series: .value(L10n.text("Serie"), L10n.text("Diastólica")))
                            .foregroundStyle(Color.coral).interpolationMethod(.catmullRom)
                        PointMark(x: .value(L10n.text("Fecha"), item.measuredAt), y: .value(L10n.text("Diastólica"), item.diastolic)).foregroundStyle(Color.coral)
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 190)
            } else {
                ContentUnavailableView(L10n.text("Tu evolución aparecerá aquí"), systemImage: "chart.xyaxis.line", description: Text(L10n.text("Guarda dos o más tomas.")))
                    .frame(height: 170)
            }
        }
        .dashboardCard()
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("Registro de tomas")).font(.title3.bold())
                }
                Spacer()
                Picker(L10n.text("Periodo"), selection: $filterDays) {
                    Text(L10n.text("7 días")).tag(Optional(7))
                    Text(L10n.text("30 días")).tag(Optional(30))
                    Text(L10n.text("Todo")).tag(Optional<Int>.none)
                }
                .pickerStyle(.menu)
            }

            if visibleReadings.isEmpty {
                ContentUnavailableView(L10n.text("Sin tomas"), systemImage: "waveform.path.ecg", description: Text(L10n.text("Guarda tu primera medición.")))
                    .dashboardCard()
            } else {
                ForEach(ReadingDayGroup.grouped(visibleReadings)) { day in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(day.date.formatted(date: .complete, time: .omitted))
                            .font(.headline).padding(.top, 8)
                        ForEach(DayPeriod.allCases) { period in
                            ReadingPeriodGroupView(period: period, readings: day.readings(in: period)) {
                                readingToDelete = $0
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Explica referencias orientativas de adultos, no diagnósticos ni objetivos terapéuticos personales.
struct PressureInterpretationView: View {
    let reading: BloodPressureReading
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                indicator("Sistólica (alta)", above: reading.systolicAboveReference)
                indicator("Diastólica (baja)", above: reading.diastolicAboveReference)
            }
            if reading.needsPromptAssessment {
                Text(L10n.text("Lectura muy elevada. Con dolor de pecho, falta de aire, debilidad o dificultad para hablar, llama a emergencias sin esperar. Sin síntomas, repite tras al menos 1 minuto y, si sigue así, contacta cuanto antes con un profesional sanitario."))
                    .font(.caption).foregroundStyle(Color.coral)
            }
            DisclosureGroup(L10n.text("Qué significan estos valores"), isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(L10n.text("La alta (sistólica) es la presión cuando el corazón se contrae. La baja (diastólica) es la presión entre latidos; ‘baja’ no significa que el valor sea bajo."))
                    Text(L10n.text("Referencia orientativa en casa para adultos: sistólica desde 135 o diastólica desde 85 mmHg. Se interpreta el promedio de varios días, no una toma aislada. Si se repite, consúltalo; no cambies tu medicación por tu cuenta. Tus objetivos pueden ser distintos. No se aplica a menores ni al embarazo."))
                    Link("NICE", destination: URL(string: "https://www.nice.org.uk/guidance/ng136/chapter/recommendations")!)
                    Link("AHA", destination: URL(string: "https://www.heart.org/en/health-topics/high-blood-pressure/understanding-blood-pressure-readings/when-to-call-911-for-high-blood-pressure")!)
                }.font(.caption).padding(.top, 6)
            }.font(.caption).tint(Color.aquaDark)
        }
        .foregroundStyle(Color.primary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private func indicator(_ title: String, above: Bool) -> some View {
        Label {
            Text(L10n.text(title) + ": " + L10n.text(above ? "Sobre la referencia" : "Por debajo de la referencia"))
        } icon: { Image(systemName: above ? "arrow.up.circle" : "minus.circle") }
        .font(.caption.weight(.medium))
        .foregroundStyle(above ? Color.nightAccent : Color.secondary)
    }
}

/// Métrica compacta con valores y unidades separados para evitar recortes.
private struct SmallMetric: View {
    let title: String
    let value: String
    let note: String
    let color: Color
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
            Text(title).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.title3.bold())
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.cardBorder))
    }
}

/// Componente compartido por resumen e histórico: una tarjeta por periodo y día.
struct ReadingPeriodGroupView: View {
    let period: DayPeriod
    let readings: [BloodPressureReading]
    let onDelete: (BloodPressureReading) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(period.title, systemImage: period.symbol)
                    .font(.headline).foregroundStyle(period == .morning ? Color.orange : Color.nightAccent)
                Spacer()
                Text(L10n.format("Tomas guardadas en este iPhone: %ld", readings.count))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if readings.isEmpty {
                Text(L10n.text("Sin tomas en este periodo")).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(readings) { reading in
                    Divider()
                    ReadingCard(reading: reading) { onDelete(reading) }
                }
            }
        }
        .padding(16)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.cardBorder))
    }
}

/// Muestra una toma inmutable y permite solicitar su eliminación, nunca editarla.
private struct ReadingCard: View {
    let reading: BloodPressureReading
    let onDelete: () -> Void

    private var shortID: String { String(reading.id.uuidString.prefix(6)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(reading.measuredAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(reading.systolic) / \(reading.diastolic)")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                Text("mmHg").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let pulse = reading.pulse {
                    Label("\(pulse)", systemImage: "heart.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.coral)
                }
            }

            if !reading.note.isEmpty {
                Text(reading.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 10))
            }

            Divider()
            PressureInterpretationView(reading: reading)
            if !reading.medications.isEmpty {
                Label(reading.medicationSummary, systemImage: "pills.fill")
                    .font(.subheadline).foregroundStyle(Color.aquaDark)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Label(L10n.text("Guardada en el iPhone"), systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.aquaDark)
                Text("ID \(shortID)").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash").frame(width: 30, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("Eliminar toma"))
            }
        }
    }
}

private extension View {
    func dashboardCard() -> some View {
        padding(18)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.cardBorder))
    }
}

extension Color {
    static let ink = Color(red: 7/255, green: 24/255, blue: 38/255)
    static let aqua = Color(red: 55/255, green: 214/255, blue: 192/255)
    static let aquaDark = adaptive(light: UIColor(red: 11/255, green: 121/255, blue: 110/255, alpha: 1), dark: UIColor(red: 79/255, green: 222/255, blue: 200/255, alpha: 1))
    static let coral = adaptive(light: UIColor(red: 195/255, green: 75/255, blue: 58/255, alpha: 1), dark: UIColor(red: 1, green: 0.60, blue: 0.53, alpha: 1))
    static let appBackground = adaptive(light: UIColor(red: 242/255, green: 247/255, blue: 248/255, alpha: 1), dark: UIColor(red: 12/255, green: 18/255, blue: 24/255, alpha: 1))
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let cardBorder = Color(uiColor: .separator).opacity(0.35)
    static let nightAccent = adaptive(light: .systemIndigo, dark: UIColor(red: 0.67, green: 0.64, blue: 1, alpha: 1))

    /// Paleta dinámica: el sistema elige colores legibles en modo claro u oscuro.
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }
}
