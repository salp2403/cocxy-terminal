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
