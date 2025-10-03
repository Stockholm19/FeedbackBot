//
//  Main.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 03.10.2025.
//

import Vapor
import App

@main
struct Runner {
    static func main() async {
        do {
            let app = try await Application.make(.detect())

            do {
                try await bootstrap(app)      // async bootstrap (см. ниже)
                try await app.execute()       // вместо app.run()
            } catch {
                let msg = String(describing: error)
                fputs("Fatal error: \(msg)\n", stderr)
                // падаем ниже на asyncShutdown
            }

            try await app.asyncShutdown()     // вместо defer { app.shutdown() }
        } catch {
            let msg = String(describing: error)
            fputs("Fatal startup error: \(msg)\n", stderr)
            exit(1)
        }
    }
}
