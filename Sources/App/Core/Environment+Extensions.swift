//
//  Environment+Extensions.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 07.10.2025.
//

import Vapor

extension Environment {
    /// Удобное чтение булевых флагов из .env
    static func bool(_ key: String, default defaultValue: Bool = false) -> Bool {
        guard let raw = Environment.get(key)?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else {
            return defaultValue
        }
        return ["1", "true", "yes", "y"].contains(raw)
    }
}
