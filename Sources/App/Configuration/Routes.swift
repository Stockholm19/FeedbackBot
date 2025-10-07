//
//  Routes.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 03.10.2025.
//

import Vapor
import Fluent
import SQLKit

public func registerRoutes(_ app: Application) throws {
    // Простая проверка живости
    app.get("health") { _ in "OK" }

    // Расширенная проверка для Kuma: сервер + БД
    /*
        Используется SQLKit, чтобы выполнить прямой запрос SELECT 1
        и проверить подключение к Postgres.
        Fluent сам по себе не имеет метода .raw(),
        поэтому req.db приводится к SQLDatabase.
    */
    app.get("healthz") { req async throws -> Response in
        var dbOK = false
        do {
            if let sql = req.db as? SQLDatabase {
                try await sql.raw("SELECT 1").run()
                dbOK = true
            } else {
                dbOK = false
            }
        } catch {
            dbOK = false
        }

        let payload: [String: String] = [
            "status": dbOK ? "ok" : "degraded",
            "db": dbOK ? "up" : "down",
            "env": req.application.environment.name
        ]

        var res = Response(status: dbOK ? .ok : .serviceUnavailable)
        try res.content.encode(payload, as: .json)
        return res
    }

    // Фичи
    try app.register(collection: BotMenuController())
    try app.register(collection: FeedbackController())
}
