import SwiftUI
import Charts

/// Gráficas del histórico local filtrado; visualizar tendencias no modifica las tomas.
struct TrendsView: View {
    @EnvironmentObject private var store: ReadingStore
    @State private var days: Int? = 30
    @State private var period: DayPeriod?

    private var readings: [BloodPressureReading] {
        store.readings(inLastDays: days).filter { period == nil || $0.period == period }
            .sorted { $0.measuredAt < $1.measuredAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.text("EVOLUCIÓN"), systemImage: "chart.xyaxis.line")
                        .font(.caption.bold()).tracking(1.5).foregroundStyle(Color.aquaDark)
                    Text(L10n.text("Tus datos, de un vistazo")).font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(L10n.text("Observa tus mediciones a lo largo del tiempo."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 12)
                VStack(spacing: 14) {
                    Picker(L10n.text("Periodo"), selection: $days) {
                        Text(L10n.text("7 días")).tag(Optional(7))
                        Text(L10n.text("30 días")).tag(Optional(30))
                        Text(L10n.text("Todo")).tag(Optional<Int>.none)
                    }.pickerStyle(.segmented)
                    Picker(L10n.text("Momento"), selection: $period) {
                        Text(L10n.text("Todas")).tag(Optional<DayPeriod>.none)
                        ForEach(DayPeriod.allCases) { Text($0.title).tag(Optional($0)) }
                    }.pickerStyle(.segmented)
                }
                if readings.isEmpty {
                    ContentUnavailableView(L10n.text("Sin tomas en este periodo"), systemImage: "chart.xyaxis.line")
                        .frame(maxWidth: .infinity).padding(.vertical, 28)
                } else {
                    HStack(spacing: 12) {
                        metric("Sistólica", value: readings.map(\.systolic), unit: "mmHg", color: .aquaDark)
                        metric("Diastólica", value: readings.map(\.diastolic), unit: "mmHg", color: .coral)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        Text(L10n.text("Tensión arterial")).font(.title3.bold())
                        Chart {
                            ForEach(readings) { item in
                                LineMark(x: .value(L10n.text("Fecha"), item.measuredAt), y: .value("mmHg", item.systolic), series: .value(L10n.text("Serie"), L10n.text("Sistólica")))
                                    .foregroundStyle(Color.aquaDark)
                                PointMark(x: .value(L10n.text("Fecha"), item.measuredAt), y: .value("mmHg", item.systolic))
                                    .foregroundStyle(Color.aquaDark)
                                LineMark(x: .value(L10n.text("Fecha"), item.measuredAt), y: .value("mmHg", item.diastolic), series: .value(L10n.text("Serie"), L10n.text("Diastólica")))
                                    .foregroundStyle(Color.coral)
                                PointMark(x: .value(L10n.text("Fecha"), item.measuredAt), y: .value("mmHg", item.diastolic))
                                    .foregroundStyle(Color.coral)
                            }
                        }.chartLegend(.hidden).frame(height: 250)
                        HStack(spacing: 20) {
                            legend("Sistólica", color: .aquaDark)
                            legend("Diastólica", color: .coral)
                        }
                    }.featureCard()
                    if !readings.compactMap(\.pulse).isEmpty {
                        VStack(alignment: .leading, spacing: 18) {
                            Label(L10n.text("Pulso"), systemImage: "heart.fill").font(.title3.bold())
                            Chart {
                                ForEach(readings.filter { $0.pulse != nil }) { item in
                                    if let pulse = item.pulse {
                                        LineMark(x: .value(L10n.text("Fecha"), item.measuredAt), y: .value(L10n.text("lpm"), pulse)).foregroundStyle(Color.nightAccent)
                                        PointMark(x: .value(L10n.text("Fecha"), item.measuredAt), y: .value(L10n.text("lpm"), pulse)).foregroundStyle(Color.nightAccent)
                                    }
                                }
                            }.frame(height: 170)
                            Text(L10n.text("lpm")).font(.caption).foregroundStyle(.secondary)
                        }.featureCard()
                    }
                    Text(L10n.format("Tomas guardadas en este iPhone: %ld", readings.count))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(20).padding(.bottom, 16)
        }
        .background(Color.appBackground)
        .navigationTitle(L10n.text("Gráficas"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metric(_ title: String, value: [Int], unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text(title)).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            Text("\(value.reduce(0, +) / max(value.count, 1))").font(.system(size: 34, weight: .bold, design: .rounded))
            Text(L10n.text("Media") + " · " + unit).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).featureCard()
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(L10n.text(title)).font(.caption.weight(.medium))
        }
    }
}

/// Filas de «Más / Cuida tu rutina». El Button/NavigationLink por defecto CENTRA
/// la etiqueta: cada fila se pinta con `.buttonStyle(.plain)` y alineación leading.
/// Identificadores estables de las herramientas secundarias del menú Más.
enum MoreToolsRow: String, CaseIterable, Identifiable {
    case alerts, guide, excel, backup
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .alerts: return "Alertas"
        case .guide: return "Guía y privacidad"
        case .excel: return "Exportar a Excel"
        case .backup: return "Importar registros de Excel"
        }
    }
    var subtitleKey: String {
        switch self {
        case .alerts: return "Configura tus horarios y días."
        case .guide: return "Cómo medir y cómo cuidamos tus datos."
        case .excel: return "Todas tus tomas en una hoja de cálculo."
        case .backup: return "Conserva y restaura tu histórico."
        }
    }
    var icon: String {
        switch self {
        case .alerts: return "bell.badge.fill"
        case .guide: return "book.closed.fill"
        case .excel: return "tablecells.fill"
        case .backup: return "externaldrive.fill"
        }
    }
    var tint: Color {
        switch self {
        case .alerts: return .orange
        case .guide: return .aquaDark
        case .excel: return .green
        case .backup: return .nightAccent
        }
    }
}

/// Textos localizados de las herramientas; mantiene separada la navegación de sus etiquetas.
enum MoreToolsCopy {
    static let titleKey = "Cuida tu rutina"
    static let leadKey = "Guía, avisos y tus datos, en un solo lugar."
    static let storedKey = "Guardado en este iPhone"
}

/// Acceso secundario a guía, avisos e intercambio de datos fuera del menú principal.
struct MoreToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingReminders = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "square.grid.2x2").font(.system(size: 32)).foregroundStyle(Color.aquaDark)
                        Text(L10n.text(MoreToolsCopy.titleKey)).font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(L10n.text(MoreToolsCopy.leadKey)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .padding(.vertical, 12)
                    Button { showingReminders = true } label: {
                        tool(MoreToolsRow.alerts)
                    }.buttonStyle(.plain)
                    NavigationLink { MeasurementGuideView() } label: {
                        tool(MoreToolsRow.guide)
                    }.buttonStyle(.plain)
                    NavigationLink { ExcelExportView() } label: {
                        tool(MoreToolsRow.excel)
                    }.buttonStyle(.plain)
                    NavigationLink { BackupView() } label: {
                        tool(MoreToolsRow.backup)
                    }.buttonStyle(.plain)
                    Label(L10n.text(MoreToolsCopy.storedKey), systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle(L10n.text("Más"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Cerrar")) { dismiss() } } }
            .sheet(isPresented: $showingReminders) { ReminderSettingsView() }
        }.tint(Color.aquaDark)
    }

    private func tool(_ row: MoreToolsRow) -> some View {
        HStack(spacing: 16) {
            Image(systemName: row.icon).font(.system(size: 23))
                .foregroundStyle(row.tint).frame(width: 52, height: 56)
                .background(row.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text(row.titleKey)).font(.headline).foregroundStyle(.primary)
                Text(L10n.text(row.subtitleKey)).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            Image(systemName: "chevron.forward").font(.caption.bold()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .featureCard()
    }
}

/// Exportación voluntaria de todas las tomas a XLSX mediante la hoja de compartir de iOS.
struct ExcelExportView: View {
    @EnvironmentObject private var store: ReadingStore
    @State private var sharePayload: SharePayload?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "tablecells.fill")
                    .font(.system(size: 48)).foregroundStyle(Color.aquaDark).padding(.top, 20)
                Text(L10n.text("Exportar a Excel")).font(.system(size: 30, weight: .bold, design: .rounded))
                Text(L10n.text("Todas tus tomas en una hoja de cálculo.")).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    Label(L10n.text("Fecha y hora"), systemImage: "calendar")
                    Label(L10n.text("Mañana") + " / " + L10n.text("Noche"), systemImage: "sun.max")
                    Label(L10n.text("Tensión arterial") + " · mmHg", systemImage: "waveform.path.ecg")
                    Label(L10n.text("Pulso") + " · " + L10n.text("lpm"), systemImage: "heart")
                    Label(L10n.text("Notas e identificador único"), systemImage: "text.alignleft")
                    Label(L10n.text("Medicamentos de esta toma"), systemImage: "pills.fill")
                }.featureCard()
                Button {
                    do {
                        sharePayload = SharePayload(url: try ExcelExport.make(readings: store.readings))
                        errorMessage = nil
                    } catch { errorMessage = L10n.text("No se pudo exportar el archivo.") }
                } label: {
                    Label(L10n.text("Crear archivo Excel"), systemImage: "square.and.arrow.up")
                        .font(.headline).frame(maxWidth: .infinity).padding(18)
                }
                .buttonStyle(.plain).foregroundStyle(.white)
                .background(Color.ink, in: RoundedRectangle(cornerRadius: 18))
                .disabled(store.readings.isEmpty)
                if store.readings.isEmpty { Text(L10n.text("Guarda tu primera medición.")).foregroundStyle(.secondary) }
                if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
                Text(L10n.text("La copia contiene datos de salud. Guárdala en un lugar privado y compártela solo con personas de confianza."))
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }
        .background(Color.appBackground)
        .navigationTitle(L10n.text("Exportar a Excel"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharePayload) { ShareSheet(items: [$0.url]) }
    }
}

private extension View {
    func featureCard() -> some View {
        padding(18)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.cardBorder, lineWidth: 1))
    }
}
