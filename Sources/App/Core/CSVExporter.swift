//
//  CSVExporter.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 03.10.2025.
//

import Vapor

struct CSVExporter {
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: ";", with: ",")
         .replacingOccurrences(of: "\n", with: " ")
    }

    static func export<T>(_ rows: [T], make: (T) -> [String]) -> ByteBuffer {
        var csv = rows.map { make($0).map(escape).joined(separator: ";") }
                      .joined(separator: "\n")
        csv.append("\n")
        var buf = ByteBufferAllocator().buffer(capacity: csv.utf8.count)
        buf.writeString(csv)
        return buf
    }
}
