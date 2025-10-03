//
//  CreateFeedback.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 03.10.2025.
//

import Fluent

struct CreateFeedback: AsyncMigration {
    func prepare(on db: Database) async throws {
        try await db.schema(Feedback.schema)
            .id()
            .field("text", .string, .required)
            .field("user_id", .int64, .required)
            .field("username", .string)
            .field("chat_id", .int64)
            .field("status", .string, .required)
            .field("admin_note", .string)
            .field("office_tag", .string)
            .field("source", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }
    func revert(on db: Database) async throws {
        try await db.schema(Feedback.schema).delete()
    }
}
