//
//  Configure.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 07.10.2025.
//

import Vapor
import Fluent
import FluentPostgresDriver

/// Основная конфигурация приложения: базы, миграции, роуты.
/// Вызывается из Bootstrap после базовых настроек сервера.
public func configure(_ app: Application) async throws {
    // --- Database ---
    if let url = Environment.get("DATABASE_URL") {
        let cfg = try SQLPostgresConfiguration(url: url)
        app.databases.use(.postgres(configuration: cfg), as: .psql)
    } else {
        let cfg = SQLPostgresConfiguration(
            hostname: Environment.get("DB_HOST") ?? Environment.get("POSTGRES_HOST") ?? "localhost",
            port: .init(Environment.get("DB_PORT").flatMap(Int.init)
                        ?? Environment.get("POSTGRES_PORT").flatMap(Int.init)
                        ?? 5432),
            username: Environment.get("DB_USER") ?? Environment.get("POSTGRES_USER") ?? "postgres",
            password: Environment.get("DB_PASSWORD") ?? Environment.get("POSTGRES_PASSWORD") ?? "postgres",
            database: Environment.get("DB_NAME") ?? Environment.get("POSTGRES_DB") ?? "feedback",
            tls: .disable
        )
        app.databases.use(.postgres(configuration: cfg), as: .psql)
        
        if let token = Environment.get("TELEGRAM_TOKEN"), !token.isEmpty {
               app.logger.info("Telegram enabled")
               app.telegram = TGHTTPService(app: app, token: token)
           } else {
               app.logger.warning("TELEGRAM_TOKEN not set — TelegramService is Noop")
               app.telegram = NoopTelegramService()
           }
    }
    
    if let poller = TelegramPolling(app: app) {
        app.lifecycle.use(poller)
    }

    // --- Migrations ---
    try registerMigrations(app)

    // --- Routes ---
    try registerRoutes(app)
}
