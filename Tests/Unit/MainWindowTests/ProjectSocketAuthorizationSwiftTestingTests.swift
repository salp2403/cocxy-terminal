// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Project socket approval target")
@MainActor
struct ProjectSocketAuthorizationSwiftTestingTests {
    @Test("approval projects a nested directory onto its canonical project root")
    func bindsCanonicalProjectRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-project-approval-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let nested = root.appendingPathComponent("Sources/Feature", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)
        let request = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "project-open",
                command: "project-open",
                params: ["path": nested.path]
            )
        ))

        let target = try #require(
            delegate.privilegedSocketCommandPresentationTarget(for: request)
        )
        #expect(target.context.scope == .project)
        #expect(target.context.workingDirectory == root.path)
        #expect(target.context.localResourcePaths == ["path": root.path])
        #expect(target.context.targetDisplayName.contains(root.path))
    }

    @Test("missing project directories have no approval target")
    func rejectsUnavailableDirectory() throws {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)
        let missing = "/tmp/cocxy-missing-project-\(UUID().uuidString)"
        let request = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "project-open-missing",
                command: "project-open",
                params: ["path": missing]
            )
        ))

        #expect(delegate.privilegedSocketCommandPresentationTarget(for: request) == nil)
    }

    @Test("clone approval binds its validated remote and canonical parent")
    func cloneBindsCanonicalParentAndRemote() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-clone-approval-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        let parent = root.appendingPathComponent("parent", isDirectory: true)
        let alias = root.appendingPathComponent("parent-alias", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: parent)

        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)
        let request = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "project-clone",
                command: "project-clone",
                params: [
                    "remote": "git@example.com:team/repo.git",
                    "parent": alias.path,
                ]
            )
        ))

        let target = try #require(
            delegate.privilegedSocketCommandPresentationTarget(for: request)
        )
        #expect(target.context.scope == .project)
        #expect(target.context.workingDirectory == parent.resolvingSymlinksInPath().path)
        #expect(target.context.localResourcePaths == [
            "parent": parent.resolvingSymlinksInPath().path,
        ])
        #expect(target.context.authorityDetails == [
            "operation": "clone",
            "remote": "ssh://git@example.com/team/repo.git",
        ])
        #expect(!target.context.targetDisplayName.contains("git@"))
        #expect(target.context.targetDisplayName.contains("example.com/team/repo.git"))
    }

    @Test("clone approval rejects unavailable parents and invalid remotes")
    func cloneRejectsInvalidTargets() throws {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)
        let missing = "/tmp/cocxy-missing-clone-parent-\(UUID().uuidString)"
        let missingParent = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "project-clone-missing",
                command: "project-clone",
                params: [
                    "remote": "https://example.com/team/repo.git",
                    "parent": missing,
                ]
            )
        ))
        let invalidRemote = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "project-clone-invalid-remote",
                command: "project-clone",
                params: [
                    "remote": "file:///tmp/repo",
                    "parent": FileManager.default.temporaryDirectory.path,
                ]
            )
        ))

        #expect(delegate.privilegedSocketCommandPresentationTarget(for: missingParent) == nil)
        #expect(delegate.privilegedSocketCommandPresentationTarget(for: invalidRemote) == nil)
    }

    @Test("clone execution consumes only its exact approved context")
    func cloneExecutionRequiresExactContext() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-clone-execution-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let existingDestination = parent.appendingPathComponent("repo", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(
            at: existingDestination,
            withIntermediateDirectories: true
        )
        let params = [
            "remote": "https://example.com/team/repo.git",
            "parent": parent.path,
        ]
        let context = SocketPrivilegedCommandContext(
            scope: .project,
            windowControllerIdentifier: nil,
            tabID: nil,
            workingDirectory: parent.path,
            localResourcePaths: ["parent": parent.path],
            authorityDetails: [
                "operation": "clone",
                "remote": "https://example.com/team/repo.git",
            ],
            surfaceID: nil,
            browserViewModelIdentifier: nil,
            browserTabID: nil,
            browserURL: nil,
            targetDisplayName: "Clone approved repository"
        )
        let delegate = AppDelegate()

        let approved = delegate.handleProjectCLIRequest(
            kind: "clone",
            params: params,
            approvedContext: context
        )
        #expect(!approved.success)
        #expect(approved.data["error"]?.contains("already exists") == true)
        #expect(!approved.data["error", default: ""].contains("context is unavailable"))

        let changed = delegate.handleProjectCLIRequest(
            kind: "clone",
            params: [
                "remote": "https://example.com/team/other.git",
                "parent": parent.path,
            ],
            approvedContext: context
        )
        #expect(!changed.success)
        #expect(changed.data["error"] == "Approved project-clone context is unavailable")
    }
}
