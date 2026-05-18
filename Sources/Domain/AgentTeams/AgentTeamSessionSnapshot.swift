// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentTeamSessionSnapshot.swift - Reproducible local team session snapshots.

import Foundation

struct AgentTeamSessionSnapshot: Identifiable, Codable, Sendable, Equatable {
    var id: String { config.id }

    let config: AgentTeamConfig
    let graph: AgentTeamGraph
    let feed: AgentTeamFeed
    let launchSpecs: [AgentTeamProviderLaunchSpec]
    let createdAt: Date
    let updatedAt: Date

    init(
        config: AgentTeamConfig,
        graph: AgentTeamGraph,
        feed: AgentTeamFeed,
        launchSpecs: [AgentTeamProviderLaunchSpec],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.config = config
        self.graph = graph
        self.feed = feed
        self.launchSpecs = launchSpecs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum AgentTeamSessionSnapshotStoreError: Error, Equatable, Sendable, CustomStringConvertible {
    case persistenceFailed(String)

    var description: String {
        switch self {
        case .persistenceFailed(let message):
            return "Agent team session snapshot persistence failed: \(message)"
        }
    }
}

struct AgentTeamSessionSnapshotStore: Sendable {
    let directory: URL

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/cocxy/team-snapshots")) {
        self.directory = directory
    }

    func save(_ snapshot: AgentTeamSessionSnapshot) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder.agentTeamSnapshots.encode(snapshot)
            let url = fileURL(teamID: snapshot.id)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw AgentTeamSessionSnapshotStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    func load(teamID: String) throws -> AgentTeamSessionSnapshot {
        do {
            let data = try Data(contentsOf: fileURL(teamID: teamID))
            return try JSONDecoder.agentTeamSnapshots.decode(AgentTeamSessionSnapshot.self, from: data)
        } catch {
            throw AgentTeamSessionSnapshotStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    func fileURL(teamID: String) -> URL {
        directory.appendingPathComponent("\(AgentTeamConfig.slug(teamID)).snapshot.json")
    }
}

private extension JSONEncoder {
    static var agentTeamSnapshots: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var agentTeamSnapshots: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
