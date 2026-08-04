// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Project fan-out flow")
@MainActor
struct ProjectFanOutFlowViewModelSwiftTestingTests {
    @Test("project defaults prefill the embedded launch editor")
    func projectDefaultsPrefillLaunch() throws {
        let harness = try Harness()
        let model = harness.makeModel(defaultAgents: ["gemini", "codex"], defaultBaseRef: "main")

        model.showLaunch()

        #expect(model.mode == .launch)
        #expect(model.selectedProviders == [.gemini, .codex])
        #expect(model.baseRef == "main")
        #expect(model.candidateCount == 2)
    }

    @Test("legacy project defaults are bounded to the supported candidate limit")
    func legacyDefaultsAreBounded() throws {
        let harness = try Harness()
        let providers = Array(AgentTeamProvider.allCases.prefix(10))
        let model = harness.makeModel(
            defaultAgents: providers.map(\.rawValue),
            availableProviders: providers
        )

        model.showLaunch()
        model.prompt = "Implement"

        #expect(model.selectedProviders.count == TaskRunRequest.maximumCandidateCount)
        #expect(model.candidateCount == TaskRunRequest.maximumCandidateCount)
        #expect(try model.makeRequest().candidateCount == TaskRunRequest.maximumCandidateCount)
    }

    @Test("collision warning is visible and does not disable launch")
    func collisionWarningIsNonblocking() async throws {
        let harness = try Harness()
        harness.launchCollisionReport = TaskCollisionReport(collisions: [collision(path: "A.swift")])
        let model = harness.makeModel()
        model.showLaunch()
        model.prompt = "Implement A.swift"
        await model.refreshLaunchCollisions()

        #expect(model.inferredPaths == ["A.swift"])
        #expect(model.launchCollisionReport.paths == ["A.swift"])
        #expect(model.canLaunch)
        await model.launch()
        #expect(harness.launchedRequests.count == 1)
        #expect(model.mode == .comparison)
    }

    @Test("promotion requires preview and executes that exact value")
    func promotionUsesPreview() async throws {
        let harness = try Harness()
        let model = harness.makeModel()
        await model.showComparison(runID: harness.run.id)
        model.selectedCandidateID = harness.run.candidates[0].id

        await model.preparePromotion()
        #expect(model.mode == .promotion)
        #expect(model.promotionPreview == harness.preview)
        #expect(harness.executedPreviews.isEmpty)

        await model.confirmPromotion()
        #expect(harness.executedPreviews == [harness.preview])
        #expect(model.mode == .comparison)
    }

    @Test("stale promotion regenerates a reviewable preview")
    func stalePromotionRefreshesPreview() async throws {
        let harness = try Harness()
        harness.executionError = TaskRunExecutionError.promotionUnavailable("task changed")
        let model = harness.makeModel()
        await model.showComparison(runID: harness.run.id)
        model.selectedCandidateID = harness.run.candidates[0].id
        await model.preparePromotion()

        await model.confirmPromotion()

        #expect(harness.executedPreviews == [harness.preview])
        #expect(harness.prepareCallCount == 2)
        #expect(model.mode == .promotion)
        #expect(model.promotionPreview == harness.preview)
        #expect(model.errorMessage?.contains("refreshed cleanup plan") == true)
        #expect(!model.isBusy)
    }

    @Test("promotion reports each worktree cleanup failure and its cause")
    func promotionReportsCleanupFailureDetails() async throws {
        let harness = try Harness()
        harness.cleanupFailures = [
            "loser-a: git cleanup exited 3",
            "loser-b: worktree metadata could not be updated",
        ]
        let model = harness.makeModel()
        await model.showComparison(runID: harness.run.id)
        model.selectedCandidateID = harness.run.candidates[0].id
        await model.preparePromotion()

        await model.confirmPromotion()

        #expect(model.successMessage?.contains("loser-a: git cleanup exited 3") == true)
        #expect(model.successMessage?.contains(
            "loser-b: worktree metadata could not be updated"
        ) == true)
    }

    @Test("discarded candidate opens a prefilled launch without copy paste")
    func discardedCandidateRecycles() async throws {
        let harness = try Harness(completed: true)
        let model = harness.makeModel()
        await model.showComparison(runID: harness.run.id)
        model.selectedCandidateID = harness.run.candidates[1].id

        await model.recycleSelectedCandidate()

        #expect(model.mode == .launch)
        #expect(model.prompt == harness.recycleDraft.prompt)
        #expect(model.inferredPaths == harness.recycleDraft.plannedPaths)
    }

    @Test("active task run can be cancelled from the comparison surface")
    func activeRunCancels() async throws {
        let harness = try Harness()
        let model = harness.makeModel()
        await model.showComparison(runID: harness.run.id)

        #expect(model.canCancelRun)
        await model.cancelRun()

        #expect(harness.cancelledRunIDs == [harness.run.id])
        #expect(model.run?.status == .cancelled)
        #expect(model.canForgetRun)
    }

    @Test("finished task run can be forgotten from the comparison surface")
    func finishedRunForgets() async throws {
        let harness = try Harness(completed: true)
        let runID = harness.run.id
        let model = harness.makeModel()
        await model.showComparison(runID: runID)

        #expect(model.canForgetRun)
        await model.forgetRun()

        #expect(harness.forgottenRunIDs == [runID])
        #expect(model.mode == .inbox)
        #expect(model.run == nil)
    }

    @Test("comparison exposes a task run persistence warning")
    func comparisonExposesPersistenceWarning() async throws {
        let harness = try Harness()
        harness.persistenceIssue = "Task flow could not be saved. Changes remain in memory."
        let model = harness.makeModel()

        await model.showComparison(runID: harness.run.id)

        #expect(model.persistenceIssue == harness.persistenceIssue)
        #expect(model.durabilityNotice == harness.persistenceIssue)
    }

    @Test("coordinator consumes a request once for the matching project")
    func coordinatorRoutesOnce() {
        let coordinator = ProjectFanOutCoordinator()
        let project = ProjectID(rawValue: "/tmp/project")
        let target = TabID()
        coordinator.presentComparison(projectID: project, targetTabID: target, runID: "run")

        #expect(coordinator.consume(
            for: ProjectID(rawValue: "/tmp/other"), targetTabID: target
        ) == nil)
        #expect(coordinator.consume(
            for: project, targetTabID: target
        ) == .comparison(runID: "run"))
        #expect(coordinator.consume(for: project, targetTabID: target) == nil)
    }

    @Test("coordinator preserves simultaneous requests for different windows")
    func coordinatorQueuesDestinations() {
        let coordinator = ProjectFanOutCoordinator()
        let project = ProjectID(rawValue: "/tmp/project")
        let firstTarget = TabID()
        let secondTarget = TabID()

        coordinator.presentLaunch(projectID: project, targetTabID: firstTarget)
        coordinator.presentComparison(
            projectID: project,
            targetTabID: secondTarget,
            runID: "second"
        )
        coordinator.presentComparison(
            projectID: project,
            targetTabID: firstTarget,
            runID: "third"
        )

        #expect(coordinator.requests.count == 3)
        #expect(coordinator.consume(
            for: project, targetTabID: secondTarget
        ) == .comparison(runID: "second"))
        #expect(coordinator.consume(
            for: project, targetTabID: firstTarget
        ) == .launch(nil))
        #expect(coordinator.consume(
            for: project, targetTabID: firstTarget
        ) == .comparison(runID: "third"))
        #expect(coordinator.requests.isEmpty)
    }

    private func collision(path: String) -> TaskFileCollision {
        TaskFileCollision(
            path: path,
            kind: .overlap,
            participants: [
                TaskCollisionParticipant(id: "planned", label: "Planned", kind: .plannedTask),
                TaskCollisionParticipant(id: "live", label: "Live", kind: .liveSession),
            ]
        )
    }

    @MainActor
    private final class Harness {
        var run: TaskRun
        let comparison: TaskRunCandidateComparison
        let preview: TaskRunPromotionPreview
        let recycleDraft: TaskRunRecycleDraft
        var launchCollisionReport = TaskCollisionReport.empty
        var launchedRequests: [TaskRunRequest] = []
        var executedPreviews: [TaskRunPromotionPreview] = []
        var prepareCallCount = 0
        var executionError: TaskRunExecutionError?
        var cleanupFailures: [String] = []
        var cancelledRunIDs: [String] = []
        var forgottenRunIDs: [String] = []
        var persistenceIssue: String?

        init(completed: Bool = false) throws {
            var run = TaskRun(
                id: "flow",
                request: try TaskRunRequest.make(prompt: "Task", agents: "codex,claude"),
                originRepoPath: URL(fileURLWithPath: "/tmp/project"),
                baseCommit: "base"
            )
            for index in run.candidates.indices {
                let id = run.candidates[index].id
                try run.updateCandidate(id: id) {
                    $0.worktree = WorktreeManifest.WorktreeEntry(
                        id: "worktree-\(index)",
                        branch: "task/\(index)",
                        path: URL(fileURLWithPath: "/tmp/worktree-\(index)"),
                        createdAt: Date(timeIntervalSince1970: 1),
                        agent: $0.provider.rawValue,
                        tabID: nil
                    )
                    $0.status = .finished
                    $0.touchedFiles = ["Sources/A.swift"]
                }
            }
            run.markRunning()
            if completed { try run.markCompleted(candidateID: run.candidates[0].id) }
            let selectedComparison = TaskRunCandidateComparison(
                candidate: run.candidates[0],
                diffs: []
            )
            self.run = run
            self.comparison = selectedComparison
            self.preview = TaskRunPromotionPreview(
                run: run,
                comparisons: [selectedComparison],
                selectedComparison: selectedComparison,
                collisionReport: .empty,
                mergedCleanupPlan: WorktreeBatchCleanupPlan(removable: [], blocked: [], skipped: []),
                cleanupEntries: []
            )
            if completed {
                self.recycleDraft = try TaskRunRecycleDraft.make(
                    run: run,
                    candidateID: run.candidates[1].id
                )
            } else {
                self.recycleDraft = TaskRunRecycleDraft(
                    sourceRunID: run.id,
                    sourceCandidateID: run.candidates[1].id,
                    prompt: "Recycled",
                    plannedPaths: ["Sources/A.swift"],
                    providers: [.codex],
                    candidateCount: 2,
                    baseRef: "HEAD",
                    artifact: TaskHandoffArtifact(
                        markdown: "Recycled",
                        includedBlockCount: 0,
                        includedTouchedFileCount: 1
                    )
                )
            }
        }

        func makeModel(
            defaultAgents: [String] = ["codex", "claude"],
            defaultBaseRef: String? = "HEAD",
            availableProviders: [AgentTeamProvider] = [.claudeCode, .codex, .gemini]
        ) -> ProjectFanOutFlowViewModel {
            ProjectFanOutFlowViewModel(
                projectID: run.projectID,
                projectRoot: run.originRepoPath,
                availableProviders: availableProviders,
                availableBaseRefs: ["HEAD", "main"],
                defaultBaseRef: defaultBaseRef,
                defaultAgentNames: defaultAgents,
                actions: ProjectFanOutActions(
                    launch: { [self] request in
                        launchedRequests.append(request)
                        return run
                    },
                    loadSnapshot: { [self] _ in
                        ProjectFanOutSnapshot(
                            run: run,
                            comparisons: run.candidates.map {
                                TaskRunCandidateComparison(candidate: $0, diffs: [])
                            },
                            candidateCollisions: .empty,
                            persistenceIssue: persistenceIssue
                        )
                    },
                    launchCollisions: { [self] _, seedPaths in
                        TaskLaunchCollisionAnalysis(
                            inferredPaths: Array(
                                Set(seedPaths + launchCollisionReport.paths)
                            ).sorted(),
                            report: launchCollisionReport
                        )
                    },
                    preparePromotion: { [self] _, _ in
                        prepareCallCount += 1
                        return preview
                    },
                    executePromotion: { [self] value in
                        executedPreviews.append(value)
                        if let executionError { throw executionError }
                        return TaskRunPromotionOutcome(
                            run: run,
                            gitResult: WorktreePromotionResult(
                                entry: run.candidates[0].worktree!,
                                candidateCommit: "candidate",
                                mergedCommit: "merged",
                                createdCandidateCommit: true
                            ),
                            cleanupFailures: cleanupFailures
                        )
                    },
                    recycle: { [self] _, _ in recycleDraft },
                    cancel: { [self] runID in
                        cancelledRunIDs.append(runID)
                        try run.markCancelled()
                        return run
                    },
                    forget: { [self] runID in forgottenRunIDs.append(runID) }
                )
            )
        }
    }
}
