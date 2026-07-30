// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+TaskHandoffCLI.swift - Exact-context export and local agent handoff.

import Foundation

enum TaskHandoffOperationError: Error, Equatable, Sendable, CustomStringConvertible {
    case sourceUnavailable
    case approvedContextChanged
    case destinationLaunchFailed(String)

    var description: String {
        switch self {
        case .sourceUnavailable:
            return "Task handoff source is unavailable"
        case .approvedContextChanged:
            return "Approved task handoff context has changed"
        case .destinationLaunchFailed(let reason):
            return "Task handoff destination could not be launched: \(reason)"
        }
    }
}

extension AppDelegate {
    nonisolated func handleTaskHandoffCLIRequest(
        kind: String,
        params: [String: String],
        approvedContext: SocketPrivilegedCommandContext?
    ) -> (success: Bool, data: [String: String]) {
        syncOnMainActor {
            do {
                switch kind {
                case "export":
                    return try self.exportTaskHandoffForCLI(
                        params: params,
                        approvedContext: approvedContext
                    )
                case "import":
                    return try self.importTaskHandoffForCLI(
                        params: params,
                        approvedContext: approvedContext
                    )
                default:
                    return (false, ["error": "Unknown task handoff action: \(kind)"])
                }
            } catch {
                return (false, ["error": String(describing: error)])
            }
        }
    }

    @MainActor
    func exportTaskHandoffArtifact(
        controller: MainWindowController,
        tabID: TabID,
        blockLimit: Int = TaskHandoffArtifactBuilder.defaultBlockLimit
    ) throws -> TaskHandoffArtifact {
        guard let tab = controller.tabManager.tab(for: tabID) else {
            throw TaskHandoffOperationError.sourceUnavailable
        }
        let limit = min(
            max(1, blockLimit),
            TaskHandoffArtifactBuilder.maximumBlockLimit
        )
        let surfaceID = taskHandoffSurfaceID(controller: controller, tabID: tabID)
        let blocks: [TerminalCommandBlock]
        if let surfaceID {
            let liveBlocks = controller.cocxyCoreBridge(forSurface: surfaceID)?
                .commandBlocks(for: surfaceID, limit: UInt32(limit)) ?? []
            blocks = controller.availableCommandBlocks(
                surfaceID: surfaceID,
                liveBlocks: liveBlocks,
                limit: UInt32(limit)
            )
        } else {
            blocks = []
        }
        let metadata = taskHandoffMetadata(controller: controller, tabID: tabID)
        return TaskHandoffArtifactBuilder.make(
            input: TaskHandoffArtifactInput(
                tabID: tabID.rawValue,
                workingDirectory: canonicalTaskHandoffWorkingDirectory(for: tab),
                branch: tab.worktreeBranch ?? tab.gitBranch,
                worktreeID: tab.worktreeID,
                taskSummary: metadata.summary,
                touchedFiles: metadata.touchedFiles,
                semanticBlocks: blocks.map {
                    TaskHandoffSemanticBlock(
                        command: $0.command,
                        output: $0.output,
                        exitCode: $0.exitCode,
                        workingDirectory: $0.pwd
                    )
                }
            ),
            blockLimit: limit
        )
    }

    @MainActor
    func launchTaskHandoff(
        _ destination: TaskHandoffDestination,
        sourceController: MainWindowController,
        sourceTabID: TabID
    ) throws -> AgentTeamAppLaunchResult {
        guard (sourceController.visibleTabID ?? sourceController.tabManager.activeTabID)
                == sourceTabID,
              let sourceTab = sourceController.tabManager.tab(for: sourceTabID) else {
            throw TaskHandoffOperationError.sourceUnavailable
        }
        let config = destination.makeAgentTeamConfig()
        do {
            let result = try launchAgentTeamConfig(
                config,
                controller: sourceController,
                targetTabID: sourceTabID.rawValue,
                workingDirectory: canonicalTaskHandoffWorkingDirectory(for: sourceTab)
            )
            guard result.launchResult.launchedCount == 1,
                  result.tabIDs.count == 1 else {
                throw TaskHandoffOperationError.destinationLaunchFailed(
                    "The destination did not create exactly one tab"
                )
            }
            return result
        } catch let error as TaskHandoffOperationError {
            throw error
        } catch {
            throw TaskHandoffOperationError.destinationLaunchFailed(
                String(describing: error)
            )
        }
    }

    @MainActor
    private func exportTaskHandoffForCLI(
        params: [String: String],
        approvedContext: SocketPrivilegedCommandContext?
    ) throws -> (Bool, [String: String]) {
        guard let approvedContext,
              approvedContext.scope == .terminalTab,
              let rawTabID = approvedContext.tabID,
              let requestedTabID = params["tabId"].flatMap(UUID.init(uuidString:)),
              requestedTabID == rawTabID,
              let rawLimit = params["limit"],
              let blockLimit = Int(rawLimit),
              let controller = privilegedSocketController(for: approvedContext),
              let tab = controller.tabManager.tab(for: TabID(rawValue: rawTabID)),
              canonicalTaskHandoffWorkingDirectory(for: tab)
                == approvedContext.workingDirectory else {
            throw TaskHandoffOperationError.approvedContextChanged
        }
        let artifact = try exportTaskHandoffArtifact(
            controller: controller,
            tabID: TabID(rawValue: rawTabID),
            blockLimit: blockLimit
        )
        return (true, [
            "status": "exported",
            "tab-id": rawTabID.uuidString,
            "artifact": artifact.markdown,
            "bytes": "\(artifact.byteCount)",
            "blocks": "\(artifact.includedBlockCount)",
            "files": "\(artifact.includedTouchedFileCount)",
        ])
    }

    @MainActor
    private func importTaskHandoffForCLI(
        params: [String: String],
        approvedContext: SocketPrivilegedCommandContext?
    ) throws -> (Bool, [String: String]) {
        guard let rawAgent = params["agent"],
              let artifact = params["artifact"] else {
            throw TaskHandoffOperationError.approvedContextChanged
        }
        let destination = try TaskHandoffDestination.make(
            agent: rawAgent,
            artifact: artifact
        )
        guard let approvedContext,
              approvedContext.scope == .localExecution,
              approvedContext.authorityDetails == destination.authorityDetails,
              let rawTabID = approvedContext.tabID,
              let controller = privilegedSocketController(for: approvedContext),
              (controller.visibleTabID ?? controller.tabManager.activeTabID)?.rawValue
                == rawTabID,
              let tab = controller.tabManager.tab(for: TabID(rawValue: rawTabID)),
              canonicalTaskHandoffWorkingDirectory(for: tab)
                == approvedContext.workingDirectory else {
            throw TaskHandoffOperationError.approvedContextChanged
        }
        let result = try launchTaskHandoff(
            destination,
            sourceController: controller,
            sourceTabID: TabID(rawValue: rawTabID)
        )
        guard let destinationTabID = result.tabIDs.first else {
            throw TaskHandoffOperationError.destinationLaunchFailed(
                "The destination tab is unavailable"
            )
        }
        return (true, [
            "status": "imported",
            "provider": destination.provider.rawValue,
            "team-id": result.launchResult.teamID,
            "tab-id": destinationTabID.rawValue.uuidString,
        ])
    }

    @MainActor
    private func taskHandoffSurfaceID(
        controller: MainWindowController,
        tabID: TabID
    ) -> SurfaceID? {
        let surfaceIDs = controller.surfaceIDs(for: tabID)
        guard !surfaceIDs.isEmpty else { return nil }
        if (controller.visibleTabID ?? controller.tabManager.activeTabID) == tabID,
           let focused = controller.activeTerminalSurfaceView?.terminalViewModel?.surfaceID,
           surfaceIDs.contains(focused) {
            return focused
        }
        if let primary = controller.tabSurfaceMap[tabID], surfaceIDs.contains(primary) {
            return primary
        }
        return surfaceIDs.sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }.first
    }

    @MainActor
    private func taskHandoffMetadata(
        controller: MainWindowController,
        tabID: TabID
    ) -> (summary: String?, touchedFiles: [String]) {
        for run in activeTaskRuns.values.sorted(by: { $0.id < $1.id }) {
            guard let candidate = run.candidates.first(where: {
                $0.worktree?.tabID == tabID
            }) else {
                continue
            }
            return (
                run.prompt,
                touchedFilesForTaskHandoff(teamID: candidate.teamID)
            )
        }

        let teamID = controller.agentTeamTabIDsByTeamID.keys.sorted().first(where: {
            controller.agentTeamTabIDsByTeamID[$0]?.contains(tabID) == true
        })
        guard let teamID, let run = activeAgentTeamRuns[teamID] else {
            return (nil, [])
        }
        let prompts = run.config.teammates.compactMap(\.prompt)
        return (
            prompts.count == 1 ? prompts[0] : nil,
            touchedFilesForTaskHandoff(teamID: teamID)
        )
    }

    @MainActor
    private func touchedFilesForTaskHandoff(teamID: String) -> [String] {
        guard let run = activeAgentTeamRuns[teamID] else { return [] }
        return Array(Set(run.graph.nodes.flatMap(\.touchedFiles))).sorted()
    }

    private func canonicalTaskHandoffWorkingDirectory(for tab: Tab) -> String {
        (tab.worktreeRoot ?? tab.workingDirectory)
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
    }
}
