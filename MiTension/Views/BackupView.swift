import SwiftUI
import UniformTypeIdentifiers

/// Importación XLSX con instrucciones de filas y columnas. No sustituye ni edita tomas existentes.
struct BackupView: View {
    @EnvironmentObject private var store: ReadingStore
    @State private var showingImporter = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "externaldrive.badge.checkmark")
                        .font(.system(size: 38)).foregroundStyle(Color.aquaDark)
                    Text(L10n.text("Importar registros de Excel")).font(.title2.bold())
                    Text(L10n.text("Selecciona un archivo Excel exportado por Mi Tensión. Se añaden los registros nuevos sin borrar tu histórico ni duplicar tomas."))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
            }
            Section {
                Button { showingImporter = true } label: { Label(L10n.text("Importar registros de Excel"), systemImage: "arrow.down.doc") }
            }
            Section(L10n.text("Formato del archivo")) {
                Text(L10n.text("Usa el Excel (.xlsx) exportado por Mi Tensión como plantilla. Conserva la primera fila y el orden de las columnas; no uses fórmulas."))
                Text(L10n.text("Cada fila desde la segunda es una toma independiente. Puedes importar 1, 2 o 3 tomas de mañana o noche por día; no se promedian ni se exige completar tres."))
                Text(L10n.text("Mañana y noche se calculan por la fecha y hora local: antes de las 14:00 es mañana; desde las 14:00 es noche. La columna B no cambia esa clasificación."))
            }
            Section(L10n.text("Columnas")) {
                column("A", "Fecha y hora")
                column("B", "Momento")
                column("C", "Sistólica", unit: "mmHg")
                column("D", "Diastólica", unit: "mmHg")
                column("E", "Pulso", unit: L10n.text("lpm"))
                column("F", "Notas")
                LabeledContent("G", value: "ID (UUID)")
                column("H", "Medicamentos de esta toma")
                Text(L10n.text("A, C, D y G son obligatorias. A debe ser una fecha y hora de Excel, no texto; C y D son números enteros sin unidades. E, F y H pueden quedar vacías."))
                Text(L10n.text("G identifica cada toma: conserva su UUID para evitar duplicados y usa un UUID distinto para una toma nueva. I, J y K son columnas técnicas ocultas; no las modifiques ni copies sus valores a tomas nuevas."))
            }
            Section(L10n.text("Contenido")) {
                LabeledContent(L10n.text("Mediciones"), value: "\(store.readings.count)")
            }
            if let message { Section { Text(message).font(.subheadline).foregroundStyle(Color.aquaDark) } }
            Section {
                Text(L10n.text("La copia contiene datos de salud. Guárdala en un lugar privado y compártela solo con personas de confianza."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L10n.text("Importar registros de Excel"))
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .spreadsheet]) { result in
            do {
                let imported = try store.importExcel(from: result.get())
                message = L10n.format("Tomas restauradas: %ld", imported)
            } catch {
                message = L10n.text("No se pudo importar el Excel. Usa un archivo exportado por Mi Tensión con registros válidos.")
            }
        }
    }

    /// Presenta la posición estable de la columna y su nombre localizado.
    private func column(_ letter: String, _ title: String, unit: String? = nil) -> some View {
        LabeledContent(letter, value: L10n.text(title) + (unit.map { " (\($0))" } ?? ""))
    }

}
