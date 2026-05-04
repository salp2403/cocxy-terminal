// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ClipboardHistoryStore.swift - Local bounded clipboard history model.

import Foundation

struct ClipboardHistoryStore: Sendable, Equatable {
    let limit: Int
    private(set) var items: [ClipboardHistoryItem]

    init(limit: Int = 50, items: [ClipboardHistoryItem] = []) {
        self.limit = max(1, limit)
        self.items = Array(items.sorted { $0.copiedAt > $1.copiedAt }.prefix(max(1, limit)))
    }

    @discardableResult
    mutating func record(
        text: String,
        at date: Date = Date()
    ) -> ClipboardHistoryItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        items.removeAll { $0.text == text }
        let item = ClipboardHistoryItem(text: text, copiedAt: date)
        items.insert(item, at: 0)
        if items.count > limit {
            items.removeSubrange(limit..<items.count)
        }
        return item
    }

    func search(_ query: String) -> [ClipboardHistoryItem] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return items }
        return items.filter { $0.text.lowercased().contains(normalized) }
    }

    mutating func clear() {
        items.removeAll()
    }
}
