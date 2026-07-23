// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonScriptTests.swift - Integration tests for cocxyd.sh daemon script.

import Darwin
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("DaemonScript", .serialized)
struct DaemonScriptTests {

    private var profileNamespace: String {
        "0123456789abcdef0123456789abcdef"
    }

    /// Path to the cocxyd.sh script in the project.
    private var scriptPath: String {
        // #filePath = .../Tests/Unit/RemoteWorkspaceTests/DaemonScriptTests.swift
        // Project root is 4 levels up.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url = url.deletingLastPathComponent() }
        return url.appendingPathComponent("Resources/cocxyd.sh").path
    }

    private func runScript(
        args: [String],
        runtimeDirectory: URL? = nil
    ) throws -> (stdout: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptPath] + args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Set XDG_RUNTIME_DIR to temp for isolation.
        var env = ProcessInfo.processInfo.environment
        let ownsRuntimeDirectory = runtimeDirectory == nil
        let tempDir = runtimeDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxyd-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        env["XDG_RUNTIME_DIR"] = tempDir.path
        process.environment = env

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // Cleanup.
        if ownsRuntimeDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }

        return (stdout: output, exitCode: process.terminationStatus)
    }

    @Test("Script prints help with no arguments")
    func helpOutput() throws {
        let result = try runScript(args: ["help"])
        #expect(result.stdout.contains("cocxyd.sh"))
        #expect(result.stdout.contains("Usage"))
        #expect(result.exitCode == 0)
    }

    @Test("Status reports not running when daemon is off")
    func statusNotRunning() throws {
        let result = try runScript(args: ["status", profileNamespace])
        #expect(result.stdout.contains("\"ok\":false"))
        #expect(result.stdout.contains("not running"))
    }

    @Test("Ping reports not running when daemon is off")
    func pingNotRunning() throws {
        let result = try runScript(args: ["ping", profileNamespace])
        #expect(result.stdout.contains("\"ok\":false"))
        #expect(result.stdout.contains("not running"))
    }

    @Test("Stop is safe when daemon not running")
    func stopWhenNotRunning() throws {
        let result = try runScript(args: ["stop", profileNamespace])
        #expect(result.stdout.contains("not running"))
        #expect(result.exitCode == 0)
    }

    @Test("Script is valid POSIX shell")
    func posixValid() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-n", scriptPath]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
    }

    @Test("Start reports a bound loopback port and serves a real request")
    func startServesLoopbackRequest() throws {
        let runtimeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxyd-lifecycle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: runtimeDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: runtimeDirectory.path
        )
        defer {
            _ = try? runScript(
                args: ["stop", profileNamespace],
                runtimeDirectory: runtimeDirectory
            )
            try? FileManager.default.removeItem(at: runtimeDirectory)
        }

        let start = try runScript(
            args: ["start", profileNamespace],
            runtimeDirectory: runtimeDirectory
        )
        #expect(start.exitCode == 0)
        let portLine = try #require(start.stdout.split(separator: "\n").first {
            $0.hasPrefix("COCXYD_PORT=")
        })
        let port = try #require(Int(portLine.dropFirst("COCXYD_PORT=".count)))
        #expect((1...65_535).contains(port))

        let portFile = runtimeDirectory
            .appendingPathComponent(
                "cocxyd-\(getuid())/\(profileNamespace)/cocxyd.port"
            )
        let capabilityFile = runtimeDirectory
            .appendingPathComponent(
                "cocxyd-\(getuid())/\(profileNamespace)/cocxyd.cap"
            )
        let daemonRuntimeDirectory = portFile.deletingLastPathComponent()
        let publishedPort = try String(contentsOf: portFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let capability = try String(contentsOf: capabilityFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(publishedPort == String(port))
        #expect(DaemonConnection.isValidCapability(capability))
        #expect(try posixPermissions(of: daemonRuntimeDirectory) == 0o700)
        #expect(try posixPermissions(of: capabilityFile) == 0o600)

        let unauthenticated = try sendLoopbackRequest(
            #"{"proto":1,"id":"req-1","cmd":"ping"}"#,
            port: port
        )
        #expect(unauthenticated.contains(#""id":"req-1""#))
        #expect(unauthenticated.contains("authentication failed"))

        let wrongCapability = try sendLoopbackRequest(
            "\(String(repeating: "0", count: 64))\t"
                + #"{"proto":1,"id":"req-2","cmd":"ping"}"#,
            port: port
        )
        #expect(wrongCapability.contains("authentication failed"))

        let response = try sendLoopbackRequest(
            "\(capability)\t" + #"{"proto":1,"id":"req-3","cmd":"ping"}"#,
            port: port
        )
        #expect(response.contains(#""id":"req-3""#))
        #expect(response.contains(#""pong":true"#))

        let unsafeTitle = try sendLoopbackRequest(
            "\(capability)\t"
                + #"{"proto":1,"id":"req-4","cmd":"session.create","args":{"title":"bad;touch"}}"#,
            port: port
        )
        #expect(unsafeTitle.contains("invalid session title"))

        let missingSession = try sendLoopbackRequest(
            "\(capability)\t"
                + #"{"proto":1,"id":"req-5","cmd":"session.kill","args":{"id":"missing-session"}}"#,
            port: port
        )
        #expect(missingSession.contains("\"ok\":false"))
        #expect(missingSession.contains("session not found"))

        let repeatedStart = try runScript(
            args: ["start", profileNamespace],
            runtimeDirectory: runtimeDirectory
        )
        #expect(repeatedStart.exitCode == 0)
        #expect(repeatedStart.stdout.contains("COCXYD_PORT=\(port)"))
        #expect(repeatedStart.stdout.contains("already running"))
        let repeatedCapability = try String(contentsOf: capabilityFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(repeatedCapability == capability)

        let logFile = daemonRuntimeDirectory.appendingPathComponent("cocxyd.log")
        let log = try String(contentsOf: logFile, encoding: .utf8)
        #expect(!log.contains(capability))

        let shutdown = try sendLoopbackRequest(
            "\(capability)\t" + #"{"proto":1,"id":"req-6","cmd":"shutdown"}"#,
            port: port
        )
        #expect(shutdown.contains("\"ok\":true"))
        for _ in 0..<30 where FileManager.default.fileExists(atPath: capabilityFile.path) {
            usleep(100_000)
        }
        #expect(!FileManager.default.fileExists(atPath: portFile.path))
        #expect(!FileManager.default.fileExists(atPath: capabilityFile.path))
    }

    @Test("Profile namespaces run independently and stop without cross-impact")
    func profileNamespacesAreIsolated() throws {
        let secondNamespace = "fedcba9876543210fedcba9876543210"
        let runtimeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxyd-profiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: runtimeDirectory,
            withIntermediateDirectories: true
        )
        defer {
            _ = try? runScript(
                args: ["stop", profileNamespace],
                runtimeDirectory: runtimeDirectory
            )
            _ = try? runScript(
                args: ["stop", secondNamespace],
                runtimeDirectory: runtimeDirectory
            )
            try? FileManager.default.removeItem(at: runtimeDirectory)
        }

        let firstStart = try runScript(
            args: ["start", profileNamespace],
            runtimeDirectory: runtimeDirectory
        )
        let secondStart = try runScript(
            args: ["start", secondNamespace],
            runtimeDirectory: runtimeDirectory
        )
        let firstPort = try daemonPort(from: firstStart.stdout)
        let secondPort = try daemonPort(from: secondStart.stdout)
        let firstCapability = try daemonCapability(
            runtimeDirectory: runtimeDirectory,
            namespace: profileNamespace
        )
        let secondCapability = try daemonCapability(
            runtimeDirectory: runtimeDirectory,
            namespace: secondNamespace
        )
        let sessionTitle = "profile-isolation-\(UUID().uuidString.prefix(8).lowercased())"
        defer {
            _ = try? sendLoopbackRequest(
                "\(firstCapability)\t"
                    + #"{"proto":1,"id":"req-18","cmd":"session.kill","args":{"id":""#
                    + sessionTitle + #""}}"#,
                port: firstPort,
                expectSuccess: false
            )
            _ = try? sendLoopbackRequest(
                "\(secondCapability)\t"
                    + #"{"proto":1,"id":"req-19","cmd":"session.kill","args":{"id":""#
                    + sessionTitle + #""}}"#,
                port: secondPort,
                expectSuccess: false
            )
        }

        #expect(firstStart.exitCode == 0)
        #expect(secondStart.exitCode == 0)
        #expect(firstPort != secondPort)
        #expect(firstCapability != secondCapability)
        #expect(try sendLoopbackRequest(
            "\(firstCapability)\t" + #"{"proto":1,"id":"req-10","cmd":"ping"}"#,
            port: firstPort
        ).contains(#""pong":true"#))
        #expect(try sendLoopbackRequest(
            "\(secondCapability)\t" + #"{"proto":1,"id":"req-11","cmd":"ping"}"#,
            port: secondPort
        ).contains(#""pong":true"#))

        let firstCreate = try sendLoopbackRequest(
            "\(firstCapability)\t"
                + #"{"proto":1,"id":"req-13","cmd":"session.create","args":{"title":""#
                + sessionTitle + #""}}"#,
            port: firstPort
        )
        let secondCreate = try sendLoopbackRequest(
            "\(secondCapability)\t"
                + #"{"proto":1,"id":"req-14","cmd":"session.create","args":{"title":""#
                + sessionTitle + #""}}"#,
            port: secondPort
        )
        #expect(firstCreate.contains(#""ok":true"#))
        #expect(secondCreate.contains(#""ok":true"#))
        #expect(try sendLoopbackRequest(
            "\(firstCapability)\t"
                + #"{"proto":1,"id":"req-15","cmd":"session.list"}"#,
            port: firstPort
        ).contains(sessionTitle))
        #expect(try sendLoopbackRequest(
            "\(secondCapability)\t"
                + #"{"proto":1,"id":"req-16","cmd":"session.list"}"#,
            port: secondPort
        ).contains(sessionTitle))

        let firstKill = try sendLoopbackRequest(
            "\(firstCapability)\t"
                + #"{"proto":1,"id":"req-17","cmd":"session.kill","args":{"id":""#
                + sessionTitle + #""}}"#,
            port: firstPort
        )
        #expect(firstKill.contains(#""ok":true"#))
        let firstSessionsAfterKill = try sendLoopbackRequest(
            "\(firstCapability)\t"
                + #"{"proto":1,"id":"req-18","cmd":"session.list"}"#,
            port: firstPort
        )
        let secondSessionsAfterFirstKill = try sendLoopbackRequest(
            "\(secondCapability)\t"
                + #"{"proto":1,"id":"req-19","cmd":"session.list"}"#,
            port: secondPort
        )
        #expect(!firstSessionsAfterKill.contains(sessionTitle))
        #expect(secondSessionsAfterFirstKill.contains(sessionTitle))
        #expect(try sendLoopbackRequest(
            "\(secondCapability)\t"
                + #"{"proto":1,"id":"req-20","cmd":"session.kill","args":{"id":""#
                + sessionTitle + #""}}"#,
            port: secondPort
        ).contains(#""ok":true"#))

        let firstStop = try runScript(
            args: ["stop", profileNamespace],
            runtimeDirectory: runtimeDirectory
        )
        let firstStatus = try runScript(
            args: ["status", profileNamespace],
            runtimeDirectory: runtimeDirectory
        )
        let secondStatus = try runScript(
            args: ["status", secondNamespace],
            runtimeDirectory: runtimeDirectory
        )

        #expect(firstStop.exitCode == 0)
        #expect(firstStatus.stdout.contains("daemon not running"))
        #expect(secondStatus.stdout.contains(#""ok":true"#))
        #expect(try sendLoopbackRequest(
            "\(secondCapability)\t" + #"{"proto":1,"id":"req-12","cmd":"ping"}"#,
            port: secondPort
        ).contains(#""pong":true"#))
    }

    @Test("Unauthenticated connection slots expire and become reusable")
    func preauthenticationSlotsExpire() throws {
        let runtimeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxyd-preauth-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: runtimeDirectory,
            withIntermediateDirectories: true
        )
        var descriptors: [Int32] = []
        defer {
            for descriptor in descriptors { Darwin.close(descriptor) }
            _ = try? runScript(
                args: ["stop", profileNamespace],
                runtimeDirectory: runtimeDirectory
            )
            try? FileManager.default.removeItem(at: runtimeDirectory)
        }

        let start = try runScript(
            args: ["start", profileNamespace],
            runtimeDirectory: runtimeDirectory
        )
        let port = try daemonPort(from: start.stdout)
        let capability = try daemonCapability(
            runtimeDirectory: runtimeDirectory,
            namespace: profileNamespace
        )
        for _ in 0..<20 {
            descriptors.append(try openLoopbackSocket(port: port))
        }

        usleep(6_000_000)

        let response = try sendLoopbackRequest(
            "\(capability)\t" + #"{"proto":1,"id":"req-20","cmd":"ping"}"#,
            port: port
        )
        #expect(response.contains(#""pong":true"#))
    }

    @Test("Stopping a generation closes already accepted connections")
    func stopRevokesAcceptedConnections() throws {
        let runtimeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxyd-revoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: runtimeDirectory,
            withIntermediateDirectories: true
        )
        defer {
            _ = try? runScript(
                args: ["stop", profileNamespace],
                runtimeDirectory: runtimeDirectory
            )
            try? FileManager.default.removeItem(at: runtimeDirectory)
        }

        let start = try runScript(
            args: ["start", profileNamespace],
            runtimeDirectory: runtimeDirectory
        )
        let port = try daemonPort(from: start.stdout)
        let capability = try daemonCapability(
            runtimeDirectory: runtimeDirectory,
            namespace: profileNamespace
        )
        let descriptor = try openLoopbackSocket(port: port)
        defer { Darwin.close(descriptor) }
        try sendAll(
            Data(
                ("\(capability)\t"
                    + #"{"proto":1,"id":"req-30","cmd":"ping"}"#
                    + "\n").utf8
            ),
            descriptor: descriptor
        )
        #expect(try readLine(descriptor: descriptor).contains(#""pong":true"#))

        let stop = try runScript(
            args: ["stop", profileNamespace],
            runtimeDirectory: runtimeDirectory
        )

        #expect(stop.exitCode == 0)
        #expect(waitForSocketClosure(descriptor: descriptor, timeoutSeconds: 3))
    }

    @Test("Python listener stays on loopback and does not use netcat exec")
    func listenerIsPortableAndFailClosed() throws {
        let script = try String(contentsOfFile: scriptPath, encoding: .utf8)

        #expect(script.contains(#"server.bind(("127.0.0.1", 0))"#))
        #expect(script.contains("requires Python 3"))
        #expect(!script.contains("nc -l"))
        #expect(!script.contains(" -e \"sh $0 _handle\""))
        #expect(!script.contains("CMD: $line"))
    }

    @Test("App build copies and verifies the reachable daemon script")
    func appBundlePipelineIncludesScript() throws {
        let root = URL(fileURLWithPath: scriptPath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let buildScript = try String(
            contentsOf: root.appendingPathComponent("scripts/build-app.sh"),
            encoding: .utf8
        )
        let bundleVerifier = try String(
            contentsOf: root.appendingPathComponent("scripts/verify-app-bundle.sh"),
            encoding: .utf8
        )

        #expect(buildScript.contains(#"REMOTE_DAEMON_SCRIPT="${PROJECT_ROOT}/Resources/cocxyd.sh""#))
        #expect(buildScript.contains(#"cp "${REMOTE_DAEMON_SCRIPT}" "${RESOURCES}/cocxyd.sh""#))
        #expect(bundleVerifier.contains(#"check_exists "$RESOURCES/cocxyd.sh""#))
        #expect(bundleVerifier.contains(#"/bin/sh -n "$RESOURCES/cocxyd.sh""#))
    }

    private func sendLoopbackRequest(
        _ request: String,
        port: Int,
        expectSuccess: Bool = true
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        process.arguments = ["-w", "3", "127.0.0.1", String(port)]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output

        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data("\(request)\n".utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        if expectSuccess {
            #expect(process.terminationStatus == 0)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func daemonPort(from output: String) throws -> Int {
        let portLine = try #require(output.split(separator: "\n").first {
            $0.hasPrefix("COCXYD_PORT=")
        })
        let port = try #require(Int(portLine.dropFirst("COCXYD_PORT=".count)))
        return try #require((1...65_535).contains(port) ? port : nil)
    }

    private func daemonCapability(
        runtimeDirectory: URL,
        namespace: String
    ) throws -> String {
        let capabilityFile = runtimeDirectory.appendingPathComponent(
            "cocxyd-\(getuid())/\(namespace)/cocxyd.cap"
        )
        let capability = try String(contentsOf: capabilityFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return try #require(DaemonConnection.isValidCapability(capability) ? capability : nil)
    }

    private func openLoopbackSocket(port: Int) throws -> Int32 {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw posixError() }
        var noSignal: Int32 = 1
        _ = withUnsafePointer(to: &noSignal) { pointer in
            Darwin.setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                pointer,
                socklen_t(MemoryLayout<Int32>.size)
            )
        }
        var address = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: in_port_t(port).bigEndian,
            sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard result == 0 else {
            let error = posixError()
            Darwin.close(descriptor)
            throw error
        }
        return descriptor
    }

    private func sendAll(_ data: Data, descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var sent = 0
            while sent < bytes.count {
                let count = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: sent),
                    bytes.count - sent,
                    0
                )
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw posixError() }
                sent += count
            }
        }
    }

    private func readLine(
        descriptor: Int32,
        timeoutSeconds: TimeInterval = 3
    ) throws -> String {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var data = Data()
        while Date() < deadline {
            let remainingMilliseconds = max(
                1,
                Int32(deadline.timeIntervalSinceNow * 1_000)
            )
            var state = pollfd(
                fd: descriptor,
                events: Int16(POLLIN | POLLHUP | POLLERR),
                revents: 0
            )
            let pollResult = Darwin.poll(&state, 1, remainingMilliseconds)
            if pollResult < 0, errno == EINTR { continue }
            guard pollResult > 0 else { break }
            var byte: UInt8 = 0
            let count = Darwin.recv(descriptor, &byte, 1, 0)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            data.append(byte)
            if byte == UInt8(ascii: "\n") { break }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func waitForSocketClosure(
        descriptor: Int32,
        timeoutSeconds: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            var state = pollfd(
                fd: descriptor,
                events: Int16(POLLIN | POLLHUP | POLLERR),
                revents: 0
            )
            let pollResult = Darwin.poll(&state, 1, 100)
            if pollResult < 0, errno == EINTR { continue }
            if pollResult <= 0 { continue }
            if state.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 {
                return true
            }
            if state.revents & Int16(POLLIN) != 0 {
                var byte: UInt8 = 0
                if Darwin.recv(descriptor, &byte, 1, 0) == 0 { return true }
            }
        }
        return false
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    private func posixPermissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? Int)
    }
}
