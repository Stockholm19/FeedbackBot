//
//  TelegramUpdateProcessor.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 10.10.2025.
//

import Vapor
import Fluent

enum SessionKey {
    static let state = "state"
    static let awaiting = "awaiting_feedback"
}

/// Вся бизнес-логика бота (меню → приём обращения → сохранение)
enum TelegramUpdateProcessor {
    static func handle(update: TGUpdate, app: Application) async throws {
        guard let msg = update.message,
              let raw = msg.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return }

        let chatID = msg.chat.id
        let userID = msg.from?.id ?? chatID
        let username = msg.from?.username
        let text = raw

        // 1) /start: показать меню
        if text == "/start" {
            let kb = TGReplyKeyboardMarkup(
                keyboard: [[TGKeyboardButton(text: "Оставить обращение")]],
                resize_keyboard: true,
                one_time_keyboard: false
            )
            await app.telegram.sendMessage(chatID, "Привет! Это *FeedbackBot*.\nВыберите действие:", keyboard: kb)
            return
        }

        // 2) нажали кнопку → ждём текст
        if text == "Оставить обращение" {
            SessionStore.shared.set(chatID, key: SessionKey.state, value: SessionKey.awaiting)
            await app.telegram.sendMessage(chatID, "Пожалуйста, отправьте текст обращения одним сообщением.")
            return
        }

        // 3) ждём текст → сохраняем в БД
        if (SessionStore.shared.get(chatID, key: SessionKey.state) as? String) == SessionKey.awaiting {
            SessionStore.shared.set(chatID, key: SessionKey.state, value: "")

            let item = Feedback(
                text: text,
                userID: userID,
                username: username,
                chatID: chatID,
                status: .new,
                officeTag: nil,
                source: "telegram"
            )
            try await item.save(on: app.db) // Fluent Application.db

            await app.telegram.sendMessageRemovingKeyboard(chatID, "✅ *Спасибо, ваше обращение принято!*")
            return
        }

        // fallback
        await app.telegram.sendMessage(chatID, "Не понял 🤖. Нажмите */start* для меню.")
    }
}
