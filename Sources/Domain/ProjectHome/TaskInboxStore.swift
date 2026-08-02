// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskInboxStore.swift - App-scoped atomic task inbox snapshots.

import Combine
import Foundation

enum TaskInboxSource: String, CaseIterable, Sendable {
    case taskRuns
    case queue
    case sessions
    case dashboard
}

struct TaskInboxIssue: Equatable, Sendable {
    let source: TaskInboxSource
    let message: String
}

enum TaskInboxAvailability: Equatable, Sendable {
    case loading
    case partial([TaskInboxIssue])
    case ready
    case failed([TaskInboxIssue])
}

struct TaskInboxSnapshot: Equatable, Sendable {
    let entries: [TaskInboxEntry]
    let badgeCounts: [String: Int]
    let availability: TaskInboxAvailability

    static let loading = TaskInboxSnapshot(entries: [], badgeCounts: [:], availability: .loading)
}

@MainActor
final class TaskInboxStore: ObservableObject {
    @Published private(set) var snapshot: TaskInboxSnapshot = .loading

    private enum SourcePhase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private let projectResolver: any ProjectResolving
    private var taskRuns: [TaskRun] = []
    private var queueItems: [TaskQueueItem] = []
    private var sessions: [SessionEntry] = []
    private var dashboardSessions: [AgentSessionInfo] = []
    private var phases = Dictionary(
        uniqueKeysWithValues: TaskInboxSource.allCases.map { ($0, SourcePhase.loading) }
    )
    private var sourceCancellables: Set<AnyCancellable> = []

    init(projectResolver: any ProjectResolving) {
        self.projectResolver = projectResolver
    }

    func connect(
        sessionRegistry: SessionRegistryImpl?,
        dashboard: AgentDashboardViewModel?
    ) {
        sourceCancellables.removeAll()

        if let sessionRegistry {
            updateSessions(sessionRegistry.allSessions)
            let changes = Publishers.Merge3(
                sessionRegistry.sessionAdded.map { _ in () }.eraseToAnyPublisher(),
                sessionRegistry.sessionRemoved.map { _ in () }.eraseToAnyPublisher(),
                sessionRegistry.sessionUpdated.map { _ in () }.eraseToAnyPublisher()
            )
            changes.sink { [weak self, weak sessionRegistry] in
                guard let self, let sessionRegistry else { return }
                self.updateSessions(sessionRegistry.allSessions)
            }.store(in: &sourceCancellables)
        } else {
            markFailed(.sessions, message: "Live session registry is unavailable")
        }

        if let dashboard {
            updateDashboardSessions(dashboard.sessions)
            dashboard.sessionsPublisher.sink { [weak self] sessions in
                self?.updateDashboardSessions(sessions)
            }.store(in: &sourceCancellables)
        } else {
            markFailed(.dashboard, message: "Agent activity is unavailable")
        }
    }

    func updateTaskRuns(_ runs: [TaskRun]) {
        taskRuns = runs
        phases[.taskRuns] = .ready
        rebuild()
    }

    func updateQueueItems(_ items: [TaskQueueItem]) {
        queueItems = items
        phases[.queue] = .ready
        rebuild()
    }

    func updateSessions(_ entries: [SessionEntry]) {
        sessions = entries
        phases[.sessions] = .ready
        rebuild()
    }

    func updateDashboardSessions(_ entries: [AgentSessionInfo]) {
        dashboardSessions = entries
        phases[.dashboard] = .ready
        rebuild()
    }

    func markFailed(_ source: TaskInboxSource, message: String) {
        phases[source] = .failed(message)
        rebuild()
    }

    func entries(for projectID: ProjectID) -> [TaskInboxEntry] {
        snapshot.entries.filter { $0.projectID == projectID }
    }

    private func rebuild() {
        let entries = TaskInboxProjector.project(
            taskRuns: taskRuns,
            queueItems: queueItems,
            sessions: sessions,
            dashboardSessions: dashboardSessions,
            resolveProjectID: { [projectResolver] directory in
                projectResolver.resolveProject(for: directory).groupingID
            }
        )
        snapshot = TaskInboxSnapshot(
            entries: entries,
            badgeCounts: Self.badgeCounts(entries),
            availability: availability()
        )
    }

    private func availability() -> TaskInboxAvailability {
        let readyCount = phases.values.filter { $0 == .ready }.count
        let issues = phases.compactMap { source, phase -> TaskInboxIssue? in
            switch phase {
            case .loading:
                return TaskInboxIssue(source: source, message: "Loading")
            case .ready:
                return nil
            case .failed(let message):
                return TaskInboxIssue(source: source, message: message)
            }
        }.sorted { $0.source.rawValue < $1.source.rawValue }

        if readyCount == TaskInboxSource.allCases.count { return .ready }
        if readyCount > 0 { return .partial(issues) }
        if phases.values.contains(where: {
            if case .failed = $0 { return true }
            return false
        }) {
            return .failed(issues)
        }
        return .loading
    }

    private static func badgeCounts(_ entries: [TaskInboxEntry]) -> [String: Int] {
        let terminalStatuses: Set<String> = [
            "cancelled", "completed", "error", "failed", "finished", "succeeded",
        ]
        return entries.reduce(into: [:]) { result, entry in
            guard entry.kind != .liveAgent, !terminalStatuses.contains(entry.status) else { return }
            result[entry.projectID.rawValue, default: 0] += 1
        }
    }
}
