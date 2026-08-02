// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectCloneService.swift - Validated bounded Git clone workflow.

import Foundation

enum ProjectCloneError: Error, Equatable, LocalizedError {
    case invalidRemote
    case embeddedCredentials
    case unsupportedScheme(String)
    case invalidParent(String)
    case symbolicLinkRejected(String)
    case invalidProjectName
    case destinationExists(String)
    case cloneFailed(exitCode: Int32, message: String)
    case clonedRepositoryMissing(String)

    var errorDescription: String? {
        switch self {
        case .invalidRemote:
            return "Enter a valid HTTPS or SSH Git URL."
        case .embeddedCredentials:
            return "The Git URL cannot contain a password, token, query, or fragment."
        case .unsupportedScheme:
            return "Only HTTPS and SSH Git URLs are supported."
        case .invalidParent(let path):
            return "The clone destination is not an existing directory: \(path)"
        case .symbolicLinkRejected(let path):
            return "The clone destination cannot be a symbolic link: \(path)"
        case .invalidProjectName:
            return "The Git URL does not contain a valid project name."
        case .destinationExists(let path):
            return "A file or folder already exists at \(path)."
        case .cloneFailed(let exitCode, let message):
            let detail = message.isEmpty ? "Git exited with code \(exitCode)." : message
            return "Git clone failed: \(detail)"
        case .clonedRepositoryMissing(let path):
            return "Git completed without creating a repository at \(path)."
        }
    }
}

struct ProjectCloneResult: Equatable, Sendable {
    let rootURL: URL
    let remoteOrigin: String
}

struct ProjectCloneService: Sendable {
    typealias GitRunner = @Sendable (URL, [String]) throws -> BoundedProcessResult

    private let fileManager: FileManager
    private let runGit: GitRunner

    init(
        fileManager: FileManager = .default,
        runGit: @escaping GitRunner = { parent, arguments in
            try MarketplaceGitProcessRunner(
                workingDirectory: parent,
                timeoutSeconds: 180
            ).run(arguments: arguments)
        }
    ) {
        self.fileManager = fileManager
        self.runGit = runGit
    }

    func clone(remote rawRemote: String, into parentDirectory: URL) throws -> ProjectCloneResult {
        let remote = try Self.validatedRemote(rawRemote)
        let parent = parentDirectory.standardizedFileURL
        try validateParent(parent)
        let projectName = try Self.projectName(from: remote)
        let destination = parent.appendingPathComponent(projectName, isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw ProjectCloneError.destinationExists(destination.path)
        }

        do {
            let result = try runGit(parent, [
                "clone", "--", remote.absoluteString, destination.path,
            ])
            guard !result.timedOut, result.exitCode == 0 else {
                throw ProjectCloneError.cloneFailed(
                    exitCode: result.exitCode,
                    message: Self.boundedMessage(result.stderr)
                )
            }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  fileManager.fileExists(
                    atPath: destination.appendingPathComponent(".git").path
                  ) else {
                throw ProjectCloneError.clonedRepositoryMissing(destination.path)
            }
            return ProjectCloneResult(
                rootURL: destination,
                remoteOrigin: remote.absoluteString
            )
        } catch {
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            throw error
        }
    }

    static func validatedRemote(_ rawRemote: String) throws -> URL {
        let trimmed = rawRemote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProjectCloneError.invalidRemote }
        let normalized = normalizeSCPRemote(trimmed) ?? trimmed
        guard let components = URLComponents(string: normalized),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty,
              let url = components.url else {
            throw ProjectCloneError.invalidRemote
        }
        guard ["https", "ssh"].contains(scheme) else {
            throw ProjectCloneError.unsupportedScheme(scheme)
        }
        guard components.password == nil,
              components.query == nil,
              components.fragment == nil,
              !(scheme == "https" && components.user != nil) else {
            throw ProjectCloneError.embeddedCredentials
        }
        return url
    }

    static func projectName(from remote: URL) throws -> String {
        var name = remote.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasSuffix(".git") {
            name.removeLast(4)
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
        guard !name.isEmpty,
              name != ".",
              name != "..",
              name.unicodeScalars.allSatisfy(allowed.contains) else {
            throw ProjectCloneError.invalidProjectName
        }
        return name
    }

    private func validateParent(_ parent: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: parent.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ProjectCloneError.invalidParent(parent.path)
        }
        let values = try parent.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw ProjectCloneError.symbolicLinkRejected(parent.path)
        }
    }

    private static func normalizeSCPRemote(_ remote: String) -> String? {
        guard !remote.contains("://"),
              let at = remote.firstIndex(of: "@"),
              let colon = remote[remote.index(after: at)...].firstIndex(of: ":") else {
            return nil
        }
        let user = remote[..<at]
        let host = remote[remote.index(after: at)..<colon]
        let path = remote[remote.index(after: colon)...]
        guard !user.isEmpty, !host.isEmpty, !path.isEmpty,
              !path.contains(".."),
              !path.contains("\\") else {
            return nil
        }
        return "ssh://\(user)@\(host)/\(path)"
    }

    private static func boundedMessage(_ message: String) -> String {
        String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000))
    }
}
