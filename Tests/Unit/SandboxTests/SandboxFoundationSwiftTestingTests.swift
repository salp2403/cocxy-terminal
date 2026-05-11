// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SandboxFoundationSwiftTestingTests.swift - Shared sandbox foundation coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Sandbox foundation")
struct SandboxFoundationSwiftTestingTests {
    @Test("capability raw values are stable for manifests and audit logs")
    func capabilityRawValuesAreStable() {
        #expect(SandboxCapability.network.rawValue == "network")
        #expect(SandboxCapability.filesystemRead.rawValue == "fs-read")
        #expect(SandboxCapability.filesystemWrite.rawValue == "fs-write")
        #expect(SandboxCapability.processExec.rawValue == "exec")
        #expect(SandboxCapability.audio.rawValue == "audio")
        #expect(SandboxCapability.screenCapture.rawValue == "screen-capture")
    }

    @Test("plugin capabilities map to shared sandbox capabilities")
    func pluginCapabilitiesMapToSharedCapabilities() {
        let mapped = Set(
            [
                PluginCapability.filesystemRead,
                .filesystemWrite,
                .processSpawn,
                .networkClient,
            ].flatMap(\.sandboxCapabilities)
        )

        #expect(mapped.contains(.filesystemRead))
        #expect(mapped.contains(.filesystemWrite))
        #expect(mapped.contains(.processExec))
        #expect(mapped.contains(.network))
        #expect(!mapped.contains(.screenCapture))
    }

    @Test("profile denies by default and only includes requested capabilities")
    func profileDeniesByDefaultAndIncludesRequestedCapabilities() {
        let profile = SandboxProfileBuilder().profile(
            capabilities: [.filesystemRead, .processExec],
            readablePaths: [URL(fileURLWithPath: "/tmp/plugin")],
            writablePaths: [URL(fileURLWithPath: "/tmp/plugin/state")],
            executablePaths: [URL(fileURLWithPath: "/bin/sh")]
        )

        #expect(profile.contains("(deny default)"))
        #expect(profile.contains(#"(allow file-read* (subpath "/tmp/plugin"))"#))
        #expect(profile.contains(#"(allow process-exec (literal "/bin/sh"))"#))
        #expect(!profile.contains("network-outbound"))
        #expect(!profile.contains("file-write*"))
    }

    @Test("profile escapes paths before embedding them in sandbox scheme")
    func profileEscapesPaths() {
        let profile = SandboxProfileBuilder().profile(
            capabilities: [.filesystemRead],
            readablePaths: [URL(fileURLWithPath: #"/tmp/plugin "quoted"\path"#)],
            writablePaths: [],
            executablePaths: []
        )

        #expect(profile.contains(#""/tmp/plugin \"quoted\"\\path""#))
    }

    @Test("executor launch plan wraps command with sandbox-exec when available")
    func executorLaunchPlanUsesSandboxExecWhenAvailable() throws {
        let executor = SandboxExecutor(
            sandboxExecURL: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
            fileManager: StubSandboxFileManager(executablePaths: ["/usr/bin/sandbox-exec"])
        )

        let plan = try executor.launchPlan(
            commandURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["ok"],
            profile: "(version 1)",
            environment: ["PATH": "/usr/bin"],
            currentDirectoryURL: URL(fileURLWithPath: "/tmp")
        )

        #expect(plan.executableURL.path == "/usr/bin/sandbox-exec")
        #expect(plan.arguments == ["-p", "(version 1)", "/bin/echo", "ok"])
        #expect(plan.environment["PATH"] == "/usr/bin")
    }

    @Test("executor reports unavailable sandbox-exec instead of silently running unsandboxed")
    func executorReportsUnavailableSandboxExec() throws {
        let executor = SandboxExecutor(
            sandboxExecURL: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
            fileManager: StubSandboxFileManager(executablePaths: [])
        )

        #expect(throws: SandboxExecutorError.sandboxExecUnavailable("/usr/bin/sandbox-exec")) {
            _ = try executor.launchPlan(
                commandURL: URL(fileURLWithPath: "/bin/echo"),
                arguments: [],
                profile: "(version 1)",
                environment: [:],
                currentDirectoryURL: URL(fileURLWithPath: "/tmp")
            )
        }
    }

    @Test("audit log appends and reloads JSONL entries")
    func auditLogAppendsAndLoadsEntries() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-sandbox-audit-\(UUID().uuidString)", isDirectory: true)
        let logURL = root.appendingPathComponent("sandbox-audit.jsonl")
        let log = SandboxAuditLog(fileURL: logURL)
        let entry = SandboxAuditEntry(
            timestamp: Date(timeIntervalSince1970: 1_234),
            subjectID: "plugin.local",
            subjectKind: .plugin,
            operation: "network connect",
            capability: .network,
            decision: .denied,
            detail: "network capability missing"
        )

        try log.append(entry)

        #expect(try log.entries() == [entry])
    }
}

private final class StubSandboxFileManager: SandboxFileManaging {
    private let executablePaths: Set<String>

    init(executablePaths: Set<String>) {
        self.executablePaths = executablePaths
    }

    func isExecutableFile(atPath path: String) -> Bool {
        executablePaths.contains(path)
    }
}
