//
//  TelegramService.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 03.10.2025.
//

import Vapor

protocol TelegramService {
    func sendMessage(_ chatID: Int64, _ text: String) async
    func sendMessage(_ chatID: Int64, _ text: String, keyboard: TGReplyKeyboardMarkup) async
    func sendMessageRemovingKeyboard(_ chatID: Int64, _ text: String) async
}

struct NoopTelegramService: TelegramService {
    func sendMessage(_ chatID: Int64, _ text: String) async {}
    func sendMessage(_ chatID: Int64, _ text: String, keyboard: TGReplyKeyboardMarkup) async {}
    func sendMessageRemovingKeyboard(_ chatID: Int64, _ text: String) async {}
}

struct TGHTTPService: TelegramService {
    let app: Application
    let token: String

    private func endpoint(_ method: String) -> URI {
        URI(string: "https://api.telegram.org/bot\(token)/\(method)")
    }

    func sendMessage(_ chatID: Int64, _ text: String) async {
        do {
            let payload = TGSendMessagePayload<TGReplyKeyboardRemove>(chat_id: chatID, text: text, reply_markup: nil)
            _ = try await app.client.post(endpoint("sendMessage")) { try $0.content.encode(payload) }
        } catch { app.logger.report(error: error) }
    }

    func sendMessage(_ chatID: Int64, _ text: String, keyboard: TGReplyKeyboardMarkup) async {
        do {
            let payload = TGSendMessagePayload(chat_id: chatID, text: text, reply_markup: keyboard)
            _ = try await app.client.post(endpoint("sendMessage")) { try $0.content.encode(payload) }
        } catch { app.logger.report(error: error) }
    }

    func sendMessageRemovingKeyboard(_ chatID: Int64, _ text: String) async {
        do {
            let payload = TGSendMessagePayload(chat_id: chatID, text: text, reply_markup: TGReplyKeyboardRemove())
            _ = try await app.client.post(endpoint("sendMessage")) { try $0.content.encode(payload) }
        } catch { app.logger.report(error: error) }
    }
}

// Application.storage
private struct TelegramServiceKey: StorageKey { typealias Value = TelegramService }
extension Application {
    var telegram: TelegramService {
        get { storage[TelegramServiceKey.self] ?? NoopTelegramService() }
        set { storage[TelegramServiceKey.self] = newValue }
    }
}
