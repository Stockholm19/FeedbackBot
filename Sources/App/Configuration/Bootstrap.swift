//
//  Bootstrap.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 03.10.2025.
//

import Vapor
import Fluent
import FluentPostgresDriver

public func bootstrap(_ app: Application) async throws {
    // Слушаем все интерфейсы и порт из ENV (важно для Docker)
    app.http.server.configuration.hostname = Environment.get("HOST") ?? "0.0.0.0"
    app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 8080

    app.logger.notice("Environment: \(app.environment.name)")

    // Подключение к Postgres: сначала пробуем DATABASE_URL, иначе — по полям
    if let url = Environment.get("DATABASE_URL") {
        let cfg = try SQLPostgresConfiguration(url: url)
        app.databases.use(.postgres(configuration: cfg), as: .psql)
    } else {
        let cfg = SQLPostgresConfiguration(
            hostname: Environment.get("DB_HOST") ?? Environment.get("POSTGRES_HOST") ?? "localhost",
            port: .init(Environment.get("DB_PORT").flatMap(Int.init) ?? Environment.get("POSTGRES_PORT").flatMap(Int.init) ?? 5432),
            username: Environment.get("DB_USER") ?? Environment.get("POSTGRES_USER") ?? "postgres",
            password: Environment.get("DB_PASSWORD") ?? Environment.get("POSTGRES_PASSWORD") ?? "postgres",
            database: Environment.get("DB_NAME") ?? Environment.get("POSTGRES_DB") ?? "feedback",
            tls: .disable
        )
        app.databases.use(.postgres(configuration: cfg), as: .psql)
    }

    // Миграции
    try registerMigrations(app)
    if app.environment == .development || Environment.get("AUTO_MIGRATE") == "true" {
        try await app.autoMigrate()
    }

    // Роуты
    try registerRoutes(app)
}
