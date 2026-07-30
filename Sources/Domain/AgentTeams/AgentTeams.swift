// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentTeams.swift - Local agent team launch and coordination models.

import Foundation

enum AgentTeamProvider: String, CaseIterable, Codable, Sendable, Equatable {
    case claudeCode = "claude-code"
    case codex
    case opencode
    case pi
    case cursor
    case gemini
    case rovoDev = "rovo-dev"
    case copilot
    case codebuddy
    case factory
    case qoder
    case kiro

    static func resolve(named rawName: String) -> AgentTeamProvider? {
        switch rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "claude", "claude-code", "claude code": return .claudeCode
        case "codex", "codex-cli", "codex cli": return .codex
        case "open-code", "open code", "opencode": return .opencode
        case "pi": return .pi
        case "cursor", "cursor-agent", "cursor agent": return .cursor
        case "gemini", "gemini-cli", "gemini cli": return .gemini
        case "rovo", "rovo-dev", "rovo dev", "rovodev": return .rovoDev
        case "copilot", "github-copilot", "github copilot": return .copilot
        case "codebuddy": return .codebuddy
        case "factory", "droid": return .factory
        case "qoder", "qodercli": return .qoder
        case "kiro", "kiro-cli", "kiro cli": return .kiro
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex CLI"
        case .opencode:
            return "OpenCode"
        case .pi:
            return "Pi"
        case .cursor:
            return "Cursor"
        case .gemini:
            return "Gemini CLI"
        case .rovoDev:
            return "Rovo Dev"
        case .copilot:
            return "Copilot"
        case .codebuddy:
            return "CodeBuddy"
        case .factory:
            return "Factory"
        case .qoder:
            return "Qoder"
        case .kiro:
            return "Kiro"
        }
    }

    var executableCandidates: [String] {
        switch self {
        case .claudeCode:
            return ["claude", "claude-code"]
        case .codex:
            return ["codex"]
        case .opencode:
            return ["opencode", "open-code"]
        case .pi:
            return ["pi"]
        case .cursor:
            return ["cursor-agent", "cursor"]
        case .gemini:
            return ["gemini"]
        case .rovoDev:
            return ["acli", "rovodev", "rovo"]
        case .copilot:
            return ["copilot"]
        case .codebuddy:
            return ["codebuddy"]
        case .factory:
            return ["droid", "factory"]
        case .qoder:
            return ["qodercli", "qoder"]
        case .kiro:
            return ["kiro", "kiro-cli"]
        }
    }
}

enum AgentTeamStatus: String, Codable, Sendable, Equatable {
    case starting
    case working
    case waiting
    case finished
    case error
}

enum AgentTeamError: Error, Equatable, Sendable {
    case emptyTeammates
    case unknownTeammate(String)
    case alreadyRunning(String)
    case paneLaunchFailed(String)
    case launchPlanMismatch(String)
    case persistenceFailed(String)
}

struct AgentTeammateConfig: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let name: String
    let prompt: String?
}

struct AgentTeamConfig: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let provider: AgentTeamProvider
    let teammates: [AgentTeammateConfig]
    let layout: String
    let notificationsIsolated: Bool

    init(
        id: String,
        provider: AgentTeamProvider,
        teammates: [AgentTeammateConfig],
        layout: String = "horizontal",
        notificationsIsolated: Bool = true
    ) {
        self.id = id
        self.provider = provider
        self.teammates = teammates
        self.layout = layout
        self.notificationsIsolated = notificationsIsolated
    }

    static func from(
        teammates rawTeammates: String,
        teamID: String? = nil,
        provider: AgentTeamProvider = .claudeCode
    ) throws -> AgentTeamConfig {
        let names = rawTeammates
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { throw AgentTeamError.emptyTeammates }

        let normalizedTeamID = Self.slug(teamID ?? "team-\(UUID().uuidString.prefix(8))")
        var usedIDs: [String: Int] = [:]
        let teammates = names.map { name -> AgentTeammateConfig in
            let baseID = "\(normalizedTeamID)-\(Self.slug(name))"
            let next = (usedIDs[baseID] ?? 0) + 1
            usedIDs[baseID] = next
            let teammateID = next == 1 ? baseID : "\(baseID)-\(next)"
            return AgentTeammateConfig(id: teammateID, name: name, prompt: nil)
        }

        return AgentTeamConfig(id: normalizedTeamID, provider: provider, teammates: teammates)
    }

    static func slug(_ value: String) -> String {
        let scalars = value
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "team" : collapsed
    }
}

struct AgentTeammateState: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let name: String
    var status: AgentTeamStatus
    var updatedAt: Date
}

struct AgentTeamNotification: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let teammateID: String
    let message: String
    let createdAt: Date
}

struct AgentTeamCoordinator: Codable, Sendable, Equatable {
    let config: AgentTeamConfig
    private var statesByTeammateID: [String: AgentTeammateState]
    private var notificationsByTeammateID: [String: [AgentTeamNotification]]

    init(config: AgentTeamConfig) {
        self.config = config
        self.statesByTeammateID = Dictionary(uniqueKeysWithValues: config.teammates.map {
            ($0.id, AgentTeammateState(id: $0.id, name: $0.name, status: .starting, updatedAt: Date()))
        })
        self.notificationsByTeammateID = Dictionary(uniqueKeysWithValues: config.teammates.map {
            ($0.id, [])
        })
    }

    mutating func updateStatus(teammateID: String, status: AgentTeamStatus, now: Date = Date()) throws {
        guard var state = statesByTeammateID[teammateID] else {
            throw AgentTeamError.unknownTeammate(teammateID)
        }
        state.status = status
        state.updatedAt = now
        statesByTeammateID[teammateID] = state
    }

    mutating func recordNotification(teammateID: String, message: String, now: Date = Date()) throws {
        guard notificationsByTeammateID[teammateID] != nil else {
            throw AgentTeamError.unknownTeammate(teammateID)
        }
        notificationsByTeammateID[teammateID, default: []].append(AgentTeamNotification(
            id: UUID(),
            teammateID: teammateID,
            message: message,
            createdAt: now
        ))
    }

    func notifications(for teammateID: String) -> [AgentTeamNotification] {
        notificationsByTeammateID[teammateID] ?? []
    }

    var teammateStates: [AgentTeammateState] {
        config.teammates.compactMap { statesByTeammateID[$0.id] }
    }
}

struct AgentTeamLaunchResult: Sendable, Equatable {
    let teamID: String
    let launchedCount: Int
    let teammateIDs: [String]
    let launchSpecs: [AgentTeamProviderLaunchSpec]
}

@MainActor
protocol AgentTeamPaneLaunching: AnyObject {
    func spawnAgentTeamPane(
        launchSpec: AgentTeamProviderLaunchSpec,
        initialPrompt: String?
    ) -> Bool
    func closeAgentTeamPanes(teamID: String)
}

@MainActor
final class AgentTeamLauncher {
    private weak var paneLauncher: (any AgentTeamPaneLaunching)?
    private let adapterRegistry: AgentTeamProviderAdapterRegistry
    private let launchProfileProvider: @Sendable (AgentTeammateConfig) -> AgentTeamLaunchProfile

    init(
        paneLauncher: any AgentTeamPaneLaunching,
        adapterRegistry: AgentTeamProviderAdapterRegistry = AgentTeamProviderAdapterRegistry(),
        launchProfileProvider: @escaping @Sendable (AgentTeammateConfig) -> AgentTeamLaunchProfile = { _ in
            AgentTeamLaunchProfile()
        }
    ) {
        self.paneLauncher = paneLauncher
        self.adapterRegistry = adapterRegistry
        self.launchProfileProvider = launchProfileProvider
    }

    func launch(config: AgentTeamConfig) throws -> AgentTeamLaunchResult {
        try launch(
            config: config,
            preparedLaunchSpecs: prepareLaunchSpecs(config: config)
        )
    }

    func prepareLaunchSpecs(config: AgentTeamConfig) throws -> [AgentTeamProviderLaunchSpec] {
        guard let adapter = adapterRegistry.adapter(for: config.provider) else {
            throw AgentTeamProviderAdapterError.executableUnavailable(
                provider: config.provider,
                candidates: config.provider.executableCandidates
            )
        }
        return try config.teammates.map { teammate in
            try adapter.makeLaunchSpec(
                config: config,
                teammate: teammate,
                profile: launchProfileProvider(teammate)
            )
        }
    }

    func launch(
        config: AgentTeamConfig,
        preparedLaunchSpecs: [AgentTeamProviderLaunchSpec]
    ) throws -> AgentTeamLaunchResult {
        guard let paneLauncher else {
            throw AgentTeamError.paneLaunchFailed("missing pane launcher")
        }
        try validatePreparedLaunchSpecs(preparedLaunchSpecs, for: config)

        var hasLaunchedPane = false
        do {
            var launchedIDs: [String] = []
            var launchSpecs: [AgentTeamProviderLaunchSpec] = []
            for (teammate, launchSpec) in zip(config.teammates, preparedLaunchSpecs) {
                let didLaunch = paneLauncher.spawnAgentTeamPane(
                    launchSpec: launchSpec,
                    initialPrompt: teammate.prompt
                )
                guard didLaunch else {
                    throw AgentTeamError.paneLaunchFailed(teammate.id)
                }
                hasLaunchedPane = true
                launchedIDs.append(teammate.id)
                launchSpecs.append(launchSpec)
            }

            return AgentTeamLaunchResult(
                teamID: config.id,
                launchedCount: launchedIDs.count,
                teammateIDs: launchedIDs,
                launchSpecs: launchSpecs
            )
        } catch {
            if hasLaunchedPane {
                paneLauncher.closeAgentTeamPanes(teamID: config.id)
            }
            throw error
        }
    }

    private func validatePreparedLaunchSpecs(
        _ launchSpecs: [AgentTeamProviderLaunchSpec],
        for config: AgentTeamConfig
    ) throws {
        guard launchSpecs.count == config.teammates.count else {
            throw AgentTeamError.launchPlanMismatch(config.id)
        }
        for (teammate, spec) in zip(config.teammates, launchSpecs) {
            guard spec.provider == config.provider,
                  spec.teamID == config.id,
                  spec.teammateID == teammate.id,
                  spec.teammateName == teammate.name.trimmingCharacters(in: .whitespacesAndNewlines),
                  spec.environment["COCXY_AGENT_TEAM_ID"] == config.id,
                  spec.environment["COCXY_AGENT_TEAMMATE_ID"] == teammate.id,
                  spec.environment["COCXY_AGENT_TEAMMATE_NAME"] == spec.teammateName,
                  spec.environment["COCXY_AGENT_PROVIDER"] == config.provider.rawValue,
                  AgentTeamLaunchCommand.makeShellCommand(for: spec) != nil else {
                throw AgentTeamError.launchPlanMismatch(teammate.id)
            }
        }
    }
}

struct AgentTeamPersistence: Sendable {
    let directory: URL

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/cocxy/teams")) {
        self.directory = directory
    }

    func save(_ config: AgentTeamConfig) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder.agentTeams.encode(config)
            let url = fileURL(teamID: config.id)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw AgentTeamError.persistenceFailed(error.localizedDescription)
        }
    }

    func load(teamID: String) throws -> AgentTeamConfig {
        do {
            let data = try Data(contentsOf: fileURL(teamID: teamID))
            return try JSONDecoder.agentTeams.decode(AgentTeamConfig.self, from: data)
        } catch {
            throw AgentTeamError.persistenceFailed(error.localizedDescription)
        }
    }

    func fileURL(teamID: String) -> URL {
        directory.appendingPathComponent("\(AgentTeamConfig.slug(teamID)).json")
    }
}

private extension JSONEncoder {
    static var agentTeams: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var agentTeams: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
