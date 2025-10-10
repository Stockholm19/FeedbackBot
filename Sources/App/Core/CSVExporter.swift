//
//  CSVExporter.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 03.10.2025.
//

import Vapor

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

    /// Собирает CSV-строку. По умолчанию разделитель `;` (как ты использовал в БД/экспорте).
    private static func buildCSV<T>(
        headers: [String]?,
        rows: [T],
        delimiter: Character,
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
        return lines.joined(separator: "\n") + "\n"
    }

    /// Экспорт в ByteBuffer (UTF‑8), без заголовков, разделитель по умолчанию — `;`.
    static func export<T>(
        _ rows: [T],
        delimiter: Character = ";",
        make: (T) -> [String]
    ) -> ByteBuffer {
        let csv = buildCSV(headers: nil, rows: rows, delimiter: delimiter, make: make)
        var buf = ByteBufferAllocator().buffer(capacity: csv.utf8.count)
        buf.writeString(csv)
        return buf
    }

    /// Экспорт с заголовками в ByteBuffer (UTF‑8).
    static func export<T>(
        headers: [String],
        rows: [T],
        delimiter: Character = ";",
        make: (T) -> [String]
    ) -> ByteBuffer {
        let csv = buildCSV(headers: headers, rows: rows, delimiter: delimiter, make: make)
        var buf = ByteBufferAllocator().buffer(capacity: csv.utf8.count)
        buf.writeString(csv)
        return buf
    }

    /// Экспорт в Data (удобно, если хочется передавать через перегрузку `sendDocument(data:)`).
    static func exportData<T>(
        headers: [String]? = nil,
        rows: [T],
        delimiter: Character = ";",
        make: (T) -> [String]
    ) -> Data {
        let csv = buildCSV(headers: headers, rows: rows, delimiter: delimiter, make: make)
        return Data(csv.utf8)
    }
}
