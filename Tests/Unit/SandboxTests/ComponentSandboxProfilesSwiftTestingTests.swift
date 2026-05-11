// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ComponentSandboxProfilesSwiftTestingTests.swift - Agent and MCP sandbox profile coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Component sandbox profiles")
struct ComponentSandboxProfilesSwiftTestingTests {
    @Test("on-device agent profile reads workspace and config without network")
    func onDeviceAgentProfileReadsWorkspaceAndConfigWithoutNetwork() {
        let profile = AgentSandboxProfile(
            provider: .foundationModelsOnDevice,
            workspaceURL: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            configURL: URL(fileURLWithPath: "/tmp/cocxy/config", isDirectory: true)
        ).profile()

        #expect(profile.contains(#"(allow file-read* (subpath "/tmp/project"))"#))
        #expect(profile.contains(#"(allow file-read* (subpath "/tmp/cocxy/config"))"#))
        #expect(!profile.contains("network-outbound"))
        #expect(!profile.contains("/Users/test/Documents"))
    }

    @Test("remote agent profile opts into network while keeping filesystem scoped")
    func remoteAgentProfileOptsIntoNetworkWhileKeepingFilesystemScoped() {
        let sandbox = AgentSandboxProfile(
            provider: .openai,
            workspaceURL: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            configURL: URL(fileURLWithPath: "/tmp/cocxy/config", isDirectory: true)
        )
        let profile = sandbox.profile()

        #expect(sandbox.capabilities == [.filesystemRead, .network])
        #expect(profile.contains("(allow network-outbound)"))
        #expect(profile.contains(#"(allow file-read* (subpath "/tmp/project"))"#))
        #expect(!profile.contains("file-write*"))
    }

    @Test("agent process runner wraps approved shell commands in workspace sandbox")
    func agentProcessRunnerWrapsCommandsInWorkspaceSandbox() throws {
        let base = RecordingSandboxAgentProcessRunner()
        let runner = AgentSandboxedProcessRunner(
            base: base,
            workspaceURL: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            configURL: URL(fileURLWithPath: "/tmp/cocxy/config", isDirectory: true),
            sandboxExecutor: SandboxExecutor(
                sandboxExecURL: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
                fileManager: StubComponentSandboxFileManager(executablePaths: ["/usr/bin/sandbox-exec"])
            )
        )

        _ = try runner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-lc", "swift test"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            timeoutSeconds: 10
        )

        let call = try #require(base.calls.first)
        let profile = try #require(call.arguments.dropFirst().first)
        #expect(call.executableURL.path == "/usr/bin/sandbox-exec")
        #expect(call.arguments.prefix(3) == ["-p", profile, "/bin/sh"])
        #expect(profile.contains(#"(allow file-read* (subpath "/tmp/project"))"#))
        #expect(profile.contains(#"(allow file-write* (subpath "/tmp/project"))"#))
        #expect(profile.contains(#"(allow process-exec (literal "/bin/sh"))"#))
        #expect(profile.contains(#"(allow process-exec (subpath "/usr/bin"))"#))
        #expect(!profile.contains("/Users/test/Documents"))
    }

    @Test("MCP stdio profile permits the launcher and configured working directory")
    func mcpStdioProfilePermitsLauncherAndWorkingDirectory() {
        let server = MCPServer(
            id: "local-tools",
            transport: .stdio(
                command: "python3",
                arguments: ["server.py"],
                workingDirectory: "/tmp/mcp-server"
            )
        )
        let sandbox = MCPServerSandboxProfile(server: server)
        let profile = sandbox.profile()

        #expect(sandbox.capabilities == [.filesystemRead, .processExec])
        #expect(profile.contains(#"(allow process-exec (literal "/usr/bin/env"))"#))
        #expect(profile.contains(#"(allow file-read* (subpath "/tmp/mcp-server"))"#))
        #expect(!profile.contains("network-outbound"))
    }

    @Test("MCP HTTP profile permits network without process execution")
    func mcpHTTPProfilePermitsNetworkWithoutProcessExecution() {
        let server = MCPServer(
            id: "http-tools",
            transport: .http(url: URL(string: "https://localhost:8080/mcp")!)
        )
        let sandbox = MCPServerSandboxProfile(server: server)
        let profile = sandbox.profile()

        #expect(sandbox.capabilities == [.network])
        #expect(profile.contains("(allow network-outbound)"))
        #expect(!profile.contains("process-exec"))
    }
}

private final class RecordingSandboxAgentProcessRunner: AgentProcessRunning, @unchecked Sendable {
    private(set) var calls: [AgentProcessCall] = []

    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval?
    ) throws -> AgentProcessResult {
        calls.append(AgentProcessCall(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: workingDirectory,
            timeoutSeconds: timeoutSeconds
        ))
        return AgentProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}

private struct AgentProcessCall: Equatable {
    let executableURL: URL
    let arguments: [String]
    let workingDirectory: URL
    let timeoutSeconds: TimeInterval?
}

private final class StubComponentSandboxFileManager: SandboxFileManaging {
    private let executablePaths: Set<String>

    init(executablePaths: Set<String>) {
        self.executablePaths = executablePaths
    }

    func isExecutableFile(atPath path: String) -> Bool {
        executablePaths.contains(path)
    }
}
