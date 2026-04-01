//
//  TelegramService.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 03.10.2025.
//

import Vapor
import Foundation

protocol TelegramService {
    func sendMessage(_ chatID: Int64, _ text: String) async
    func sendMessage(_ chatID: Int64, _ text: String, keyboard: TGReplyKeyboardMarkup) async
    func sendMessageRemovingKeyboard(_ chatID: Int64, _ text: String) async
    func sendDocument(_ chatID: Int64, filename: String, data: ByteBuffer) async
    func sendDocument(_ chatID: Int64, filename: String, data: ByteBuffer, caption: String?, keyboard: TGReplyKeyboardMarkup?) async
    func sendDocument(_ chatID: Int64, filename: String, data: Data, caption: String?, keyboard: TGReplyKeyboardMarkup?) async
    func sendDocument(_ chatID: Int64, fileURL: URL, fileName: String, caption: String?, keyboard: TGReplyKeyboardMarkup?) async
    func sendPhoto(_ chatID: Int64, photoURL: String, caption: String?, keyboard: TGReplyKeyboardMarkup?) async
    func sendPhotoByFileID(_ chatID: Int64, fileID: String, caption: String?, keyboard: TGReplyKeyboardMarkup?) async
    func sendVideoByFileID(_ chatID: Int64, fileID: String, caption: String?, keyboard: TGReplyKeyboardMarkup?) async
    func sendDocumentByFileID(_ chatID: Int64, fileID: String, caption: String?, keyboard: TGReplyKeyboardMarkup?) async
    func sendMediaGroup(_ chatID: Int64, attachments: [TGAttachment], caption: String?) async
}

struct NoopTelegramService: TelegramService {
    func sendMessage(_ chatID: Int64, _ text: String) async {}
    func sendMessage(_ chatID: Int64, _ text: String, keyboard: TGReplyKeyboardMarkup) async {}
    func sendMessageRemovingKeyboard(_ chatID: Int64, _ text: String) async {}
    func sendDocument(_ chatID: Int64, filename: String, data: ByteBuffer) async {}
    func sendDocument(_ chatID: Int64, filename: String, data: ByteBuffer, caption: String?, keyboard: TGReplyKeyboardMarkup?) async {}
    func sendDocument(_ chatID: Int64, filename: String, data: Data, caption: String?, keyboard: TGReplyKeyboardMarkup?) async {}
    func sendDocument(_ chatID: Int64, fileURL: URL, fileName: String, caption: String?, keyboard: TGReplyKeyboardMarkup?) async {}
    func sendPhoto(_ chatID: Int64, photoURL: String, caption: String?, keyboard: TGReplyKeyboardMarkup?) async {}
    func sendPhotoByFileID(_ chatID: Int64, fileID: String, caption: String?, keyboard: TGReplyKeyboardMarkup?) async {}
    func sendVideoByFileID(_ chatID: Int64, fileID: String, caption: String?, keyboard: TGReplyKeyboardMarkup?) async {}
    func sendDocumentByFileID(_ chatID: Int64, fileID: String, caption: String?, keyboard: TGReplyKeyboardMarkup?) async {}
    func sendMediaGroup(_ chatID: Int64, attachments: [TGAttachment], caption: String?) async {}
}

struct TGHTTPService: TelegramService {
    let app: Application
    let token: String

    private func endpoint(_ method: String) -> URI {
        URI(string: "https://api.telegram.org/bot\(token)/\(method)")
    }

    func sendMessage(_ chatID: Int64, _ text: String) async {
        do {
            let payload = TGSendMessagePayload<TGReplyKeyboardMarkup>(chat_id: chatID, text: text, reply_markup: nil)
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
    
    func sendDocument(_ chatID: Int64, filename: String, data: ByteBuffer) async {
        do {
            try await sendDocument(chatID, filename: filename, data: data, caption: nil, keyboard: nil)
        } catch {
            app.logger.report(error: error)
        }
    }
    
    func sendDocument(_ chatID: Int64, filename: String, data: ByteBuffer, caption: String?, keyboard: TGReplyKeyboardMarkup?) async {
        do {
            let boundary = "----FB\(UUID().uuidString)"
            var body = ByteBufferAllocator().buffer(capacity: 0)
            func write(_ s: String) { body.writeString(s) }

            // chat_id
            write("--\(boundary)\r\n")
            write("Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n")
            write("\(chatID)\r\n")

            // caption (optional)
            if let caption = caption, !caption.isEmpty {
                write("--\(boundary)\r\n")
                write("Content-Disposition: form-data; name=\"caption\"\r\n\r\n")
                write(caption)
                write("\r\n")
            }

            // reply_markup (optional) — Telegram ожидает JSON-строку
            if let keyboard = keyboard {
                let json = try JSONEncoder().encode(keyboard)
                if let jsonString = String(data: json, encoding: .utf8) {
                    write("--\(boundary)\r\n")
                    write("Content-Disposition: form-data; name=\"reply_markup\"\r\n\r\n")
                    write(jsonString)
                    write("\r\n")
                }
            }

            // document (file)
            write("--\(boundary)\r\n")
            write("Content-Disposition: form-data; name=\"document\"; filename=\"\(filename)\"\r\n")
            write("Content-Type: text/csv\r\n\r\n")
            var file = data
            body.writeBuffer(&file)
            write("\r\n--\(boundary)--\r\n")

            var req = ClientRequest(method: .POST, url: endpoint("sendDocument"))
            req.headers.add(name: "Content-Type", value: "multipart/form-data; boundary=\(boundary)")
            req.body = .init(buffer: body)
            let resp = try await app.client.send(req)
            if resp.status != .ok {
                let raw: String = {
                    if let b = resp.body, let s = b.getString(at: b.readerIndex, length: b.readableBytes) { return s }
                    return "<empty body>"
                }()
                app.logger.warning("[Telegram] sendDocument status=\(resp.status.code) body=\(raw)")
                return
            }
            struct TGOK: Decodable { let ok: Bool; let description: String? }
            if let b = resp.body,
               let raw = b.getString(at: b.readerIndex, length: b.readableBytes),
               let d = raw.data(using: .utf8) {
                if let parsed = try? JSONDecoder().decode(TGOK.self, from: d), parsed.ok == false {
                    app.logger.warning("[Telegram] sendDocument ok=false desc=\(parsed.description ?? "?")")
                }
            }
        } catch {
            app.logger.report(error: error)
        }
    }

    func sendDocument(_ chatID: Int64, filename: String, data: Data, caption: String?, keyboard: TGReplyKeyboardMarkup?) async {
        var buf = ByteBufferAllocator().buffer(capacity: data.count)
        buf.writeBytes(data)
        await sendDocument(chatID, filename: filename, data: buf, caption: caption, keyboard: keyboard)
    }

    func sendDocument(_ chatID: Int64, fileURL: URL, fileName: String, caption: String?, keyboard: TGReplyKeyboardMarkup?) async {
        do {
            let data = try Data(contentsOf: fileURL)
            await sendDocument(chatID, filename: fileName, data: data, caption: caption, keyboard: keyboard)
        } catch {
            app.logger.report(error: error)
        }
    }

    func sendPhoto(_ chatID: Int64, photoURL: String, caption: String?, keyboard: TGReplyKeyboardMarkup?) async {
        struct TGSendPhotoPayload: Content {
            let chat_id: Int64
            let photo: String
            let caption: String?
            let reply_markup: TGReplyKeyboardMarkup?
        }

        do {
            let payload = TGSendPhotoPayload(
                chat_id: chatID,
                photo: photoURL,
                caption: caption,
                reply_markup: keyboard
            )

            _ = try await app.client.post(endpoint("sendPhoto")) { req in
                try req.content.encode(payload)
            }
        } catch {
            app.logger.report(error: error)
        }
    }

    func sendVideoByFileID(_ chatID: Int64, fileID: String, caption: String?, keyboard: TGReplyKeyboardMarkup?) async {
        struct Payload: Content {
            let chat_id: Int64
            let video: String
            let caption: String?
            let reply_markup: TGReplyKeyboardMarkup?
        }
        do {
            let payload = Payload(chat_id: chatID, video: fileID, caption: caption, reply_markup: keyboard)
            _ = try await app.client.post(endpoint("sendVideo")) { try $0.content.encode(payload) }
        } catch { app.logger.report(error: error) }
    }

    func sendMediaGroup(_ chatID: Int64, attachments: [TGAttachment], caption: String?) async {
        guard !attachments.isEmpty else { return }

        // Если вложение одно, используем специализированный метод
        if attachments.count == 1 {
            let att = attachments[0]
            switch att.type {
            case "photo":
                await sendPhotoByFileID(chatID, fileID: att.fileID, caption: caption, keyboard: nil)
            case "video":
                await sendVideoByFileID(chatID, fileID: att.fileID, caption: caption, keyboard: nil)
            default:
                await sendDocumentByFileID(chatID, fileID: att.fileID, caption: caption, keyboard: nil)
            }
            return
        }

        // Telegram позволяет смешивать фото и видео в одной группе,
        // но не разрешает смешивать их с документами. Разделяем.
        let visuals = attachments.filter { $0.type == "photo" || $0.type == "video" }
        let docs = attachments.filter { $0.type == "document" }

        // Отправляем фото/видео-группу (если есть)
        if !visuals.isEmpty {
            struct InputMediaVisual: Encodable {
                let type: String // "photo" or "video"
                let media: String
                let caption: String?
            }
            let mediaItems = visuals.enumerated().map { i, att in
                InputMediaVisual(type: att.type, media: att.fileID, caption: (i == 0 && docs.isEmpty) ? caption : nil)
            }
            await sendMediaGroupGeneric(chatID, media: mediaItems)
        }

        // Отправляем документы группой (если есть)
        if !docs.isEmpty {
            struct InputMediaDoc: Encodable {
                let type: String = "document"
                let media: String
                let caption: String?
            }
            let mediaItems = docs.enumerated().map { i, id in
                InputMediaDoc(media: id.fileID, caption: (i == 0) ? caption : nil)
            }
            await sendMediaGroupGeneric(chatID, media: mediaItems)
        }
    }

    private struct TGMediaGroupPayload<M: Encodable>: Encodable {
        let chat_id: Int64
        let media: [M]
    }

    private func sendMediaGroupGeneric<M: Encodable>(_ chatID: Int64, media: [M]) async {
        do {
            let body = try JSONEncoder().encode(TGMediaGroupPayload(chat_id: chatID, media: media))
            var req = ClientRequest(method: .POST, url: endpoint("sendMediaGroup"))
            req.headers.add(name: "Content-Type", value: "application/json")
            req.body = .init(data: body)
            _ = try await app.client.send(req)
        } catch {
            app.logger.report(error: error)
        }
    }
    
    func sendDocumentByFileID(_ chatID: Int64, fileID: String, caption: String?, keyboard: TGReplyKeyboardMarkup?) async {
        struct Payload: Content {
            let chat_id: Int64
            let document: String
            let caption: String?
            let reply_markup: TGReplyKeyboardMarkup?
        }
        do {
            let payload = Payload(chat_id: chatID, document: fileID, caption: caption, reply_markup: keyboard)
            _ = try await app.client.post(endpoint("sendDocument")) { try $0.content.encode(payload) }
        } catch { app.logger.report(error: error) }
    }
    
    func sendPhotoByFileID(_ chatID: Int64, fileID: String, caption: String?, keyboard: TGReplyKeyboardMarkup?) async {
        struct TGSendPhotoPayload: Content {
            let chat_id: Int64
            let photo: String
            let caption: String?
            let reply_markup: TGReplyKeyboardMarkup?
        }

        do {
            let payload = TGSendPhotoPayload(
                chat_id: chatID,
                photo: fileID,
                caption: caption,
                reply_markup: keyboard
            )
            _ = try await app.client.post(endpoint("sendPhoto")) { req in
                try req.content.encode(payload)
            }
        } catch {
            app.logger.report(error: error)
        }
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
