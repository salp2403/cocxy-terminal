// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentSandboxProfile.swift - Sandbox profile planning for Agent providers.

import Foundation

struct AgentSandboxProfile: Sendable, Equatable {
    let provider: AgentProviderKind
    let workspaceURL: URL
    let configURL: URL
    let additionalReadableURLs: [URL]

    init(
        provider: AgentProviderKind,
        workspaceURL: URL,
        configURL: URL,
        additionalReadableURLs: [URL] = []
    ) {
        self.provider = provider
        self.workspaceURL = workspaceURL
        self.configURL = configURL
        self.additionalReadableURLs = additionalReadableURLs
    }

    var capabilities: Set<SandboxCapability> {
        var capabilities: Set<SandboxCapability> = [.filesystemRead]
        if provider.requiresNetworkSandboxCapability {
            capabilities.insert(.network)
        }
        return capabilities
    }

    func profile(builder: SandboxProfileBuilder = SandboxProfileBuilder()) -> String {
        builder.profile(
            capabilities: capabilities,
            readablePaths: [workspaceURL, configURL] + additionalReadableURLs,
            writablePaths: [],
            executablePaths: []
        )
    }
}

private extension AgentProviderKind {
    var requiresNetworkSandboxCapability: Bool {
        self != .foundationModelsOnDevice
    }
}

struct AgentSandboxedProcessRunner: AgentProcessRunning {
    let base: any AgentProcessRunning
    let workspaceURL: URL
    let configURL: URL
    let enabled: Bool
    let sandboxExecutor: SandboxExecutor
    let profileBuilder: SandboxProfileBuilder
    let auditLog: SandboxAuditLog?

    init(
        base: any AgentProcessRunning,
        workspaceURL: URL,
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy", isDirectory: true),
        enabled: Bool = true,
        sandboxExecutor: SandboxExecutor = SandboxExecutor(),
        profileBuilder: SandboxProfileBuilder = SandboxProfileBuilder(),
        auditLog: SandboxAuditLog? = nil
    ) {
        self.base = base
        self.workspaceURL = workspaceURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        self.configURL = configURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        self.enabled = enabled
        self.sandboxExecutor = sandboxExecutor
        self.profileBuilder = profileBuilder
        self.auditLog = auditLog
    }

    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval?
    ) throws -> AgentProcessResult {
        guard enabled else {
            recordAudit(
                executableURL: executableURL,
                decision: .denied,
                detail: "legacy-disabled"
            )
            return try base.run(
                executableURL: executableURL,
                arguments: arguments,
                workingDirectory: workingDirectory,
                timeoutSeconds: timeoutSeconds
            )
        }

        let profile = commandProfile(executableURL: executableURL)
        do {
            let plan = try sandboxExecutor.launchPlan(
                commandURL: executableURL,
                arguments: arguments,
                profile: profile,
                environment: ProcessInfo.processInfo.environment,
                currentDirectoryURL: workingDirectory
            )
            recordAudit(
                executableURL: executableURL,
                decision: .granted,
                detail: "kernel"
            )
            return try base.run(
                executableURL: plan.executableURL,
                arguments: plan.arguments,
                workingDirectory: plan.currentDirectoryURL,
                timeoutSeconds: timeoutSeconds
            )
        } catch SandboxExecutorError.sandboxExecUnavailable {
            recordAudit(
                executableURL: executableURL,
                decision: .denied,
                detail: "legacy-unavailable"
            )
            return try base.run(
                executableURL: executableURL,
                arguments: arguments,
                workingDirectory: workingDirectory,
                timeoutSeconds: timeoutSeconds
            )
        }
    }

    func commandProfile(executableURL: URL) -> String {
        profileBuilder.profile(
            capabilities: [.filesystemRead, .filesystemWrite, .processExec],
            readablePaths: [workspaceURL, configURL],
            writablePaths: [workspaceURL],
            executablePaths: [executableURL],
            readableLiteralPaths: SandboxProfileBuilder.parentDirectoryLiterals(for: workspaceURL),
            executableSubpaths: Self.defaultExecutableSubpaths,
            includeSystemReadBaseline: true
        )
    }

    private func recordAudit(
        executableURL: URL,
        decision: SandboxAuditDecision,
        detail: String
    ) {
        try? auditLog?.append(SandboxAuditEntry(
            timestamp: Date(),
            subjectID: "agent.local-tools",
            subjectKind: .agent,
            operation: "run command \(executableURL.lastPathComponent)",
            capability: .processExec,
            decision: decision,
            detail: detail
        ))
    }

    private static let defaultExecutableSubpaths = [
        URL(fileURLWithPath: "/bin", isDirectory: true),
        URL(fileURLWithPath: "/usr/bin", isDirectory: true),
        URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
        URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
        URL(fileURLWithPath: "/private/var/select", isDirectory: true),
        URL(fileURLWithPath: "/var/select", isDirectory: true),
    ]
}
