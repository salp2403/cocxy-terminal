// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RichInputAttachmentStore.swift - Local cache for terminal rich input attachments.

import Foundation

enum RichInputAttachmentStoreError: Error, Equatable, Sendable {
    case attachmentTooLarge(byteCount: Int, maxBytes: Int)
}

extension RichInputAttachmentStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .attachmentTooLarge(let byteCount, let maxBytes):
            return "Image attachment is too large (\(byteCount) bytes, limit \(maxBytes) bytes)."
        }
    }
}

struct RichInputAttachmentStore {
    static let defaultTTLDays = 7
    static let defaultMaxSizeMB = 25

    let rootDirectory: URL
    let ttlDays: Int
    let maxSizeBytes: Int
    private let fileManager: FileManager
    private let clock: @Sendable () -> Date

    init(
        rootDirectory: URL = Self.defaultRootDirectory(),
        ttlDays: Int = Self.defaultTTLDays,
        maxSizeBytes: Int = Self.defaultMaxSizeMB * 1024 * 1024,
        fileManager: FileManager = .default,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.rootDirectory = rootDirectory
        self.ttlDays = max(0, ttlDays)
        self.maxSizeBytes = max(0, maxSizeBytes)
        self.fileManager = fileManager
        self.clock = clock
    }

    static func defaultRootDirectory() -> URL {
        let baseDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Cocxy", isDirectory: true)
            .appendingPathComponent("RichInputAttachments", isDirectory: true)
    }

    func store(
        _ image: ProcessedAgentImage,
        originalFilename: String? = nil
    ) throws -> AgentImageAttachment {
        guard image.data.count <= maxSizeBytes else {
            throw RichInputAttachmentStoreError.attachmentTooLarge(
                byteCount: image.data.count,
                maxBytes: maxSizeBytes
            )
        }

        _ = pruneExpired(now: clock())
        return try AgentAttachmentStorage(
            rootDirectory: rootDirectory,
            fileManager: fileManager
        ).store(image, originalFilename: originalFilename)
    }

    func remove(_ attachment: AgentImageAttachment) {
        try? fileManager.removeItem(atPath: attachment.filePath)
    }

    @discardableResult
    func pruneExpired(now: Date = Date()) -> Int {
        let cutoff = now.addingTimeInterval(-TimeInterval(ttlDays) * 24 * 60 * 60)
        guard let urls = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var removed = 0
        for url in urls where Self.isManagedAttachmentFile(url) {
            guard isRegularFile(url),
                  let modified = modificationDate(for: url),
                  modified < cutoff else {
                continue
            }
            if (try? fileManager.removeItem(at: url)) != nil {
                removed += 1
            }
        }
        return removed
    }

    private func isRegularFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile == true
    }

    private func modificationDate(for url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        if let modified = values?.contentModificationDate {
            return modified
        }
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }

    private static func isManagedAttachmentFile(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp":
            return true
        default:
            return false
        }
    }
}
