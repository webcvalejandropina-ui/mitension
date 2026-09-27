import Foundation
import zlib

/// Importador del formato XLSX de Mi Tensión. Valida en memoria antes de permitir cambios en el histórico.
enum ExcelImport {
    /// Cada fila es una toma independiente. El periodo se deriva de la fecha local, no de la columna B.
    static func read(url: URL) throws -> [BloodPressureReading] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 32 * 1024 * 1024 + 1) ?? Data()
        guard data.count <= 32 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
        let files = try unzip(data)
        guard let sheet = files["xl/worksheets/sheet1.xml"] else { throw CocoaError(.fileReadCorruptFile) }
        let shared = try files["xl/sharedStrings.xml"].map { try SpreadsheetXML.parse($0, shared: true).strings } ?? []
        let parsed = try SpreadsheetXML.parse(sheet, shared: false)
        guard let header = parsed.rows.first, let idHeader = header["G"], !idHeader.formula else { throw CocoaError(.fileReadCorruptFile) }
        if idHeader.type == "s" {
            guard let index = Int(idHeader.value), shared.indices.contains(index), shared[index] == "ID" else { throw CocoaError(.fileReadCorruptFile) }
        } else if idHeader.value != "ID" { throw CocoaError(.fileReadCorruptFile) }
        var readings: [BloodPressureReading] = []
        var seen: [UUID: BloodPressureReading] = [:]
        for row in parsed.rows.dropFirst() {
            func text(_ column: String) throws -> String {
                guard let cell = row[column] else { return "" }
                guard !cell.formula else { throw CocoaError(.fileReadCorruptFile) }
                if cell.type == "s" {
                    guard let index = Int(cell.value), shared.indices.contains(index) else { throw CocoaError(.fileReadCorruptFile) }
                    return shared[index]
                }
                return cell.value
            }
            let pressure = try text("C")
            let low = try text("D")
            let identifier = try text("G")
            if pressure.isEmpty && low.isEmpty && identifier.isEmpty { continue }
            func integer(_ value: String) throws -> Int {
                guard let number = Double(value), number.isFinite, number.rounded() == number, (0...1000).contains(number) else { throw CocoaError(.fileReadCorruptFile) }
                return Int(number)
            }
            guard let id = UUID(uuidString: identifier) else { throw CocoaError(.fileReadCorruptFile) }
            let serialText = try text("A")
            let exactDate = try text("I")
            let originalSerial = try text("K")
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let date: Date
            if !exactDate.isEmpty, let serial = Double(serialText), let original = Double(originalSerial), abs(serial - original) < 0.00000001, let exact = formatter.date(from: exactDate) {
                date = exact
            } else {
                guard let serial = Double(serialText), serial.isFinite, (1...100000).contains(serial) else { throw CocoaError(.fileReadCorruptFile) }
                let epoch = Date(timeIntervalSince1970: -2_209_161_600)
                var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
                let wallTime = epoch.addingTimeInterval((serial * 86400).rounded())
                let parts = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: wallTime)
                guard let localDate = Calendar.current.date(from: parts) else { throw CocoaError(.fileReadCorruptFile) }
                date = localDate
            }
            let medicationText = try text("H")
            let medicationMetadata = try text("J")
            var medications: [ReadingMedication] = []
            if !medicationMetadata.isEmpty {
                medications = try JSONDecoder().decode([ReadingMedication].self, from: Data(medicationMetadata.utf8))
            }
            if medications.map(\.description).joined(separator: "\n") != medicationText {
                // Older exports or manually changed summary: keep its text without guessing doses.
                medications = medicationText.isEmpty ? [] : [ReadingMedication(name: medicationText)]
            }
            let pulse = try text("E")
            let reading = try BloodPressureReading(id: id, systolic: integer(pressure), diastolic: integer(low), pulse: pulse.isEmpty ? nil : integer(pulse), measuredAt: date, period: DayPeriod.suggested(for: date), note: text("F"), medications: medications)
            guard reading.isValid else { throw CocoaError(.fileReadCorruptFile) }
            if let previous = seen[id] {
                guard previous == reading else { throw CocoaError(.fileReadCorruptFile) }
            } else { seen[id] = reading; readings.append(reading) }
        }
        return readings
    }

    /// Bounded ZIP reader: stored/deflated entries, CRC verification, no disk extraction.
    /// ZIP limitado en tamaño y expansión, con CRC; no extrae rutas al sistema de archivos.
    private static func unzip(_ data: Data) throws -> [String: Data] {
        func u16(_ position: Int) throws -> Int {
            guard position >= 0 && position + 2 <= data.count else { throw CocoaError(.fileReadCorruptFile) }
            return Int(data[position]) | Int(data[position + 1]) << 8
        }
        func u32(_ position: Int) throws -> Int { try u16(position) | u16(position + 2) << 16 }
        guard data.count >= 22 else { throw CocoaError(.fileReadCorruptFile) }
        var end: Int?
        for offset in stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1) {
            if try u32(offset) == 0x06054b50, offset + 22 + (try u16(offset + 20)) == data.count { end = offset; break }
        }
        guard let end, try u16(end + 4) == 0, try u16(end + 6) == 0 else { throw CocoaError(.fileReadCorruptFile) }
        let count = try u16(end + 10)
        guard count <= 2000, try u16(end + 8) == count else { throw CocoaError(.fileReadCorruptFile) }
        var cursor = try u32(end + 16)
        let directoryEnd = try cursor + u32(end + 12)
        guard directoryEnd <= end else { throw CocoaError(.fileReadCorruptFile) }
        var files: [String: Data] = [:]
        var total = 0
        for _ in 0..<count {
            guard try u32(cursor) == 0x02014b50 else { throw CocoaError(.fileReadCorruptFile) }
            let flags = try u16(cursor + 8), method = try u16(cursor + 10)
            let crc = try u32(cursor + 16), compressed = try u32(cursor + 20), size = try u32(cursor + 24)
            let nameLength = try u16(cursor + 28), extra = try u16(cursor + 30), comment = try u16(cursor + 32)
            let local = try u32(cursor + 42)
            guard flags & 1 == 0, (method == 0 || method == 8), size <= 32 * 1024 * 1024,
                  cursor + 46 + nameLength + extra + comment <= directoryEnd,
                  let name = String(data: data.subdata(in: cursor + 46..<cursor + 46 + nameLength), encoding: .utf8),
                  !name.contains(".."), !name.hasPrefix("/"), files[name] == nil,
                  try u32(local) == 0x04034b50 else { throw CocoaError(.fileReadCorruptFile) }
            let start = try local + 30 + u16(local + 26) + u16(local + 28)
            guard start >= 0, start + compressed <= data.count else { throw CocoaError(.fileReadCorruptFile) }
            total += size
            guard total <= 64 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
            let payload = data.subdata(in: start..<start + compressed)
            let decoded: Data
            if method == 0 {
                guard compressed == size else { throw CocoaError(.fileReadCorruptFile) }
                decoded = payload
            } else {
                var output = Data(count: max(1, size))
                var stream = z_stream()
                guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw CocoaError(.fileReadCorruptFile) }
                defer { inflateEnd(&stream) }
                let status = payload.withUnsafeBytes { input in
                    output.withUnsafeMutableBytes { buffer in
                        stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                        stream.avail_in = uInt(compressed)
                        stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress
                        stream.avail_out = uInt(max(1, size))
                        return inflate(&stream, Z_FINISH)
                    }
                }
                guard status == Z_STREAM_END, stream.total_out == size, stream.total_in == compressed else { throw CocoaError(.fileReadCorruptFile) }
                decoded = output.prefix(size)
            }
            let checksum = decoded.withUnsafeBytes { bytes in
                crc32(0, bytes.bindMemory(to: Bytef.self).baseAddress, uInt(decoded.count))
            }
            guard UInt32(truncatingIfNeeded: checksum) == UInt32(crc) else { throw CocoaError(.fileReadCorruptFile) }
            files[name] = decoded
            cursor += 46 + nameLength + extra + comment
        }
        guard cursor == directoryEnd else { throw CocoaError(.fileReadCorruptFile) }
        return files
    }
}

private final class SpreadsheetXML: NSObject, XMLParserDelegate {
    struct Cell { var type = ""; var value = ""; var formula = false }
    var rows: [[String: Cell]] = []
    var strings: [String] = []
    private var row: [String: Cell] = [:]
    private var cell = Cell()
    private var column = ""
    private var capture = false
    private var shared = false
    private var sharedText = ""
    private var invalid = false

    static func parse(_ data: Data, shared: Bool) throws -> SpreadsheetXML {
        let delegate = SpreadsheetXML(); delegate.shared = shared
        let parser = XMLParser(data: data); parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), !delegate.invalid else { throw CocoaError(.fileReadCorruptFile) }
        return delegate
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        switch elementName {
        case "row": row = [:]
        case "si": sharedText = ""
        case "c":
            cell = Cell(type: attributes["t"] ?? "")
            column = String((attributes["r"] ?? "").prefix { $0.isLetter })
        case "f": cell.formula = true
        case "v", "t": capture = true
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capture {
            if shared { sharedText += string } else { cell.value += string }
            if max(sharedText.utf16.count, cell.value.utf16.count) > 32767 { invalid = true; parser.abortParsing() }
        }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "v", "t": capture = false
        case "c":
            if row[column] != nil { invalid = true; parser.abortParsing() }
            row[column] = cell
        case "row":
            rows.append(row)
            if rows.count > 200000 { invalid = true; parser.abortParsing() }
        case "si": strings.append(sharedText)
        default: break
        }
    }
}

/// Offline OOXML export. Inline strings keep user notes as text, never Excel formulas.
/// Genera un libro XLSX local sin dependencias externas ni envío de datos a servidores.
enum ExcelExport {
    /// A–H son columnas visibles; I–K conservan fecha exacta y medicamentos para una restauración sin pérdidas.
    static func make(readings: [BloodPressureReading]) throws -> URL {
        guard readings.count < 1_048_576 else { throw CocoaError(.fileWriteUnknown) }
        guard readings.allSatisfy({ $0.note.utf16.count <= 32_767 && $0.medicationSummary.utf16.count <= 32_767 }) else { throw CocoaError(.fileWriteUnknown) }
        let namespace = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        let headers = [L10n.text("Fecha y hora"), L10n.text("Momento"), L10n.text("Sistólica") + " (mmHg)",
                       L10n.text("Diastólica") + " (mmHg)", L10n.text("Pulso") + " (" + L10n.text("lpm") + ")",
                       L10n.text("Notas"), "ID", L10n.text("Medicamentos de esta toma"), "MiTension.DateISO8601", "MiTension.Medications.v1", "MiTension.OriginalSerial"]
        var rows = "<row r=\"1\" ht=\"48\" customHeight=\"1\">"
        for (column, title) in headers.enumerated() { rows += textCell(title, ref: reference(column, 1), style: 1) }
        rows += "</row>"
        let sorted = readings.sorted { $0.measuredAt < $1.measuredAt }
        for (index, reading) in sorted.enumerated() {
            let row = index + 2
            let lines = (reading.note + "\n" + reading.medicationSummary).components(separatedBy: .newlines).reduce(0) { total, line in
                let width = line.unicodeScalars.reduce(0) { $0 + ($1.value >= 0x2E80 ? 2 : 1) }
                return total + max(1, (width + 44) / 45)
            }
            let height = min(409, max(24, lines * 16))
            rows += "<row r=\"\(row)\" ht=\"\(height)\" customHeight=\"1\">"
            // Excel serial dates use local wall-clock time, retaining sortable numeric values.
            let epoch = Date(timeIntervalSince1970: -2_209_161_600)
            let serial = (reading.measuredAt.timeIntervalSince(epoch) + Double(TimeZone.current.secondsFromGMT(for: reading.measuredAt))) / 86_400
            rows += numberCell(String(serial), ref: "A\(row)", style: 2)
            rows += textCell(reading.period.title, ref: "B\(row)")
            rows += numberCell(String(reading.systolic), ref: "C\(row)")
            rows += numberCell(String(reading.diastolic), ref: "D\(row)")
            if let pulse = reading.pulse { rows += numberCell(String(pulse), ref: "E\(row)") }
            rows += textCell(reading.note, ref: "F\(row)")
            rows += textCell(reading.id.uuidString, ref: "G\(row)")
            rows += textCell(reading.medicationSummary, ref: "H\(row)")
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            rows += textCell(formatter.string(from: reading.measuredAt), ref: "I\(row)")
            let medications = String(decoding: try JSONEncoder().encode(reading.medications), as: UTF8.self)
            guard medications.utf16.count <= 32_767 else { throw CocoaError(.fileWriteUnknown) }
            rows += textCell(medications, ref: "J\(row)")
            rows += numberCell(String(serial), ref: "K\(row)", style: 2)
            rows += "</row>"
        }
        let last = sorted.count + 1
        let sheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="\(namespace)"><dimension ref="A1:K\(last)"/>
        <sheetViews><sheetView showGridLines="0" workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
        <cols><col min="1" max="1" width="24" customWidth="1"/><col min="2" max="2" width="18" customWidth="1"/><col min="3" max="4" width="24" customWidth="1"/><col min="5" max="5" width="20" customWidth="1"/><col min="6" max="6" width="52" customWidth="1"/><col min="7" max="7" width="40" customWidth="1"/><col min="8" max="8" width="52" customWidth="1"/><col min="9" max="11" hidden="1"/></cols>
        <sheetData>\(rows)</sheetData><autoFilter ref="A1:H\(last)"/></worksheet>
        """
        let styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="\(namespace)">
        <numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy-mm-dd hh:mm"/></numFmts>
        <fonts count="2"><font><sz val="11"/><name val="Arial"/><color rgb="FF172B3A"/></font><font><b/><sz val="11"/><name val="Arial"/><color rgb="FFFFFFFF"/></font></fonts>
        <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF126B70"/><bgColor indexed="64"/></patternFill></fill></fills>
        <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
        <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
        <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"><alignment vertical="center"/></xf>
        <xf numFmtId="1" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"><alignment horizontal="right" vertical="center"/></xf></cellXfs>
        <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
        """
        let files: [(String, String)] = [
            ("[Content_Types].xml", """
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
            """),
            ("_rels/.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"),
            ("xl/workbook.xml", "<workbook xmlns=\"\(namespace)\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"\(xml(L10n.text("Mediciones")))\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"),
            ("xl/_rels/workbook.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"),
            ("xl/styles.xml", styles), ("xl/worksheets/sheet1.xml", sheet)
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Mi-Tension-\(UUID().uuidString.prefix(8)).xlsx")
        try archive(files).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        return url
    }

    private static func reference(_ column: Int, _ row: Int) -> String { "\(UnicodeScalar(65 + column)!)\(row)" }
    private static func textCell(_ value: String, ref: String, style: Int = 0) -> String {
        "<c r=\"\(ref)\" s=\"\(style)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xml(value))</t></is></c>"
    }
    private static func numberCell(_ value: String, ref: String, style: Int = 3) -> String {
        "<c r=\"\(ref)\" s=\"\(style)\"><v>\(value)</v></c>"
    }
    private static func xml(_ text: String) -> String {
        let valid = text.unicodeScalars.filter { scalar in
            let n = scalar.value
            return n == 9 || n == 10 || n == 13 || (32...0xD7FF).contains(n) || (0xE000...0xFFFD).contains(n) || (0x10000...0x10FFFF).contains(n)
        }
        return String(String.UnicodeScalarView(valid)).replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Store-only ZIP avoids dependencies and preserves Unicode XML without lossy conversion.
    static func archive(_ files: [(String, String)], compress: Bool = false) -> Data {
        var output = Data(), directory = Data()
        func u16(_ value: UInt16, to data: inout Data) {
            data.append(UInt8(truncatingIfNeeded: value)); data.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        func u32(_ value: UInt32, to data: inout Data) {
            u16(UInt16(truncatingIfNeeded: value), to: &data); u16(UInt16(truncatingIfNeeded: value >> 16), to: &data)
        }
        for (path, contents) in files {
            let name = Data(path.utf8), payload = Data(contents.utf8)
            var encoded = payload
            var method: UInt16 = 0
            if compress {
                var stream = z_stream()
                if deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK {
                    var outputBuffer = Data(count: Int(deflateBound(&stream, uLong(payload.count))))
                    let capacity = outputBuffer.count
                    let result = payload.withUnsafeBytes { input in
                        outputBuffer.withUnsafeMutableBytes { output in
                            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                            stream.avail_in = uInt(payload.count)
                            stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
                            stream.avail_out = uInt(capacity)
                            return deflate(&stream, Z_FINISH)
                        }
                    }
                    if result == Z_STREAM_END { encoded = outputBuffer.prefix(Int(stream.total_out)); method = 8 }
                    deflateEnd(&stream)
                }
            }
            let offset = UInt32(output.count), size = UInt32(payload.count), compressedSize = UInt32(encoded.count)
            var crc: UInt32 = 0xFFFFFFFF
            for byte in payload {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB88320 : 0) }
            }
            crc ^= 0xFFFFFFFF
            u32(0x04034B50, to: &output)
            for v: UInt16 in [20, 0, method, 0, 33] { u16(v, to: &output) }
            for v in [crc, compressedSize, size] { u32(v, to: &output) }
            u16(UInt16(name.count), to: &output); u16(0, to: &output)
            output.append(name); output.append(encoded)
            u32(0x02014B50, to: &directory)
            for v: UInt16 in [20, 20, 0, method, 0, 33] { u16(v, to: &directory) }
            for v in [crc, compressedSize, size] { u32(v, to: &directory) }
            for v in [UInt16(name.count), 0, 0, 0, 0] { u16(v, to: &directory) }
            u32(0, to: &directory); u32(offset, to: &directory); directory.append(name)
        }
        let offset = UInt32(output.count)
        output.append(directory)
        u32(0x06054B50, to: &output); u16(0, to: &output); u16(0, to: &output)
        u16(UInt16(files.count), to: &output); u16(UInt16(files.count), to: &output)
        u32(UInt32(directory.count), to: &output); u32(offset, to: &output); u16(0, to: &output)
        return output
    }
}
