// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import SwiftUI
import Testing
@testable import CocxyTerminal

@Suite("TaskRun UI")
@MainActor
struct TaskRunUISwiftTestingTests {
    @Test("launch model keeps provider order and builds a bounded request")
    func launchModelBuildsRequest() throws {
        let model = TaskRunLaunchSheetViewModel(
            availableProviders: [.claudeCode, .codex, .gemini],
            availableBaseRefs: ["main", "HEAD", "main"],
            initialBaseRef: "main"
        )

        #expect(model.selectedProviders == [.claudeCode, .codex])
        #expect(model.availableBaseRefs == ["main", "HEAD"])
        #expect(!model.canLaunch)

        model.prompt = "Implement and verify"
        model.candidateCount = 5
        model.setProvider(.gemini, selected: true)
        let request = try model.makeRequest()

        #expect(model.canLaunch)
        #expect(request.providers == [
            .claudeCode, .codex, .gemini, .claudeCode, .codex,
        ])
        #expect(request.baseRef == "main")
    }

    @Test("launch model prevents a ninth selected provider")
    func launchModelCapsProviderSelection() {
        let providers = Array(AgentTeamProvider.allCases.prefix(9))
        let model = TaskRunLaunchSheetViewModel(
            availableProviders: providers,
            availableBaseRefs: ["HEAD"],
            initialBaseRef: "HEAD"
        )

        for provider in providers.prefix(8) {
            model.setProvider(provider, selected: true)
        }
        let ninth = providers[8]

        #expect(model.selectedProviders.count == 8)
        #expect(model.isSelectionDisabled(ninth))
        model.setProvider(ninth, selected: true)
        #expect(!model.isSelected(ninth))
    }

    @Test("comparison model rejects stale reloads and enables a bound winner")
    func comparisonModelCoordinatesOperations() throws {
        var run = try makeRun()
        let firstID = try #require(run.candidates.first?.id)
        let entry = WorktreeManifest.WorktreeEntry(
            id: "candidate-worktree",
            branch: "cocxy/codex/candidate",
            path: URL(fileURLWithPath: "/tmp/candidate-worktree"),
            createdAt: Date(timeIntervalSince1970: 1),
            agent: "codex",
            tabID: nil
        )
        try run.updateCandidate(id: firstID) {
            $0.worktree = entry
            $0.status = .finished
            $0.estimatedCostMicros = 12_500
        }
        run.markRunning()

        let model = TaskRunComparisonSheetViewModel(run: run)
        let staleRevision = model.beginReload()
        let currentRevision = model.beginReload()
        model.failReload("stale", revision: staleRevision)
        #expect(model.isLoading)

        let comparison = TaskRunCandidateComparison(
            candidate: try #require(run.candidates.first),
            diffs: []
        )
        model.apply(
            run: run,
            comparisons: [comparison],
            revision: currentRevision
        )

        #expect(!model.isLoading)
        #expect(model.canPromote)
        #expect(model.selectedComparison?.id == firstID)
        #expect(TaskRunComparisonSheetViewModel.costLabel(
            micros: 12_500,
            unavailable: "N/A"
        ) == "$0.0125")
        #expect(TaskRunComparisonSheetViewModel.costLabel(
            micros: 0,
            unavailable: "N/A"
        ) == "N/A")
    }

    @Test("comparison model skips orphaned candidates and disables promotion")
    func comparisonModelSkipsOrphanedCandidates() throws {
        var run = try makeRun()
        let firstID = try #require(run.candidates.first?.id)
        let secondID = try #require(run.candidates.last?.id)
        let entry = WorktreeManifest.WorktreeEntry(
            id: "missing-worktree",
            branch: "task/missing",
            path: URL(fileURLWithPath: "/tmp/missing-worktree"),
            createdAt: Date(timeIntervalSince1970: 1),
            agent: "codex",
            tabID: nil
        )
        try run.updateCandidate(id: firstID) {
            $0.worktree = entry
            $0.status = .orphaned
        }
        try run.updateCandidate(id: secondID) {
            $0.worktree = entry
            $0.status = .finished
        }
        run.markRunning()

        let model = TaskRunComparisonSheetViewModel(run: run)
        #expect(model.selectedCandidateID == secondID)
        #expect(model.canPromote)

        model.selectedCandidateID = firstID
        #expect(!model.canPromote)
    }

    @Test("launch and comparison views construct with read-only diff mode")
    func viewsConstruct() throws {
        let launchModel = TaskRunLaunchSheetViewModel(
            availableBaseRefs: ["HEAD"],
            initialBaseRef: "HEAD"
        )
        _ = TaskRunLaunchSheet(
            viewModel: launchModel,
            onCancel: {},
            onLaunch: { _ in }
        ).body

        let comparisonModel = TaskRunComparisonSheetViewModel(run: try makeRun())
        _ = TaskRunComparisonSheet(
            viewModel: comparisonModel,
            onRefresh: {},
            onPromote: { _ in },
            onDismiss: {}
        ).body

        var mode = DiffViewerMode.unified
        _ = DiffViewerView(
            diffs: [],
            mode: Binding(get: { mode }, set: { mode = $0 }),
            onStage: { _, _, _ in },
            showsStagingControls: false
        ).body
    }

    @Test("both palette presentations discover parallel task actions")
    func paletteActionsAreDiscoverable() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let engine = controller.createWiredCommandPaletteEngine()
        let actionIDs = Set(engine.allActions.map(\.id))

        #expect(actionIDs.contains("taskRun.fanOut"))
        #expect(actionIDs.contains("taskRun.compare"))
        #expect(actionIDs.contains("navigation.jumpProject"))

        let auroraIDs = Set(controller.buildAuroraPaletteActions().map(\.id))
        #expect(auroraIDs.contains("taskRun.fanOut"))
        #expect(auroraIDs.contains("taskRun.compare"))
        #expect(auroraIDs.contains("navigation.jumpProject"))
    }

    private func makeRun() throws -> TaskRun {
        let request = try TaskRunRequest.make(
            prompt: "Compare implementations",
            agents: "codex,claude"
        )
        return TaskRun(
            id: "ui-run",
            request: request,
            originRepoPath: URL(fileURLWithPath: "/tmp/repo"),
            baseCommit: "abc123"
        )
    }
}
