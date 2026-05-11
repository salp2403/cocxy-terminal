// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RichInputAttachmentStoreSwiftTestingTests.swift - Rich Input attachment cache tests.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Rich input attachment store")
struct RichInputAttachmentStoreSwiftTestingTests {
    @Test("store uses private permissions and rich input cache root")
    func storeUsesPrivatePermissionsAndRichInputCacheRoot() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RichInputAttachmentStore(rootDirectory: root)

        let attachment = try store.store(Self.processedImage, originalFilename: "pasted/image.png")

        #expect(attachment.displayName == "pasted-image.png")
        #expect(attachment.fileURL.deletingLastPathComponent() == root)
        #expect(FileManager.default.fileExists(atPath: attachment.filePath))

        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: attachment.filePath)
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("prune expired removes old attachments and keeps fresh files")
    func pruneExpiredRemovesOldAttachmentsAndKeepsFreshFiles() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RichInputAttachmentStore(rootDirectory: root, ttlDays: 7)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let oldURL = root.appendingPathComponent("old.png")
        let freshURL = root.appendingPathComponent("fresh.png")
        let nonAttachmentURL = root.appendingPathComponent("notes.txt")
        try Data([1]).write(to: oldURL)
        try Data([2]).write(to: freshURL)
        try Data([3]).write(to: nonAttachmentURL)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try setModificationDate(now.addingTimeInterval(-8 * 24 * 60 * 60), for: oldURL)
        try setModificationDate(now.addingTimeInterval(-2 * 24 * 60 * 60), for: freshURL)
        try setModificationDate(now.addingTimeInterval(-8 * 24 * 60 * 60), for: nonAttachmentURL)

        let removed = store.pruneExpired(now: now)

        #expect(removed == 1)
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        #expect(FileManager.default.fileExists(atPath: freshURL.path))
        #expect(FileManager.default.fileExists(atPath: nonAttachmentURL.path))
    }

    @Test("store prunes expired files before adding new attachment")
    func storePrunesExpiredFilesBeforeAddingNewAttachment() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = RichInputAttachmentStore(rootDirectory: root, ttlDays: 7, clock: { now })
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let oldURL = root.appendingPathComponent("old.jpg")
        try Data([1]).write(to: oldURL)
        try setModificationDate(now.addingTimeInterval(-9 * 24 * 60 * 60), for: oldURL)

        let attachment = try store.store(Self.processedImage, originalFilename: "new.png")

        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        #expect(FileManager.default.fileExists(atPath: attachment.filePath))
    }

    @Test("store rejects attachments larger than configured limit")
    func storeRejectsAttachmentsLargerThanConfiguredLimit() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RichInputAttachmentStore(rootDirectory: root, maxSizeBytes: 2)
        let oversized = ProcessedAgentImage(
            data: Data([1, 2, 3]),
            mimeType: "image/png",
            fileExtension: "png",
            pixelWidth: 1,
            pixelHeight: 1
        )

        #expect(throws: RichInputAttachmentStoreError.attachmentTooLarge(byteCount: 3, maxBytes: 2)) {
            _ = try store.store(oversized, originalFilename: "big.png")
        }
    }

    private static let processedImage = ProcessedAgentImage(
        data: Data([0x89, 0x50, 0x4E, 0x47]),
        mimeType: "image/png",
        fileExtension: "png",
        pixelWidth: 1,
        pixelHeight: 1
    )

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-rich-input-attachments-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}
