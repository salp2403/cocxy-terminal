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
}
