// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultSessionDetector.swift - Deterministic session detection from process snapshots.

import Foundation

public struct VaultSessionDetector: Sendable {
    public typealias Clock = @Sendable () -> Date

    public let registry: VaultAgentRegistry
    private let clock: Clock

    public init(registry: VaultAgentRegistry = .builtIn, clock: @escaping Clock = { Date() }) {
        self.registry = registry
        self.clock = clock
    }

    public func detect(from snapshot: VaultProcessSnapshot) -> VaultSession? {
        let executableCandidates = [snapshot.executableName] + Array(snapshot.arguments.prefix(1))
        guard let agent = executableCandidates.lazy.compactMap({ registry.agent(matching: $0) }).first else {
            return nil
        }
        guard let sessionID = VaultArgvExtractor.extractSessionID(from: snapshot.arguments) else {
            return nil
        }

        let now = clock()
        return VaultSession(
            id: "\(agent.id.rawValue):\(sessionID)",
            agentID: agent.id,
            agentDisplayName: agent.displayName,
            sessionID: sessionID,
            workingDirectory: snapshot.workingDirectory,
            capturedAt: now,
            lastSeenAt: now,
            source: .processSnapshot,
            sanitizedArguments: VaultArgvExtractor.sanitizedArguments(from: snapshot.arguments)
        )
    }

    public func detect(
        agentID: VaultAgentID,
        fileURL: URL,
        workingDirectory: String?
    ) -> VaultSession? {
        guard let agent = registry.agent(matching: agentID.rawValue),
              let sessionID = VaultFileExtractor.extractSessionID(fromFileAt: fileURL) else {
            return nil
        }

        let now = clock()
        return VaultSession(
            id: "\(agent.id.rawValue):\(sessionID)",
            agentID: agent.id,
            agentDisplayName: agent.displayName,
            sessionID: sessionID,
            workingDirectory: workingDirectory,
            capturedAt: now,
            lastSeenAt: now,
            source: .fileSnapshot,
            sanitizedArguments: []
        )
    }
}
