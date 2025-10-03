//
//  SessionStore.swift
//  FeedbackBot
//
//  Created by Роман Пшеничников on 03.10.2025.
//

import Foundation

final class SessionStore {
    static let shared = SessionStore()
    private var storage: [Int64:[String:Any]] = [:]
    private let lock = NSLock()

    private init() {}

    func set(_ chatId: Int64, key: String, value: Any) {
        lock.lock(); defer { lock.unlock() }
        var dict = storage[chatId] ?? [:]
        dict[key] = value
        storage[chatId] = dict
    }

    func get(_ chatId: Int64, key: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return storage[chatId]?[key]
    }
}
