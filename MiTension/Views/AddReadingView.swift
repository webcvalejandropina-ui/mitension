import SwiftUI

/// Borrador de formulario: no se persiste hasta validar y confirmar el lote completo.
private struct ReadingDraft {
    var systolic = ""
    var diastolic = ""
    var pulse = ""
    var note = ""
    var medications: [ReadingMedication] = []
}

/// Identidad estable de cada campo para recorrer el formulario sin cerrar el teclado.
enum ReadingInput: Hashable {
    case systolic(Int), diastolic(Int), pulse(Int), note(Int)
    case medicationName(UUID), medicationDose(UUID), medicationNote(UUID)
}

/// Captura de una o tres tomas individuales, cada una con su pulso, notas y medicamentos.
struct AddReadingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ReadingStore
    @State private var drafts = (0..<3).map { _ in ReadingDraft() }
    @State private var readingCount = 1
    @State private var errorMessage: String?
    @FocusState private var focusedInput: ReadingInput?

    private var inputOrder: [ReadingInput] {
        (0..<readingCount).flatMap { index in
            [.systolic(index), .diastolic(index), .pulse(index), .note(index)] + drafts[index].medications.flatMap {
                [.medicationName($0.id), .medicationDose($0.id), .medicationNote($0.id)]
            }
        }
    }

    /// Navega solo entre los campos actualmente visibles, incluidos los medicamentos.
    private func moveFocus(_ offset: Int) {
        guard let focusedInput, let index = inputOrder.firstIndex(of: focusedInput), inputOrder.indices.contains(index + offset) else { return }
        self.focusedInput = inputOrder[index + offset]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    localStorageMessage
                    Picker(L10n.text("Número de tomas"), selection: $readingCount) {
                        Text(L10n.text("1 toma")).tag(1)
                        Text(L10n.text("3 tomas")).tag(3)
                    }.pickerStyle(.segmented)
                    Text(L10n.text("Cada toma se guarda por separado. Introduce los valores de cada medición."))
                        .font(.caption).foregroundStyle(.secondary)
                    momentCard
                    ForEach(0..<readingCount, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.format("Toma %ld", index + 1)).font(.title3.bold()).foregroundStyle(Color.aquaDark)
                            pressureCard($drafts[index], index: index)
                            detailsCard($drafts[index], index: index)
                            MedicationFieldsView(medications: $drafts[index].medications, focus: $focusedInput).inputCardStyle()
                        }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(18)
            }
            .background(Color.appBackground)
            .navigationTitle(L10n.text("Nueva toma"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("Cancelar")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("Guardar"), action: save).fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Button { moveFocus(-1) } label: { Image(systemName: "chevron.up") }
                        .accessibilityLabel(L10n.text("Campo anterior"))
                        .disabled(focusedInput == inputOrder.first)
                    Button { moveFocus(1) } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel(L10n.text("Campo siguiente"))
                        .disabled(focusedInput == inputOrder.last)
                    Spacer()
                    Button(L10n.text("Cerrar teclado")) { focusedInput = nil }
                }
            }
            .onChange(of: readingCount) { _, _ in
                if let focusedInput, !inputOrder.contains(focusedInput) { self.focusedInput = nil }
            }
            .onSubmit { moveFocus(1) }
        }
        .presentationDragIndicator(.visible)
        .alert(L10n.text("Nueva toma"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(L10n.text("Cerrar")) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var localStorageMessage: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone.gen3")
                .font(.title3)
                .foregroundStyle(Color.aquaDark)
                .frame(width: 42, height: 42)
                .background(Color.aquaDark.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text("Registro individual")).font(.headline)
                Text(L10n.text("Esta toma tendrá un identificador único y se guardará en este iPhone."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18))
    }

    private func pressureCard(_ draft: Binding<ReadingDraft>, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: L10n.text("Tensión arterial"), symbol: "heart.text.square.fill")
            HStack(alignment: .center, spacing: 10) {
                PressureField(title: L10n.text("Sistólica"), value: draft.systolic, placeholder: "120", focus: $focusedInput, input: .systolic(index))
                Text("/").font(.system(size: 30, weight: .medium)).foregroundStyle(Color.aquaDark)
                PressureField(title: L10n.text("Diastólica"), value: draft.diastolic, placeholder: "80", focus: $focusedInput, input: .diastolic(index))
            }
            if let sys = L10n.integer(draft.wrappedValue.systolic), let dia = L10n.integer(draft.wrappedValue.diastolic), (40...300).contains(sys), (30...200).contains(dia), dia < sys {
                PressureInterpretationView(reading: BloodPressureReading(systolic: sys, diastolic: dia, measuredAt: Date(), period: DayPeriod.suggested(for: Date())))
            }
        }
        .inputCardStyle()
    }

    private var momentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: L10n.text("Momento de la toma"), symbol: "clock.fill")
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 10) {
                    let period = DayPeriod.suggested(for: context.date)
                    Label(period.title, systemImage: period.symbol).foregroundStyle(Color.aquaDark)
                    LabeledContent(L10n.text("Fecha y hora"), value: context.date.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Text(L10n.text("Se asigna automáticamente al guardar según la hora local del iPhone: mañana antes de las 14:00 y noche desde las 14:00. Una toma guardada solo se puede eliminar."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .inputCardStyle()
    }

    private func detailsCard(_ draft: Binding<ReadingDraft>, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: L10n.text("Datos opcionales"), symbol: "plus.circle.fill")
            HStack {
                TextField(L10n.text("Pulso"), text: draft.pulse).keyboardType(.numberPad)
                    .focused($focusedInput, equals: .pulse(index))
                Text(L10n.text("lpm")).foregroundStyle(.secondary)
            }
            .padding(13)
            .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 12))

            TextField(L10n.text("Nota para esta toma"), text: draft.note, axis: .vertical)
                .focused($focusedInput, equals: .note(index))
                .submitLabel(.next)
                .lineLimit(2...4)
                .padding(13)
                .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 12))

            Text(L10n.text("Máximo 140 caracteres")).font(.caption2).foregroundStyle(.secondary)
        }
        .inputCardStyle()
    }

    /// Valida todos los borradores antes de guardar. Usa un instante local común y un UUID por toma.
    private func save() {
        let measuredAt = Date()
        var readings: [BloodPressureReading] = []
        for (index, draft) in drafts.prefix(readingCount).enumerated() {
            func invalid(_ text: String) { errorMessage = L10n.format("Toma %ld", index + 1) + ": " + L10n.text(text) }
            let systolic = draft.systolic, diastolic = draft.diastolic, pulse = draft.pulse
            guard let sys = L10n.integer(systolic), (40...300).contains(sys) else {
                invalid("Introduce una sistólica entre 40 y 300 mmHg.")
                return
            }
            guard let dia = L10n.integer(diastolic), (30...200).contains(dia), dia < sys else {
                invalid("La diastólica debe estar entre 30 y 200 y ser menor que la sistólica.")
                return
            }
            let pulseText = pulse.trimmingCharacters(in: .whitespacesAndNewlines)
            let pulseValue = L10n.integer(pulseText)
            if !pulseText.isEmpty && (pulseValue == nil || !(20...250).contains(pulseValue ?? 0)) {
                invalid("Introduce un pulso entre 20 y 250 lpm.")
                return
            }

            let recordedMedications = draft.medications.map { medication in
                var clean = medication
                clean.name = clean.name.trimmingCharacters(in: .whitespacesAndNewlines)
                clean.dose = clean.dose.trimmingCharacters(in: .whitespacesAndNewlines)
                clean.note = clean.note.trimmingCharacters(in: .whitespacesAndNewlines)
                return clean
            }
            guard recordedMedications.allSatisfy({ !$0.name.isEmpty }) else {
                invalid("Introduce el nombre del medicamento o elimina la fila vacía.")
                return
            }
            readings.append(
                BloodPressureReading(
                    systolic: sys,
                    diastolic: dia,
                    pulse: pulseValue,
                    measuredAt: measuredAt,
                    period: DayPeriod.suggested(for: measuredAt),
                    note: String(draft.note.prefix(140)),
                    medications: recordedMedications
                )
            )
        }
        do {
            try store.add(readings)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}


/// Campos de un medicamento asociado al borrador, sin interpretar ni recomendar dosis.
private struct MedicationFieldsView: View {
    @Binding var medications: [ReadingMedication]
    var focus: FocusState<ReadingInput?>.Binding
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: L10n.text("Medicamentos de esta toma"), symbol: "pills.fill")
            Text(L10n.text("Registra la medicación asociada a esta medición. Es un registro, no una recomendación de tratamiento."))
                .font(.caption).foregroundStyle(.secondary)
            ForEach($medications) { $medication in
                VStack(spacing: 10) {
                    HStack {
                        TextField(L10n.text("Nombre del medicamento"), text: $medication.name)
                            .focused(focus, equals: .medicationName(medication.id)).submitLabel(.next)
                        Button {
                            medications.removeAll { $0.id == medication.id }
                        } label: { Image(systemName: "minus.circle.fill").foregroundStyle(Color.coral) }
                            .accessibilityLabel(L10n.text("Quitar medicamento"))
                    }
                    TextField(L10n.text("Dosis (opcional)"), text: $medication.dose)
                        .focused(focus, equals: .medicationDose(medication.id)).submitLabel(.next)
                    TextField(L10n.text("Nota del medicamento (opcional)"), text: $medication.note, axis: .vertical)
                        .focused(focus, equals: .medicationNote(medication.id))
                        .lineLimit(1...3)
                }.padding(14).background(Color.appBackground, in: RoundedRectangle(cornerRadius: 14))
            }
            Button { medications.append(ReadingMedication()) } label: {
                Label(L10n.text("Añadir medicamento"), systemImage: "plus.circle.fill")
            }
        }
    }
}

/// Encabezado reutilizable de las secciones del formulario.
private struct SectionTitle: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

/// Entrada numérica con foco gestionado por el formulario y presentación adaptable.
private struct PressureField: View {
    let title: String
    @Binding var value: String
    let placeholder: String
    var focus: FocusState<ReadingInput?>.Binding
    let input: ReadingInput

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField(placeholder, text: $value)
                    .focused(focus, equals: input)
                    .accessibilityLabel(title)
                    .keyboardType(.numberPad)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("mmHg").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(13)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 14))
    }
}

private extension View {
    func inputCardStyle() -> some View {
        padding(16)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.cardBorder))
    }
}
