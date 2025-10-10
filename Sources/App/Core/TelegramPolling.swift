//
//  TelegramPolling.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 10.10.2025.
//

import Vapor

/// Запускает getUpdates в фоне (long-polling).
struct TelegramPolling: LifecycleHandler {
    private let token: String

    init?(app: Application) {
        guard let t = Environment.get("TELEGRAM_TOKEN"), !t.isEmpty else { return nil }
        token = t
    }

    func willBoot(_ app: Application) throws {
        guard Environment.bool("TELEGRAM_POLLING", default: true) else { return }
        app.logger.info("Telegram long-polling: ON")

        Task.detached { [token] in
            var offset = 0
            while !Task.isCancelled {
                do {
                    let uri = URI(string: "https://api.telegram.org/bot\(token)/getUpdates?timeout=50&offset=\(offset)")
                    let resp = try await app.client.get(uri)
                    struct Envelope: Content { let ok: Bool; let result: [TGUpdate] }
                    let data = try resp.content.decode(Envelope.self)

                    for upd in data.result {
                        offset = max(offset, upd.update_id + 1)
                        // В общий обработчик логики
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
