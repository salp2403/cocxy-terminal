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
    case destinationChanged(String)
    case cleanupUnverified(String)

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
        case .destinationChanged(let path):
            return "The clone destination changed while Git was running: \(path)"
        case .cleanupUnverified(let path):
            return "Cocxy could not safely verify clone cleanup at \(path)."
        }
    }
}

struct ProjectCloneResult: Equatable, Sendable {
    let rootURL: URL
    let remoteOrigin: String
    private let publication: ProjectDirectoryPublication

    init(
        rootURL: URL,
        remoteOrigin: String,
        publication: ProjectDirectoryPublication
    ) {
        self.rootURL = rootURL
        self.remoteOrigin = remoteOrigin
        self.publication = publication
    }

    func verifiedRootURL() throws -> URL {
        try publication.verifiedURL()
    }

    static func == (lhs: ProjectCloneResult, rhs: ProjectCloneResult) -> Bool {
        lhs.rootURL == rhs.rootURL && lhs.remoteOrigin == rhs.remoteOrigin
    }
}

struct ProjectCloneService: Sendable {
    typealias GitRunner = @Sendable (
        BoundedProcessWorkingDirectory,
        [String]
    ) throws -> BoundedProcessResult

    private let hooks: ProjectDirectoryTransactionHooks
    private let runGit: GitRunner

    init(
        hooks: ProjectDirectoryTransactionHooks = .none,
        runGit: @escaping GitRunner = { workingDirectory, arguments in
            try MarketplaceGitProcessRunner(
                workingDirectory: workingDirectory.displayURL,
                timeoutSeconds: 180
            ).run(arguments: arguments, workingDirectory: workingDirectory)
        }
    ) {
        self.hooks = hooks
        self.runGit = runGit
    }

    func clone(remote rawRemote: String, into parentDirectory: URL) throws -> ProjectCloneResult {
        let root: ProjectDirectoryRoot
        do {
            root = try ProjectDirectoryRoot.open(
                parentDirectory,
                afterOpen: hooks.afterRootOpen
            )
        } catch {
            throw Self.cloneError(error, fallbackPath: parentDirectory.path)
        }
        return try clone(remote: rawRemote, in: root)
    }

    func clone(
        remote rawRemote: String,
        in parent: ProjectDirectoryRoot
    ) throws -> ProjectCloneResult {
        let remote = try Self.validatedRemote(rawRemote)
        let projectName = try Self.projectName(from: remote)
        let transaction: ProjectDirectoryTransaction
        do {
            transaction = try ProjectDirectoryTransaction.begin(
                in: parent,
                destinationName: projectName,
                hooks: hooks
            )
        } catch {
            throw Self.cloneError(error, fallbackPath: parent.displayURL.path)
        }

        do {
            let result = try runGit(try transaction.workingDirectory, [
                "clone", "--", remote.absoluteString, ".",
            ])
            guard !result.timedOut, result.exitCode == 0 else {
                throw ProjectCloneError.cloneFailed(
                    exitCode: result.exitCode,
                    message: Self.boundedMessage(result.stderr)
                )
            }
            try transaction.verifyRepositoryMetadata()
            let publication = try transaction.publish()
            let destination = try publication.verifiedURL()
            return ProjectCloneResult(
                rootURL: destination,
                remoteOrigin: remote.absoluteString,
                publication: publication
            )
        } catch let originalError {
            do {
                try transaction.cleanup()
            } catch {
                throw Self.cloneError(error, fallbackPath: parent.displayURL.path)
            }
            throw Self.cloneError(originalError, fallbackPath: parent.displayURL.path)
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

    private static func cloneError(_ error: Error, fallbackPath: String) -> Error {
        guard let directoryError = error as? ProjectDirectoryError else { return error }
        switch directoryError {
        case .invalidRoot(let path):
            return ProjectCloneError.invalidParent(path)
        case .symbolicLinkRejected(let path):
            return ProjectCloneError.symbolicLinkRejected(path)
        case .invalidDestinationName:
            return ProjectCloneError.invalidProjectName
        case .destinationExists(let path):
            return ProjectCloneError.destinationExists(path)
        case .repositoryMetadataMissing(let path):
            return ProjectCloneError.clonedRepositoryMissing(path)
        case .publicationChanged(let path):
            return ProjectCloneError.destinationChanged(path)
        case .cleanupUnverified(let path):
            return ProjectCloneError.cleanupUnverified(path)
        case .systemCallFailed:
            return ProjectCloneError.invalidParent(fallbackPath)
        }
    }
}
