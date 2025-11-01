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
        var row: [TGKeyboardButton] = [TGKeyboardButton(text: "Оставить сообщение")]
        if app.adminIDs.contains(userID) {
            row.append(TGKeyboardButton(text: "Экспорт"))
        }
        return TGReplyKeyboardMarkup(
            keyboard: [row],
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }

    // Клавиатура режима ввода (одна кнопка "Назад")
    private static func inputKeyboard() -> TGReplyKeyboardMarkup {
        return TGReplyKeyboardMarkup(
            keyboard: [[TGKeyboardButton(text: "Назад")]],
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
            let headers = [
                "Дата",
                "Время",
                "ID",
                "Статус",
                "ID пользователя",
                "Username",
                "Отдел/Тег",
                "Источник",
                "Текст"
            ]

            // Базовое «сейчас» — будем использовать только для пустых дат
            let now = Date()

            // Хелпер форматирования даты конкретной записи
            func formatDatePair(_ date: Date?) -> (String, String) {
                
                let d = date ?? now
                
                // Фиксированный сдвиг для Москвы: +03:00 (переходов нет)
                let offset: TimeInterval = 3 * 3600
                let local = d.addingTimeInterval(offset)
                var gmtCal = Calendar(identifier: .gregorian)
                gmtCal.timeZone = TimeZone(secondsFromGMT: 0)!
                let c = gmtCal.dateComponents([.day, .month, .year, .hour, .minute], from: local)
                let dStr = String(format: "%02d.%02d.%04d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
                let tStr = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
                return (dStr, tStr)
            }

            // Собираем CSV в Data (CRLF + BOM), безопасно для Linux/Excel
            let data = CSVExporter.exportData(
                headers: headers,
                rows: items,
                delimiter: ";",
                lineEnding: .crlf,
                addUTF8BOM: true
            ) { f in
                let (dStr, tStr) = formatDatePair(f.createdAt)
                return [
                    dStr,
                    tStr,
                    f.id?.uuidString ?? "",
                    String(describing: f.status),
                    String(describing: f.userID),
                    f.username ?? "",
                    f.officeTag ?? "",
                    f.source ?? "",
                    f.text
                ]
            }

            var buf = ByteBufferAllocator().buffer(capacity: data.count)
            buf.writeBytes(data)
            app.logger.info("CSV: built buffer, bytes=\(data.count)")

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
            app.logger.info("CSV: sent to Telegram")

        } catch {
            app.logger.error("export failed: \(String(describing: error))")
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
            // сбросим режим ввода, если пользователь ушёл в экспорт
            SessionStore.shared.set(chatID, key: SessionKey.state, value: "")
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
            let welcome = """
            Привет! Я твой офисный помощник — *Саяныч*! 😊

            Со мной легко и приятно решать любые вопросы! Заметил что-то сломанное? Закончилось печенье? Есть гениальная идея? Я тут как тут!

            Просто напиши мне, и я всё передам:
            • 🛠 Поломка (принтер, свет, вода)
            • 🍩 Вкусняшки (закончился чай, кофейные зерна, печеньки)
            • 💡 Идея (как сделать наш офис лучше)

            Я всегда на связи! Вместе сделаем нашу работу комфортнее.
            """
            await app.telegram.sendMessage(chatID, welcome, keyboard: kb)
            return
        }

        // 4) Нажали кнопку "Экспорт"
        if text == "Экспорт" {
            // сбросим режим ввода, если пользователь ушёл в экспорт
            SessionStore.shared.set(chatID, key: SessionKey.state, value: "")
            try await doExport(app: app, chatID: chatID, userID: userID)
            return
        }

        // 5) Нажали кнопку "Оставить сообщение" — ждём текст
        if text == "Оставить сообщение" {
            SessionStore.shared.set(chatID, key: SessionKey.state, value: SessionKey.awaiting)
            await app.telegram.sendMessage(
                chatID,
                "Расскажите, с чем столкнулись, или предложите идеи по улучшению офиса. Я передам информацию ответственным сотрудникам.",
                keyboard: inputKeyboard()
            )
            return
        }

        // 5.1) "Назад" — выходим из режима ввода и показываем меню
        if text == "Назад" {
            SessionStore.shared.set(chatID, key: SessionKey.state, value: "")
            await app.telegram.sendMessage(
                chatID,
                "Хорошо, вернул в главное меню. Выберите действие:",
                keyboard: mainKeyboard(app: app, userID: userID)
            )
            return
        }

        // 6) Если ждём текст — сохраняем сообщение
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

            // Уведомление ответственным (список из .env: NOTIFY_CHAT_IDS=123,456)
            let notifyEnabled = (Environment.get("NOTIFY_ENABLED") ?? "false").lowercased() == "true"
            if notifyEnabled, let idsString = Environment.get("NOTIFY_CHAT_IDS") {
                let ids = idsString
                    .split(separator: ",")
                    .compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }

                guard !ids.isEmpty else {
                    app.logger.info("NOTIFY_ENABLED=true, но список NOTIFY_CHAT_IDS пуст — уведомления пропущены")
                    return
                }

                // Форматируем дату/время с фиксированным московским +03:00
                let created = item.createdAt ?? Date()
                let offset: TimeInterval = 3 * 3600
                let local = created.addingTimeInterval(offset)
                var gmtCal = Calendar(identifier: .gregorian)
                gmtCal.timeZone = TimeZone(secondsFromGMT: 0)!
                let c = gmtCal.dateComponents([.day, .month, .year, .hour, .minute], from: local)
                let dStr = String(format: "%02d.%02d.%04d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
                let tStr = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)

                // Формируем текст уведомления с явным ID обращения (короткий UUID)
                let ticketUUID = item.id?.uuidString ?? ""
                let ticketShort = ticketUUID.isEmpty ? "—" : String(ticketUUID.prefix(8))
                let userTag = (username?.isEmpty == false) ? "@\(username!)" : "<без username>"

                // Формируем текст: сначала пользователь, затем ID обращения.
                // Чат выводим только если он отличается от userID (актуально для групп).
                let chatLine: String = (chatID != userID) ? "\nЧат Telegram: \(chatID)\n" : "\n"

                let msg = """
                ✉️ Новое сообщение
                Дата: \(dStr) \(tStr)
                Пользователь: \(userTag) (ID пользователя: \(userID))
                ID обращения: \(ticketUUID)
                \(chatLine)
                Текст:
                \(text)
                """

                for id in ids {
                    await app.telegram.sendMessage(id, msg)
                }

                app.logger.info("Notifications sent to \(ids.count) responsible user(s)")
            } else {
                app.logger.info("Уведомления отключены (NOTIFY_ENABLED=false)")
            }
            
            /* 
            let caption = """
            ✅ Спасибо, что поделились!
            Вы помогаете нам становиться лучше.
            """
            */
            
            await app.telegram.sendPhoto(
                chatID,
                photoURL: "https://raw.githubusercontent.com/Stockholm19/FeedbackBot/main/Assets/thanks.jpg",
                caption: nil,
                keyboard: mainKeyboard(app: app, userID: userID)
            )
            return
        }

        // 7) Fallback
        await app.telegram.sendMessage(chatID, "Не понял. Нажмите */start* для меню.", keyboard: mainKeyboard(app: app, userID: userID))
    }
}
