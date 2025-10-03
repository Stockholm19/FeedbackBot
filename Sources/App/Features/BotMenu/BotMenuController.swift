//
//  BotMenuController.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 03.10.2025.
//

import Vapor

final class BotMenuController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let g = routes.grouped("menu")
        g.get("start", use: start)    // GET /menu/start?user=...
    }

    func start(req: Request) async throws -> String {
        let user = (try? req.query.get(String.self, at: "user")) ?? "guest"
        return "Hello, \(user)! Выберите действие: [Оставить обращение]"
    }
}
