// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+TaskRunCLIRequest.swift - Task run CLI routing and authority binding.

import Foundation

private struct TaskRunCLICandidateSummary: Codable {
    let id: String
    let provider: String
    let branch: String?
    let status: String
    let estimatedCostMicros: Int64?
}

private struct TaskRunCLISummary: Codable {
    let id: String
    let project: String
    let origin: String
    let baseRef: String
    let baseCommit: String
    let status: String
    let createdAt: Date
    let promotedCandidateID: String?
    let candidates: [TaskRunCLICandidateSummary]
}

extension AppDelegate {
    nonisolated func handleTaskRunCLIRequest(
        kind: String,
        params: [String: String],
        approvedContext: SocketPrivilegedCommandContext? = nil
    ) -> (success: Bool, data: [String: String]) {
        if kind == "list" {
            return syncOnMainActor {
                self.listTaskRunsForCLI(projectPath: params["project"])
            }
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = LockedBox<(Bool, [String: String])>((
            false,
            ["error": "Parallel task dispatch did not complete"]
        ))
        Task.detached { [self] in
            let result = await performTaskRunCLIRequest(
                kind: kind,
                params: params,
                approvedContext: approvedContext
            )
            box.withValue { $0 = result }
            semaphore.signal()
        }
        semaphore.wait()
        return box.withValue { $0 }
    }

    nonisolated func performTaskRunCLIRequest(
        kind: String,
        params: [String: String],
        approvedContext: SocketPrivilegedCommandContext?
    ) async -> (Bool, [String: String]) {
        do {
            switch kind {
            case "launch":
                guard let approvedContext,
                      let context = await MainActor.run(body: {
                          self.approvedTaskRunLaunchContext(approvedContext)
                      }) else {
                    return (false, ["error": "Approved parallel task target is unavailable"])
                }
                let count = try params["count"].map { raw -> Int in
                    guard let value = Int(raw) else {
                        throw TaskRunError.invalidCandidateCount(0)
                    }
                    return value
                }
                let request = try TaskRunRequest.make(
                    prompt: params["prompt"] ?? "",
                    agents: params["agents"] ?? "",
                    count: count,
                    baseRef: params["base-ref"]
                )
                let run = try await performTaskRunLaunch(
                    request: request,
                    context: context
                )
                guard let credential = await MainActor.run(body: {
                    self.taskOrchestrationSessionManager.credential(forRunID: run.id)
                }) else {
                    return (false, ["error": "Task orchestration session is unavailable"])
                }
                return (true, [
                    "status": "launched",
                    "run-id": run.id,
                    "candidates": "\(run.candidates.count)",
                    "base-ref": run.baseRef,
                    "base-commit": run.baseCommit,
                    "orchestration-session": credential.token,
                    "orchestration-expires-at": ISO8601DateFormatter().string(
                        from: credential.expiresAt
                    ),
                ])

            case "promote":
                let runID = params["run-id"] ?? ""
                let candidateID = params["candidate-id"] ?? ""
                guard let approvedContext,
                      await MainActor.run(body: {
                          self.approvedTaskRunPromotionMatches(
                              approvedContext,
                              runID: runID,
                              candidateID: candidateID
                          )
                      }) else {
                    return (false, ["error": "Approved task promotion target is unavailable"])
                }
                let outcome = try await promoteTaskRun(
                    runID: runID,
                    candidateID: candidateID
                )
                return (true, [
                    "status": "promoted",
                    "run-id": outcome.run.id,
                    "candidate-id": outcome.run.promotedCandidateID ?? "",
                    "candidate-commit": outcome.gitResult.candidateCommit,
                    "merged-commit": outcome.gitResult.mergedCommit,
                    "cleanup-failures": outcome.cleanupFailures.joined(separator: "\n"),
                ])

            default:
                return (false, ["error": "Unknown task run action: \(kind)"])
            }
        } catch {
            return (false, ["error": String(describing: error)])
        }
    }

    @MainActor
    func focusedTaskRunLaunchContext() -> TaskRunLaunchContext? {
        guard let controller = focusedWindowController() ?? windowController,
              let tab = controller.tabManager.activeTab else {
            return nil
        }
        return makeTaskRunLaunchContext(controller: controller, tab: tab)
    }

    @MainActor
    func approvedTaskRunLaunchContext(
        _ approvedContext: SocketPrivilegedCommandContext
    ) -> TaskRunLaunchContext? {
        guard approvedContext.scope == .localExecution,
              let rawTabID = approvedContext.tabID,
              let controller = privilegedSocketController(for: approvedContext),
              let tab = controller.tabManager.tab(for: TabID(rawValue: rawTabID)) else {
            return nil
        }
        let actualWorkingDirectory = canonicalTaskRunWorkingDirectory(for: tab)
        guard actualWorkingDirectory == approvedContext.workingDirectory else {
            return nil
        }
        guard let context = makeTaskRunLaunchContext(controller: controller, tab: tab),
              approvedContext.authorityDetails == Self.taskRunLaunchAuthorityDetails(
                  for: context
              ) else {
            return nil
        }
        return context
    }

    @MainActor
    func approvedTaskRunPromotionMatches(
        _ approvedContext: SocketPrivilegedCommandContext,
        runID rawRunID: String,
        candidateID rawCandidateID: String
    ) -> Bool {
        let runID = AgentTeamConfig.slug(rawRunID)
        let candidateID = AgentTeamConfig.slug(rawCandidateID)
        guard approvedContext.scope == .localExecution,
              let run = activeTaskRuns[runID],
              run.status == .running,
              let candidate = run.candidates.first(where: { $0.id == candidateID }),
              candidate.status != .orphaned,
              let entry = candidate.worktree,
              let tabID = entry.tabID,
              approvedContext.tabID == tabID.rawValue,
              let controller = privilegedSocketController(for: approvedContext),
              controller.tabManager.tab(for: tabID) != nil,
              entry.path.resolvingSymlinksInPath().standardizedFileURL.path
                == approvedContext.workingDirectory,
              approvedContext.authorityDetails == Self.taskRunPromotionAuthorityDetails(
                  run: run,
                  candidate: candidate,
                  entry: entry
              ) else {
            return false
        }
        return true
    }

    nonisolated static func taskRunLaunchAuthorityDetails(
        for context: TaskRunLaunchContext
    ) -> [String: String] {
        let origin = resolveOriginRepoRoot(from: context.originRepoPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        let expandedBasePath = (context.worktreeConfig.basePath as NSString)
            .expandingTildeInPath
        let worktreeRoot = URL(
            fileURLWithPath: expandedBasePath,
            isDirectory: true
        ).standardizedFileURL.path
        return [
            "origin-repository": origin,
            "worktree-root": worktreeRoot,
        ]
    }

    nonisolated static func taskRunPromotionAuthorityDetails(
        run: TaskRun,
        candidate: TaskRunCandidate,
        entry: WorktreeManifest.WorktreeEntry
    ) -> [String: String] {
        [
            "run-id": run.id,
            "candidate-id": candidate.id,
            "branch": entry.branch,
            "origin-repository": run.originRepoPath
                .resolvingSymlinksInPath()
                .standardizedFileURL.path,
            "base-commit": run.baseCommit,
            "discarded-candidates": "\(max(0, run.candidates.count - 1))",
        ]
    }

    @MainActor
    private func listTaskRunsForCLI(projectPath: String?) -> (Bool, [String: String]) {
        let projectID: ProjectID?
        if let projectPath {
            do {
                projectID = try resolveProjectReference(
                    projectPath,
                    registerIfAvailable: false
                )
            } catch {
                return (false, ["error": String(describing: error)])
            }
        } else {
            projectID = nil
        }
        let summaries = taskRunsSnapshot().filter { run in
            projectID.map { run.projectID == $0 } ?? true
        }.map { run in
            TaskRunCLISummary(
                id: run.id,
                project: run.projectID.rawValue,
                origin: run.originRepoPath.path,
                baseRef: run.baseRef,
                baseCommit: run.baseCommit,
                status: run.status.rawValue,
                createdAt: run.createdAt,
                promotedCandidateID: run.promotedCandidateID,
                candidates: run.candidates.map { candidate in
                    TaskRunCLICandidateSummary(
                        id: candidate.id,
                        provider: candidate.provider.rawValue,
                        branch: candidate.worktree?.branch,
                        status: candidate.status.rawValue,
                        estimatedCostMicros: candidate.estimatedCostMicros > 0
                            ? candidate.estimatedCostMicros
                            : nil
                    )
                }
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let json = (try? encoder.encode(summaries))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "[]"
        return (true, [
            "status": "listed",
            "count": "\(summaries.count)",
            "runs": json,
        ])
    }
}
