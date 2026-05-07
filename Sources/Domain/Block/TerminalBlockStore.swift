// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalBlockStore.swift - Append-only JSONL persistence for command blocks.

import Foundation

struct TerminalBlockStore {
    let rootDirectory: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL = TerminalBlockStore.defaultRootDirectory(),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    static func defaultRootDirectory() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/blocks", isDirectory: true)
    }

    func append(_ block: TerminalCommandBlock, sessionID: String) throws {
        try ensureRootDirectory()
        let line = try TerminalBlockSerializer.encodeLine(block)
        let fileURL = fileURL(forSessionID: sessionID)
        let data = Data(line.utf8)

        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: fileURL, options: [.atomic])
        }
    }

    func load(sessionID: String) throws -> [TerminalCommandBlock] {
        let fileURL = fileURL(forSessionID: sessionID)
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? TerminalBlockSerializer.decodeLine(String(line))
            }
    }

    func sessionIDs() throws -> [String] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return []
        }

        return try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .compactMap { url in
            guard url.pathExtension == "jsonl" else { return nil }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { return nil }
            return url.deletingPathExtension().lastPathComponent
        }
        .sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    func fileURL(forSessionID sessionID: String) -> URL {
        rootDirectory.appendingPathComponent("\(Self.sanitizedSessionID(sessionID)).jsonl")
    }

    static func sanitizedSessionID(_ sessionID: String) -> String {
        var output = ""
        var previousWasSeparator = false

        for scalar in sessionID.unicodeScalars {
            let value = scalar.value
            let isAllowed = (48...57).contains(value)
                || (65...90).contains(value)
                || (97...122).contains(value)
                || scalar == "-"
                || scalar == "_"

            if isAllowed {
                output.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                output.append("-")
                previousWasSeparator = true
            }
        }

        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return trimmed.isEmpty ? "default" : trimmed
    }

    private func ensureRootDirectory() throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: rootDirectory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw CocoaError(.fileWriteFileExists)
            }
            return
        }

        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}
