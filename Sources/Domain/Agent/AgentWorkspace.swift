// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentWorkspace.swift - Workspace path validation for Agent tools.

import Foundation

enum AgentWorkspaceError: Error, Sendable, Equatable {
    case emptyPath
    case outsideRoot(String)
    case notFound(String)
    case notRegularFile(String)
    case notDirectory(String)
    case fileTooLarge(path: String, maxBytes: Int)
    case binaryFile(String)
    case nonUTF8File(String)
    case protectedSensitivePath(String)

    var code: String {
        switch self {
        case .emptyPath:
            return "workspace_empty_path"
        case .outsideRoot:
            return "workspace_outside_root"
        case .notFound:
            return "workspace_not_found"
        case .notRegularFile:
            return "workspace_not_regular_file"
        case .notDirectory:
            return "workspace_not_directory"
        case .fileTooLarge:
            return "workspace_file_too_large"
        case .binaryFile:
            return "workspace_binary_file"
        case .nonUTF8File:
            return "workspace_non_utf8_file"
        case .protectedSensitivePath:
            return "workspace_sensitive_path"
        }
    }

    var message: String {
        switch self {
        case .emptyPath:
            return "Path is required."
        case .outsideRoot(let path):
            return "Path escapes the Agent workspace: \(path)"
        case .notFound(let path):
            return "Path does not exist: \(path)"
        case .notRegularFile(let path):
            return "Path is not a regular file: \(path)"
        case .notDirectory(let path):
            return "Path is not a directory: \(path)"
        case .fileTooLarge(let path, let maxBytes):
            return "File is larger than the Agent read limit (\(maxBytes) bytes): \(path)"
        case .binaryFile(let path):
            return "File appears to be binary: \(path)"
        case .nonUTF8File(let path):
            return "File is not valid UTF-8: \(path)"
        case .protectedSensitivePath(let path):
            return "Path is protected from Agent tools: \(path)"
        }
    }
}

struct AgentWorkspace {
    let rootURL: URL
    private let fileManager: FileManager
    private let normalizedRootPath: String

    init(rootURL: URL, fileManager: FileManager = .default) {
        let normalizedRootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        self.rootURL = normalizedRootURL
        self.fileManager = fileManager
        self.normalizedRootPath = normalizedRootURL.path
    }

    func resolveExistingPath(_ rawPath: String) throws -> URL {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentWorkspaceError.emptyPath
        }

        let candidate = trimmed.hasPrefix("/")
            ? URL(fileURLWithPath: trimmed)
            : rootURL.appendingPathComponent(trimmed)
        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()

        guard contains(resolved) else {
            throw AgentWorkspaceError.outsideRoot(rawPath)
        }
        guard fileManager.fileExists(atPath: resolved.path) else {
            throw AgentWorkspaceError.notFound(relativePath(for: resolved))
        }
        let relativePath = relativePath(for: resolved)
        guard !AgentSensitivePathPolicy.isProtected(relativePath: relativePath) else {
            throw AgentWorkspaceError.protectedSensitivePath(relativePath)
        }

        return resolved
    }

    func requireRegularFile(_ rawPath: String) throws -> URL {
        let url = try resolveExistingPath(rawPath)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw AgentWorkspaceError.notRegularFile(relativePath(for: url))
        }
        return url
    }

    func requireDirectory(_ rawPath: String) throws -> URL {
        let url = try resolveExistingPath(rawPath)
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            throw AgentWorkspaceError.notDirectory(relativePath(for: url))
        }
        return url
    }

    func relativePath(for url: URL) -> String {
        let resolvedPath = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard resolvedPath != normalizedRootPath else { return "." }
        let prefix = normalizedRootPath + "/"
        guard resolvedPath.hasPrefix(prefix) else { return resolvedPath }
        return String(resolvedPath.dropFirst(prefix.count))
    }

    func contains(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path == normalizedRootPath || path.hasPrefix(normalizedRootPath + "/")
    }
}

enum AgentSensitivePathPolicy {
    static func isProtected(relativePath: String, isDirectory: Bool = false) -> Bool {
        let normalized = relativePath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalized != "." else { return false }

        let components = normalized.split(separator: "/").map(String.init)
        if components.contains(where: protectedComponents.contains) {
            return true
        }

        guard let filename = components.last else { return false }
        if protectedFilenames.contains(filename) {
            return true
        }
        if protectedSuffixes.contains(where: filename.hasSuffix) {
            return true
        }
        if isDirectory, protectedDirectoryNames.contains(filename) {
            return true
        }
        return false
    }

    private static let protectedComponents: Set<String> = [
        ".aws",
        ".azure",
        ".env",
        ".env.development",
        ".env.local",
        ".env.production",
        ".gcloud",
        ".gnupg",
        ".ssh",
    ]

    private static let protectedDirectoryNames: Set<String> = [
        "secrets",
    ]

    private static let protectedFilenames: Set<String> = [
        ".npmrc",
        ".pypirc",
        "credentials",
        "credentials.json",
        "id_dsa",
        "id_ecdsa",
        "id_ed25519",
        "id_rsa",
        "service-account.json",
        "service_account.json",
    ]

    private static let protectedSuffixes = [
        ".key",
        ".p12",
        ".pem",
        ".pfx",
    ]
}
