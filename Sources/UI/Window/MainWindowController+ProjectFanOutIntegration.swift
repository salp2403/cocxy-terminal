// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+ProjectFanOutIntegration.swift - Project-bound fan-out services.

import AppKit
import Foundation

@MainActor
extension MainWindowController {
    func makeProjectFanOutViewModel(
        projectID: ProjectID,
        projectRoot: URL,
        preferredSourceTabID: TabID?,
        record: ProjectRecord?,
        worktreeConfig: WorktreeConfig
    ) -> ProjectFanOutFlowViewModel {
        let sourceTabID = launchSourceTabID(
            preferred: preferredSourceTabID,
            projectID: projectID
        )
        let actions = ProjectFanOutActions(
            launch: { [weak self] request in
                guard let self,
                      let delegate = NSApp.delegate as? AppDelegate,
                      let sourceTabID,
                      let tab = tabManager.tab(for: sourceTabID),
                      projectResolver.resolveProject(for: tab.workingDirectory).groupingID
                        == projectID,
                      let context = delegate.makeTaskRunLaunchContext(
                          controller: self,
                          tab: tab
                      ) else {
                    throw ProjectHomeActionFailure(
                        message: "The project session changed before launch."
                    )
                }
                guard context.worktreeConfig.enabled else {
                    throw TaskRunExecutionError.featureDisabled
                }
                return try await delegate.performTaskRunLaunch(
                    request: request,
                    context: context
                )
            },
            loadSnapshot: { runID in
                guard let delegate = NSApp.delegate as? AppDelegate else {
                    throw ProjectHomeActionFailure(message: "Parallel task services are unavailable.")
                }
                let comparisons = try await delegate.taskRunComparisons(runID: runID)
                guard let run = delegate.taskRunsSnapshot().first(where: { $0.id == runID }),
                      run.projectID == projectID else {
                    throw TaskRunError.runNotFound(runID)
                }
                return ProjectFanOutSnapshot(
                    run: run,
                    comparisons: comparisons,
                    candidateCollisions: TaskCollisionDetector.betweenCandidates(
                        comparisons,
                        projectRoot: projectRoot
                    )
                )
            },
            launchCollisions: { plannedPaths in
                guard let delegate = NSApp.delegate as? AppDelegate else { return .empty }
                return delegate.taskLaunchCollisionReport(
                    plannedPaths: plannedPaths,
                    projectID: projectID,
                    projectRoot: projectRoot
                )
            },
            preparePromotion: { runID, candidateID in
                guard let delegate = NSApp.delegate as? AppDelegate else {
                    throw ProjectHomeActionFailure(message: "Promotion services are unavailable.")
                }
                return try await delegate.prepareTaskRunPromotion(
                    runID: runID,
                    candidateID: candidateID
                )
            },
            executePromotion: { preview in
                guard let delegate = NSApp.delegate as? AppDelegate else {
                    throw ProjectHomeActionFailure(message: "Promotion services are unavailable.")
                }
                return try await delegate.executeTaskRunPromotion(preview)
            },
            recycle: { runID, candidateID in
                guard let delegate = NSApp.delegate as? AppDelegate else {
                    throw ProjectHomeActionFailure(message: "Task recycling is unavailable.")
                }
                return try await delegate.recycleTaskRunCandidate(
                    runID: runID,
                    candidateID: candidateID
                )
            }
        )
        return ProjectFanOutFlowViewModel(
            projectID: projectID,
            projectRoot: projectRoot,
            availableBaseRefs: availableWorktreeBaseRefs(for: projectRoot),
            defaultBaseRef: record?.defaultBaseRef ?? worktreeConfig.baseRef,
            defaultAgentNames: record?.defaultAgents ?? [],
            actions: actions
        )
    }

    private func launchSourceTabID(
        preferred: TabID?,
        projectID: ProjectID
    ) -> TabID? {
        if let preferred,
           let tab = tabManager.tab(for: preferred),
           projectResolver.resolveProject(for: tab.workingDirectory).groupingID == projectID {
            return preferred
        }
        return tabManager.tabs.first {
            projectResolver.resolveProject(for: $0.workingDirectory).groupingID == projectID
        }?.id
    }
}
