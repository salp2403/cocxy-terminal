// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentPromptAttachmentPasteboardReaderSwiftTestingTests.swift - Paste/drop image attachment decoding contracts.

import AppKit
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Agent prompt attachment pasteboard reader")
struct AgentPromptAttachmentPasteboardReaderSwiftTestingTests {

    @Test("file URL payloads are preferred over image data")
    func fileURLPayloadsArePreferredOverImageData() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-agent-pasteboard-\(UUID().uuidString).png", isDirectory: false)
        try Self.pngData.write(to: fileURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("cocxy-agent-pasteboard-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        pasteboard.setData(Self.pngData, forType: .png)

        let reader = AgentPromptAttachmentPasteboardReader()
        let payload = try #require(reader.payload(from: pasteboard))

        #expect(reader.containsSupportedAttachment(pasteboard))
        #expect(payload == .fileURLs([fileURL]))
    }

    @Test("PNG payloads decode as pasted image data")
    func pngPayloadsDecodeAsPastedImageData() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("cocxy-agent-pasteboard-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setData(Self.pngData, forType: .png)

        let reader = AgentPromptAttachmentPasteboardReader()
        let payload = try #require(reader.payload(from: pasteboard))

        #expect(reader.containsSupportedAttachment(pasteboard))
        #expect(payload == .imageData(Self.pngData, suggestedFilename: "pasted-image.png"))
    }

    @Test("unsupported pasteboard content is ignored")
    func unsupportedPasteboardContentIsIgnored() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("cocxy-agent-pasteboard-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("not an attachment", forType: .string)

        let reader = AgentPromptAttachmentPasteboardReader()

        #expect(reader.payload(from: pasteboard) == nil)
        #expect(!reader.containsSupportedAttachment(pasteboard))
    }

    private static let pngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
    )!
}
