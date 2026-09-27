import SwiftUI

/// Vista de consulta con tomas por día y periodo; comparte un informe PDF independiente del Excel.
struct MedicalReportView: View {
    @EnvironmentObject private var store: ReadingStore
    @State private var selectedDays: Int? = 30
    @State private var sharePayload: SharePayload?
    @State private var exportError: String?

    private var readings: [BloodPressureReading] { store.readings(inLastDays: selectedDays) }
    private var grouped: [DailyReport] {
        Dictionary(grouping: readings) { Calendar.current.startOfDay(for: $0.measuredAt) }
            .map { day, items in DailyReport(date: day, morning: items.filter { $0.period == .morning }, evening: items.filter { $0.period == .evening }) }
            .sorted { $0.date > $1.date }
    }
    private var average: String {
        guard !readings.isEmpty else { return "— / —" }
        return "\(readings.map(\.systolic).reduce(0,+) / readings.count) / \(readings.map(\.diastolic).reduce(0,+) / readings.count)"
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                Picker(L10n.text("Periodo"), selection: $selectedDays) {
                    Text(L10n.text("30 días")).tag(Optional(30))
                    Text(L10n.text("90 días")).tag(Optional(90))
                    Text(L10n.text("Todo")).tag(Optional<Int>.none)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    ReportMetric(label: L10n.text("Mediciones"), value: "\(readings.count)")
                    ReportMetric(label: L10n.text("Promedio"), value: average, suffix: "mmHg")
                }

                Button { shareReport() } label: {
                    Label(L10n.text("Compartir o imprimir"), systemImage: "square.and.arrow.up")
                        .font(.headline).frame(maxWidth: .infinity).padding(16)
                }
                .buttonStyle(.plain).foregroundStyle(Color.aquaDark)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                .disabled(readings.isEmpty)

                if grouped.isEmpty {
                    ContentUnavailableView(L10n.text("Sin mediciones"), systemImage: "doc.text", description: Text(L10n.text("No hay datos en este periodo.")))
                        .frame(minHeight: 300)
                } else {
                    ForEach(grouped) { day in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.headline)
                            ReportColumn(period: .morning, items: day.morning, color: .orange)
                            Divider()
                            ReportColumn(period: .evening, items: day.evening, color: .nightAccent)
                        }
                        .padding(16)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.cardBorder))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .background(Color.appBackground)
        .navigationTitle(L10n.text("Vista médica"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: [payload.url])
        }
        .alert(L10n.text("No se pudo exportar el archivo."), isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button(L10n.text("Cerrar")) { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    /// Exporta solo el periodo seleccionado y presenta errores sin mostrar un archivo incompleto.
    private func shareReport() {
        do {
            let title = selectedDays.map { L10n.format("Últimos %ld días", $0) } ?? L10n.text("Historial completo")
            let url = try ReportPDFGenerator.make(readings: readings, periodTitle: title)
            sharePayload = SharePayload(url: url)
        } catch { sharePayload = nil; exportError = L10n.text("No se pudo exportar el archivo.") }
    }
}

/// Datos de presentación del día: mantiene las listas independientes de mañana y noche.
private struct DailyReport: Identifiable {
    let date: Date
    let morning: [BloodPressureReading]
    let evening: [BloodPressureReading]
    var id: Date { date }
}

/// Métrica de consulta que evita superponer la unidad y el valor en pantallas pequeñas.
private struct ReportMetric: View {
    let label: String
    let value: String
    var suffix: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text(label).uppercased()).font(.caption2.bold()).tracking(0.8).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(value).font(.title2.bold()).minimumScaleFactor(0.7).lineLimit(1)
                if !suffix.isEmpty { Text(suffix).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 15))
    }
}

/// Bloque de periodo a ancho completo en pantalla; el PDF usa su propia maquetación.
private struct ReportColumn: View {
    let period: DayPeriod
    let items: [BloodPressureReading]
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(period.title, systemImage: period.symbol).font(.subheadline.bold()).foregroundStyle(color)
            if items.isEmpty { Text("—").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(item.systolic) / \(item.diastolic)").font(.headline)
                    Text("mmHg · \(item.measuredAt.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    if let pulse = item.pulse { Text("\(pulse) " + L10n.text("lpm")).font(.caption2).foregroundStyle(color) }
                    if !item.note.isEmpty { Text(item.note).font(.caption).foregroundStyle(.secondary) }
                    if !item.medications.isEmpty {
                        Label(item.medicationSummary, systemImage: "pills.fill").font(.caption2).foregroundStyle(color)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
