//
//  TelegramUpdateProcessor.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 10.10.2025.
//

import Vapor
import Fluent
import Foundation

enum SessionKey {
    static let state = "state"
    static let awaiting = "awaiting_feedback"
}

/// Вся бизнес-логика бота (меню → приём обращения → сохранение)
enum TelegramUpdateProcessor {

    // MARK: - Helpers
    
    // Главная клавиатура (всегда возвращаем её пользователю)
    private static func mainKeyboard(app: Application, userID: Int64) -> TGReplyKeyboardMarkup {
        var row: [TGKeyboardButton] = [TGKeyboardButton(text: "Оставить обращение")]
        if app.adminIDs.contains(userID) {
            row.append(TGKeyboardButton(text: "Экспорт"))
        }
        return TGReplyKeyboardMarkup(
            keyboard: [row],
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }

    // Простой замок для предотвращения параллельных/повторных экспортов на чат
    private static var exportLocks = Set<Int64>()
    private static let exportLockQueue = DispatchQueue(label: "tg.export.lock")
    private static func beginExportLock(chatID: Int64) -> Bool {
        return exportLockQueue.sync {
            if exportLocks.contains(chatID) { return false }
            exportLocks.insert(chatID)
            return true
        }
    }
    private static func endExportLock(chatID: Int64) {
        exportLockQueue.sync { exportLocks.remove(chatID) }
    }

    /// Нормализует команду: срезает суффикс @BotName и пробелы/аргументы. Пример: "/export@MyBot arg" -> "/export"
    private static func normalizeCommand(_ text: String) -> String {
        guard text.hasPrefix("/") else { return text }
        let firstToken = text.split(separator: " ").first.map(String.init) ?? text
        let head = firstToken.split(separator: "@").first.map(String.init) ?? firstToken
        return head
    }

    /// Выполняет экспорт CSV. Доступен только администраторам.
    private static func doExport(app: Application, chatID: Int64, userID: Int64) async throws {
        guard app.adminIDs.contains(userID) else {
            await app.telegram.sendMessage(chatID, "Команда доступна только администраторам.", keyboard: mainKeyboard(app: app, userID: userID))
            return
        }

        // Анти-дубль: если экспорт уже идёт в этом чате — ничего не запускаем
        guard beginExportLock(chatID: chatID) else {
            await app.telegram.sendMessage(chatID, "Экспорт уже готовится…", keyboard: mainKeyboard(app: app, userID: userID))
            return
        }
        defer { endExportLock(chatID: chatID) }

        do {
            let items = try await Feedback.query(on: app.db)
                .sort(\.$createdAt, .descending)
                .all()
            if items.isEmpty {
                app.logger.info("Export requested but no items found")
                await app.telegram.sendMessage(chatID, "Пока нет записей для экспорта.", keyboard: mainKeyboard(app: app, userID: userID))
                return
            }

            app.logger.info("Export requested by userID=\(userID), count=\(items.count)")
            await app.telegram.sendMessage(chatID, "Готовлю экспорт: \(items.count) записей…", keyboard: mainKeyboard(app: app, userID: userID))

            app.logger.info("CSV: start building")
            let buf = CSVExporter.export(items) { f in
                // Безопасные строковые представления для всех полей
                let created = (f.createdAt?.timeIntervalSince1970).map { String($0) } ?? ""
                let statusStr = String(describing: f.status)
                let userIDStr = String(describing: f.userID)
                let usernameStr = f.username ?? ""
                let officeStr = f.officeTag ?? ""
                let sourceStr = f.source ?? ""
                let textStr = String(describing: f.text).replacingOccurrences(of: "\n", with: " ")
                return [
                    f.id?.uuidString ?? "",
                    created,
                    statusStr,
                    userIDStr,
                    usernameStr,
                    officeStr,
                    sourceStr,
                    textStr
                ]
            }
            app.logger.info("CSV: built buffer")

            if buf.readableBytes == 0 {
                app.logger.warning("CSV buffer is empty — aborting sendDocument")
                await app.telegram.sendMessage(chatID, "Не удалось сформировать CSV: файл пустой.", keyboard: mainKeyboard(app: app, userID: userID))
                return
            }

            await app.telegram.sendDocument(
                chatID,
                filename: "feedback_export.csv",
                data: buf,
                caption: "Экспорт готов ✅",
                keyboard: mainKeyboard(app: app, userID: userID)
            )
        } catch {
            app.logger.report(error: error)
            await app.telegram.sendMessage(chatID, "Не получилось сделать экспорт 😕\n" + String(describing: error), keyboard: mainKeyboard(app: app, userID: userID))
        }
    }

    // MARK: - Entry

    static func handle(update: TGUpdate, app: Application) async throws {
        guard let msg = update.message,
              let raw = msg.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return }

        let chatID = msg.chat.id
        let userID = msg.from?.id ?? chatID
        let username = msg.from?.username
        let text = raw
        let cmd = normalizeCommand(text)

        app.logger.info("TG Update: text=\(text), cmd=\(cmd), userID=\(userID), chatID=\(chatID)")

        // 1) /export — только для админов
        if cmd == "/export" {
            try await doExport(app: app, chatID: chatID, userID: userID)
            return
        }

        // 2) /whoami — диагностика
        if cmd == "/whoami" {
            await app.telegram.sendMessage(chatID, "userID=\(userID), chatID=\(chatID)\nadmins=\(Array(app.adminIDs))", keyboard: mainKeyboard(app: app, userID: userID))
            return
        }

        // 3) /start — главное меню (добавляем кнопку экспорта для админов)
        if cmd == "/start" {
            let kb = mainKeyboard(app: app, userID: userID)
            await app.telegram.sendMessage(chatID, "Привет! Это *FeedbackBot*.\nВыберите действие:", keyboard: kb)
            return
        }

        // 4) Нажали кнопку "Экспорт"
        if text == "Экспорт" {
            try await doExport(app: app, chatID: chatID, userID: userID)
            return
        }

        // 5) Нажали кнопку "Оставить обращение" — ждём текст
        if text == "Оставить обращение" {
            SessionStore.shared.set(chatID, key: SessionKey.state, value: SessionKey.awaiting)
            await app.telegram.sendMessage(chatID, "Напишите ваше обращение. Я передам его анонимно.", keyboard: mainKeyboard(app: app, userID: userID))
            return
        }

        // 6) Если ждём текст — сохраняем обращение
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
            try await item.save(on: app.db)
            await app.telegram.sendMessage(chatID, "✅ *Спасибо, ваше обращение принято!*", keyboard: mainKeyboard(app: app, userID: userID))
            return
        }

        // 7) Fallback
        await app.telegram.sendMessage(chatID, "Не понял. Нажмите */start* для меню.", keyboard: mainKeyboard(app: app, userID: userID))
    }
}
