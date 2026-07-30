// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentTeamCLILaunchPlan.swift - Exact launch authority for local agent teams.

import Foundation

struct AgentTeamCLILaunchPlan: Sendable, Equatable {
    let config: AgentTeamConfig
    let launchSpecs: [AgentTeamProviderLaunchSpec]
    let authorityDetails: [String: String]
}

enum AgentTeamCLILaunchPlanError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingTeammates
    case missingTeamID
    case unsupportedProvider(String)
    case authorityEncodingFailed

    var description: String {
        switch self {
        case .missingTeammates:
            return "Missing required param: teammates"
        case .missingTeamID:
            return "Agent team launch identity is unavailable"
        case .unsupportedProvider(let provider):
            return "Unsupported agent team provider: \(provider)"
        case .authorityEncodingFailed:
            return "Agent team launch authority could not be encoded"
        }
    }
}

enum AgentTeamCLILaunchPlanner {
    static func make(
        params: [String: String],
        workingDirectory: String,
        fallbackTeamID: String?,
        adapterRegistry: AgentTeamProviderAdapterRegistry
    ) throws -> AgentTeamCLILaunchPlan {
        let providerName = normalized(params["provider"])
            ?? AgentTeamProvider.claudeCode.rawValue
        guard let provider = AgentTeamProvider(rawValue: providerName) else {
            throw AgentTeamCLILaunchPlanError.unsupportedProvider(providerName)
        }

        let requestedTeamID = normalized(params["team-id"]).map(AgentTeamConfig.slug)
        let fallbackTeamID = normalized(fallbackTeamID).map(AgentTeamConfig.slug)
        guard let teamID = requestedTeamID ?? fallbackTeamID else {
            throw AgentTeamCLILaunchPlanError.missingTeamID
        }

        let config: AgentTeamConfig
        if let templateID = normalized(params["template"]) {
            config = try AgentTeamTemplateCatalog.builtin.makeConfig(
                templateID: templateID,
                teamID: teamID,
                provider: provider
            )
        } else if let teammates = normalized(params["teammates"]) {
            config = try AgentTeamConfig.from(
                teammates: teammates,
                teamID: teamID,
                provider: provider
            )
        } else {
            throw AgentTeamCLILaunchPlanError.missingTeammates
        }

        guard let adapter = adapterRegistry.adapter(for: provider) else {
            throw AgentTeamProviderAdapterError.executableUnavailable(
                provider: provider,
                candidates: provider.executableCandidates
            )
        }
        let launchSpecs = try config.teammates.map { teammate in
            try adapter.makeLaunchSpec(
                config: config,
                teammate: teammate,
                profile: AgentTeamLaunchProfile(workingDirectory: workingDirectory)
            )
        }

        return AgentTeamCLILaunchPlan(
            config: config,
            launchSpecs: launchSpecs,
            authorityDetails: try authorityDetails(config: config, launchSpecs: launchSpecs)
        )
    }

    private static func authorityDetails(
        config: AgentTeamConfig,
        launchSpecs: [AgentTeamProviderLaunchSpec]
    ) throws -> [String: String] {
        var details = [
            "operation": "launch",
            "provider": config.provider.rawValue,
            "team-id": config.id,
            "teammate-count": "\(launchSpecs.count)",
        ]
        for (offset, spec) in launchSpecs.enumerated() {
            let prefix = "teammate.\(offset + 1)"
            details["\(prefix).id"] = spec.teammateID
            details["\(prefix).name"] = spec.teammateName
            details["\(prefix).executable"] = spec.executable
            details["\(prefix).arguments"] = try encodedAuthorityValue(spec.arguments)
            details["\(prefix).environment"] = try encodedAuthorityValue(spec.environment)
            details["\(prefix).working-directory"] = spec.workingDirectory ?? ""
        }
        return details
    }

    private static func encodedAuthorityValue<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw AgentTeamCLILaunchPlanError.authorityEncodingFailed
        }
        return encoded
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
