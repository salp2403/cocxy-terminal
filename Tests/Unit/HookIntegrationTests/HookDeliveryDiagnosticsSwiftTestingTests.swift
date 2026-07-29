// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Hook delivery diagnostics")
struct HookDeliveryDiagnosticsSwiftTestingTests {
    @Test("receiver counts CWD drops and acknowledgement preserves the total")
    func receiverTracksCwdDrops() {
        let receiver = HookEventReceiverImpl()
        var diagnostics: [HookReceiverDiagnostics] = []
        let cancellable = receiver.diagnosticsPublisher.sink {
            diagnostics.append($0)
        }
        defer { cancellable.cancel() }
        let event = HookEvent(
            type: .fileChanged,
            sessionId: "dropped-session",
            timestamp: Date(timeIntervalSince1970: 42),
            data: .fileChanged(FileChangedData(
                filePath: "/tmp/unmatched/App.swift",
                changeType: "change"
            )),
            cwd: "/tmp/unmatched"
        )

        receiver.recordDroppedByCwd(event)

        #expect(receiver.droppedByCwdCount == 1)
        #expect(receiver.lastDroppedByCwd?.sessionId == "dropped-session")
        #expect(receiver.lastDroppedByCwd?.cwd == "/tmp/unmatched")
        #expect(receiver.lastDroppedByCwd?.eventType == .fileChanged)
        #expect(diagnostics.last?.droppedByCwdCount == 1)

        receiver.acknowledgeDroppedByCwd(sessionId: "different-session")
        #expect(receiver.lastDroppedByCwd != nil)

        receiver.acknowledgeDroppedByCwd(sessionId: "dropped-session")
        #expect(receiver.droppedByCwdCount == 1)
        #expect(receiver.lastDroppedByCwd == nil)
        #expect(diagnostics.last == HookReceiverDiagnostics(
            droppedByCwdCount: 1,
            lastDroppedByCwd: nil
        ))
    }

    @Test("receiver context uses canonical new_cwd")
    func receiverContextUsesCanonicalNewCwd() {
        let receiver = HookEventReceiverImpl()
        let payload = Data(#"{"hook_event_name":"CwdChanged","session_id":"cwd-session","old_cwd":"/tmp/old","new_cwd":"/tmp/new"}"#.utf8)

        #expect(receiver.receiveRawJSON(payload))
        #expect(receiver.lastReceivedSessionId == "cwd-session")
        #expect(receiver.lastReceivedCwd == "/tmp/new")
    }
}

@Suite("Agent dashboard hook diagnostics")
@MainActor
struct AgentDashboardHookDiagnosticsSwiftTestingTests {
    @Test("detected Claude without hooks exposes repair after the configured interval")
    func detectedClaudeWithoutHooksExposesRepair() async throws {
        let tabID = UUID()
        let viewModel = AgentDashboardViewModel(hookSilenceInterval: 0)

        viewModel.processDetectionSignal(
            agentName: "Claude Code",
            state: .working,
            tabId: tabID,
            workingDirectory: "/tmp/project"
        )
        try await settleMainActor()

        guard case .noEvents(let affectedTabID, let detectedAt) = viewModel.hookConnectionIssue else {
            Issue.record("Expected no-events hook diagnostic")
            return
        }
        #expect(affectedTabID == tabID)
        #expect(detectedAt <= Date())
    }

    @Test("a routed hook cancels the pending no-events diagnostic")
    func routedHookCancelsNoEventsDiagnostic() async throws {
        let tabID = UUID()
        let receiver = HookEventReceiverImpl()
        let viewModel = AgentDashboardViewModel(
            hookEventReceiver: receiver,
            hookSilenceInterval: 0.05
        )
        viewModel.tabIdResolver = { _, _ in tabID }
        viewModel.tabCwdProvider = { ["/tmp/project"] }

        viewModel.processDetectionSignal(
            agentName: "Claude Code",
            state: .working,
            tabId: tabID,
            workingDirectory: "/tmp/project"
        )
        receiver.receive(HookEvent(
            type: .sessionStart,
            sessionId: "routed-session",
            data: .sessionStart(SessionStartData(workingDirectory: "/tmp/project")),
            cwd: "/tmp/project"
        ))
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(viewModel.hookConnectionIssue == nil)
    }

    @Test("CWD mismatch forwards the exact context to explicit binding")
    func cwdMismatchCanBeExplicitlyBound() async throws {
        let receiver = HookEventReceiverImpl()
        let viewModel = AgentDashboardViewModel(hookEventReceiver: receiver)
        let event = HookEvent(
            type: .fileChanged,
            sessionId: "bind-session",
            timestamp: Date(timeIntervalSince1970: 123),
            data: .fileChanged(FileChangedData(
                filePath: "/tmp/moved/App.swift",
                changeType: "change"
            )),
            cwd: "/tmp/moved"
        )
        var boundContext: DroppedHookEventContext?
        viewModel.onBindDroppedSession = {
            boundContext = $0
            return true
        }

        receiver.recordDroppedByCwd(event)
        try await settleMainActor()
        guard case .cwdMismatch(let issueContext) = viewModel.hookConnectionIssue else {
            Issue.record("Expected CWD mismatch diagnostic")
            return
        }
        #expect(issueContext.sessionId == "bind-session")

        viewModel.bindDroppedSession()

        #expect(boundContext == issueContext)
        #expect(viewModel.hookConnectionIssue == nil)
        #expect(viewModel.hookRepairSucceeded == true)
    }

    @Test("reinstall reports failure without hiding the actionable issue")
    func reinstallFailureKeepsIssueVisible() async throws {
        let tabID = UUID()
        let viewModel = AgentDashboardViewModel(hookSilenceInterval: 0)
        viewModel.onReinstallHooks = { false }
        viewModel.processDetectionSignal(
            agentName: "Claude Code",
            state: .working,
            tabId: tabID
        )
        try await settleMainActor()

        viewModel.reinstallHooks()

        #expect(viewModel.hookRepairSucceeded == false)
        guard case .noEvents(let affectedTabID, _) = viewModel.hookConnectionIssue else {
            Issue.record("Expected no-events issue to remain actionable")
            return
        }
        #expect(affectedTabID == tabID)
    }

    @Test("CwdChanged never bypasses its AppDelegate authorization gate")
    func cwdChangedIsIgnoredByDashboardSubscription() async throws {
        let receiver = HookEventReceiverImpl()
        let viewModel = AgentDashboardViewModel(hookEventReceiver: receiver)
        var resolverCalls = 0
        viewModel.tabIdResolver = { _, _ in
            resolverCalls += 1
            return UUID()
        }

        receiver.receive(HookEvent(
            type: .cwdChanged,
            sessionId: "bound-but-rejected",
            data: .cwdChanged(CwdChangedData(previousCwd: "/tmp/untrusted-old")),
            cwd: "/tmp/open-tab"
        ))
        try await settleMainActor()

        #expect(resolverCalls == 0)
        #expect(viewModel.sessions.isEmpty)
    }

    private func settleMainActor() async throws {
        await Task.yield()
        try await Task.sleep(nanoseconds: 10_000_000)
        await Task.yield()
    }
}
