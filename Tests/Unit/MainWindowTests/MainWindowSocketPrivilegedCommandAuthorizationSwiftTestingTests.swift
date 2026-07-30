// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Privileged socket command native approval")
struct MainWindowSocketPrivilegedCommandAuthorizationSwiftTestingTests {
    @Test("specialized browser approval can resolve the active model without a generic grant")
    func specializedBrowserApprovalResolvesActiveModel() {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let viewModel = BrowserViewModel()
        controller.browserViewModel = viewModel
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)

        #expect(delegate.socketBrowserViewModel(for: nil) === viewModel)
    }

    @Test("approval is one-use and bound to the presented context")
    func approvalIsOneUseAndContextBound() throws {
        let fixture = makeFixture()
        let request = try makeGitAssistantRequest()
        let coordinator = SocketPrivilegedCommandAuthorizationCoordinator()
        var presentationCount = 0
        var firstGrant: SocketPrivilegedCommandAuthorizationGrant?
        var secondGrant: SocketPrivilegedCommandAuthorizationGrant?
        coordinator.presenter = { received, context in
            presentationCount += 1
            return received == request
                && context.tabID == fixture.tabID.rawValue
                && context.workingDirectory == fixture.directory.path
        }

        coordinator.requestAuthorization(
            request,
            targetProvider: { fixture.target },
            completion: { firstGrant = $0 }
        )
        coordinator.requestAuthorization(
            request,
            targetProvider: { fixture.target },
            completion: { secondGrant = $0 }
        )

        #expect(firstGrant?.requestID == request.id)
        #expect(firstGrant?.context == fixture.context)
        #expect(secondGrant == nil)
        #expect(presentationCount == 1)
    }

    @Test("changing the target during approval fails closed")
    func changedContextFailsClosed() throws {
        let fixture = makeFixture()
        let request = try makeGitAssistantRequest()
        let coordinator = SocketPrivilegedCommandAuthorizationCoordinator()
        var context = fixture.context
        var grant: SocketPrivilegedCommandAuthorizationGrant?
        coordinator.presenter = { _, _ in
            context = SocketPrivilegedCommandContext(
                scope: .repository,
                windowControllerIdentifier: ObjectIdentifier(fixture.controller),
                tabID: fixture.tabID.rawValue,
                workingDirectory: "/tmp/cocxy-privileged-after",
                surfaceID: nil,
                browserViewModelIdentifier: nil,
                browserTabID: nil,
                browserURL: nil,
                targetDisplayName: "/tmp/cocxy-privileged-after"
            )
            return true
        }

        coordinator.requestAuthorization(
            request,
            targetProvider: {
                SocketPrivilegedCommandPresentationTarget(
                    context: context,
                    controller: fixture.controller
                )
            },
            completion: { grant = $0 }
        )

        #expect(grant == nil)
    }

    @Test("expired authorization never reaches the presenter")
    func expiredRequestNeverReachesPresenter() throws {
        let fixture = makeFixture()
        let request = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "expired",
                command: "git-assistant-commit-message",
                params: nil
            ),
            createdAt: Date(timeIntervalSince1970: 0),
            lifetime: 1
        ))
        let coordinator = SocketPrivilegedCommandAuthorizationCoordinator()
        var presentationCount = 0
        var grant: SocketPrivilegedCommandAuthorizationGrant?
        coordinator.presenter = { _, _ in
            presentationCount += 1
            return true
        }

        coordinator.requestAuthorization(
            request,
            targetProvider: { fixture.target },
            completion: { grant = $0 }
        )

        #expect(grant == nil)
        #expect(presentationCount == 0)
    }

    @Test("a reentrant approval request is rejected while another is active")
    func reentrantApprovalIsRejected() throws {
        let fixture = makeFixture()
        let firstRequest = try makeGitAssistantRequest()
        let secondRequest = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "second",
                command: "git-assistant-pr-draft",
                params: ["base": "main"]
            )
        ))
        let coordinator = SocketPrivilegedCommandAuthorizationCoordinator()
        var presentationCount = 0
        var firstGrant: SocketPrivilegedCommandAuthorizationGrant?
        var secondGrant: SocketPrivilegedCommandAuthorizationGrant?
        coordinator.presenter = { _, _ in
            presentationCount += 1
            coordinator.requestAuthorization(
                secondRequest,
                targetProvider: { fixture.target },
                completion: { secondGrant = $0 }
            )
            return true
        }

        coordinator.requestAuthorization(
            firstRequest,
            targetProvider: { fixture.target },
            completion: { firstGrant = $0 }
        )

        #expect(firstGrant != nil)
        #expect(secondGrant == nil)
        #expect(presentationCount == 1)
    }

    @Test("approval preview exposes resolved profile and local paths")
    func approvalPreviewIncludesResolvedAuthority() throws {
        let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let request = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "browser-import-preview",
                command: "browser-import-preview",
                params: ["source": "chrome"]
            )
        ))
        let context = SocketPrivilegedCommandContext(
            scope: .browserGlobal,
            windowControllerIdentifier: nil,
            tabID: nil,
            workingDirectory: "Cocxy application",
            localResourcePaths: [
                "browser-import.0.history": "/Users/test/Library/Application Support/Browser/History",
            ],
            localResourceDigests: [
                "browser-import.0.history": String(repeating: "a", count: 64),
            ],
            authorityDetails: [
                "operation": "pr-draft",
                "provider": "openai",
                "repository": "/tmp/project",
            ],
            surfaceID: nil,
            browserViewModelIdentifier: nil,
            browserTabID: nil,
            browserURL: nil,
            browserProfileID: profileID,
            targetDisplayName: "Import Chrome into Default (1 location)"
        )

        let preview = MainWindowController.privilegedSocketCommandApprovalPreview(
            request: request,
            context: context
        )

        #expect(preview.contains("Resolved authority:"))
        #expect(preview.contains("browser-profile: \(profileID.uuidString)"))
        #expect(preview.contains("browser-import.0.history"))
        #expect(preview.contains("/Users/test/Library/Application Support/Browser/History"))
        #expect(preview.contains("browser-import.0.history-sha256"))
        #expect(preview.contains(String(repeating: "a", count: 64)))
        #expect(preview.contains("authority.operation: pr-draft"))
        #expect(preview.contains("authority.provider: openai"))
        #expect(preview.contains("authority.repository: /tmp/project"))
    }

    @Test("task enqueue preview hashes prompt content instead of displaying it")
    func taskEnqueuePreviewRedactsPrompt() throws {
        let prompt = "Review a private implementation detail"
        let request = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "task-enqueue-preview",
                command: "task-enqueue",
                params: [
                    "task-id": "review",
                    "provider": "codex",
                    "prompt": prompt,
                    "cwd": "/tmp/project",
                    "trigger": "manual",
                ]
            )
        ))

        let preview = SocketPrivilegedCommandSecurity.approvalPreview(request)
        let expectedDigest = SocketPrivilegedCommandSecurity.digest(data: Data(prompt.utf8))

        #expect(!preview.contains(prompt))
        #expect(preview.contains("prompt: \(prompt.utf8.count) UTF-8 bytes"))
        #expect(preview.contains(expectedDigest))
    }

    @Test("task enqueue approval binds canonical pipeline bytes and worktree")
    func taskEnqueueApprovalBindsPipelineAndWorktree() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-task-approval-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let pipelineURL = root.appendingPathComponent("pipeline.json")
        let pipelineData = Data("{\"id\":\"review\",\"steps\":[]}".utf8)
        try pipelineData.write(to: pipelineURL)

        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)
        let request = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "task-enqueue-pipeline",
                command: "task-enqueue",
                params: [
                    "task-id": "review",
                    "input": pipelineURL.path,
                    "cwd": root.path,
                    "trigger": "manual",
                ]
            )
        ))

        let target = try #require(
            delegate.privilegedSocketCommandPresentationTarget(for: request)
        )

        #expect(target.context.scope == .localExecution)
        #expect(target.context.workingDirectory == root.path)
        #expect(target.context.localResourcePaths["cwd"] == root.path)
        #expect(target.context.localResourcePaths["input"] == pipelineURL.path)
        #expect(
            target.context.localResourceDigests["input"]
                == SocketPrivilegedCommandSecurity.digest(data: pipelineData)
        )
        #expect(target.context.authorityDetails == [
            "operation": "enqueue",
            "task-id": "review",
            "trigger": "manual",
        ])
    }

    @Test("cell cloud-init reads and binds bytes only after approval")
    func cellCloudInitApprovalBindsPathAndDigest() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-cell-approval-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let source = root.appendingPathComponent("cloud-init.yml")
        let data = Data("#cloud-config\nruncmd:\n  - echo ready\n".utf8)
        try data.write(to: source)

        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)
        let request = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "cell-cloud-init",
                command: "cell-create",
                params: [
                    "provider": "gcp",
                    "project": "project-a",
                    "zone": "us-central1-a",
                    "cloud-init": source.path,
                ]
            )
        ))

        let presentedTarget = try #require(
            delegate.privilegedSocketCommandPresentationTarget(for: request)
        )
        let canonicalPath = source.resolvingSymlinksInPath().standardizedFileURL.path
        let expectedDigest = SocketPrivilegedCommandSecurity.digest(data: data)
        let coordinator = SocketPrivilegedCommandAuthorizationCoordinator()
        var grant: SocketPrivilegedCommandAuthorizationGrant?
        coordinator.presenter = { _, context in
            #expect(context.localResourceDigests["cloud-init"] == nil)
            return true
        }
        coordinator.requestAuthorization(
            request,
            targetProvider: {
                delegate.privilegedSocketCommandPresentationTarget(for: request)
            },
            completion: { grant = $0 }
        )

        #expect(presentedTarget.context.scope == .computeCell)
        #expect(presentedTarget.context.localResourcePaths["cloud-init"] == canonicalPath)
        #expect(presentedTarget.context.localResourceDigests["cloud-init"] == nil)
        #expect(presentedTarget.context.authorityDetails["cloud-init-bytes"] == "\(data.count)")
        #expect(grant?.context.localResourceDigests["cloud-init"] == expectedDigest)
    }

    @Test("denied approval never resolves post-approval resources")
    func deniedApprovalSkipsApprovedContextProvider() throws {
        let fixture = makeFixture()
        let request = try makeGitAssistantRequest()
        let coordinator = SocketPrivilegedCommandAuthorizationCoordinator()
        var approvedContextCalls = 0
        var grant: SocketPrivilegedCommandAuthorizationGrant?
        let target = SocketPrivilegedCommandPresentationTarget(
            context: fixture.context,
            controller: fixture.controller,
            approvedContextProvider: {
                approvedContextCalls += 1
                return fixture.context
            }
        )
        coordinator.presenter = { _, _ in false }

        coordinator.requestAuthorization(
            request,
            targetProvider: { target },
            completion: { grant = $0 }
        )

        #expect(grant == nil)
        #expect(approvedContextCalls == 0)
    }

    @Test("missing post-approval resources fail closed")
    func missingApprovedContextFailsClosed() throws {
        let fixture = makeFixture()
        let request = try makeGitAssistantRequest()
        let coordinator = SocketPrivilegedCommandAuthorizationCoordinator()
        var grant: SocketPrivilegedCommandAuthorizationGrant?
        let target = SocketPrivilegedCommandPresentationTarget(
            context: fixture.context,
            controller: fixture.controller,
            approvedContextProvider: { nil }
        )
        coordinator.presenter = { _, _ in true }

        coordinator.requestAuthorization(
            request,
            targetProvider: { target },
            completion: { grant = $0 }
        )

        #expect(grant == nil)
    }

    @Test("directed terminal input approval binds the requested tab and its surface")
    func directedTerminalInputBindsRequestedTabAndSurface() throws {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        controller.showWindow(nil)
        let sourceTab = try #require(controller.tabManager.activeTab)
        let targetTabID = controller.createTab(
            workingDirectory: URL(fileURLWithPath: "/tmp/cocxy-directed-input")
        )
        let targetSurfaceID = try #require(controller.tabSurfaceMap[targetTabID])
        #expect(controller.focusTab(id: sourceTab.id))

        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)
        let request = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "directed-send",
                command: "send",
                params: [
                    "text": "status",
                    "tabId": targetTabID.rawValue.uuidString,
                ]
            )
        ))

        let target = try #require(
            delegate.privilegedSocketCommandPresentationTarget(for: request)
        )

        #expect(target.context.scope == .terminalSurface)
        #expect(target.context.tabID == targetTabID.rawValue)
        #expect(target.context.surfaceID == targetSurfaceID.rawValue)
        #expect(target.context.workingDirectory == "/tmp/cocxy-directed-input")
        #expect(target.context.targetDisplayName.contains(targetTabID.rawValue.uuidString))
        #expect(
            delegate.privilegedSocketTerminalTarget(for: target.context)?.surfaceID
                == targetSurfaceID
        )
    }

    @Test("TaskRun lease preauthorizes only its live candidate tab and audits the write")
    func taskRunLeaseBindsLiveCandidateAndAuditsWrite() throws {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        controller.showWindow(nil)
        let directory = URL(fileURLWithPath: "/tmp/cocxy-orchestrated-input")
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let tabID = controller.createTab(workingDirectory: directory)

        let audit = SocketTaskOrchestrationAuditLog()
        let sessionManager = TaskOrchestrationSessionManager(
            secret: Data(repeating: 5, count: 32),
            auditLog: audit
        )
        let delegate = AppDelegate()
        delegate.taskOrchestrationSessionManager = sessionManager
        delegate.installWindowControllerForTesting(controller)

        let taskRequest = try TaskRunRequest.make(
            prompt: "Continue safely",
            agents: "codex,claude"
        )
        var run = TaskRun(
            id: "task-orchestration",
            request: taskRequest,
            originRepoPath: directory,
            baseCommit: "abc123"
        )
        let candidateID = try #require(run.candidates.first?.id)
        try run.updateCandidate(id: candidateID) { candidate in
            candidate.status = .running
            candidate.worktree = WorktreeManifest.WorktreeEntry(
                id: "wt-1",
                branch: "cocxy/wt-1",
                path: directory,
                createdAt: Date(timeIntervalSince1970: 4_000),
                agent: candidate.provider.rawValue,
                tabID: tabID
            )
        }
        run.markRunning()
        delegate.activeTaskRuns[run.id] = run
        let credential = try sessionManager.issue(
            runID: run.id,
            tabIDs: [tabID.rawValue]
        )
        let request = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "orchestrated-send",
                command: "send",
                params: [
                    "text": "continue",
                    "tabId": tabID.rawValue.uuidString,
                    "orchestration-session": credential.token,
                ]
            )
        ))

        let grant = try #require(
            delegate.preauthorizedTaskOrchestrationGrant(for: request)
        )
        #expect(grant.context.tabID == tabID.rawValue)
        #expect(grant.context.authorityDetails["orchestration-run-id"] == run.id)
        #expect(delegate.auditTaskOrchestrationWriteIfNeeded(
            context: grant.context,
            command: .send,
            payloadBytes: 8
        ))
        #expect(audit.recordedEvents.count == 1)
        #expect(audit.recordedEvents.first?.tabID == tabID.rawValue)

        let tampered = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "tampered-send",
                command: "send",
                params: [
                    "text": "continue",
                    "tabId": tabID.rawValue.uuidString,
                    "orchestration-session": credential.token + "x",
                ]
            )
        ))
        #expect(delegate.preauthorizedTaskOrchestrationGrant(for: tampered) == nil)

        try run.updateCandidate(id: candidateID) { $0.status = .finished }
        delegate.activeTaskRuns[run.id] = run
        #expect(delegate.preauthorizedTaskOrchestrationGrant(for: request) == nil)
        #expect(!delegate.auditTaskOrchestrationWriteIfNeeded(
            context: grant.context,
            command: .send,
            payloadBytes: 8
        ))
    }

    @Test("handoff export binds an exact tab and returns its current metadata")
    func handoffExportUsesApprovedTabContext() throws {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        controller.showWindow(nil)
        let sourceTabID = try #require(controller.tabManager.activeTabID)
        let targetTabID = controller.createTab(
            workingDirectory: URL(fileURLWithPath: "/tmp/cocxy-handoff-export")
        )
        controller.tabManager.updateTab(id: targetTabID) { tab in
            tab.gitBranch = "feature/export"
            tab.worktreeID = "wt-export"
            tab.worktreeBranch = "worktree/export"
        }
        #expect(controller.focusTab(id: sourceTabID))

        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)
        let taskRequest = try TaskRunRequest.make(
            prompt: "Finish the handoff flow",
            agents: "codex,claude"
        )
        var taskRun = TaskRun(
            id: "handoff-export-run",
            request: taskRequest,
            originRepoPath: URL(fileURLWithPath: "/tmp/cocxy-handoff-export"),
            baseCommit: "abc123"
        )
        let candidate = try #require(taskRun.candidates.first)
        try taskRun.updateCandidate(id: candidate.id) { candidate in
            candidate.worktree = WorktreeManifest.WorktreeEntry(
                id: "wt-export",
                branch: "worktree/export",
                path: URL(fileURLWithPath: "/tmp/cocxy-handoff-export"),
                createdAt: Date(timeIntervalSince1970: 5_000),
                agent: candidate.provider.rawValue,
                tabID: targetTabID
            )
        }
        delegate.activeTaskRuns[taskRun.id] = taskRun
        let teamConfig = AgentTeamConfig(
            id: candidate.teamID,
            provider: candidate.provider,
            teammates: [
                AgentTeammateConfig(
                    id: "handoff-worker",
                    name: "Worker",
                    prompt: taskRun.prompt
                ),
            ]
        )
        var teamRun = AgentTeamRunState(config: teamConfig, launchSpecs: [])
        try teamRun.graph.recordTouchedFile(
            nodeID: "handoff-worker",
            path: "Sources/Handoff.swift"
        )
        delegate.activeAgentTeamRuns[candidate.teamID] = teamRun
        let rawTabID = targetTabID.rawValue.uuidString.lowercased()
        let request = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "handoff-export",
                command: "handoff-export",
                params: ["tabId": rawTabID, "limit": "8"]
            )
        ))
        let target = try #require(
            delegate.privilegedSocketCommandPresentationTarget(for: request)
        )

        #expect(target.context.scope == .terminalTab)
        #expect(target.context.tabID == targetTabID.rawValue)
        #expect(target.context.workingDirectory == "/tmp/cocxy-handoff-export")
        let result = delegate.handleTaskHandoffCLIRequest(
            kind: "export",
            params: request.params,
            approvedContext: target.context
        )
        #expect(result.success)
        #expect(result.data["tab-id"] == targetTabID.rawValue.uuidString)
        #expect(result.data["artifact"]?.contains("worktree/export") == true)
        #expect(result.data["artifact"]?.contains("wt-export") == true)
        #expect(result.data["artifact"]?.contains("Finish the handoff flow") == true)
        #expect(result.data["artifact"]?.contains("Sources/Handoff.swift") == true)
        #expect(result.data["artifact"]?.contains("No semantic command blocks") == true)
    }

    @Test("handoff import authority binds source, provider, and artifact digest")
    func handoffImportBindsExactAuthority() throws {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        controller.showWindow(nil)
        let sourceTabID = try #require(controller.tabManager.activeTabID)
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)
        let artifact = "# Task Handoff\n\nContinue the current task."
        let request = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "handoff-import",
                command: "handoff-import",
                params: ["agent": "codex", "artifact": artifact]
            )
        ))
        let target = try #require(
            delegate.privilegedSocketCommandPresentationTarget(for: request)
        )
        let destination = try TaskHandoffDestination.make(
            agent: "codex",
            artifact: artifact
        )

        #expect(target.context.scope == .localExecution)
        #expect(target.context.tabID == sourceTabID.rawValue)
        #expect(target.context.authorityDetails == destination.authorityDetails)
        #expect(target.context.targetDisplayName.contains("Codex CLI"))

        let tamperedResult = delegate.handleTaskHandoffCLIRequest(
            kind: "import",
            params: ["agent": "codex", "artifact": artifact + "tampered"],
            approvedContext: target.context
        )
        #expect(!tamperedResult.success)
        #expect(controller.tabManager.tabs.count == 1)
    }

    private func makeFixture() -> (
        controller: MainWindowController,
        tabID: TabID,
        directory: URL,
        context: SocketPrivilegedCommandContext,
        target: SocketPrivilegedCommandPresentationTarget
    ) {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let directory = URL(fileURLWithPath: "/tmp/cocxy-privileged-approval")
        let tab = controller.tabManager.addTab(workingDirectory: directory)
        let context = SocketPrivilegedCommandContext(
            scope: .repository,
            windowControllerIdentifier: ObjectIdentifier(controller),
            tabID: tab.id.rawValue,
            workingDirectory: directory.path,
            surfaceID: nil,
            browserViewModelIdentifier: nil,
            browserTabID: nil,
            browserURL: nil,
            targetDisplayName: directory.path
        )
        return (
            controller,
            tab.id,
            directory,
            context,
            SocketPrivilegedCommandPresentationTarget(
                context: context,
                controller: controller
            )
        )
    }

    private func makeGitAssistantRequest() throws -> SocketPrivilegedCommandAuthorizationRequest {
        try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "git-assistant",
                command: "git-assistant-commit-message",
                params: nil
            )
        ))
    }
}

private final class SocketTaskOrchestrationAuditLog: TaskOrchestrationAuditLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [TaskOrchestrationAuditEvent] = []

    var recordedEvents: [TaskOrchestrationAuditEvent] {
        lock.withLock { events }
    }

    func append(_ event: TaskOrchestrationAuditEvent) {
        lock.withLock {
            events.append(event)
        }
    }
}
