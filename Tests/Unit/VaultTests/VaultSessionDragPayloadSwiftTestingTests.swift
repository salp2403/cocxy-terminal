// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultSessionDragPayloadSwiftTestingTests.swift - Pasteboard coverage for Vault drag/drop.

import AppKit
import Foundation
import Testing
@testable import CocxyTerminal
@testable import CocxyVault

@Suite("Vault session drag payload")
struct VaultSessionDragPayloadSwiftTestingTests {
    @Test("payload round-trips through encoded data")
    func payloadRoundTripsThroughEncodedData() throws {
        let payload = VaultSessionDragPayload(sessionID: "codex:sess-123", agentID: "codex")

        let decoded = try VaultSessionDragPayload.decode(payload.encodedData())

        #expect(decoded == payload)
    }

    @Test("payload decodes from private pasteboard type")
    func payloadDecodesFromPrivatePasteboardType() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("vault-session-\(UUID().uuidString)"))
        let payload = VaultSessionDragPayload(sessionID: "claude:sess-456", agentID: "claude")
        pasteboard.clearContents()
        pasteboard.setData(
            try payload.encodedData(),
            forType: NSPasteboard.PasteboardType(VaultSessionDragPayload.pasteboardType)
        )

        #expect(VaultSessionDragPayload.from(pasteboard: pasteboard) == payload)
    }

    @Test("item provider exposes the private drag payload type")
    func itemProviderExposesPrivateDragPayloadType() async throws {
        let session = VaultSession(
            id: "codex:sess-provider",
            agentID: VaultAgentID("codex"),
            agentDisplayName: "Codex",
            sessionID: "sess-provider",
            workingDirectory: "/tmp/provider",
            capturedAt: Date(timeIntervalSince1970: 1_778_000_000),
            lastSeenAt: Date(timeIntervalSince1970: 1_778_000_100),
            source: .manual,
            sanitizedArguments: ["codex", "resume", "sess-provider"]
        )

        let provider = VaultSessionDragPayload.itemProvider(for: session)

        #expect(provider.hasItemConformingToTypeIdentifier(VaultSessionDragPayload.pasteboardType))
        let data = try await loadData(
            from: provider,
            typeIdentifier: VaultSessionDragPayload.pasteboardType
        )
        #expect(try VaultSessionDragPayload.decode(data) == VaultSessionDragPayload(session: session))
    }

    private func loadData(from provider: NSItemProvider, typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
    }
}
