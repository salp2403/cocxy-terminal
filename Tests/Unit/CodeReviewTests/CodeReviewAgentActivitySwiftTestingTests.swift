// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("CodeReview live agent activity")
struct CodeReviewAgentActivitySwiftTestingTests {

    @Test("dashboard sessions are filtered to the active review tab and update live")
    func dashboardSessionsFilterToActiveTabAndUpdateLive() async {
        let tabA = TabID()
        let tabB = TabID()
        var activeTab = tabA
        let subject = CurrentValueSubject<[AgentSessionInfo], Never>([])

        let viewModel = CodeReviewPanelViewModel(tracker: SessionDiffTrackerImpl(), hookEventReceiver: nil)
        viewModel.activeTabIDProvider = { activeTab }
        viewModel.bindAgentSessionsPublisher(subject.eraseToAnyPublisher())

        let claude = makeSession(
            id: "claude-session",
            tabID: tabA,
            agentName: "Claude Code",
            subagents: [makeSubagent(id: "researcher", touchedFiles: ["Sources/App.swift"])],
            filesTouched: [FileImpact(path: "Sources/App.swift", operations: [.edit])],
            totalToolCalls: 2
        )
        let codex = makeSession(
            id: "codex-session",
            tabID: tabA,
            agentName: "Codex CLI",
            filesTouched: [FileImpact(path: "Tests/AppTests.swift", operations: [.write])],
            totalToolCalls: 1
        )
        let otherTab = makeSession(id: "other-tab", tabID: tabB, agentName: "Claude Code")

        subject.send([claude, codex, otherTab])
        await MainActorTestSupport.drainMainQueue()

        #expect(viewModel.reviewAgentSessions.map(\.id).sorted() == ["claude-session", "codex-session"])
        #expect(viewModel.reviewSubagentCount == 1)
        #expect(viewModel.reviewTouchedFileCount == 2)
        #expect(viewModel.reviewToolCallCount == 3)

        let updatedCodex = makeSession(
            id: "codex-session",
            tabID: tabA,
            agentName: "Codex CLI",
            filesTouched: [
                FileImpact(path: "Tests/AppTests.swift", operations: [.write]),
                FileImpact(path: "Sources/App.swift", operations: [.read]),
            ],
            fileConflicts: ["Sources/App.swift"],
            totalToolCalls: 4
        )
        subject.send([claude, updatedCodex, otherTab])
        await MainActorTestSupport.drainMainQueue()

        #expect(viewModel.reviewAgentSessions.first { $0.id == "codex-session" }?.filesTouched.count == 2)
        #expect(viewModel.reviewConflictCount == 1)
        #expect(viewModel.reviewToolCallCount == 6)

        activeTab = tabB
        subject.send([claude, updatedCodex, otherTab])
        await MainActorTestSupport.drainMainQueue()

        #expect(viewModel.reviewAgentSessions.map(\.id) == ["other-tab"])
    }

    @Test("active session id keeps an exact hook session visible without a tab provider")
    func activeSessionIDKeepsExactSessionVisible() async {
        let tabA = TabID()
        let subject = CurrentValueSubject<[AgentSessionInfo], Never>([])

        let viewModel = CodeReviewPanelViewModel(tracker: SessionDiffTrackerImpl(), hookEventReceiver: nil)
        viewModel.activeSessionIdProvider = { "hook-session" }
        viewModel.bindAgentSessionsPublisher(subject.eraseToAnyPublisher())

        subject.send([
            makeSession(id: "hook-session", tabID: tabA, agentName: "Claude Code"),
            makeSession(id: "other-session", tabID: TabID(), agentName: "Codex CLI"),
        ])
        await MainActorTestSupport.drainMainQueue()

        #expect(viewModel.reviewAgentSessions.map(\.id) == ["hook-session"])
    }

    private func makeSession(
        id: String,
        tabID: TabID,
        agentName: String,
        subagents: [SubagentInfo] = [],
        filesTouched: [FileImpact] = [],
        fileConflicts: [String] = [],
        totalToolCalls: Int = 0,
        totalErrors: Int = 0
    ) -> AgentSessionInfo {
        AgentSessionInfo(
            id: id,
            projectName: "sisocs-v3",
            gitBranch: "main",
            agentName: agentName,
            state: .working,
            lastActivity: "Edit: App.swift",
            lastActivityTime: Date(),
            tabId: tabID.rawValue,
            subagents: subagents,
            priority: .standard,
            model: "test-model",
            filesTouched: filesTouched,
            fileConflicts: fileConflicts,
            totalToolCalls: totalToolCalls,
            totalErrors: totalErrors
        )
    }

    private func makeSubagent(id: String, touchedFiles: Set<String>) -> SubagentInfo {
        var subagent = SubagentInfo(
            id: id,
            type: "research",
            state: .working,
            startTime: Date().addingTimeInterval(-12)
        )
        subagent.toolUseCount = 2
        subagent.lastActivity = "Read: App.swift"
        subagent.touchedFilePaths = touchedFiles
        return subagent
    }
}
