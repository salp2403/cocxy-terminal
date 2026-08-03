// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonClientDescriptorIdentitySwiftTestingTests.swift - Descriptor-bound request coverage.

import AppKit
import CocxyShared
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
extension PTYDaemonClientSwiftTestingTests {
    @Test("descriptor-bound creation transmits the exact directory identity")
    func descriptorBoundCreationTransmitsIdentity() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-daemon-cwd-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let directory = try ProjectDirectoryRoot.open(directoryURL)
        let surfaceID = UUID()
        let connection = MockPTYDaemonClientConnection(responses: [
            PTYDaemonResponse(id: "hello", ok: true, hello: terminalSurfaceHello()),
            PTYDaemonResponse(id: "create", ok: true, surfaceID: surfaceID.uuidString),
        ])
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig())

        _ = try client.createSurface(
            in: NSView(),
            verifiedWorkingDirectory: directory,
            command: "/bin/zsh"
        )

        let payload = try #require(connection.requests.last?.payload)
        #expect(payload["workingDirectory"] == directoryURL.path)
        #expect(payload["workingDirectoryDevice"] == "\(directory.identity.device)")
        #expect(payload["workingDirectoryInode"] == "\(directory.identity.inode)")
        #expect(payload["workingDirectoryFileType"] == "\(directory.identity.fileType)")
    }
}
