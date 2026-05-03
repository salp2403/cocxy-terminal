// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentImageAttachmentSwiftTestingTests.swift - Agent image attachment contracts.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Agent image attachments")
struct AgentImageAttachmentSwiftTestingTests {

    @Test("image processor decodes and stores local attachment with private permissions")
    func processorAndStoragePersistAttachment() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let processed = try AgentImageProcessor(maxPixelDimension: 32).process(data: Self.pngData)
        let storage = AgentAttachmentStorage(rootDirectory: root)
        let attachment = try storage.store(processed, originalFilename: " pasted/image.png ")

        #expect(attachment.displayName == "pasted-image.png")
        #expect(attachment.mimeType.hasPrefix("image/"))
        #expect(attachment.pixelWidth == 1)
        #expect(attachment.pixelHeight == 1)
        #expect(FileManager.default.fileExists(atPath: attachment.filePath))

        let attributes = try FileManager.default.attributesOfItem(atPath: attachment.filePath)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("image processor rejects unsupported data")
    func processorRejectsUnsupportedData() {
        #expect(throws: AgentImageProcessorError.self) {
            _ = try AgentImageProcessor().process(data: Data("not an image".utf8))
        }
    }

    @Test("agent message decodes missing image attachments as empty")
    func messageDecodesMissingAttachmentsAsEmpty() throws {
        let data = Data("""
        {
          "id": "m1",
          "role": "user",
          "content": "hello",
          "createdAt": 1777800000
        }
        """.utf8)

        let message = try JSONDecoder().decode(AgentMessage.self, from: data)

        #expect(message.imageAttachments.isEmpty)
    }

    static let pngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
    )!

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-agent-attachment-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
