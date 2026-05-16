// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultSessionDragPayload.swift - Pasteboard payload for Vault session drag/drop.

import AppKit
import Foundation
import CocxyVault

struct VaultSessionDragPayload: Codable, Equatable, Sendable {
    static let pasteboardType = "dev.cocxy.terminal.vault-session"

    let sessionID: String
    let agentID: String

    init(sessionID: String, agentID: String) {
        self.sessionID = sessionID
        self.agentID = agentID
    }

    init(session: VaultSession) {
        self.init(sessionID: session.id, agentID: session.agentID.rawValue)
    }

    static func itemProvider(for session: VaultSession) -> NSItemProvider {
        itemProvider(for: VaultSessionDragPayload(session: session))
    }

    static func itemProvider(for payload: VaultSessionDragPayload) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: pasteboardType,
            visibility: .all
        ) { completion in
            completion(try? payload.encodedData(), nil)
            return nil
        }
        return provider
    }

    func encodedData() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> VaultSessionDragPayload {
        try JSONDecoder().decode(VaultSessionDragPayload.self, from: data)
    }

    static func from(pasteboard: NSPasteboard) -> VaultSessionDragPayload? {
        let type = NSPasteboard.PasteboardType(pasteboardType)
        guard let data = pasteboard.data(forType: type) else { return nil }
        return try? decode(data)
    }
}
