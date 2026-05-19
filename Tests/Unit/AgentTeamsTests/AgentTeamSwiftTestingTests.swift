// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentTeamSwiftTestingTests.swift - Agent team domain coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("AgentTeams")
struct AgentTeamSwiftTestingTests {

    @Test("provider catalog covers the local agent launchers without hosted providers")
    func providerCatalogCoversLocalAgentLaunchers() {
        #expect(AgentTeamProvider.allCases.map(\.rawValue) == [
            "claude-code",
            "codex",
            "opencode",
            "pi",
            "cursor",
            "gemini",
            "rovo-dev",
            "copilot",
            "codebuddy",
            "factory",
            "qoder",
            "kiro",
        ])
        #expect(AgentTeamProvider.allCases.map(\.rawValue).contains("hosted-cocxy") == false)
        #expect(AgentTeamProvider.codex.displayName == "Codex CLI")
        #expect(AgentTeamProvider.gemini.executableCandidates == ["gemini"])
    }

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

    @Test("config preserves non-Claude team providers")
    func configPreservesNonClaudeProviders() throws {
        let config = try AgentTeamConfig.from(
            teammates: "Plan, Build",
            teamID: "codex-team",
            provider: .codex
        )

        #expect(config.provider == .codex)
        #expect(config.teammates.map(\.id) == ["codex-team-plan", "codex-team-build"])
    }

    @Test("provider adapter registry covers every local team provider")
    func providerAdapterRegistryCoversEveryLocalTeamProvider() {
        let registry = AgentTeamProviderAdapterRegistry(executableResolver: { executable in
            "/usr/local/bin/\(executable)"
        })

        #expect(registry.providers == AgentTeamProvider.allCases)
        #expect(registry.adapter(for: .claudeCode)?.displayName == "Claude Code")
        #expect(registry.adapter(for: .qoder)?.executableCandidates == ["qodercli", "qoder"])
        let adapterTypeNames = AgentTeamProvider.allCases.compactMap { provider in
            registry.adapter(for: provider).map { String(describing: type(of: $0)) }
        }
        #expect(adapterTypeNames == [
            "ClaudeCodeTeamProviderAdapter",
            "CodexTeamProviderAdapter",
            "OpenCodeTeamProviderAdapter",
            "PiTeamProviderAdapter",
            "CursorTeamProviderAdapter",
            "GeminiTeamProviderAdapter",
            "RovoDevTeamProviderAdapter",
            "CopilotTeamProviderAdapter",
            "CodeBuddyTeamProviderAdapter",
            "FactoryTeamProviderAdapter",
            "QoderTeamProviderAdapter",
            "KiroTeamProviderAdapter",
        ])
    }

    @Test("provider adapters build preview-only launch specs without config mutation")
    func providerAdaptersBuildPreviewOnlyLaunchSpecs() throws {
        let config = try AgentTeamConfig.from(
            teammates: "Plan, Build",
            teamID: "codex-team",
            provider: .codex
        )
        let registry = AgentTeamProviderAdapterRegistry(executableResolver: { executable in
            executable == "codex" ? "/opt/homebrew/bin/codex" : nil
        })
        let adapter = try #require(registry.adapter(for: .codex))

        let spec = try adapter.makeLaunchSpec(
            config: config,
            teammate: config.teammates[0],
            profile: AgentTeamLaunchProfile(
                workingDirectory: "/tmp/workspace",
                environment: ["SAFE_FLAG": "1"],
                arguments: ["--profile", "local"]
            )
        )

        #expect(spec.provider == .codex)
        #expect(spec.teamID == "codex-team")
        #expect(spec.executable == "/opt/homebrew/bin/codex")
        #expect(spec.arguments == ["--profile", "local"])
        #expect(spec.workingDirectory == "/tmp/workspace")
        #expect(spec.environment["SAFE_FLAG"] == "1")
        #expect(spec.environment["COCXY_AGENT_TEAM_ID"] == "codex-team")
        #expect(spec.environment["COCXY_AGENT_TEAMMATE_ID"] == "codex-team-plan")
        #expect(spec.environment["COCXY_AGENT_TEAMMATE_NAME"] == "Plan")
        #expect(spec.environment["COCXY_AGENT_PROVIDER"] == "codex")
        #expect(spec.mutatesUserConfiguration == false)
        #expect(spec.requiresPreviewBeforeLaunch == true)
    }

    @Test("provider launch specs decode legacy snapshots without teamID")
    func providerLaunchSpecsDecodeLegacySnapshotsWithoutTeamID() throws {
        let data = Data("""
        {
          "provider": "codex",
          "teammateID": "ship-plan",
          "teammateName": "Plan",
          "executable": "/usr/local/bin/codex",
          "arguments": [],
          "environment": {
            "COCXY_AGENT_TEAM_ID": "ship",
            "COCXY_AGENT_PROVIDER": "codex"
          },
          "mutatesUserConfiguration": false,
          "requiresPreviewBeforeLaunch": true
        }
        """.utf8)

        let spec = try JSONDecoder().decode(AgentTeamProviderLaunchSpec.self, from: data)

        #expect(spec.teamID == "ship")
        #expect(spec.teammateID == "ship-plan")
        #expect(spec.provider == .codex)
    }

    @Test("provider adapters reject missing executables without launch side effects")
    func providerAdaptersRejectMissingExecutablesWithoutLaunchSideEffects() throws {
        let config = try AgentTeamConfig.from(
            teammates: "Plan",
            teamID: "missing-provider",
            provider: .gemini
        )
        let adapter = GeminiTeamProviderAdapter(executableResolver: { _ in nil })

        do {
            _ = try adapter.makeLaunchSpec(
                config: config,
                teammate: config.teammates[0],
                profile: AgentTeamLaunchProfile()
            )
            Issue.record("Expected missing executable error")
        } catch let error as AgentTeamProviderAdapterError {
            #expect(error == .executableUnavailable(provider: .gemini, candidates: ["gemini"]))
        }
    }

    @Test("team graph starts with root node and teammate spawn edges")
    func teamGraphStartsWithRootNodeAndTeammateSpawnEdges() throws {
        let config = try AgentTeamConfig.from(
            teammates: "Plan, Build",
            teamID: "ship-team",
            provider: .codex
        )
        let now = Date(timeIntervalSince1970: 1_000)

        let graph = AgentTeamGraph(config: config, now: now)

        #expect(graph.rootID == "ship-team")
        #expect(graph.nodes.map(\.id) == ["ship-team", "ship-team-plan", "ship-team-build"])
        #expect(graph.nodes.map(\.status) == [.starting, .starting, .starting])
        #expect(graph.edges == [
            AgentTeamGraphEdge(parentID: "ship-team", childID: "ship-team-plan"),
            AgentTeamGraphEdge(parentID: "ship-team", childID: "ship-team-build"),
        ])
        #expect(graph.node(id: "ship-team")?.provider == .codex)
        #expect(graph.node(id: "ship-team-plan")?.updatedAt == now)
    }

    @Test("team graph tracks status permissions and touched files per node")
    func teamGraphTracksStatusPermissionsAndTouchedFilesPerNode() throws {
        let config = try AgentTeamConfig.from(
            teammates: "Plan, Build",
            teamID: "ship-team",
            provider: .codex
        )
        var graph = AgentTeamGraph(config: config, now: Date(timeIntervalSince1970: 1_000))
        let later = Date(timeIntervalSince1970: 2_000)

        try graph.updateStatus(nodeID: "ship-team-build", status: .working, now: later)
        try graph.setPermissions(
            nodeID: "ship-team-build",
            permissions: [.fileRead, .fileWrite, .exec],
            now: later
        )
        try graph.recordTouchedFile(nodeID: "ship-team-build", path: "/tmp/app/Sources/App.swift", now: later)
        try graph.recordTouchedFile(nodeID: "ship-team-build", path: "/tmp/app/Tests/AppTests.swift", now: later)

        let buildNode = try #require(graph.node(id: "ship-team-build"))
        #expect(buildNode.status == .working)
        #expect(buildNode.permissions == [.fileRead, .fileWrite, .exec])
        #expect(buildNode.touchedFiles == ["/tmp/app/Sources/App.swift", "/tmp/app/Tests/AppTests.swift"])
        #expect(buildNode.updatedAt == later)
        #expect(graph.node(id: "ship-team-plan")?.touchedFiles == [])
    }

    @Test("team graph rejects unknown node updates")
    func teamGraphRejectsUnknownNodeUpdates() throws {
        let config = try AgentTeamConfig.from(teammates: "Plan", teamID: "ship-team", provider: .codex)
        var graph = AgentTeamGraph(config: config)

        do {
            try graph.updateStatus(nodeID: "missing", status: .error)
            Issue.record("Expected unknown graph node error")
        } catch let error as AgentTeamGraphError {
            #expect(error == .unknownNode("missing"))
        }
    }

    @Test("team feed keeps per-agent events isolated and globally ordered")
    func teamFeedKeepsPerAgentEventsIsolatedAndGloballyOrdered() throws {
        let config = try AgentTeamConfig.from(
            teammates: "Plan, Build",
            teamID: "ship-team",
            provider: .codex
        )
        var feed = AgentTeamFeed(config: config)
        let first = Date(timeIntervalSince1970: 1_000)
        let second = Date(timeIntervalSince1970: 2_000)

        let planEvent = try feed.record(
            teammateID: "ship-team-plan",
            kind: .userPrompt,
            message: "Design API",
            createdAt: second
        )
        let buildEvent = try feed.record(
            teammateID: "ship-team-build",
            kind: .completion,
            message: "Implemented parser",
            createdAt: first
        )

        #expect(feed.events(for: "ship-team-plan").map(\.id) == [planEvent.id])
        #expect(feed.events(for: "ship-team-build").map(\.id) == [buildEvent.id])
        #expect(feed.allEvents.map(\.id) == [buildEvent.id, planEvent.id])
    }

    @Test("team feed filters by kind and searches messages")
    func teamFeedFiltersByKindAndSearchesMessages() throws {
        let config = try AgentTeamConfig.from(
            teammates: "Plan, Build",
            teamID: "ship-team",
            provider: .codex
        )
        var feed = AgentTeamFeed(config: config)
        let now = Date(timeIntervalSince1970: 1_000)

        _ = try feed.record(
            teammateID: "ship-team-plan",
            kind: .permissionRequest,
            message: "Needs network access",
            createdAt: now
        )
        let errorEvent = try feed.record(
            teammateID: "ship-team-plan",
            kind: .error,
            message: "Network request failed",
            createdAt: now
        )

        #expect(feed.events(for: "ship-team-plan", kind: .error).map(\.id) == [errorEvent.id])
        #expect(feed.events(for: "ship-team-plan", matching: "network").map(\.kind) == [
            .permissionRequest,
            .error,
        ])
        #expect(feed.events(for: "ship-team-plan", matching: "missing").isEmpty)
    }

    @Test("team feed rejects events for unknown teammates")
    func teamFeedRejectsEventsForUnknownTeammates() throws {
        let config = try AgentTeamConfig.from(teammates: "Plan", teamID: "ship-team", provider: .codex)
        var feed = AgentTeamFeed(config: config)

        do {
            _ = try feed.record(teammateID: "missing", kind: .error, message: "No target")
            Issue.record("Expected unknown feed teammate error")
        } catch let error as AgentTeamFeedError {
            #expect(error == .unknownTeammate("missing"))
        }
    }

    @Test("template catalog exposes built-in team workflows")
    func templateCatalogExposesBuiltInTeamWorkflows() {
        let catalog = AgentTeamTemplateCatalog.builtin

        #expect(catalog.templates.map(\.id) == ["web-stack", "data-pipeline", "cli-tool"])
        #expect(catalog.template(id: "web-stack")?.roles.map(\.name) == ["Frontend", "Backend", "Tests"])
        #expect(catalog.template(id: "cli-tool")?.defaultProvider == .codex)
    }

    @Test("template catalog creates reproducible configs with prompts")
    func templateCatalogCreatesReproducibleConfigsWithPrompts() throws {
        let catalog = AgentTeamTemplateCatalog.builtin

        let config = try catalog.makeConfig(
            templateID: "cli-tool",
            teamID: "ship-cli",
            provider: .opencode
        )

        #expect(config.id == "ship-cli")
        #expect(config.provider == .opencode)
        #expect(config.teammates.map(\.id) == ["ship-cli-core", "ship-cli-parser", "ship-cli-tests"])
        #expect(config.teammates.map(\.name) == ["Core", "Parser", "Tests"])
        #expect(config.teammates.allSatisfy { $0.prompt?.isEmpty == false })
    }

    @Test("template catalog rejects duplicate template identifiers")
    func templateCatalogRejectsDuplicateTemplateIdentifiers() {
        let template = AgentTeamTemplate(
            id: "duplicate",
            name: "Duplicate",
            summary: "Duplicate template",
            defaultProvider: .codex,
            roles: [
                AgentTeamTemplateRole(id: "one", name: "One", prompt: "Do one thing"),
            ]
        )

        do {
            _ = try AgentTeamTemplateCatalog(templates: [template, template])
            Issue.record("Expected duplicate template error")
        } catch let error as AgentTeamTemplateError {
            #expect(error == .duplicateTemplateID("duplicate"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("session snapshot captures reproducible team state")
    func sessionSnapshotCapturesReproducibleTeamState() throws {
        let config = try AgentTeamTemplateCatalog.builtin.makeConfig(templateID: "cli-tool", teamID: "ship-cli")
        var graph = AgentTeamGraph(config: config, now: Date(timeIntervalSince1970: 1_000))
        var feed = AgentTeamFeed(config: config)
        try graph.updateStatus(nodeID: "ship-cli-core", status: .working, now: Date(timeIntervalSince1970: 2_000))
        let event = try feed.record(
            teammateID: "ship-cli-core",
            kind: .status,
            message: "Core is working",
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        let launchSpec = AgentTeamProviderLaunchSpec(
            provider: .codex,
            teamID: "ship-cli",
            teammateID: "ship-cli-core",
            teammateName: "Core",
            executable: "/usr/local/bin/codex",
            arguments: ["--profile", "local"],
            environment: ["COCXY_AGENT_TEAM_ID": "ship-cli"],
            workingDirectory: "/tmp/workspace",
            mutatesUserConfiguration: false,
            requiresPreviewBeforeLaunch: true
        )

        let snapshot = AgentTeamSessionSnapshot(
            config: config,
            graph: graph,
            feed: feed,
            launchSpecs: [launchSpec],
            createdAt: Date(timeIntervalSince1970: 900),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )

        #expect(snapshot.id == "ship-cli")
        #expect(snapshot.config == config)
        #expect(snapshot.graph.node(id: "ship-cli-core")?.status == .working)
        #expect(snapshot.feed.events(for: "ship-cli-core").map(\.id) == [event.id])
        #expect(snapshot.launchSpecs == [launchSpec])
    }

    @Test("session snapshot store round trips with owner-only permissions")
    func sessionSnapshotStoreRoundTripsWithOwnerOnlyPermissions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-agent-team-snapshots-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let config = try AgentTeamTemplateCatalog.builtin.makeConfig(templateID: "cli-tool", teamID: "ship-cli")
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = AgentTeamSessionSnapshot(
            config: config,
            graph: AgentTeamGraph(config: config, now: now),
            feed: AgentTeamFeed(config: config),
            launchSpecs: [],
            createdAt: now,
            updatedAt: now
        )
        let store = AgentTeamSessionSnapshotStore(directory: root)

        try store.save(snapshot)
        let loaded = try store.load(teamID: "ship-cli")

        #expect(loaded == snapshot)
        let permissions = try FileManager.default.attributesOfItem(
            atPath: root.appendingPathComponent("ship-cli.snapshot.json").path
        )[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    @Test("team run auto-links subagents and requests review before ship")
    func teamRunAutoLinksSubagentsAndRequestsReviewBeforeShip() throws {
        let config = try AgentTeamConfig.from(
            teammates: "Plan, Build",
            teamID: "ship-team",
            provider: .codex
        )
        var run = AgentTeamRunState(
            config: config,
            launchSpecs: [],
            now: Date(timeIntervalSince1970: 1_000)
        )

        let startResult = try run.apply(
            HookEvent(
                type: .subagentStart,
                sessionId: "codex-thread-1",
                timestamp: Date(timeIntervalSince1970: 1_010),
                data: .subagent(SubagentData(subagentId: "research-1", subagentType: "Research")),
                cwd: "/tmp/ship",
                teamID: "ship-team",
                teammateID: "ship-team-build",
                teammateName: "Build"
            )
        )
        let toolResult = try run.apply(
            HookEvent(
                type: .postToolUse,
                sessionId: "codex-thread-1",
                timestamp: Date(timeIntervalSince1970: 1_020),
                data: .toolUse(ToolUseData(
                    toolName: "Edit",
                    toolInput: ["file_path": "Sources/App.swift"]
                )),
                cwd: "/tmp/ship",
                teamID: "ship-team",
                teammateID: "research-1",
                teammateName: "Research"
            )
        )
        let finishResult = try run.apply(
            HookEvent(
                type: .taskCompleted,
                sessionId: "codex-thread-1",
                timestamp: Date(timeIntervalSince1970: 1_030),
                data: .taskCompleted(TaskCompletedData(taskDescription: "Ready to ship")),
                cwd: "/tmp/ship",
                teamID: "ship-team",
                teammateID: "research-1",
                teammateName: "Research"
            )
        )

        #expect(startResult.linkedSubagentID == "research-1")
        #expect(toolResult.touchedFilePath == "Sources/App.swift")
        #expect(run.graph.node(id: "research-1")?.status == .finished)
        #expect(run.graph.node(id: "research-1")?.touchedFiles == ["Sources/App.swift"])
        #expect(run.graph.edges.contains(AgentTeamGraphEdge(parentID: "ship-team-build", childID: "research-1")))
        #expect(run.feed.events(for: "research-1").map(\.kind) == [.status, .fileTouched, .completion])
        #expect(finishResult.reviewBeforeShipRequest?.teamID == "ship-team")
        #expect(finishResult.reviewBeforeShipRequest?.sessionID == "codex-thread-1")
        #expect(finishResult.reviewBeforeShipRequest?.touchedFiles == ["Sources/App.swift"])
        #expect(run.reviewBeforeShipRequests.count == 1)
    }

    @Test("launcher spawns one native pane per teammate")
    @MainActor
    func launcherSpawnsOnePanePerTeammate() throws {
        let config = try AgentTeamConfig.from(
            teammates: "Planner, Implementer, Reviewer",
            teamID: "ship",
            provider: .codex
        )
        let paneLauncher = RecordingAgentTeamPaneLauncher()
        let launcher = AgentTeamLauncher(
            paneLauncher: paneLauncher,
            adapterRegistry: AgentTeamProviderAdapterRegistry(executableResolver: { executable in
                executable == "codex" ? "/usr/local/bin/codex" : nil
            }),
            launchProfileProvider: { teammate in
                AgentTeamLaunchProfile(
                    workingDirectory: "/tmp/ship",
                    environment: ["ROLE_ID": teammate.id],
                    arguments: ["--profile", "agent-team"]
                )
            }
        )

        let result = try launcher.launch(config: config)

        #expect(result.teamID == "ship")
        #expect(result.launchedCount == 3)
        #expect(paneLauncher.requests.map(\.teammateID) == [
            "ship-planner",
            "ship-implementer",
            "ship-reviewer",
        ])
        #expect(result.launchSpecs.map(\.teamID) == ["ship", "ship", "ship"])
        #expect(result.launchSpecs.allSatisfy { $0.provider == .codex })
        #expect(result.launchSpecs.allSatisfy { $0.executable == "/usr/local/bin/codex" })
        #expect(result.launchSpecs.allSatisfy { $0.requiresPreviewBeforeLaunch })
        #expect(result.launchSpecs.allSatisfy { !$0.mutatesUserConfiguration })
        #expect(result.launchSpecs.map(\.arguments) == [
            ["--profile", "agent-team"],
            ["--profile", "agent-team"],
            ["--profile", "agent-team"],
        ])
        #expect(result.launchSpecs.map { $0.environment["ROLE_ID"] } == [
            "ship-planner",
            "ship-implementer",
            "ship-reviewer",
        ])
        #expect(paneLauncher.requests == result.launchSpecs)
    }

    @Test("launcher rejects missing provider executable before opening panes")
    @MainActor
    func launcherRejectsMissingProviderExecutableBeforeOpeningPanes() throws {
        let config = try AgentTeamConfig.from(
            teammates: "Plan",
            teamID: "ship",
            provider: .gemini
        )
        let paneLauncher = RecordingAgentTeamPaneLauncher()
        let launcher = AgentTeamLauncher(
            paneLauncher: paneLauncher,
            adapterRegistry: AgentTeamProviderAdapterRegistry(executableResolver: { _ in nil })
        )

        do {
            _ = try launcher.launch(config: config)
            Issue.record("Expected missing executable error")
        } catch let error as AgentTeamProviderAdapterError {
            #expect(error == .executableUnavailable(provider: .gemini, candidates: ["gemini"]))
        }
        #expect(paneLauncher.requests.isEmpty)
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
    typealias Request = AgentTeamProviderLaunchSpec

    private(set) var requests: [Request] = []

    func spawnAgentTeamPane(launchSpec: AgentTeamProviderLaunchSpec) -> Bool {
        requests.append(launchSpec)
        return true
    }
}
