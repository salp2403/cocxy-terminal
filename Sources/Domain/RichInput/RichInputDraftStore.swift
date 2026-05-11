// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RichInputDraftStore.swift - Local JSON persistence for terminal rich input drafts.

import Foundation

struct RichInputDraftStore {
    let rootDirectory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        rootDirectory: URL = Self.defaultRootDirectory(),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    static func defaultRootDirectory() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/rich-input-drafts", isDirectory: true)
    }

    func load(tabID: String) throws -> RichInputDraft? {
        let url = fileURL(forTabID: tabID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(RichInputDraft.self, from: data)
    }

    func save(_ draft: RichInputDraft) throws {
        try ensureRootDirectory()
        let data = try encoder.encode(draft)
        let url = fileURL(forTabID: draft.tabID)
        try data.write(to: url, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func delete(tabID: String) {
        try? fileManager.removeItem(at: fileURL(forTabID: tabID))
    }

    func fileURL(forTabID tabID: String) -> URL {
        rootDirectory.appendingPathComponent("\(Self.sanitizedTabID(tabID)).json", isDirectory: false)
    }

    static func sanitizedTabID(_ tabID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = tabID.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let output = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return output.isEmpty ? "default" : output
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
}

