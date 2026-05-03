// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AttachmentStorage.swift - Local Agent Mode attachment persistence.

import Foundation

struct AgentAttachmentStorage {
    let rootDirectory: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL = Self.defaultRootDirectory(),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    static func defaultRootDirectory() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/agent/attachments", isDirectory: true)
    }

    func store(
        _ image: ProcessedAgentImage,
        originalFilename: String? = nil
    ) throws -> AgentImageAttachment {
        try ensureRootDirectory()

        let id = UUID().uuidString
        let filename = "\(id).\(image.fileExtension)"
        let fileURL = rootDirectory.appendingPathComponent(filename, isDirectory: false)
        try image.data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)

        return AgentImageAttachment(
            id: id,
            displayName: sanitizedDisplayName(originalFilename) ?? "image.\(image.fileExtension)",
            mimeType: image.mimeType,
            filePath: fileURL.path,
            byteCount: image.data.count,
            pixelWidth: image.pixelWidth,
            pixelHeight: image.pixelHeight
        )
    }

    func remove(_ attachment: AgentImageAttachment) {
        try? fileManager.removeItem(atPath: attachment.filePath)
    }

    private func ensureRootDirectory() throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: rootDirectory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw CocoaError(.fileWriteFileExists)
            }
        } else {
            try fileManager.createDirectory(
                at: rootDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootDirectory.path)
    }

    private func sanitizedDisplayName(_ filename: String?) -> String? {
        let trimmed = filename?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: "/:"))
            .joined(separator: "-")
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(120))
    }
}
