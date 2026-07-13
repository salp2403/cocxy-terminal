// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProxyControlViewTests.swift - Sensitive proxy credential presentation contracts.

import AppKit
import Testing
@testable import CocxyTerminal

@Suite("Proxy credential controls")
struct ProxyControlViewTests {
    @Test("Copied credentials are marked concealed and transient")
    @MainActor
    func copiedCredentialsUseSensitivePasteboardTypes() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("cocxy-proxy-credential-\(UUID().uuidString)")
        )
        pasteboard.clearContents()

        let changeCount = try #require(
            SensitivePasteboardWriter.write("ephemeral-secret", to: pasteboard)
        )

        #expect(changeCount == pasteboard.changeCount)
        #expect(pasteboard.string(forType: .string) == "ephemeral-secret")
        #expect(pasteboard.types?.contains(SensitivePasteboardWriter.concealedType) == true)
        #expect(pasteboard.types?.contains(SensitivePasteboardWriter.transientType) == true)
        #expect(pasteboard.data(forType: SensitivePasteboardWriter.concealedType) != nil)
        #expect(pasteboard.data(forType: SensitivePasteboardWriter.transientType) != nil)

        pasteboard.clearContents()
    }
}
