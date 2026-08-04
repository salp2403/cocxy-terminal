// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorProjectService.swift - Constrained local project creation.

import Foundation

protocol MobileMirrorProjectCreating: Sendable {
    func createProject(
        named name: String,
        in authorizedRoot: ProjectDirectoryRoot
    ) async throws -> ProjectDirectoryPublication
}

struct MobileMirrorProjectService: MobileMirrorProjectCreating, Sendable {
    typealias GitRunner = @Sendable (
        BoundedProcessWorkingDirectory,
        [String]
    ) throws -> BoundedProcessResult

    static let maximumNameUTF8Bytes = 160

    private let hooks: ProjectDirectoryTransactionHooks
    private let runGit: GitRunner

    init(
        gitExecutable: URL = URL(fileURLWithPath: "/usr/bin/git"),
        hooks: ProjectDirectoryTransactionHooks = .none,
        runGit: GitRunner? = nil
    ) {
        self.hooks = hooks
        self.runGit = runGit ?? { workingDirectory, arguments in
            try MarketplaceGitProcessRunner(
                gitExecutableURL: gitExecutable,
                workingDirectory: workingDirectory.displayURL,
                timeoutSeconds: 30,
                maximumRetainedBytesPerStream: 64 * 1_024
            ).run(arguments: arguments, workingDirectory: workingDirectory)
        }
    }

    func createProject(
        named rawName: String,
        in authorizedRoot: ProjectDirectoryRoot
    ) async throws -> ProjectDirectoryPublication {
        try Task.checkCancellation()
        let name = try Self.normalizedProjectName(rawName)
        let operation = Task.detached(priority: .userInitiated) {
            try createProjectSynchronously(named: name, in: authorizedRoot)
        }
        return try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
    }

    func createProject(
        named rawName: String,
        in authorizedRootURL: URL
    ) async throws -> ProjectDirectoryPublication {
        let root: ProjectDirectoryRoot
        do {
            root = try ProjectDirectoryRoot.open(
                authorizedRootURL,
                afterOpen: hooks.afterRootOpen
            )
        } catch {
            throw Self.mobileError(error)
        }
        return try await createProject(named: rawName, in: root)
    }

    func normalizedProjectName(_ rawName: String) throws -> String {
        try Self.normalizedProjectName(rawName)
    }

    static func normalizedProjectName(_ rawName: String) throws -> String {
        let name = rawName
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.utf8.count <= Self.maximumNameUTF8Bytes,
              name != ".",
              name != "..",
              !name.hasPrefix("."),
              !name.hasSuffix("."),
              !name.contains("/"),
              !name.contains(":"),
              !name.contains("\0"),
              name.unicodeScalars.allSatisfy({ scalar in
                  switch scalar.properties.generalCategory {
                  case .control, .format, .lineSeparator, .paragraphSeparator:
                      return false
                  default:
                      return true
                  }
              }) else {
            throw MobileMirrorError.invalidProjectName
        }
        return name
    }

    private func createProjectSynchronously(
        named name: String,
        in root: ProjectDirectoryRoot
    ) throws -> ProjectDirectoryPublication {
        try Task.checkCancellation()
        let transaction: ProjectDirectoryTransaction
        do {
            transaction = try ProjectDirectoryTransaction.begin(
                in: root,
                destinationName: name,
                hooks: hooks
            )
        } catch {
            throw Self.mobileError(error)
        }

        do {
            try Task.checkCancellation()
            let result = try runGit(try transaction.workingDirectory, [
                "init", "--quiet", "--initial-branch=main", "--", ".",
            ])
            guard !result.timedOut, result.exitCode == 0 else {
                let message = result.stderr
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw MobileMirrorError.projectCreationFailed(
                    message.isEmpty
                        ? "git init exited with status \(result.exitCode)"
                        : String(message.prefix(1_000))
                )
            }
            try transaction.verifyRepositoryMetadata()
            try Task.checkCancellation()
            let publication = try transaction.publish()
            _ = try publication.verifiedURL()
            return publication
        } catch let originalError {
            do {
                try transaction.cleanup()
            } catch {
                throw Self.mobileError(error)
            }
            throw Self.mobileError(originalError)
        }
    }

    private static func mobileError(_ error: Error) -> Error {
        guard let directoryError = error as? ProjectDirectoryError else { return error }
        switch directoryError {
        case .invalidRoot, .symbolicLinkRejected:
            return MobileMirrorError.projectCreationUnavailable
        case .invalidDestinationName:
            return MobileMirrorError.invalidProjectName
        case .destinationExists:
            return MobileMirrorError.projectAlreadyExists
        case .repositoryMetadataMissing:
            return MobileMirrorError.projectCreationFailed(
                "git did not create repository metadata"
            )
        case .publicationChanged(let path):
            return MobileMirrorError.projectCreationFailed(
                "the destination changed while publishing \(path)"
            )
        case .cleanupUnverified(let path):
            return MobileMirrorError.projectCreationFailed(
                "cleanup could not be verified at \(path)"
            )
        case .systemCallFailed:
            return MobileMirrorError.projectCreationFailed(
                directoryError.localizedDescription
            )
        }
    }
}
