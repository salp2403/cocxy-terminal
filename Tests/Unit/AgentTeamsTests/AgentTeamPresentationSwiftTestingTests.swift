// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentTeamPresentationSwiftTestingTests.swift - Agent team UI presentation contracts.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Agent team UI presentation")
struct AgentTeamPresentationSwiftTestingTests {
    @Test("graph presentation exposes stable rows with permissions files and accessibility labels")
    func graphPresentationExposesStableRows() throws {
        let config = try AgentTeamConfig.from(
            teammates: "Plan, Build",
            teamID: "ship-team",
            provider: .codex
        )
        var graph = AgentTeamGraph(config: config, now: Date(timeIntervalSince1970: 1_000))
        try graph.updateStatus(
            nodeID: "ship-team-build",
            status: .working,
            now: Date(timeIntervalSince1970: 2_000)
        )
        try graph.setPermissions(
            nodeID: "ship-team-build",
            permissions: [.fileRead, .fileWrite, .exec],
            now: Date(timeIntervalSince1970: 2_000)
        )
        try graph.recordTouchedFile(
            nodeID: "ship-team-build",
            path: "/tmp/app/Sources/App.swift",
            now: Date(timeIntervalSince1970: 2_000)
        )
        try graph.recordTouchedFile(
            nodeID: "ship-team-build",
            path: "/tmp/app/Tests/AppTests.swift",
            now: Date(timeIntervalSince1970: 2_000)
        )

        let presentation = AgentTeamGraphPresentation(graph: graph)

        #expect(presentation.rows.map(\.id) == ["ship-team", "ship-team-plan", "ship-team-build"])
        #expect(presentation.rows[0].isRoot)
        let build = try #require(presentation.rows.first { $0.id == "ship-team-build" })
        #expect(build.status == .working)
        #expect(build.permissionSummary == "file-read, file-write, exec")
        #expect(build.touchedFileSummary == "2 files")
        #expect(build.accessibilityLabel == "Build, Codex CLI, working, permissions file-read, file-write, exec, 2 files touched")
    }

    @Test("feed presentation filters by kind and query while preserving chronological order")
    func feedPresentationFiltersByKindAndQuery() throws {
        let config = try AgentTeamConfig.from(
            teammates: "Plan, Build",
            teamID: "ship-team",
            provider: .codex
        )
        var feed = AgentTeamFeed(config: config)
        let later = Date(timeIntervalSince1970: 2_000)
        let earlier = Date(timeIntervalSince1970: 1_000)
        let permission = try feed.record(
            teammateID: "ship-team-plan",
            kind: .permissionRequest,
            message: "Needs network access",
            createdAt: later
        )
        let completion = try feed.record(
            teammateID: "ship-team-build",
            kind: .completion,
            message: "Implemented parser",
            createdAt: earlier
        )
        let error = try feed.record(
            teammateID: "ship-team-build",
            kind: .error,
            message: "Network request failed",
            createdAt: later
        )

        let allRows = AgentTeamFeedPresentation(feed: feed).rows
        let filteredRows = AgentTeamFeedPresentation(
            feed: feed,
            kind: .error,
            query: "network"
        ).rows

        #expect(allRows.map(\.id) == [
            completion.id.uuidString,
            permission.id.uuidString,
            error.id.uuidString,
        ])
        #expect(filteredRows.map(\.id) == [error.id.uuidString])
        #expect(filteredRows[0].accessibilityLabel == "Build, error, Network request failed")
    }

    @Test("panel source exposes VoiceOver container and teammate row labels")
    func panelSourceExposesVoiceOverContainerAndRows() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("Sources/UI/AgentTeams/AgentTeamViews.swift"),
            encoding: .utf8
        )

        #expect(source.contains(".accessibilityElement(children: .contain)"))
        #expect(source.contains("agentTeams.panel.title"))
        #expect(source.contains(".accessibilityElement(children: .ignore)"))
        #expect(source.contains("notifications.count"))
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
