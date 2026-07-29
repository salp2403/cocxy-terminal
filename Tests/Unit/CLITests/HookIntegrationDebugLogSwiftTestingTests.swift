// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
import CocxyShared

@Suite("Hook integration debug log")
struct HookIntegrationDebugLogSwiftTestingTests {
    @Test("logging is opt-in and does not create a file while disabled")
    func loggingIsOptIn() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let logURL = root.appendingPathComponent("logs/hook.log")

        HookIntegrationDebugLog.append(
            "must-not-exist",
            environment: [
                HookIntegrationDebugLog.pathOverrideEnvironmentKey: logURL.path,
            ]
        )

        #expect(FileManager.default.fileExists(atPath: logURL.path) == false)
    }

    @Test("enabled logging is private and sanitizes control characters")
    func enabledLoggingIsPrivateAndSanitized() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directoryURL = root.appendingPathComponent("logs", isDirectory: true)
        let logURL = directoryURL.appendingPathComponent("hook.log")
        let environment = [
            HookIntegrationDebugLog.enabledEnvironmentKey: "1",
            HookIntegrationDebugLog.pathOverrideEnvironmentKey: logURL.path,
        ]

        HookIntegrationDebugLog.append(
            "first\nsecond\u{001B}[31m",
            environment: environment,
            timestamp: Date(timeIntervalSince1970: 0)
        )

        let content = try String(contentsOf: logURL, encoding: .utf8)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: logURL.path)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directoryURL.path)
        let fileMode = try #require(fileAttributes[.posixPermissions] as? NSNumber).intValue
        let directoryMode = try #require(directoryAttributes[.posixPermissions] as? NSNumber).intValue

        #expect(content.contains("[hook-integration] first second [31m"))
        #expect(content.filter { $0 == "\n" }.count == 1)
        #expect(content.contains("\u{001B}") == false)
        #expect(fileMode & 0o777 == 0o600)
        #expect(directoryMode & 0o777 == 0o700)
    }

    @Test("logger refuses to follow a symlink destination")
    func refusesSymlinkDestination() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let targetURL = root.appendingPathComponent("target.txt")
        let linkURL = root.appendingPathComponent("hook.log")
        try Data("sentinel".utf8).write(to: targetURL)
        try FileManager.default.createSymbolicLink(
            at: linkURL,
            withDestinationURL: targetURL
        )

        HookIntegrationDebugLog.append(
            "should-not-follow",
            environment: [
                HookIntegrationDebugLog.enabledEnvironmentKey: "1",
                HookIntegrationDebugLog.pathOverrideEnvironmentKey: linkURL.path,
            ]
        )

        #expect(try String(contentsOf: targetURL, encoding: .utf8) == "sentinel")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-hook-log-\(UUID().uuidString)", isDirectory: true)
    }
}
