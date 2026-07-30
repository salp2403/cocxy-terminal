// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskHandoffDestination.swift - Validated destination for a local task handoff.

import CocxyShared
import CryptoKit
import Foundation

enum TaskHandoffDestinationError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedProvider(String)
    case emptyArtifact
    case artifactTooLarge(maximumBytes: Int)
    case invalidArtifact

    var description: String {
        switch self {
        case .unsupportedProvider(let provider):
            return "Unsupported task handoff provider: \(provider)"
        case .emptyArtifact:
            return "Task handoff artifact cannot be empty"
        case .artifactTooLarge(let maximumBytes):
            return "Task handoff artifact exceeds the \(maximumBytes)-byte limit"
        case .invalidArtifact:
            return "Task handoff artifact contains invalid control data"
        }
    }
}

struct TaskHandoffDestination: Equatable, Sendable {
    static let authorityProviderKey = "handoff-provider"
    static let authorityArtifactBytesKey = "handoff-artifact-bytes"
    static let authorityArtifactDigestKey = "handoff-artifact-sha256"

    let provider: AgentTeamProvider
    let artifact: String
    let artifactByteCount: Int
    let artifactDigest: String

    static func make(agent rawAgent: String, artifact: String) throws -> Self {
        let normalizedAgent = rawAgent
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let provider = AgentTeamProvider.resolve(named: normalizedAgent) else {
            throw TaskHandoffDestinationError.unsupportedProvider(normalizedAgent)
        }
        guard !artifact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TaskHandoffDestinationError.emptyArtifact
        }
        let data = Data(artifact.utf8)
        guard data.count <= CocxyTaskHandoffWireContract.maximumArtifactBytes else {
            throw TaskHandoffDestinationError.artifactTooLarge(
                maximumBytes: CocxyTaskHandoffWireContract.maximumArtifactBytes
            )
        }
        guard !artifact.contains("\0") else {
            throw TaskHandoffDestinationError.invalidArtifact
        }
        return Self(
            provider: provider,
            artifact: artifact,
            artifactByteCount: data.count,
            artifactDigest: SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        )
    }

    var authorityDetails: [String: String] {
        [
            Self.authorityProviderKey: provider.rawValue,
            Self.authorityArtifactBytesKey: "\(artifactByteCount)",
            Self.authorityArtifactDigestKey: artifactDigest,
        ]
    }

    func makeAgentTeamConfig(identifier: UUID = UUID()) -> AgentTeamConfig {
        let teamID = AgentTeamConfig.slug(
            "handoff-\(provider.rawValue)-\(identifier.uuidString.prefix(8))"
        )
        return AgentTeamConfig(
            id: teamID,
            provider: provider,
            teammates: [
                AgentTeammateConfig(
                    id: "\(teamID)-task",
                    name: "Task Handoff",
                    prompt: artifact
                ),
            ]
        )
    }
}
