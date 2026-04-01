//
//  AddPhotoFileIDToFeedback.swift
//  FeedbackBot
//

import Fluent

struct AddPhotoFileIDToFeedback: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("feedback")
            .field("photo_file_id", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("feedback")
            .deleteField("photo_file_id")
            .update()
    }
}
