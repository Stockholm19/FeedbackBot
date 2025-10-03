//
//  Feedback.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 03.10.2025.
//

import Vapor
import Fluent

enum FeedbackStatus: String, Codable, CaseIterable {
    case new, ack, closed
}

final class Feedback: Model, Content {
    static let schema = "feedback"

    @ID(key: .id) var id: UUID?
    @Field(key: "text") var text: String
    @Field(key: "user_id") var userID: Int64
    @OptionalField(key: "username") var username: String?
    @OptionalField(key: "chat_id") var chatID: Int64?
    @Enum(key: "status") var status: FeedbackStatus
    @OptionalField(key: "admin_note") var adminNote: String?
    @OptionalField(key: "office_tag") var officeTag: String?
    @OptionalField(key: "source") var source: String?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() { }

    init(text: String, userID: Int64, username: String? = nil, chatID: Int64? = nil,
         status: FeedbackStatus = .new, officeTag: String? = nil, source: String? = nil)
    {
        self.text = text
        self.userID = userID
        self.username = username
        self.chatID = chatID
        self.status = status
        self.officeTag = officeTag
        self.source = source
    }
}
