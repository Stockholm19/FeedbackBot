//
//  Routes.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 03.10.2025.
//

import Vapor

public func registerRoutes(_ app: Application) throws {
    // Health
    app.get("health") { _ in "OK" }

    // Features route groups
    try app.register(collection: BotMenuController())
    try app.register(collection: FeedbackController())
}
