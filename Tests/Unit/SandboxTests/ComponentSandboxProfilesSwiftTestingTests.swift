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
        let credentialPath = SandboxProfileBuilder.controlCredentialLiteralPaths[0]
            .resolvingSymlinksInPath().standardizedFileURL.path
        #expect(profile.contains(#"(deny file-read* (literal "\#(credentialPath)"))"#))
        #expect(!profile.contains("network-outbound"))
        #expect(!profile.contains("/Users/test/Documents"))
        assertNoSharedTemporaryDirectoryGrant(profile)
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
        #expect(!profile.contains(#"(allow file-read* (subpath "/tmp/cocxy/config"))"#))
        #expect(!profile.contains("/Users/test/Documents"))
        assertNoSharedTemporaryDirectoryGrant(profile)
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
        assertNoSharedTemporaryDirectoryGrant(profile)
    }

    @Test("MCP stdio file arguments stay literal while directory arguments are recursive")
    func mcpStdioProfileKeepsFileArgumentsLiteral() throws {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy-mcp-profile-\(UUID().uuidString)", isDirectory: true)
        let workingDirectory = root.appendingPathComponent("working", isDirectory: true)
        let readableDirectory = root.appendingPathComponent("directory-argument", isDirectory: true)
        let inputURL = root.appendingPathComponent("input.json")
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: readableDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: inputURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let server = MCPServer(
            id: "file-boundary",
            transport: .stdio(
                command: "/bin/cat",
                arguments: [inputURL.path, readableDirectory.path],
                workingDirectory: workingDirectory.path
            )
        )
        let profile = MCPServerSandboxProfile(server: server)
            .profile(commandURL: URL(fileURLWithPath: "/bin/cat"))
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let canonicalInput = inputURL.resolvingSymlinksInPath().standardizedFileURL.path
        let canonicalDirectory = readableDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let canonicalWorkingDirectory = workingDirectory.resolvingSymlinksInPath().standardizedFileURL.path

        #expect(profile.contains(#"(allow file-read* (literal "\#(canonicalInput)"))"#))
        #expect(!profile.contains(#"(allow file-read* (subpath "\#(canonicalRoot)"))"#))
        #expect(profile.contains(#"(allow file-read* (subpath "\#(canonicalDirectory)"))"#))
        #expect(profile.contains(#"(allow file-read* (subpath "\#(canonicalWorkingDirectory)"))"#))
    }

    @Test("MCP stdio relative symlink and output arguments preserve path type")
    func mcpStdioProfileClassifiesResolvedArgumentTypes() throws {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy-mcp-relative-profile-\(UUID().uuidString)", isDirectory: true)
        let workingDirectory = root.appendingPathComponent("working", isDirectory: true)
        let filesDirectory = root.appendingPathComponent("files", isDirectory: true)
        let readableDirectory = root.appendingPathComponent("directories/readable", isDirectory: true)
        let outputsDirectory = root.appendingPathComponent("outputs", isDirectory: true)
        for directory in [workingDirectory, filesDirectory, readableDirectory, outputsDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let inputURL = filesDirectory.appendingPathComponent("input.json")
        let outputURL = outputsDirectory.appendingPathComponent("future.json")
        try Data("{}".utf8).write(to: inputURL)

        let server = MCPServer(
            id: "resolved-path-types",
            transport: .stdio(
                command: "/bin/cat",
                arguments: [
                    "../files/input.json",
                    "../directories/readable",
                    "../outputs/future.json",
                ],
                workingDirectory: workingDirectory.path
            )
        )
        let profile = MCPServerSandboxProfile(server: server)
            .profile(commandURL: URL(fileURLWithPath: "/bin/cat"))
        let canonicalInput = inputURL.resolvingSymlinksInPath().standardizedFileURL.path
        let canonicalDirectory = readableDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let canonicalFilesDirectory = filesDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let canonicalOutputsDirectory = outputsDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let canonicalOutput = outputURL.resolvingSymlinksInPath().standardizedFileURL.path

        #expect(profile.contains(#"(allow file-read* (literal "\#(canonicalInput)"))"#))
        #expect(profile.contains(#"(allow file-read* (subpath "\#(canonicalDirectory)"))"#))
        #expect(!profile.contains(#"(allow file-read* (subpath "\#(canonicalFilesDirectory)"))"#))
        #expect(!profile.contains(#"(allow file-read* (subpath "\#(canonicalOutputsDirectory)"))"#))
        #expect(profile.contains(#"(allow file-write* (literal "\#(canonicalOutput)"))"#))
        #expect(!profile.contains("network-outbound"))
    }

    @Test("MCP stdio symlink arguments do not inherit target capabilities")
    func mcpStdioProfileRejectsSymlinkTargetCapabilities() throws {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy-mcp-symlink-profile-\(UUID().uuidString)", isDirectory: true)
        let targetsDirectory = root.appendingPathComponent("targets", isDirectory: true)
        let readableDirectory = targetsDirectory.appendingPathComponent("readable", isDirectory: true)
        let linksDirectory = root.appendingPathComponent("links", isDirectory: true)
        try FileManager.default.createDirectory(at: readableDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linksDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let inputURL = targetsDirectory.appendingPathComponent("input.json")
        let nestedInputURL = readableDirectory.appendingPathComponent("nested.json")
        let linkedFileURL = linksDirectory.appendingPathComponent("input-link.json")
        let linkedDirectoryURL = linksDirectory.appendingPathComponent("directory-link", isDirectory: true)
        try Data("{}".utf8).write(to: inputURL)
        try Data("{}".utf8).write(to: nestedInputURL)
        try FileManager.default.createSymbolicLink(at: linkedFileURL, withDestinationURL: inputURL)
        try FileManager.default.createSymbolicLink(at: linkedDirectoryURL, withDestinationURL: readableDirectory)

        let fileProfile = MCPServerSandboxProfile(server: MCPServer(
            id: "linked-file",
            transport: .stdio(command: "/bin/cat", arguments: [linkedFileURL.path])
        )).profile(commandURL: URL(fileURLWithPath: "/bin/cat"))
        let directoryProfile = MCPServerSandboxProfile(server: MCPServer(
            id: "linked-directory",
            transport: .stdio(command: "/bin/cat", arguments: [linkedDirectoryURL.path])
        )).profile(commandURL: URL(fileURLWithPath: "/bin/cat"))
        let nestedProfile = MCPServerSandboxProfile(server: MCPServer(
            id: "linked-ancestor",
            transport: .stdio(
                command: "/bin/cat",
                arguments: [linkedDirectoryURL.appendingPathComponent("nested.json").path]
            )
        )).profile(commandURL: URL(fileURLWithPath: "/bin/cat"))
        let canonicalInput = inputURL.resolvingSymlinksInPath().standardizedFileURL.path
        let canonicalNestedInput = nestedInputURL.resolvingSymlinksInPath().standardizedFileURL.path
        let canonicalDirectory = readableDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let canonicalLinksDirectory = linksDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let canonicalTargetsDirectory = targetsDirectory.resolvingSymlinksInPath().standardizedFileURL.path

        #expect(!fileProfile.contains(#"(allow file-read* (literal "\#(canonicalInput)"))"#))
        #expect(!fileProfile.contains(#"(allow file-read* (subpath "\#(canonicalTargetsDirectory)"))"#))
        #expect(!fileProfile.contains(#"(allow file-read* (subpath "\#(canonicalLinksDirectory)"))"#))
        #expect(!directoryProfile.contains(#"(allow file-read* (subpath "\#(canonicalDirectory)"))"#))
        #expect(!directoryProfile.contains(#"(allow file-read* (subpath "\#(canonicalLinksDirectory)"))"#))
        #expect(!nestedProfile.contains(#"(allow file-read* (literal "\#(canonicalNestedInput)"))"#))
        #expect(!nestedProfile.contains(#"(allow file-read* (subpath "\#(canonicalDirectory)"))"#))
    }

    @Test("MCP stdio invalid traversal cannot become a recursive directory grant")
    func mcpStdioProfileRejectsInvalidTraversalDirectories() throws {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy-mcp-invalid-traversal-\(UUID().uuidString)", isDirectory: true)
        let workingDirectory = root.appendingPathComponent("working", isDirectory: true)
        let filesDirectory = root.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inputURL = filesDirectory.appendingPathComponent("input.json")
        try Data("{}".utf8).write(to: inputURL)

        let server = MCPServer(
            id: "invalid-traversal",
            transport: .stdio(
                command: "/bin/cat",
                arguments: [
                    inputURL.path + "/..",
                    root.appendingPathComponent("missing").path + "/..",
                    "../files/input.json/..",
                    "../missing/..",
                ],
                workingDirectory: workingDirectory.path
            )
        )
        let profile = MCPServerSandboxProfile(server: server)
            .profile(commandURL: URL(fileURLWithPath: "/bin/cat"))
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let canonicalFilesDirectory = filesDirectory.resolvingSymlinksInPath().standardizedFileURL.path

        #expect(!profile.contains(#"(allow file-read* (subpath "\#(canonicalRoot)"))"#))
        #expect(!profile.contains(#"(allow file-read* (subpath "\#(canonicalFilesDirectory)"))"#))
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

    private func assertNoSharedTemporaryDirectoryGrant(_ profile: String) {
        #expect(!profile.contains(#"(allow file-read* (subpath "/tmp"))"#))
        #expect(!profile.contains(#"(allow file-read* (subpath "/private/tmp"))"#))
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
