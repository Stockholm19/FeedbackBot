//
//  Bootstrap.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 03.10.2025.
//

import Vapor
import Fluent

public func bootstrap(_ app: Application) async throws {
    // Слушаем все интерфейсы и порт (важно для Docker)
    app.http.server.configuration.hostname = Environment.get("HOST") ?? "0.0.0.0"
    app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 8080

    app.logger.notice("Environment: \(app.environment.name)")

    // Базовая конфигурация (БД, миграции, роуты)
    try await configure(app)

    // Автомиграции: в dev (Флаг окружения явно задан)
    /*
     Проверка на наличие флага через docker compose exec app printenv AUTO_MIGRATE
     
     Если запускаю проект локально (режим development),
     или если в Docker-файле/ENV указано AUTO_MIGRATE=true,
     тогда Vapor сам применит все миграции при старте.
    */
    if app.environment == .development || Environment.bool("AUTO_MIGRATE") {
        try await app.autoMigrate()
    }
}
