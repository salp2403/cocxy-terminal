// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Project directory transaction", .serialized)
struct ProjectDirectoryTransactionSwiftTestingTests {
    @Test("root authority remains bound after its pathname is replaced")
    func rootReplacementUsesOpenedDirectory() throws {
        let container = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: container) }
        let selected = container.appendingPathComponent("selected", isDirectory: true)
        let moved = container.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false)

        let root = try ProjectDirectoryRoot.open(selected) { _ in
            try FileManager.default.moveItem(at: selected, to: moved)
            try FileManager.default.createDirectory(
                at: selected,
                withIntermediateDirectories: false
            )
        }
        let transaction = try ProjectDirectoryTransaction.begin(
            in: root,
            destinationName: "Demo"
        )
        try createGitDirectory(in: transaction)
        try transaction.verifyRepositoryMetadata()
        let publication = try transaction.publish()

        #expect(try publication.verifiedURL() == moved.appendingPathComponent("Demo"))
        #expect(!FileManager.default.fileExists(
            atPath: selected.appendingPathComponent("Demo").path
        ))
    }

    @Test("exclusive publication preserves a concurrent destination")
    func concurrentDestinationWinsWithoutBeingDeleted() throws {
        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let root = try ProjectDirectoryRoot.open(rootURL)
        let hooks = ProjectDirectoryTransactionHooks(beforePublish: { context in
            try FileManager.default.createDirectory(
                at: context.destinationURL,
                withIntermediateDirectories: false
            )
            try "keep".write(
                to: context.destinationURL.appendingPathComponent("owner.txt"),
                atomically: true,
                encoding: .utf8
            )
        })
        let transaction = try ProjectDirectoryTransaction.begin(
            in: root,
            destinationName: "Demo",
            hooks: hooks
        )
        try createGitDirectory(in: transaction)

        #expect(throws: ProjectDirectoryError.self) {
            try transaction.publish()
        }
        try transaction.cleanup()
        #expect(try String(
            contentsOf: rootURL.appendingPathComponent("Demo/owner.txt"),
            encoding: .utf8
        ) == "keep")
        #expect(try stagingEntries(in: rootURL).isEmpty)
    }

    @Test("a publication rejected after the creation inventory still cleans its staging directory")
    func rejectedPublicationCleansInventoriedStaging() throws {
        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let hooks = ProjectDirectoryTransactionHooks(beforePublish: { context in
            try FileManager.default.createDirectory(
                at: context.destinationURL,
                withIntermediateDirectories: false
            )
        })
        let transaction = try ProjectDirectoryTransaction.begin(
            in: ProjectDirectoryRoot.open(rootURL),
            destinationName: "Demo",
            hooks: hooks
        )
        try createGitDirectory(in: transaction)
        try "created".write(
            to: try transaction.workingDirectory.displayURL.appendingPathComponent(".git/HEAD"),
            atomically: false,
            encoding: .utf8
        )

        do {
            _ = try transaction.publish()
            Issue.record("Publication should fail when the destination exists")
        } catch ProjectDirectoryError.destinationExists {
        }
        #expect(throws: Never.self) { try transaction.cleanup() }
        #expect(try stagingEntries(in: rootURL).isEmpty)
    }

    @Test("a staging symlink is never published or cleaned through")
    func stagingSymlinkSwapFailsClosed() throws {
        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let movedStage = rootURL.appendingPathComponent("original-stage", isDirectory: true)
        let replacement = rootURL.appendingPathComponent("replacement", isDirectory: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: false)
        try "keep".write(
            to: replacement.appendingPathComponent("owner.txt"),
            atomically: true,
            encoding: .utf8
        )
        let hooks = ProjectDirectoryTransactionHooks(afterStagingOpen: { context in
            try FileManager.default.moveItem(at: context.stagingURL, to: movedStage)
            try FileManager.default.createSymbolicLink(
                at: context.stagingURL,
                withDestinationURL: replacement
            )
        })
        let transaction = try ProjectDirectoryTransaction.begin(
            in: ProjectDirectoryRoot.open(rootURL),
            destinationName: "Demo",
            hooks: hooks
        )
        try FileManager.default.createDirectory(
            at: movedStage.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: false
        )
        try transaction.verifyRepositoryMetadata()

        #expect(throws: ProjectDirectoryError.self) {
            try transaction.publish()
        }
        #expect(throws: ProjectDirectoryError.self) {
            try transaction.cleanup()
        }
        #expect(try String(
            contentsOf: replacement.appendingPathComponent("owner.txt"),
            encoding: .utf8
        ) == "keep")
    }

    @Test("cleanup preserves a replacement at the staging name")
    func cleanupSwapPreservesReplacement() throws {
        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let movedStage = rootURL.appendingPathComponent("abandoned-stage", isDirectory: true)
        let hooks = ProjectDirectoryTransactionHooks(beforeCleanup: { context in
            try FileManager.default.moveItem(at: context.stagingURL, to: movedStage)
            try FileManager.default.createDirectory(
                at: context.stagingURL,
                withIntermediateDirectories: false
            )
            try "keep".write(
                to: context.stagingURL.appendingPathComponent("owner.txt"),
                atomically: true,
                encoding: .utf8
            )
        })
        let transaction = try ProjectDirectoryTransaction.begin(
            in: ProjectDirectoryRoot.open(rootURL),
            destinationName: "Demo",
            hooks: hooks
        )

        #expect(throws: ProjectDirectoryError.self) {
            try transaction.cleanup()
        }
        let replacement = try #require(try stagingEntries(in: rootURL).first)
        #expect(try String(
            contentsOf: replacement.appendingPathComponent("owner.txt"),
            encoding: .utf8
        ) == "keep")
        #expect(FileManager.default.fileExists(atPath: movedStage.path))
    }

    @Test("repository metadata must be a real directory")
    func gitSymlinkIsRejected() throws {
        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let externalGit = rootURL.appendingPathComponent("external-git", isDirectory: true)
        try FileManager.default.createDirectory(at: externalGit, withIntermediateDirectories: false)
        let transaction = try ProjectDirectoryTransaction.begin(
            in: ProjectDirectoryRoot.open(rootURL),
            destinationName: "Demo"
        )
        let staging = try transaction.workingDirectory.displayURL
        try FileManager.default.createSymbolicLink(
            at: staging.appendingPathComponent(".git"),
            withDestinationURL: externalGit
        )

        #expect(throws: ProjectDirectoryError.self) {
            try transaction.verifyRepositoryMetadata()
        }
        try transaction.cleanup()
        #expect(FileManager.default.fileExists(atPath: externalGit.path))
    }

    @Test("repository metadata is revalidated at publication")
    func metadataSwapBeforePublicationIsRejected() throws {
        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let externalGit = rootURL.appendingPathComponent("external-git", isDirectory: true)
        try FileManager.default.createDirectory(at: externalGit, withIntermediateDirectories: false)
        try "keep".write(
            to: externalGit.appendingPathComponent("owner.txt"),
            atomically: true,
            encoding: .utf8
        )
        let hooks = ProjectDirectoryTransactionHooks(beforePublish: { context in
            let metadata = context.stagingURL.appendingPathComponent(".git")
            try FileManager.default.removeItem(at: metadata)
            try FileManager.default.createSymbolicLink(
                at: metadata,
                withDestinationURL: externalGit
            )
        })
        let transaction = try ProjectDirectoryTransaction.begin(
            in: ProjectDirectoryRoot.open(rootURL),
            destinationName: "Demo",
            hooks: hooks
        )
        try createGitDirectory(in: transaction)
        try transaction.verifyRepositoryMetadata()

        #expect(throws: ProjectDirectoryError.self) {
            try transaction.publish()
        }
        try transaction.cleanup()
        #expect(!FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent("Demo").path
        ))
        #expect(try String(
            contentsOf: externalGit.appendingPathComponent("owner.txt"),
            encoding: .utf8
        ) == "keep")
    }

    @Test("post-publication replacement is detected before registration")
    func postPublishSwapIsRejected() throws {
        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let movedProject = rootURL.appendingPathComponent("published-project", isDirectory: true)
        let hooks = ProjectDirectoryTransactionHooks(afterPublish: { context in
            try FileManager.default.moveItem(at: context.destinationURL, to: movedProject)
            try FileManager.default.createDirectory(
                at: context.destinationURL,
                withIntermediateDirectories: false
            )
            try "keep".write(
                to: context.destinationURL.appendingPathComponent("owner.txt"),
                atomically: true,
                encoding: .utf8
            )
        })
        let transaction = try ProjectDirectoryTransaction.begin(
            in: ProjectDirectoryRoot.open(rootURL),
            destinationName: "Demo",
            hooks: hooks
        )
        try createGitDirectory(in: transaction)

        #expect(throws: ProjectDirectoryError.self) {
            try transaction.publish()
        }
        #expect(try String(
            contentsOf: rootURL.appendingPathComponent("Demo/owner.txt"),
            encoding: .utf8
        ) == "keep")
        #expect(FileManager.default.fileExists(
            atPath: movedProject.appendingPathComponent(".git").path
        ))
    }

    @Test("post-publication validation failure rolls back the verified destination")
    func postPublicationFailureRollsBackVerifiedDestination() throws {
        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let hooks = ProjectDirectoryTransactionHooks(afterPublish: { _ in
            throw PostPublicationFailure.injected
        })
        let transaction = try ProjectDirectoryTransaction.begin(
            in: ProjectDirectoryRoot.open(rootURL),
            destinationName: "Demo",
            hooks: hooks
        )
        try createGitDirectory(in: transaction)

        #expect(throws: PostPublicationFailure.injected) {
            try transaction.publish()
        }
        #expect(!FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent("Demo", isDirectory: true).path
        ))
        #expect(try stagingEntries(in: rootURL).isEmpty)
    }

    @Test("post-publication rollback leaves a publication that gained foreign files untouched")
    func postPublicationRollbackKeepsTaintedPublicationWhole() throws {
        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let hooks = ProjectDirectoryTransactionHooks(afterPublish: { context in
            try "user".write(
                to: context.destinationURL.appendingPathComponent(".git/user-hook"),
                atomically: false,
                encoding: .utf8
            )
            throw PostPublicationFailure.injected
        })
        let transaction = try ProjectDirectoryTransaction.begin(
            in: ProjectDirectoryRoot.open(rootURL),
            destinationName: "Demo",
            hooks: hooks
        )
        try createGitDirectory(in: transaction)
        let staging = try transaction.workingDirectory.displayURL
        try "ref: refs/heads/main".write(
            to: staging.appendingPathComponent(".git/HEAD"),
            atomically: false,
            encoding: .utf8
        )
        try "created".write(
            to: staging.appendingPathComponent("README.md"),
            atomically: false,
            encoding: .utf8
        )

        #expect(throws: PostPublicationFailure.injected) {
            try transaction.publish()
        }
        let published = rootURL.appendingPathComponent("Demo", isDirectory: true)
        for entry in ["README.md", ".git/HEAD", ".git/user-hook"] {
            #expect(
                FileManager.default.fileExists(atPath: published.appendingPathComponent(entry).path),
                "\(entry) should survive a rollback that found foreign files"
            )
        }
    }

    @Test("opened publication remains bound when its pathname is replaced")
    func openedPublicationRetainsExactDirectory() throws {
        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let transaction = try ProjectDirectoryTransaction.begin(
            in: ProjectDirectoryRoot.open(rootURL),
            destinationName: "Demo"
        )
        try createGitDirectory(in: transaction)
        let publication = try transaction.publish()
        let openedDirectory = try publication.openVerifiedDirectory()
        let originalIdentity = openedDirectory.identity
        let moved = rootURL.appendingPathComponent("moved", isDirectory: true)

        try FileManager.default.moveItem(
            at: rootURL.appendingPathComponent("Demo", isDirectory: true),
            to: moved
        )
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("Demo", isDirectory: true),
            withIntermediateDirectories: false
        )

        #expect(openedDirectory.identity == originalIdentity)
        #expect(try openedDirectory.currentURL() == moved)
        #expect(throws: ProjectDirectoryError.self) {
            try publication.verifiedURL(for: openedDirectory)
        }
    }

    @Test("ancestor symbolic links are rejected")
    func ancestorSymlinkIsRejected() throws {
        let container = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: container) }
        let real = container.appendingPathComponent("real/child", isDirectory: true)
        let link = container.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: real.deletingLastPathComponent()
        )

        #expect(throws: ProjectDirectoryError.self) {
            try ProjectDirectoryRoot.open(link.appendingPathComponent("child"))
        }
    }

    private func createGitDirectory(
        in transaction: ProjectDirectoryTransaction
    ) throws {
        try FileManager.default.createDirectory(
            at: try transaction.workingDirectory.displayURL.appendingPathComponent(
                ".git",
                isDirectory: true
            ),
            withIntermediateDirectories: false
        )
    }

    private func stagingEntries(in root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".cocxy-project-") }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ProjectDirectoryTransaction-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url.standardizedFileURL
    }
}

private enum PostPublicationFailure: Error {
    case injected
}
