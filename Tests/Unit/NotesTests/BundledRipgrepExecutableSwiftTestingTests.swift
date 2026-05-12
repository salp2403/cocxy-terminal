// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("BundledRipgrepExecutable")
struct BundledRipgrepExecutableSwiftTestingTests {

    @Test("resolver finds an executable rg in PATH without launching a shell")
    func resolverFindsExecutableFromPath() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cocxy-rg-path-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let rg = root.appendingPathComponent("rg")
        try "#!/bin/sh\nexit 0\n".write(to: rg, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: rg.path)

        let resolved = BundledRipgrepExecutable.resolve(
            bundle: Bundle(for: TestBundleAnchor.self),
            developmentRoot: nil,
            pathEnvironment: root.path
        )

        #expect(resolved == rg)
    }

    @Test("repository ships the bundled rg source resource")
    func repositoryShipsBundledResource() {
        let rg = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources")
            .appendingPathComponent("rg")

        #expect(FileManager.default.isExecutableFile(atPath: rg.path))
    }
}

private final class TestBundleAnchor {}
