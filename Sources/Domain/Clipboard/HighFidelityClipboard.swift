// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HighFidelityClipboard.swift - Multi-type NSPasteboard capture and restore.

import AppKit
import Foundation

struct HighFidelityClipboardSnapshot: Equatable, Sendable {
    let changeCount: Int
    let items: [HighFidelityPasteboardItem]

    var isEmpty: Bool {
        items.isEmpty
    }
}

struct HighFidelityPasteboardItem: Equatable, Sendable {
    let representations: [HighFidelityPasteboardRepresentation]

    var types: [String] {
        representations.map(\.type)
    }
}

struct HighFidelityPasteboardRepresentation: Equatable, Sendable {
    let type: String
    let data: Data
}

@MainActor
final class HighFidelityClipboard {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func capture() -> HighFidelityClipboardSnapshot {
        let items = pasteboard.pasteboardItems?.compactMap(Self.captureItem) ?? []
        return HighFidelityClipboardSnapshot(
            changeCount: pasteboard.changeCount,
            items: items
        )
    }

    @discardableResult
    func restore(_ snapshot: HighFidelityClipboardSnapshot) -> Bool {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return true }

        let items = snapshot.items.compactMap(Self.makePasteboardItem)
        guard items.count == snapshot.items.count else { return false }
        return pasteboard.writeObjects(items)
    }

    private static func captureItem(_ item: NSPasteboardItem) -> HighFidelityPasteboardItem? {
        let representations = item.types.compactMap { type -> HighFidelityPasteboardRepresentation? in
            if let data = item.data(forType: type) {
                return HighFidelityPasteboardRepresentation(type: type.rawValue, data: data)
            }
            if let string = item.string(forType: type),
               let data = string.data(using: .utf8) {
                return HighFidelityPasteboardRepresentation(type: type.rawValue, data: data)
            }
            return nil
        }
        guard !representations.isEmpty else { return nil }
        return HighFidelityPasteboardItem(representations: representations)
    }

    private static func makePasteboardItem(_ item: HighFidelityPasteboardItem) -> NSPasteboardItem? {
        guard !item.representations.isEmpty else { return nil }
        let pasteboardItem = NSPasteboardItem()
        for representation in item.representations {
            pasteboardItem.setData(
                representation.data,
                forType: NSPasteboard.PasteboardType(representation.type)
            )
        }
        return pasteboardItem
    }
}
