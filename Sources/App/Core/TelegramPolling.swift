//
//  TelegramPolling.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 10.10.2025.
//


import Vapor
import Foundation

struct TelegramPolling: LifecycleHandler {
    private let token: String
    private let offsetPath: String

    init?(app: Application) {
        guard let t = Environment.get("TELEGRAM_TOKEN"), !t.isEmpty else { return nil }
        self.token = t
        // Путь к файлу для сохранения смещения (offset) между рестартами.
        // Можно задать через ENV `TELEGRAM_OFFSET_FILE`, иначе используем ".tg_offset" в рабочей директории.
        self.offsetPath = Environment.get("TELEGRAM_OFFSET_FILE") ?? ".tg_offset"
    }

    func willBoot(_ app: Application) throws {
        guard Environment.bool("TELEGRAM_POLLING", default: true) else { return }
        app.logger.info("Telegram long-polling: ON")

        Task.detached { [app, token, offsetPath] in
            var offset = loadSavedOffset(path: offsetPath) ?? 0
            while !Task.isCancelled {
                do {
                    let uri = URI(string: "https://api.telegram.org/bot\(token)/getUpdates?timeout=50&offset=\(offset)")
                    let resp = try await app.client.get(uri)
                    struct Envelope: Content { let ok: Bool; let result: [TGUpdate] }
                    let data = try resp.content.decode(Envelope.self)

                    if data.ok == false {
                        app.logger.warning("Telegram getUpdates returned ok=false")
                    }

                    if data.result.isEmpty {
                        continue
                    }

                    // Обрабатываем апдейты по одному. Перед обработкой каждого —
                    // двигаем offset и сохраняем на диск, чтобы при крэше не зациклиться.
                    for upd in data.result {
                        let next = upd.update_id + 1
                        if next > offset {
                            offset = next
                            saveOffset(offset, path: offsetPath)
                        }
                        // Передаём в общий обработчик
                        try await TelegramUpdateProcessor.handle(update: upd, app: app)
                    }
                } catch {
                    app.logger.report(error: error)
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s backoff
                }
            }
        }
    }

    func shutdown(_ app: Application) {
        app.logger.info("Telegram long-polling: OFF")
    }
}

// MARK: - Offset persistence helpers
private func loadSavedOffset(path: String) -> Int? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          let value = Int(str) else { return nil }
    return value
}

private func saveOffset(_ value: Int, path: String) {
    let str = String(value)
    do {
        try str.data(using: .utf8)?.write(to: URL(fileURLWithPath: path), options: [.atomic])
    } catch {
        // Ошибка сохранения offset не критична — просто логируем.
        NSLog("[TelegramPolling] Failed to save offset: \(error)")
    }
}
