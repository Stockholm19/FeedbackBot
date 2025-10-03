//
//  Migrations.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 03.10.2025.
//

import Vapor
import Fluent

public func registerMigrations(_ app: Application) throws {
    // Features
    app.migrations.add(CreateFeedback())
}
