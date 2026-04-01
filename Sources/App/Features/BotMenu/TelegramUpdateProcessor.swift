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
    static let awaitingPhotoConfirm = "awaiting_photo_confirm"
    static let awaitingPhotoUpload  = "awaiting_photo_upload"
    static let pendingText          = "pending_text"
    static let pendingPhotos        = "pending_photos"
    static let isWaitingForNextPhoto = "is_waiting_for_next_photo"
}

/// Вся бизнес-логика бота (меню → приём сообщения → сохранение)
enum TelegramUpdateProcessor {

    // MARK: - Helpers
    
    // Главная клавиатура (всегда возвращаем её пользователю)
    private static func mainKeyboard(app: Application, userID: Int64) -> TGReplyKeyboardMarkup {
        var row: [TGKeyboardButton] = [TGKeyboardButton(text: "Оставить пожелание")]
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

    // Клавиатура подтверждения фото
    private static func photoConfirmKeyboard(hasAttachments: Bool) -> TGReplyKeyboardMarkup {
        if hasAttachments {
            return TGReplyKeyboardMarkup(
                keyboard: [
                    [TGKeyboardButton(text: "Отправить сообщение"), TGKeyboardButton(text: "Да, добавить ещё")],
                    [TGKeyboardButton(text: "Назад")]
                ],
                resize_keyboard: true,
                one_time_keyboard: false
            )
        } else {
            return TGReplyKeyboardMarkup(
                keyboard: [
                    [TGKeyboardButton(text: "Да, добавить фото/файл"), TGKeyboardButton(text: "Отправить без файлов")],
                    [TGKeyboardButton(text: "Назад")]
                ],
                resize_keyboard: true,
                one_time_keyboard: false
            )
        }
    }

    // Клавиатура ожидания загрузки фото (ещё не добавлено ни одного)
    private static func photoUploadKeyboard() -> TGReplyKeyboardMarkup {
        return TGReplyKeyboardMarkup(
            keyboard: [[TGKeyboardButton(text: "Назад")]],
            resize_keyboard: true,
            one_time_keyboard: false
        )
    }

    // Клавиатура после того, как фото уже добавлено
    private static func photoAddedKeyboard() -> TGReplyKeyboardMarkup {
        return TGReplyKeyboardMarkup(
            keyboard: [
                [TGKeyboardButton(text: "Отправить"), TGKeyboardButton(text: "Добавить ещё")],
                [TGKeyboardButton(text: "Назад")]
            ],
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

    private static func russianPlural(count: Int, single: String, few: String, many: String) -> String {
        let lastDigit = count % 10
        let lastTwoDigits = count % 100
        if lastTwoDigits >= 11 && lastTwoDigits <= 19 {
            return "\(count) \(many)"
        }
        if lastDigit == 1 {
            return "1 \(single)"
        }
        if lastDigit >= 2 && lastDigit <= 4 {
            return "\(count) \(few)"
        }
        return "\(count) \(many)"
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
                "Текст",
                "Фото (file_id)"
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
                    f.text,
                    (f.photoFileID ?? "").replacingOccurrences(of: ",", with: "\n")
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

    /// Сохраняет feedback и уведомляет ответственных. Возвращает после отправки благодарности.
    private static func saveFeedbackAndNotify(
        text: String,
        attachments: [TGAttachment],
        userID: Int64,
        username: String?,
        chatID: Int64,
        app: Application
    ) async throws {
        let fileIDs = attachments.map { $0.fileID }.joined(separator: ",")
        let item = Feedback(
            text: text,
            userID: userID,
            username: username,
            chatID: chatID,
            status: .new,
            officeTag: nil,
            source: "telegram",
            photoFileID: fileIDs.isEmpty ? nil : fileIDs
        )
        try await item.save(on: app.db)

        let notifyEnabled = (Environment.get("NOTIFY_ENABLED") ?? "false").lowercased() == "true"
        if notifyEnabled, let idsString = Environment.get("NOTIFY_CHAT_IDS") {
            let ids = idsString
                .split(separator: ",")
                .compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }

            guard !ids.isEmpty else {
                app.logger.info("NOTIFY_ENABLED=true, но список NOTIFY_CHAT_IDS пуст — уведомления пропущены")
                return
            }

            let created = item.createdAt ?? Date()
            let offset: TimeInterval = 3 * 3600
            let local = created.addingTimeInterval(offset)
            var gmtCal = Calendar(identifier: .gregorian)
            gmtCal.timeZone = TimeZone(secondsFromGMT: 0)!
            let c = gmtCal.dateComponents([.day, .month, .year, .hour, .minute], from: local)
            let dStr = String(format: "%02d.%02d.%04d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
            let tStr = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)

            let ticketUUID = item.id?.uuidString ?? ""
            let userTag = (username?.isEmpty == false) ? "@\(username!)" : "<без username>"
            let chatLine: String = (chatID != userID) ? "\nЧат Telegram: \(chatID)\n" : "\n"

            let notifyText = """
            ✉️ Новое сообщение
            Дата: \(dStr) \(tStr)
            Пользователь: \(userTag) (ID пользователя: \(userID))
            ID обращения: \(ticketUUID)
            \(chatLine)
            Текст:
            \(text)
            """

            for id in ids {
                if attachments.isEmpty {
                    await app.telegram.sendMessage(id, notifyText)
                } else {
                    await app.telegram.sendMediaGroup(id, attachments: attachments, caption: notifyText)
                }
            }

            app.logger.info("Notifications sent to \(ids.count) responsible user(s)")
        } else {
            app.logger.info("Уведомления отключены (NOTIFY_ENABLED=false)")
        }

        await app.telegram.sendPhoto(
            chatID,
            photoURL: "https://raw.githubusercontent.com/Stockholm19/FeedbackBot/main/Assets/thanks.jpg",
            caption: nil,
            keyboard: mainKeyboard(app: app, userID: userID)
        )
    }

    static func handle(update: TGUpdate, app: Application) async throws {
        guard let msg = update.message else { return }

        let chatID = msg.chat.id
        let userID = msg.from?.id ?? chatID
        let username = msg.from?.username
        let currentState = SessionStore.shared.get(chatID, key: SessionKey.state) as? String ?? ""

        // Обработка входящего медиа (фото или документ/файл)
        let incomingAttachment: TGAttachment? = {
            if let photos = msg.photo, !photos.isEmpty {
                if let fileID = photos.sorted(by: { $0.width * $0.height < $1.width * $1.height }).last?.file_id {
                    return TGAttachment(fileID: fileID, type: "photo")
                }
            }
            if let doc = msg.document {
                return TGAttachment(fileID: doc.file_id, type: "document")
            }
            return nil
        }()

        if let att = incomingAttachment {
            if currentState == SessionKey.awaitingPhotoUpload {
                var accumulated = SessionStore.shared.get(chatID, key: SessionKey.pendingPhotos) as? [TGAttachment] ?? []
                accumulated.append(att)
                SessionStore.shared.set(chatID, key: SessionKey.pendingPhotos, value: accumulated)

                let count = accumulated.count
                let countLabel = russianPlural(count: count, single: "вложение", few: "вложения", many: "вложений")
                
                // Сбрасываем флаг "ожидания следующего фото", так как файл получен
                SessionStore.shared.set(chatID, key: SessionKey.isWaitingForNextPhoto, value: false)
                
                await app.telegram.sendMessage(
                    chatID,
                    "Вложение добавлено (\(countLabel)). Отправить сообщение или добавить ещё?",
                    keyboard: photoAddedKeyboard()
                )
                return
            } else {
                // Файл прислан в другом состоянии (например, в самом начале)
                await app.telegram.sendMessage(
                    chatID,
                    "Сначала напишите текст вашего сообщения, а потом я предложу добавить к нему фото или файл. 😊",
                    keyboard: currentState.isEmpty ? mainKeyboard(app: app, userID: userID) : inputKeyboard()
                )
                return
            }
        }

        // Для текстовых команд требуем непустой текст
        guard let raw = msg.text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }

        let text = raw
        let cmd = normalizeCommand(text)

        app.logger.info("TG Update: text=\(text), cmd=\(cmd), userID=\(userID), chatID=\(chatID)")

        // 1) /export — только для админов
        if cmd == "/export" {
            SessionStore.shared.set(chatID, key: SessionKey.state, value: "")
            try await doExport(app: app, chatID: chatID, userID: userID)
            return
        }

        // 2) /whoami — диагностика
        if cmd == "/whoami" {
            await app.telegram.sendMessage(chatID, "userID=\(userID), chatID=\(chatID)\nadmins=\(Array(app.adminIDs))", keyboard: mainKeyboard(app: app, userID: userID))
            return
        }

        // 3) /start — главное меню
        if cmd == "/start" {
            SessionStore.shared.set(chatID, key: SessionKey.state, value: "")
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

        // 4) Кнопка "Экспорт"
        if text == "Экспорт" {
            SessionStore.shared.set(chatID, key: SessionKey.state, value: "")
            try await doExport(app: app, chatID: chatID, userID: userID)
            return
        }

        // 5) Кнопка "Оставить пожелание" — ждём текст
        if text == "Оставить пожелание" {
            SessionStore.shared.set(chatID, key: SessionKey.state, value: SessionKey.awaiting)
            await app.telegram.sendMessage(
                chatID,
                "Расскажите, с чем столкнулись, или предложите идеи по улучшению офиса. Я передам информацию ответственным сотрудникам.",
                keyboard: inputKeyboard()
            )
            return
        }

        // 6) Кнопка "Назад" — контекстный возврат
        if text == "Назад" {
            switch currentState {
            case SessionKey.awaitingPhotoUpload:
                let photos = SessionStore.shared.get(chatID, key: SessionKey.pendingPhotos) as? [TGAttachment] ?? []
                let isWaiting = SessionStore.shared.get(chatID, key: SessionKey.isWaitingForNextPhoto) as? Bool ?? false
                
                if !photos.isEmpty && isWaiting {
                    // Пользователь нажал "Добавить еще", но передумал и нажал "Назад".
                    // Возвращаем его к меню выбора (Отправить/Добавить еще), сохраняя фото.
                    SessionStore.shared.set(chatID, key: SessionKey.isWaitingForNextPhoto, value: false)
                    let count = photos.count
                    let countLabel = russianPlural(count: count, single: "вложение", few: "вложения", many: "вложений")
                    await app.telegram.sendMessage(
                        chatID,
                        "Вложение добавлено (\(countLabel)). Отправить сообщение или добавить ещё?",
                        keyboard: photoAddedKeyboard()
                    )
                } else {
                    // Пользователь уже на экране подтверждения (после добавления вложений) и нажал "Назад".
                    // Или фото еще нет. 
                    // Мы переходим к этапу подтверждения фото, но НЕ удаляем уже загруженные, если они есть.
                    SessionStore.shared.set(chatID, key: SessionKey.state, value: SessionKey.awaitingPhotoConfirm)
                    SessionStore.shared.set(chatID, key: SessionKey.isWaitingForNextPhoto, value: false)
                    
                    if photos.isEmpty {
                        await app.telegram.sendMessage(
                            chatID,
                            "Хотите добавить фото или файл?",
                            keyboard: photoConfirmKeyboard(hasAttachments: false)
                        )
                    } else {
                        let count = photos.count
                        let countLabel = russianPlural(count: count, single: "вложение", few: "вложения", many: "вложений")
                        await app.telegram.sendMessage(
                            chatID,
                            "У вас уже добавлены \(countLabel). Хотите добавить ещё или отправить сообщение?",
                            keyboard: photoConfirmKeyboard(hasAttachments: true)
                        )
                    }
                }
            case SessionKey.awaitingPhotoConfirm:
                // Возврат к вводу текста — вот ТУТ мы очищаем всё, так как пользователь хочет переписать текст
                SessionStore.shared.set(chatID, key: SessionKey.state, value: SessionKey.awaiting)
                SessionStore.shared.set(chatID, key: SessionKey.pendingText, value: "")
                SessionStore.shared.set(chatID, key: SessionKey.pendingPhotos, value: [TGAttachment]())
                SessionStore.shared.set(chatID, key: SessionKey.isWaitingForNextPhoto, value: false)
                await app.telegram.sendMessage(
                    chatID,
                    "Введите текст сообщения заново:",
                    keyboard: inputKeyboard()
                )
            default:
                // Из любого другого состояния — главное меню
                SessionStore.shared.set(chatID, key: SessionKey.state, value: "")
                SessionStore.shared.set(chatID, key: SessionKey.pendingText, value: "")
                SessionStore.shared.set(chatID, key: SessionKey.pendingPhotos, value: [TGAttachment]())
                SessionStore.shared.set(chatID, key: SessionKey.isWaitingForNextPhoto, value: false)
                await app.telegram.sendMessage(
                    chatID,
                    "Хорошо, вернул в главное меню. Выберите действие:",
                    keyboard: mainKeyboard(app: app, userID: userID)
                )
            }
            return
        }

        // 7) Ждём текст сообщения
        if currentState == SessionKey.awaiting {
            SessionStore.shared.set(chatID, key: SessionKey.pendingText, value: text)
            SessionStore.shared.set(chatID, key: SessionKey.state, value: SessionKey.awaitingPhotoConfirm)
            await app.telegram.sendMessage(
                chatID,
                "Хотите добавить фото или файл?",
                keyboard: photoConfirmKeyboard(hasAttachments: false)
            )
            return
        }

        // 8) Подтверждение фото
        if currentState == SessionKey.awaitingPhotoConfirm {
            let currentAttachments = SessionStore.shared.get(chatID, key: SessionKey.pendingPhotos) as? [TGAttachment] ?? []

            if text == "Отправить без файлов" || text == "Отправить сообщение" {
                let pendingText = SessionStore.shared.get(chatID, key: SessionKey.pendingText) as? String ?? ""
                SessionStore.shared.set(chatID, key: SessionKey.state, value: "")
                SessionStore.shared.set(chatID, key: SessionKey.pendingText, value: "")
                SessionStore.shared.set(chatID, key: SessionKey.pendingPhotos, value: [TGAttachment]())
                SessionStore.shared.set(chatID, key: SessionKey.isWaitingForNextPhoto, value: false)
                try await saveFeedbackAndNotify(
                    text: pendingText,
                    attachments: currentAttachments,
                    userID: userID,
                    username: username,
                    chatID: chatID,
                    app: app
                )
                return
            }
            if text == "Да, добавить фото/файл" || text == "Да, добавить ещё" {
                SessionStore.shared.set(chatID, key: SessionKey.state, value: SessionKey.awaitingPhotoUpload)
                // Сохраняем уже накопленные фото в сессии
                SessionStore.shared.set(chatID, key: SessionKey.isWaitingForNextPhoto, value: true)
                await app.telegram.sendMessage(
                    chatID,
                    "Отправьте фото или файл, и я прикреплю его к вашему сообщению.",
                    keyboard: photoUploadKeyboard()
                )
                return
            }
            
            // Если в этом состоянии прислали что-то другое
            let hasAtt = !currentAttachments.isEmpty
            await app.telegram.sendMessage(
                chatID,
                hasAtt ? "Пожалуйста, выберите: добавить ещё файлы или отправить сообщение." : "Пожалуйста, выберите: прикрепить файлы или отправить сообщение без них.",
                keyboard: photoConfirmKeyboard(hasAttachments: hasAtt)
            )
            return
        }

        // 8.1) Управление накопленными вложениями
        if currentState == SessionKey.awaitingPhotoUpload {
            if text == "Отправить" {
                let pendingText = SessionStore.shared.get(chatID, key: SessionKey.pendingText) as? String ?? ""
                let attachments = SessionStore.shared.get(chatID, key: SessionKey.pendingPhotos) as? [TGAttachment] ?? []
                SessionStore.shared.set(chatID, key: SessionKey.state, value: "")
                SessionStore.shared.set(chatID, key: SessionKey.pendingText, value: "")
                SessionStore.shared.set(chatID, key: SessionKey.pendingPhotos, value: [TGAttachment]())
                SessionStore.shared.set(chatID, key: SessionKey.isWaitingForNextPhoto, value: false)
                try await saveFeedbackAndNotify(
                    text: pendingText,
                    attachments: attachments,
                    userID: userID,
                    username: username,
                    chatID: chatID,
                    app: app
                )
                return
            }
            if text == "Добавить ещё" {
                SessionStore.shared.set(chatID, key: SessionKey.isWaitingForNextPhoto, value: true)
                await app.telegram.sendMessage(
                    chatID,
                    "Отправьте следующее фото или файл.",
                    keyboard: photoUploadKeyboard()
                )
                return
            }
            
            // Любой другой текст — напоминаем, что ждём фото или файл
            let accumulated = SessionStore.shared.get(chatID, key: SessionKey.pendingPhotos) as? [TGAttachment] ?? []
            let keyboard = accumulated.isEmpty ? photoUploadKeyboard() : photoAddedKeyboard()
            await app.telegram.sendMessage(
                chatID,
                "Жду фото или файл 📷 Если хотите изменить сообщение — нажмите «Назад».",
                keyboard: keyboard
            )
            return
        }

        // 9) Fallback
        // Сбрасываем состояние в пустое, чтобы пользователь не "застрял" в середине сценария
        SessionStore.shared.set(chatID, key: SessionKey.state, value: "")
        SessionStore.shared.set(chatID, key: SessionKey.pendingText, value: "")
        SessionStore.shared.set(chatID, key: SessionKey.pendingPhotos, value: [TGAttachment]())
        SessionStore.shared.set(chatID, key: SessionKey.isWaitingForNextPhoto, value: false)
        
        await app.telegram.sendMessage(
            chatID, 
            "Не понял вас. 😕 Нажмите /start для вызова меню.", 
            keyboard: mainKeyboard(app: app, userID: userID)
        )
    }
}
