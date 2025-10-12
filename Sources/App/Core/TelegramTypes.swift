//
//  TelegramTypes.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 10.10.2025.
//

import Vapor

// MARK: - Incoming
struct TGUpdate: Content { let update_id: Int; let message: TGMessage? }
struct TGMessage: Content {
    let message_id: Int
    let date: Int
    let chat: TGChat
    let from: TGUser?
    let text: String?
}
struct TGChat: Content { let id: Int64 }
struct TGUser: Content { let id: Int64; let username: String? }

// MARK: - Reply keyboard
struct TGKeyboardButton: Content { let text: String }
struct TGReplyKeyboardMarkup: Content {
    let keyboard: [[TGKeyboardButton]]
    let resize_keyboard: Bool
    let one_time_keyboard: Bool
}

struct TGReplyKeyboardRemove: Content {
    var remove_keyboard: Bool = true
}

// MARK: - Outgoing
struct TGSendMessagePayload<M: Content>: Content {
    let chat_id: Int64
    let text: String
    let parse_mode: String?
    let reply_markup: M?
    init(chat_id: Int64, text: String, parse_mode: String? = "Markdown", reply_markup: M? = nil) {
        self.chat_id = chat_id
        self.text = text
        self.parse_mode = parse_mode
        self.reply_markup = reply_markup
    }
}
