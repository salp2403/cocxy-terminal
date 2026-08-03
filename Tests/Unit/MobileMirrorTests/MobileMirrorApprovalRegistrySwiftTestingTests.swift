// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Mobile mirror app-scoped approvals")
@MainActor
struct MobileMirrorApprovalRegistrySwiftTestingTests {
    @Test("records from independent producers remain visible and decisions are one-use")
    func independentProducersAndOneUseDecisions() async {
        let registry = MobileMirrorApprovalRegistry()
        let first = ApprovalResolutionCapture()
        let second = ApprovalResolutionCapture()
        let firstRecord = Self.record(id: "approval-a", sessionID: UUID())
        let secondRecord = Self.record(id: "approval-b", sessionID: UUID())

        #expect(registry.register(
            sourceID: "window-a",
            record: firstRecord,
            isCurrent: { first.isCurrent },
            resolve: { decision in first.resolve(decision) }
        ))
        #expect(registry.register(
            sourceID: "window-b",
            record: secondRecord,
            isCurrent: { second.isCurrent },
            resolve: { decision in second.resolve(decision) }
        ))
        #expect(registry.currentRecords().map(\.id) == ["approval-a", "approval-b"])

        #expect(await registry.resolve(id: firstRecord.id, decision: .approve(response: nil)))
        #expect(first.decisions == [.approve(response: nil)])
        #expect(registry.currentRecords().map(\.id) == ["approval-b"])
        #expect(!(await registry.resolve(id: firstRecord.id, decision: .reject)))
        #expect(first.decisions.count == 1)
    }

    @Test("expired and stale producers are pruned without invoking them")
    func staleAndExpiredProducersArePruned() {
        let registry = MobileMirrorApprovalRegistry()
        let now = Date()
        let stale = ApprovalResolutionCapture()
        stale.isCurrent = false
        let expired = ApprovalResolutionCapture()

        #expect(!registry.register(
            sourceID: "stale",
            record: Self.record(id: "stale", sessionID: UUID()),
            isCurrent: { stale.isCurrent },
            resolve: { decision in stale.resolve(decision) }
        ))
        #expect(registry.register(
            sourceID: "expires",
            record: Self.record(
                id: "expires",
                sessionID: UUID(),
                expiresAt: now.addingTimeInterval(1)
            ),
            isCurrent: { expired.isCurrent },
            resolve: { decision in expired.resolve(decision) }
        ))

        #expect(registry.currentRecords(at: now.addingTimeInterval(2)).isEmpty)
        #expect(stale.decisions.isEmpty)
        #expect(expired.decisions.isEmpty)
    }

    @Test("agent tool approval stays bound to its original app session")
    func agentToolApprovalUsesOriginalSession() async throws {
        let approvalRegistry = MobileMirrorApprovalRegistry()
        let sessionRegistry = SessionRegistryImpl()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        controller.mobileMirrorApprovalRegistry = approvalRegistry
        controller.sessionRegistry = sessionRegistry
        sessionRegistry.registerWindow(controller.windowID)
        let firstTab = controller.tabManager.addTab(
            workingDirectory: URL(fileURLWithPath: "/tmp/mobile-approval-a")
        )
        let secondTab = controller.tabManager.addTab(
            workingDirectory: URL(fileURLWithPath: "/tmp/mobile-approval-b")
        )
        let firstSession = SessionID()
        let secondSession = SessionID()
        controller.tabSessionMap[firstTab.id] = firstSession
        controller.tabSessionMap[secondTab.id] = secondSession
        sessionRegistry.registerSession(Self.entry(
            sessionID: firstSession,
            controller: controller,
            tab: firstTab
        ))
        sessionRegistry.registerSession(Self.entry(
            sessionID: secondSession,
            controller: controller,
            tab: secondTab
        ))
        #expect(controller.focusTab(id: firstTab.id))

        let request = Self.toolRequest()
        let runner = MobileApprovalAgentRunner(request: request)
        let viewModel = AgentPanelViewModel(
            configuration: AgentModeConfig(enabled: true),
            runner: runner
        )
        controller.bindMobileMirrorApprovals(to: viewModel)
        viewModel.promptDraft = "Run checks"
        await viewModel.submitPrompt()
        await Task.yield()

        let record = try #require(approvalRegistry.currentRecords().first)
        #expect(record.kind == .agentTool)
        #expect(record.sessionID == firstSession.rawValue.uuidString)
        #expect(controller.focusTab(id: secondTab.id))
        #expect(approvalRegistry.currentRecords().first?.sessionID == firstSession.rawValue.uuidString)
        #expect(await approvalRegistry.resolve(id: record.id, decision: .approve(response: nil)))
        #expect(await runner.approvedRequestIDs == [request.id])
        #expect(viewModel.pendingApproval == nil)
        #expect(approvalRegistry.currentRecords().isEmpty)
    }

    private static func record(
        id: String,
        sessionID: UUID,
        expiresAt: Date? = nil
    ) -> MobileMirrorApprovalRecord {
        MobileMirrorApprovalRecord(
            id: id,
            kind: .agentTool,
            sessionID: sessionID.uuidString,
            title: "Approval",
            body: "Review exact local action",
            requiresResponse: false,
            expiresAt: expiresAt
        )
    }

    private static func entry(
        sessionID: SessionID,
        controller: MainWindowController,
        tab: Tab
    ) -> SessionEntry {
        SessionEntry(
            sessionID: sessionID,
            ownerWindowID: controller.windowID,
            tabID: tab.id,
            title: tab.displayTitle,
            workingDirectory: tab.workingDirectory,
            agentState: .waitingInput,
            detectedAgentName: "Agent",
            hasUnreadNotification: false
        )
    }

    private static func toolRequest() -> AgentToolApprovalRequest {
        AgentToolApprovalRequest(
            call: AgentToolCall(
                id: "mobile-tool-call",
                toolID: "run_command",
                arguments: ["command": .string("swift test")]
            ),
            reason: .commandApprovalRequired(command: "swift test"),
            preview: AgentToolApprovalPreview(
                kind: .command,
                title: "Approve command",
                body: "swift test"
            )
        )
    }
}

@MainActor
private final class ApprovalResolutionCapture {
    var isCurrent = true
    var decisions: [MobileMirrorApprovalDecision] = []

    func resolve(_ decision: MobileMirrorApprovalDecision) -> Bool {
        decisions.append(decision)
        return true
    }
}

private actor MobileApprovalAgentRunner: AgentApprovalRunning {
    let request: AgentToolApprovalRequest
    private(set) var approvedRequestIDs: [String] = []

    init(request: AgentToolApprovalRequest) {
        self.request = request
    }

    func run(
        prompt: String,
        history: [AgentMessage],
        configuration: AgentModeConfig
    ) async throws -> AgentLoopResult {
        AgentLoopResult(messages: history, stopReason: .permissionRequired(request))
    }

    func approve(
        request: AgentToolApprovalRequest,
        userInput: String?,
        history: [AgentMessage],
        configuration: AgentModeConfig
    ) async throws -> AgentLoopResult {
        approvedRequestIDs.append(request.id)
        return AgentLoopResult(messages: history, stopReason: .completed)
    }
}
