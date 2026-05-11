// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SandboxFoundationSwiftTestingTests.swift - Shared sandbox foundation coverage.

import Foundation
import Darwin
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

    @Test("profile adds private aliases for macOS var and tmp firmlinks")
    func profileAddsPrivateAliasesForVarAndTmpFirmlinks() {
        let profile = SandboxProfileBuilder().profile(
            capabilities: [.filesystemRead],
            readablePaths: [
                URL(fileURLWithPath: "/tmp/cocxy-mcp", isDirectory: true),
                URL(fileURLWithPath: "/var/folders/cocxy", isDirectory: true),
            ],
            writablePaths: [],
            executablePaths: []
        )

        #expect(profile.contains(#"(allow file-read* (subpath "/tmp/cocxy-mcp"))"#))
        #expect(profile.contains(#"(allow file-read* (subpath "/private/tmp/cocxy-mcp"))"#))
        #expect(profile.contains(#"(allow file-read* (subpath "/var/folders/cocxy"))"#))
        #expect(profile.contains(#"(allow file-read* (subpath "/private/var/folders/cocxy"))"#))
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

    @Test("executor launch planning stays under interactive overhead budget")
    func executorLaunchPlanningStaysUnderInteractiveBudget() throws {
        let executor = SandboxExecutor(
            sandboxExecURL: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
            fileManager: StubSandboxFileManager(executablePaths: ["/usr/bin/sandbox-exec"])
        )
        let profile = SandboxProfileBuilder().profile(
            capabilities: [.filesystemRead, .filesystemWrite, .processExec],
            readablePaths: [URL(fileURLWithPath: "/tmp/workspace")],
            writablePaths: [URL(fileURLWithPath: "/tmp/workspace")],
            executablePaths: [URL(fileURLWithPath: "/bin/sh")]
        )

        let iterations = 100
        let startedAt = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = try executor.launchPlan(
                commandURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-lc", "true"],
                profile: profile,
                environment: [:],
                currentDirectoryURL: URL(fileURLWithPath: "/tmp/workspace")
            )
        }
        let averageSeconds = (CFAbsoluteTimeGetCurrent() - startedAt) / Double(iterations)

        #expect(averageSeconds < 0.030)
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

    @Test("audit log rotates before it exceeds configured size")
    func auditLogRotatesBeforeExceedingConfiguredSize() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-sandbox-audit-rotate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let logURL = root.appendingPathComponent("sandbox-audit.jsonl")
        let log = SandboxAuditLog(
            fileURL: logURL,
            maxSizeBytes: 240,
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        try log.append(sampleAuditEntry(detail: String(repeating: "a", count: 120)))
        try log.append(sampleAuditEntry(detail: String(repeating: "b", count: 120)))

        let archives = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix("sandbox-audit.jsonl.") }
        #expect(archives.count == 1)
        #expect(try log.entries().count == 1)
    }

    @Test("audit log prunes expired archives")
    func auditLogPrunesExpiredArchives() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-sandbox-audit-prune-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let logURL = root.appendingPathComponent("sandbox-audit.jsonl")
        let oldArchive = root.appendingPathComponent("sandbox-audit.jsonl.2026-01-01T00-00-00.000Z")
        try Data("old\n".utf8).write(to: oldArchive)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)],
            ofItemAtPath: oldArchive.path
        )

        let log = SandboxAuditLog(
            fileURL: logURL,
            maxSizeBytes: 10_000,
            retentionDays: 30,
            now: { Date(timeIntervalSince1970: 60 * 24 * 60 * 60) }
        )
        try log.append(sampleAuditEntry())

        #expect(!FileManager.default.fileExists(atPath: oldArchive.path))
    }

    @Test("kernel sandbox denies network outbound when capability is absent")
    func kernelSandboxDeniesNetworkOutboundWhenCapabilityIsAbsent() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec"),
              Self.pythonExecutableURL() != nil
        else {
            return
        }

        let server = try LocalTCPProbeServer()
        defer { server.close() }

        let allowedProbe = try runPythonSocketProbe(
            port: server.port,
            capabilities: [.filesystemRead, .processExec, .network]
        )
        let deniedProbe = try runPythonSocketProbe(
            port: server.port,
            capabilities: [.filesystemRead, .processExec]
        )

        #expect(allowedProbe.status == 0)
        #expect(deniedProbe.status != 0)
    }

    private func sampleAuditEntry(detail: String = "ok") -> SandboxAuditEntry {
        SandboxAuditEntry(
            timestamp: Date(timeIntervalSince1970: 1_234),
            subjectID: "plugin.local",
            subjectKind: .plugin,
            operation: "network connect",
            capability: .network,
            decision: .denied,
            detail: detail
        )
    }

    private func runPythonSocketProbe(
        port: UInt16,
        capabilities: Set<SandboxCapability>
    ) throws -> (status: Int32, stderr: String) {
        guard let pythonURL = Self.pythonExecutableURL() else {
            throw POSIXError(.ENOENT)
        }
        let script = """
        import socket
        s = socket.create_connection(("127.0.0.1", \(port)), 1)
        s.close()
        """
        let profile = SandboxProfileBuilder().profile(
            capabilities: capabilities,
            readablePaths: [FileManager.default.temporaryDirectory],
            writablePaths: [],
            executablePaths: [pythonURL],
            executableSubpaths: Self.pythonExecutableSubpaths,
            includeSystemReadBaseline: true
        )
        let plan = try SandboxExecutor().launchPlan(
            commandURL: pythonURL,
            arguments: ["-c", script],
            profile: profile,
            environment: ["PATH": "/usr/bin:/bin"],
            currentDirectoryURL: FileManager.default.temporaryDirectory
        )

        let process = Process()
        process.executableURL = plan.executableURL
        process.arguments = plan.arguments
        process.environment = plan.environment
        process.currentDirectoryURL = plan.currentDirectoryURL
        process.standardOutput = Pipe()
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return (
            process.terminationStatus,
            String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    private static func pythonExecutableURL() -> URL? {
        [
            "/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/Current/bin/python3",
            "/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9",
            "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/Current/bin/python3",
            "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9",
            "/usr/bin/python3",
        ]
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static var pythonExecutableSubpaths: [URL] {
        [
            "/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework",
            "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework",
        ].map { URL(fileURLWithPath: $0, isDirectory: true) }
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

private final class LocalTCPProbeServer {
    let fileDescriptor: Int32
    let port: UInt16

    init() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var reuse: Int32 = 1
        guard setsockopt(
            fd,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuse,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            Darwin.close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var address = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: in_port_t(0).bigEndian,
            sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(
                    fd,
                    sockaddrPointer,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard bindResult == 0 else {
            Darwin.close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        guard listen(fd, 2) == 0 else {
            Darwin.close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(fd, sockaddrPointer, &length)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        fileDescriptor = fd
        port = UInt16(bigEndian: boundAddress.sin_port)
    }

    func close() {
        Darwin.close(fileDescriptor)
    }
}
