import Foundation
import UIKit

/// Informe A4 para compartir o imprimir, organizado por día con mañana y noche en columnas.
enum ReportPDFGenerator {
    /// Crea un PDF temporal protegido. El usuario decide si lo comparte mediante la hoja de iOS.
    static func make(readings: [BloodPressureReading], periodTitle: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Informe-Mi-Tension-\(UUID().uuidString).pdf")
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let data = renderer.pdfData { context in
            var y: CGFloat = 34
            func newPageIfNeeded(_ needed: CGFloat) {
                if y + needed > page.height - 42 { context.beginPage(); y = 34 }
            }
            context.beginPage()
            draw("Mi Tensión", at: CGPoint(x: 36, y: y), font: .boldSystemFont(ofSize: 22), color: UIColor(red: 7/255, green: 24/255, blue: 38/255, alpha: 1)); y += 32
            draw(L10n.format("Informe de seguimiento · %@", periodTitle), at: CGPoint(x: 36, y: y), font: .systemFont(ofSize: 13), color: .darkGray); y += 25
            draw(L10n.format("Generado el %@", Date().formatted(date: .long, time: .shortened)), at: CGPoint(x: 36, y: y), font: .systemFont(ofSize: 10), color: .gray); y += 27

            let grouped = Dictionary(grouping: readings) { Calendar.current.startOfDay(for: $0.measuredAt) }
            let days = grouped.keys.sorted(by: >)
            for day in days {
                let dayReadings = (grouped[day] ?? []).sorted { $0.measuredAt < $1.measuredAt }
                let morning = dayReadings.filter { $0.period == .morning }
                let evening = dayReadings.filter { $0.period == .evening }
                func header() {
                    (day.formatted(.dateTime.day().month(.abbreviated).year()) as NSString).draw(in: CGRect(x: 36, y: y, width: 108, height: 32), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 10), .foregroundColor: UIColor.black])
                    draw(DayPeriod.morning.title.uppercased(), at: CGPoint(x: 155, y: y), font: .boldSystemFont(ofSize: 9), color: .darkGray)
                    draw(DayPeriod.evening.title.uppercased(), at: CGPoint(x: 355, y: y), font: .boldSystemFont(ofSize: 9), color: .darkGray)
                    y += 34
                }
                newPageIfNeeded(100)
                header()
                for index in 0..<max(morning.count, evening.count) {
                    let left = index < morning.count ? morning[index] : nil
                    let right = index < evening.count ? evening[index] : nil
                    let leftChunks = chunks(left)
                    let rightChunks = chunks(right)
                    for chunkIndex in 0..<max(leftChunks.count, rightChunks.count) {
                        let l = chunkIndex < leftChunks.count ? leftChunks[chunkIndex] : nil
                        let r = chunkIndex < rightChunks.count ? rightChunks[chunkIndex] : nil
                        let height = 36 + CGFloat(max(l?.count ?? 0, r?.count ?? 0)) * detailFont.lineHeight
                        if y + height > page.height - 48 { context.beginPage(); y = 34; header() }
                        drawReading(l == nil ? nil : left, lines: l ?? [], x: 155, y: y, continued: chunkIndex > 0)
                        drawReading(r == nil ? nil : right, lines: r ?? [], x: 355, y: y, continued: chunkIndex > 0)
                        y += height
                    }
                    UIColor.lightGray.setStroke()
                    let line = UIBezierPath(); line.move(to: CGPoint(x: 36, y: y)); line.addLine(to: CGPoint(x: 559, y: y)); line.stroke()
                    y += 10
                }
            }
            newPageIfNeeded(38)
            (L10n.text("Las mediciones han sido introducidas por el usuario. Este informe no sustituye la valoración clínica.") as NSString).draw(in: CGRect(x: 36, y: y, width: 523, height: 38), withAttributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.gray])
        }
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }

    private static let detailFont = UIFont.systemFont(ofSize: 9)

    // Paginate at actual shaped line boundaries, including one exceptionally long medication note.
    /// Divide notas según líneas realmente maquetadas para evitar pérdidas al saltar de página.
    private static func chunks(_ reading: BloodPressureReading?) -> [[String]] {
        guard let reading else { return [] }
        let text = readingDetails(reading)
        guard !text.isEmpty else { return [[]] }
        let storage = NSTextStorage(string: text, attributes: [.font: detailFont])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 190, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container); storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        var lines: [String] = []
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { _, _, _, range, _ in
            let characters = layout.characterRange(forGlyphRange: range, actualGlyphRange: nil)
            lines.append((text as NSString).substring(with: characters).trimmingCharacters(in: .newlines))
        }
        return stride(from: 0, to: lines.count, by: 40).map { Array(lines[$0..<min($0 + 40, lines.count)]) }
    }

    /// Repite hora e ID en las continuaciones para identificar claramente cada medición.
    private static func drawReading(_ reading: BloodPressureReading?, lines: [String], x: CGFloat, y: CGFloat, continued: Bool) {
        guard let reading else { return }
        draw(continued ? L10n.text("Continuación") : "\(reading.systolic) / \(reading.diastolic) mmHg", at: CGPoint(x: x, y: y), font: .boldSystemFont(ofSize: 12), color: .black)
        let details = reading.measuredAt.formatted(date: .omitted, time: .shortened) + (reading.pulse.map { " · \($0) " + L10n.text("lpm") } ?? "") + " · ID " + reading.id.uuidString.prefix(6)
        draw(details, at: CGPoint(x: x, y: y + 15), font: .systemFont(ofSize: 8), color: .gray)
        for (index, line) in lines.enumerated() {
            draw(line, at: CGPoint(x: x, y: y + 28 + CGFloat(index) * detailFont.lineHeight), font: detailFont, color: .darkGray)
        }
    }

    private static func readingDetails(_ reading: BloodPressureReading) -> String {
        [reading.note, reading.medications.isEmpty ? "" : L10n.text("Medicamentos de esta toma") + ":\n" + reading.medicationSummary]
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func draw(_ text: String, at point: CGPoint, font: UIFont, color: UIColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }
}
