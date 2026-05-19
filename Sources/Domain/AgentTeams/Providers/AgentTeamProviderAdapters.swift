// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentTeamProviderAdapters.swift - Local-first launch planning for agent team providers.

import Foundation

struct AgentTeamLaunchProfile: Codable, Sendable, Equatable {
    let workingDirectory: String?
    let environment: [String: String]
    let arguments: [String]

    init(
        workingDirectory: String? = nil,
        environment: [String: String] = [:],
        arguments: [String] = []
    ) {
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.arguments = arguments
    }
}

struct AgentTeamProviderLaunchSpec: Codable, Sendable, Equatable {
    let provider: AgentTeamProvider
    let teamID: String
    let teammateID: String
    let teammateName: String
    let executable: String
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: String?
    let mutatesUserConfiguration: Bool
    let requiresPreviewBeforeLaunch: Bool

    init(
        provider: AgentTeamProvider,
        teamID: String,
        teammateID: String,
        teammateName: String,
        executable: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String?,
        mutatesUserConfiguration: Bool,
        requiresPreviewBeforeLaunch: Bool
    ) {
        self.provider = provider
        self.teamID = teamID
        self.teammateID = teammateID
        self.teammateName = teammateName
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.mutatesUserConfiguration = mutatesUserConfiguration
        self.requiresPreviewBeforeLaunch = requiresPreviewBeforeLaunch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(AgentTeamProvider.self, forKey: .provider)
        teammateID = try container.decode(String.self, forKey: .teammateID)
        teammateName = try container.decode(String.self, forKey: .teammateName)
        executable = try container.decode(String.self, forKey: .executable)
        arguments = try container.decode([String].self, forKey: .arguments)
        environment = try container.decode([String: String].self, forKey: .environment)
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        mutatesUserConfiguration = try container.decode(Bool.self, forKey: .mutatesUserConfiguration)
        requiresPreviewBeforeLaunch = try container.decode(Bool.self, forKey: .requiresPreviewBeforeLaunch)
        teamID = try container.decodeIfPresent(String.self, forKey: .teamID)
            ?? environment["COCXY_AGENT_TEAM_ID"]
            ?? teammateID
    }
}

enum AgentTeamProviderAdapterError: Error, Equatable, Sendable, CustomStringConvertible {
    case executableUnavailable(provider: AgentTeamProvider, candidates: [String])
    case providerMismatch(expected: AgentTeamProvider, actual: AgentTeamProvider)
    case unknownTeammate(String)
    case emptyTeammateName

    var description: String {
        switch self {
        case .executableUnavailable(let provider, let candidates):
            return "No executable found for \(provider.rawValue). Tried: \(candidates.joined(separator: ", "))"
        case .providerMismatch(let expected, let actual):
            return "Provider mismatch. Expected \(expected.rawValue), got \(actual.rawValue)"
        case .unknownTeammate(let teammateID):
            return "Unknown teammate: \(teammateID)"
        case .emptyTeammateName:
            return "Teammate name cannot be empty"
        }
    }
}

protocol AgentTeamProviderAdapter: Sendable {
    var provider: AgentTeamProvider { get }
    var displayName: String { get }
    var executableCandidates: [String] { get }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec
}

typealias AgentTeamExecutableResolver = @Sendable (String) -> String?

private struct AgentTeamProviderAdapterCore: Sendable {
    let provider: AgentTeamProvider
    private let executableResolver: AgentTeamExecutableResolver

    init(
        provider: AgentTeamProvider,
        executableResolver: @escaping AgentTeamExecutableResolver
    ) {
        self.provider = provider
        self.executableResolver = executableResolver
    }

    var displayName: String {
        provider.displayName
    }

    var executableCandidates: [String] {
        provider.executableCandidates
    }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile = AgentTeamLaunchProfile()
    ) throws -> AgentTeamProviderLaunchSpec {
        guard config.provider == provider else {
            throw AgentTeamProviderAdapterError.providerMismatch(expected: provider, actual: config.provider)
        }
        guard config.teammates.contains(teammate) else {
            throw AgentTeamProviderAdapterError.unknownTeammate(teammate.id)
        }
        let teammateName = teammate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !teammateName.isEmpty else {
            throw AgentTeamProviderAdapterError.emptyTeammateName
        }
        guard let executable = executableCandidates.lazy.compactMap({ executableResolver($0) }).first else {
            throw AgentTeamProviderAdapterError.executableUnavailable(
                provider: provider,
                candidates: executableCandidates
            )
        }

        var environment = profile.environment
        environment["COCXY_AGENT_TEAM_ID"] = config.id
        environment["COCXY_AGENT_TEAMMATE_ID"] = teammate.id
        environment["COCXY_AGENT_TEAMMATE_NAME"] = teammateName
        environment["COCXY_AGENT_PROVIDER"] = provider.rawValue

        return AgentTeamProviderLaunchSpec(
            provider: provider,
            teamID: config.id,
            teammateID: teammate.id,
            teammateName: teammateName,
            executable: executable,
            arguments: profile.arguments,
            environment: environment,
            workingDirectory: profile.workingDirectory,
            mutatesUserConfiguration: false,
            requiresPreviewBeforeLaunch: true
        )
    }
}

struct ClaudeCodeTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .claudeCode, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct CodexTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .codex, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct OpenCodeTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .opencode, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct PiTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .pi, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct CursorTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .cursor, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct GeminiTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .gemini, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct RovoDevTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .rovoDev, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct CopilotTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .copilot, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct CodeBuddyTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .codebuddy, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct FactoryTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .factory, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct QoderTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .qoder, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct KiroTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .kiro, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct AgentTeamProviderAdapterRegistry: Sendable {
    private let adaptersByProvider: [AgentTeamProvider: any AgentTeamProviderAdapter]

    init(executableResolver: @escaping AgentTeamExecutableResolver = Self.defaultExecutableResolver) {
        let adapters: [any AgentTeamProviderAdapter] = [
            ClaudeCodeTeamProviderAdapter(executableResolver: executableResolver),
            CodexTeamProviderAdapter(executableResolver: executableResolver),
            OpenCodeTeamProviderAdapter(executableResolver: executableResolver),
            PiTeamProviderAdapter(executableResolver: executableResolver),
            CursorTeamProviderAdapter(executableResolver: executableResolver),
            GeminiTeamProviderAdapter(executableResolver: executableResolver),
            RovoDevTeamProviderAdapter(executableResolver: executableResolver),
            CopilotTeamProviderAdapter(executableResolver: executableResolver),
            CodeBuddyTeamProviderAdapter(executableResolver: executableResolver),
            FactoryTeamProviderAdapter(executableResolver: executableResolver),
            QoderTeamProviderAdapter(executableResolver: executableResolver),
            KiroTeamProviderAdapter(executableResolver: executableResolver),
        ]
        self.adaptersByProvider = Dictionary(uniqueKeysWithValues: adapters.map { ($0.provider, $0) })
    }

    var providers: [AgentTeamProvider] {
        AgentTeamProvider.allCases.filter { adaptersByProvider[$0] != nil }
    }

    func adapter(for provider: AgentTeamProvider) -> (any AgentTeamProviderAdapter)? {
        adaptersByProvider[provider]
    }

    static let defaultExecutableResolver: AgentTeamExecutableResolver = { executable in
        if executable.contains("/") {
            return FileManager.default.isExecutableFile(atPath: executable) ? executable : nil
        }

        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        for directory in pathValue.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(executable).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
