//
//  TelegramService.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 03.10.2025.
//

import Vapor

// Позже добавить свою реализацию. Сейчас просто интерфейс/протокол.
protocol TelegramService {
    func sendMessage(_ chatID: Int64, _ text: String) async
    // + другие методы (sendDocument, etc.)
}

// Пример no-op, чтобы проект компилировался
struct NoopTelegramService: TelegramService {
    func sendMessage(_ chatID: Int64, _ text: String) async {
        // no-op
    }
}
