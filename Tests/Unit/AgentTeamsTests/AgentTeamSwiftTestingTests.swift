// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentTeamSwiftTestingTests.swift - Agent team domain coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("AgentTeams")
struct AgentTeamSwiftTestingTests {

    @Test("config parses teammate lists with stable IDs and isolated notifications")
    func configParsesTeammateLists() throws {
        let config = try AgentTeamConfig.from(
            teammates: "Design, Build, Review",
            teamID: "local-team",
            provider: .claudeCode
        )

        #expect(config.id == "local-team")
        #expect(config.provider == .claudeCode)
        #expect(config.notificationsIsolated)
        #expect(config.teammates.map(\.name) == ["Design", "Build", "Review"])
        #expect(config.teammates.map(\.id) == ["local-team-design", "local-team-build", "local-team-review"])
    }

    @Test("launcher spawns one native pane per teammate")
    @MainActor
    func launcherSpawnsOnePanePerTeammate() throws {
        let config = try AgentTeamConfig.from(
            teammates: "Planner, Implementer, Reviewer",
            teamID: "ship",
            provider: .claudeCode
        )
        let paneLauncher = RecordingAgentTeamPaneLauncher()
        let launcher = AgentTeamLauncher(paneLauncher: paneLauncher)

        let result = try launcher.launch(config: config)

        #expect(result.teamID == "ship")
        #expect(result.launchedCount == 3)
        #expect(paneLauncher.requests.map(\.teammateID) == [
            "ship-planner",
            "ship-implementer",
            "ship-reviewer",
        ])
        #expect(paneLauncher.requests.allSatisfy { $0.sessionID == "ship" })
        #expect(paneLauncher.requests.map(\.agentType) == ["Planner", "Implementer", "Reviewer"])
    }

    @Test("coordinator keeps teammate notifications isolated")
    func coordinatorKeepsNotificationsIsolated() throws {
        let config = try AgentTeamConfig.from(teammates: "A, B", teamID: "pair", provider: .claudeCode)
        var coordinator = AgentTeamCoordinator(config: config)

        try coordinator.recordNotification(teammateID: "pair-a", message: "needs input")
        try coordinator.recordNotification(teammateID: "pair-b", message: "finished")

        #expect(coordinator.notifications(for: "pair-a").map(\.message) == ["needs input"])
        #expect(coordinator.notifications(for: "pair-b").map(\.message) == ["finished"])
        #expect(coordinator.notifications(for: "missing").isEmpty)
    }

    @Test("persistence round trips configs with owner-only file permissions")
    func persistenceRoundTripsWithOwnerOnlyPermissions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-agent-teams-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AgentTeamPersistence(directory: root)
        let config = try AgentTeamConfig.from(teammates: "A, B, C", teamID: "persisted", provider: .claudeCode)

        try store.save(config)
        let loaded = try store.load(teamID: "persisted")

        #expect(loaded == config)
        let permissions = try FileManager.default.attributesOfItem(
            atPath: root.appendingPathComponent("persisted.json").path
        )[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }
}

@MainActor
private final class RecordingAgentTeamPaneLauncher: AgentTeamPaneLaunching {
    struct Request: Equatable {
        let teammateID: String
        let sessionID: String
        let agentType: String
    }

    private(set) var requests: [Request] = []

    func spawnAgentTeamPane(teammateID: String, sessionID: String, agentType: String) -> Bool {
        requests.append(Request(teammateID: teammateID, sessionID: sessionID, agentType: agentType))
        return true
    }
}
