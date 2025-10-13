//
//  CSVExporter.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 03.10.2025.
//

import Vapor
import Foundation

/// Переводы строк для CSV
enum LineEnding {
    case lf   // \n — Unix/macOS
    case crlf // \r\n — Windows/Excel

    var string: String {
        switch self {
        case .lf: return "\n"
        case .crlf: return "\r\n"
        }
    }
}

/// Простая утилита для экспорта CSV.
/// Делает корректное RFC‑4180 экранирование (двойные кавычки и переносы строк),
/// поддерживает заголовки и на выход отдаёт ByteBuffer в UTF‑8 без BOM.
struct CSVExporter {
    /// Экранирует значение под CSV: если есть разделитель, кавычки или перевод строки —
    /// оборачивает в двойные кавычки и дублирует внутренние кавычки.
    private static func quote(_ s: String, delimiter: Character) -> String {
        var needsQuoting = false
        for ch in s { if ch == delimiter || ch == "\n" || ch == "\r" || ch == "\"" { needsQuoting = true; break } }
        guard needsQuoting else { return s }
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"" + escaped + "\""
    }

    private static func buildCSV<T>(
        headers: [String]?,
        rows: [T],
        delimiter: Character,
        lineEnding: LineEnding,
        make: (T) -> [String]
    ) -> String {
        let sep = String(delimiter)
        var lines: [String] = []
        if let headers, !headers.isEmpty {
            lines.append(headers.map { quote($0, delimiter: delimiter) }.joined(separator: sep))
        }
        for row in rows {
            let cols = make(row).map { quote($0, delimiter: delimiter) }
            lines.append(cols.joined(separator: sep))
        }
        // Завершаем переводом строки, чтобы CSV корректно открывался в Excel/Numbers
        return lines.joined(separator: lineEnding.string) + lineEnding.string
    }

    static func export<T>(
        _ rows: [T],
        delimiter: Character = ";",
        lineEnding: LineEnding = .lf,
        addUTF8BOM: Bool = false,
        make: (T) -> [String]
    ) -> ByteBuffer {
        let csv = buildCSV(headers: nil, rows: rows, delimiter: delimiter, lineEnding: lineEnding, make: make)
        let bom = addUTF8BOM ? "\u{FEFF}" : ""
        var buf = ByteBufferAllocator().buffer(capacity: bom.utf8.count + csv.utf8.count)
        if addUTF8BOM { buf.writeString(bom) }
        buf.writeString(csv)
        return buf
    }

    static func export<T>(
        headers: [String],
        rows: [T],
        delimiter: Character = ";",
        lineEnding: LineEnding = .lf,
        addUTF8BOM: Bool = false,
        make: (T) -> [String]
    ) -> ByteBuffer {
        let csv = buildCSV(headers: headers, rows: rows, delimiter: delimiter, lineEnding: lineEnding, make: make)
        let bom = addUTF8BOM ? "\u{FEFF}" : ""
        var buf = ByteBufferAllocator().buffer(capacity: bom.utf8.count + csv.utf8.count)
        if addUTF8BOM { buf.writeString(bom) }
        buf.writeString(csv)
        return buf
    }

    static func exportData<T>(
        headers: [String]? = nil,
        rows: [T],
        delimiter: Character = ";",
        lineEnding: LineEnding = .lf,
        addUTF8BOM: Bool = false,
        make: (T) -> [String]
    ) -> Data {
        let csv = buildCSV(headers: headers, rows: rows, delimiter: delimiter, lineEnding: lineEnding, make: make)
        if addUTF8BOM {
            var data = Data("\u{FEFF}".utf8)
            data.append(Data(csv.utf8))
            return data
        } else {
            return Data(csv.utf8)
        }
    }
}
