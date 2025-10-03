//
//  FeedbackController.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 03.10.2025.
//

import Vapor
import Fluent

struct FeedbackDTO: Content {
    let text: String
    let userID: Int64
    let username: String?
    let officeTag: String?
}

final class FeedbackController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let g = routes.grouped("feedback")
        g.get(use: list)
        g.post(use: create)
    }

    // GET /feedback
    func list(req: Request) async throws -> [Feedback] {
        try await Feedback.query(on: req.db)
            .sort(\.$createdAt, .descending)
            .limit(50)
            .all()
    }

    // POST /feedback
    func create(req: Request) async throws -> Response {
        let dto = try req.content.decode(FeedbackDTO.self)
        let item = Feedback(
            text: dto.text,
            userID: dto.userID,
            username: dto.username,
            officeTag: dto.officeTag
        )
        try await item.save(on: req.db)

        // пример CSV экспорта одной записи (как заглушка)
        _ = CSVExporter.export([item]) { f in
            let df = ISO8601DateFormatter()
            let created = f.createdAt.map { df.string(from: $0) } ?? ""
            return [
                f.id?.uuidString ?? "",
                created,
                f.status.rawValue,
                String(f.userID),
                f.username ?? "",
                f.officeTag ?? "",
                f.source ?? "",
                f.text.replacingOccurrences(of: "\n", with: " ")
            ]
        }

        return Response(status: .created)
    }
}
