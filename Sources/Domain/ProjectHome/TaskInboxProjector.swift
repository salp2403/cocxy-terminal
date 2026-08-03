// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskInboxProjector.swift - Pure unified project task projection.

import Foundation

enum TaskInboxProjector {
    typealias ProjectResolver = (URL) -> ProjectID

    static func project(
        taskRuns: [TaskRun],
        queueItems: [TaskQueueItem],
        sessions: [SessionEntry],
        dashboardSessions: [AgentSessionInfo],
        resolveProjectID: ProjectResolver
    ) -> [TaskInboxEntry] {
        var entries: [TaskInboxEntry] = []
        let dashboardByTab = Dictionary(grouping: dashboardSessions.filter {
            !$0.id.hasPrefix("handoff-")
        }, by: \.tabId)

        for run in taskRuns {
            let projectID = resolveProjectID(run.originRepoPath)
            let teamIDs = Set(run.candidates.flatMap { [$0.id, $0.teamID] })
            let relatedDashboard = dashboardSessions.filter { teamIDs.contains($0.id) }
            entries.append(TaskInboxEntry(
                id: entryID(kind: .fanOut, sourceID: run.id, projectID: projectID),
                kind: .fanOut,
                projectID: projectID,
                title: run.prompt,
                status: run.status.rawValue,
                agents: uniqueSorted(run.candidates.map { $0.provider.displayName }),
                worktreePaths: uniqueSorted(run.candidates.compactMap { $0.worktree?.path.path }),
                touchedFiles: uniqueSorted(
                    run.candidates.flatMap(\.touchedFiles) + touchedFiles(from: relatedDashboard)
                ),
                updatedAt: run.updatedAt,
                navigation: TaskInboxNavigation(sessionID: run.id)
            ))
        }

        for item in queueItems {
            let projectIDs = queueProjectIDs(item, resolveProjectID: resolveProjectID)
            for projectID in projectIDs {
                entries.append(TaskInboxEntry(
                    id: entryID(kind: .queuedTask, sourceID: item.id, projectID: projectID),
                    kind: .queuedTask,
                    projectID: projectID,
                    title: item.displayName,
                    status: item.status.rawValue,
                    agents: uniqueSorted(item.pipeline.steps.map { $0.provider.displayName }),
                    worktreePaths: uniqueSorted(item.pipeline.steps.compactMap(\.worktree)),
                    updatedAt: item.updatedAt
                ))
            }
        }

        for session in sessions where isLive(session.agentState) {
            let projectID = resolveProjectID(session.workingDirectory)
            let dashboard = dashboardByTab[session.tabID.rawValue]?.max {
                ($0.lastActivityTime ?? .distantPast) < ($1.lastActivityTime ?? .distantPast)
            }
            let agent = dashboard?.agentName ?? session.detectedAgentName
            entries.append(TaskInboxEntry(
                id: entryID(
                    kind: .liveAgent,
                    sourceID: session.sessionID.rawValue.uuidString,
                    projectID: projectID
                ),
                kind: .liveAgent,
                projectID: projectID,
                title: session.title,
                status: dashboard?.state.rawValue ?? session.agentState.rawValue,
                agents: uniqueSorted([agent].compactMap { $0 }),
                touchedFiles: dashboard.map { touchedFiles(from: [$0]) } ?? [],
                updatedAt: dashboard?.lastActivityTime ?? session.createdAt,
                navigation: TaskInboxNavigation(
                    windowID: session.ownerWindowID,
                    tabID: session.tabID,
                    sessionID: dashboard?.id
                )
            ))
        }

        for handoff in dashboardSessions where isPendingHandoff(handoff) {
            guard let projectID = handoff.projectIdentity else { continue }
            let activity = handoff.lastActivity?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = activity.flatMap { $0.isEmpty ? nil : $0 } ?? "Task handoff"
            entries.append(TaskInboxEntry(
                id: entryID(kind: .handoff, sourceID: handoff.id, projectID: projectID),
                kind: .handoff,
                projectID: projectID,
                title: title,
                status: handoff.state.rawValue,
                agents: uniqueSorted([handoff.agentName].compactMap { $0 }),
                touchedFiles: touchedFiles(from: [handoff]),
                updatedAt: handoff.lastActivityTime ?? .distantPast,
                navigation: TaskInboxNavigation(
                    windowID: handoff.windowID,
                    tabID: TabID(rawValue: handoff.tabId),
                    sessionID: handoff.id
                )
            ))
        }

        return deduplicated(entries).sorted(by: precedes)
    }

    private static func queueProjectIDs(
        _ item: TaskQueueItem,
        resolveProjectID: ProjectResolver
    ) -> [ProjectID] {
        var paths: [String] = []
        if let project = item.project { paths.append(project) }
        for step in item.pipeline.steps {
            if let project = step.project { paths.append(project) }
            if let worktree = step.worktree { paths.append(worktree) }
        }
        return Set(paths.map {
            resolveProjectID(URL(fileURLWithPath: $0, isDirectory: true))
        }).sorted { $0.rawValue < $1.rawValue }
    }

    private static func isLive(_ state: AgentState) -> Bool {
        switch state {
        case .launched, .working, .waitingInput, .error:
            return true
        case .idle, .finished:
            return false
        }
    }

    private static func isPendingHandoff(_ session: AgentSessionInfo) -> Bool {
        guard session.id.hasPrefix("handoff-") else { return false }
        return session.state != .finished && session.state != .error
    }

    private static func touchedFiles(from sessions: [AgentSessionInfo]) -> [String] {
        uniqueSorted(sessions.flatMap { session in
            session.filesTouched.map(\.path) + session.fileConflicts
        })
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { !$0.isEmpty })).sorted()
    }

    private static func entryID(
        kind: TaskInboxEntryKind,
        sourceID: String,
        projectID: ProjectID
    ) -> String {
        "\(kind.rawValue):\(sourceID):\(projectID.storageKey)"
    }

    private static func deduplicated(_ entries: [TaskInboxEntry]) -> [TaskInboxEntry] {
        entries.reduce(into: [:]) { (result: inout [String: TaskInboxEntry], entry) in
            guard let current = result[entry.id] else {
                result[entry.id] = entry
                return
            }
            if precedes(entry, current) {
                result[entry.id] = entry
            }
        }.values.map { $0 }
    }

    private static func precedes(_ lhs: TaskInboxEntry, _ rhs: TaskInboxEntry) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        let lhsKind = TaskInboxEntryKind.allCases.firstIndex(of: lhs.kind) ?? .max
        let rhsKind = TaskInboxEntryKind.allCases.firstIndex(of: rhs.kind) ?? .max
        if lhsKind != rhsKind { return lhsKind < rhsKind }
        return lhs.id < rhs.id
    }
}
