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
    case paneLaunchFailed(String)
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
    func spawnAgentTeamPane(launchSpec: AgentTeamProviderLaunchSpec) -> Bool
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
        guard let paneLauncher else {
            throw AgentTeamError.paneLaunchFailed("missing pane launcher")
        }
        guard let adapter = adapterRegistry.adapter(for: config.provider) else {
            throw AgentTeamProviderAdapterError.executableUnavailable(
                provider: config.provider,
                candidates: config.provider.executableCandidates
            )
        }

        var launchedIDs: [String] = []
        var launchSpecs: [AgentTeamProviderLaunchSpec] = []
        for teammate in config.teammates {
            let launchSpec = try adapter.makeLaunchSpec(
                config: config,
                teammate: teammate,
                profile: launchProfileProvider(teammate)
            )
            let didLaunch = paneLauncher.spawnAgentTeamPane(launchSpec: launchSpec)
            guard didLaunch else {
                throw AgentTeamError.paneLaunchFailed(teammate.id)
            }
            launchedIDs.append(teammate.id)
            launchSpecs.append(launchSpec)
        }

        return AgentTeamLaunchResult(
            teamID: config.id,
            launchedCount: launchedIDs.count,
            teammateIDs: launchedIDs,
            launchSpecs: launchSpecs
        )
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
