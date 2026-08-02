// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+ProjectCLI.swift - App-owned project CLI operations.

import Foundation

private struct ProjectCLIProjectPayload: Codable {
    let id: String
    let name: String
    let path: String
    let parentPath: String
    let lastOpenedAt: Date
    let openCount: Int
    let isPinned: Bool
    let isCollapsed: Bool
    let isLive: Bool
    let isAvailable: Bool
    let accent: String?
    let remoteOrigin: String?
    let tags: [String]
    let defaultBaseRef: String?
    let defaultAgents: [String]
}

private struct ProjectCLITaskPayload: Codable {
    let id: String
    let kind: String
    let title: String
    let status: String
    let projectIDs: [String]
    let createdAt: Date
    let updatedAt: Date
    let agentCount: Int
    let estimatedCostMicros: Int64
}

private enum ProjectCLIRequestError: Error, LocalizedError {
    case unauthorizedOpen
    case unknownProject(String)
    case registryUnavailable(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unauthorizedOpen:
            return "Approved project-open context is unavailable"
        case .unknownProject(let path):
            return "Project is not registered or available: \(path)"
        case .registryUnavailable(let message):
            return "Project registry is unavailable: \(message)"
        case .encodingFailed:
            return "Project command response could not be encoded"
        }
    }
}

extension AppDelegate {
    nonisolated func handleProjectCLIRequest(
        kind: String,
        params: [String: String],
        approvedContext: SocketPrivilegedCommandContext? = nil
    ) -> (success: Bool, data: [String: String]) {
        let semaphore = DispatchSemaphore(value: 0)
        let result = LockedBox<(Bool, [String: String])>((
            false,
            ["error": "Project dispatch did not complete"]
        ))
        Task.detached { [self] in
            let value = await performProjectCLIRequest(
                kind: kind,
                params: params,
                approvedContext: approvedContext
            )
            result.withValue { $0 = value }
            semaphore.signal()
        }
        semaphore.wait()
        return result.withValue { $0 }
    }

    nonisolated private func performProjectCLIRequest(
        kind: String,
        params: [String: String],
        approvedContext: SocketPrivilegedCommandContext?
    ) async -> (Bool, [String: String]) {
        do {
            switch kind {
            case "open":
                guard let context = approvedContext,
                      context.scope == .project,
                      let bound = context.bindingLocalResourcePaths(
                        in: params,
                        keys: ["path"],
                        requiredScope: .project
                      ),
                      let path = bound["path"],
                      path == context.workingDirectory else {
                    throw ProjectCLIRequestError.unauthorizedOpen
                }
                return try await MainActor.run { try openProjectForCLI(path: path) }
            case "list":
                return try await MainActor.run { try listProjectsForCLI() }
            case "pin", "unpin", "alias", "forget":
                return try await MainActor.run {
                    try mutateProjectForCLI(kind: kind, params: params)
                }
            case "clone":
                let clone = try ProjectCloneService().clone(
                    remote: params["remote"] ?? "",
                    into: URL(fileURLWithPath: params["parent"] ?? "", isDirectory: true)
                )
                return try await MainActor.run { try finishProjectCloneForCLI(clone) }
            case "tasks":
                return try await projectTasksForCLI(projectReference: params["project"])
            default:
                return (false, ["error": "Unknown project action: \(kind)"])
            }
        } catch {
            return (false, ["error": error.localizedDescription])
        }
    }

    @MainActor
    private func openProjectForCLI(path: String) throws -> (Bool, [String: String]) {
        let root = URL(fileURLWithPath: path, isDirectory: true)
        projectResolver.invalidate(directory: root)
        let descriptor = projectResolver.resolveProject(for: root)
        guard descriptor.groupingRootURL.resolvingSymlinksInPath().standardizedFileURL.path == path else {
            throw ProjectCLIRequestError.unauthorizedOpen
        }
        try projectRegistry.recordOpen(descriptor, incrementOpenCount: false)
        let tabID = try activateProject(descriptor.groupingID)
        return (true, [
            "status": "opened",
            "project-id": descriptor.groupingID.rawValue,
            "path": descriptor.groupingRootURL.path,
            "tab-id": tabID.rawValue.uuidString,
            "name": projectDisplayName(for: descriptor.groupingID),
        ])
    }

    @MainActor
    private func listProjectsForCLI() throws -> (Bool, [String: String]) {
        try requireProjectRegistry()
        let liveIDs = liveProjectIDs()
        let payloads = projectRegistry.records.map { record in
            projectPayload(record: record, liveIDs: liveIDs)
        }
        return (true, [
            "status": "listed",
            "count": String(payloads.count),
            "projects": try encodeProjectCLI(payloads),
            "summary": projectSummary(payloads),
        ])
    }

    @MainActor
    private func mutateProjectForCLI(
        kind: String,
        params: [String: String]
    ) throws -> (Bool, [String: String]) {
        try requireProjectRegistry()
        let reference = params["project"] ?? ""
        let projectID = try resolveProjectReference(reference, registerIfAvailable: kind != "forget")
        switch kind {
        case "pin":
            try projectRegistry.setPinned(true, projectID: projectID)
        case "unpin":
            try projectRegistry.setPinned(false, projectID: projectID)
        case "alias":
            auroraWorkspaceTitleStore.setTitle(params["alias"], for: projectID.rawValue)
        case "forget":
            try projectRegistry.forget(projectID)
        default:
            preconditionFailure("Project mutation routing drifted")
        }
        let status = ["pin": "pinned", "unpin": "unpinned", "alias": "aliased"][kind]
            ?? "forgotten"
        return (true, [
            "status": status,
            "project-id": projectID.rawValue,
            "path": projectID.rawValue,
            "name": projectDisplayName(for: projectID),
        ])
    }

    @MainActor
    private func finishProjectCloneForCLI(
        _ clone: ProjectCloneResult
    ) throws -> (Bool, [String: String]) {
        projectResolver.invalidate(directory: clone.rootURL)
        gitInfoProvider.invalidateCache(for: clone.rootURL)
        let descriptor = projectResolver.resolveProject(for: clone.rootURL)
        var warning: String?
        do {
            try projectRegistry.recordOpen(
                descriptor,
                incrementOpenCount: false,
                remoteOrigin: clone.remoteOrigin
            )
        } catch {
            warning = error.localizedDescription
        }
        let tabID = try activateProject(descriptor.groupingID)
        var data = [
            "status": "cloned",
            "project-id": descriptor.groupingID.rawValue,
            "path": descriptor.groupingRootURL.path,
            "tab-id": tabID.rawValue.uuidString,
            "remote": clone.remoteOrigin,
        ]
        if let warning { data["warning"] = warning }
        return (true, data)
    }

    nonisolated private func projectTasksForCLI(
        projectReference: String?
    ) async throws -> (Bool, [String: String]) {
        let filter = try await MainActor.run {
            try projectReference.map { try resolveProjectReference($0, registerIfAvailable: false) }
        }
        let queue = await MainActor.run { taskQueueIsReady ? taskQueue : nil }
        let queuedItems = await queue?.list() ?? []
        let runs = await MainActor.run { taskRunsSnapshot() }
        let payloads = await MainActor.run {
            projectTaskPayloads(queueItems: queuedItems, runs: runs, filter: filter)
        }
        var data = [
            "status": "listed",
            "count": String(payloads.count),
            "tasks": try encodeProjectCLI(payloads),
            "summary": projectTaskSummary(payloads),
        ]
        if queue == nil {
            data["warning"] = "Persistent task queue is still starting or unavailable"
        }
        return (true, data)
    }

    @MainActor
    private func projectTaskPayloads(
        queueItems: [TaskQueueItem],
        runs: [TaskRun],
        filter: ProjectID?
    ) -> [ProjectCLITaskPayload] {
        let queued = queueItems.compactMap { item -> ProjectCLITaskPayload? in
            let projectIDs = Set(item.pipeline.steps.compactMap { step in
                step.worktree.map {
                    projectResolver.resolveProject(
                        for: URL(fileURLWithPath: $0, isDirectory: true)
                    ).groupingID.rawValue
                }
            }).sorted()
            guard filter.map({ projectIDs.contains($0.rawValue) }) ?? true else { return nil }
            return ProjectCLITaskPayload(
                id: item.id,
                kind: "queued",
                title: item.displayName,
                status: item.status.rawValue,
                projectIDs: projectIDs,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                agentCount: item.pipeline.steps.count,
                estimatedCostMicros: 0
            )
        }
        let active = runs.compactMap { run -> ProjectCLITaskPayload? in
            let projectID = projectResolver.resolveProject(for: run.originRepoPath).groupingID
            guard filter.map({ $0 == projectID }) ?? true else { return nil }
            return ProjectCLITaskPayload(
                id: run.id,
                kind: "parallel",
                title: run.id,
                status: run.status.rawValue,
                projectIDs: [projectID.rawValue],
                createdAt: run.createdAt,
                updatedAt: run.updatedAt,
                agentCount: run.candidates.count,
                estimatedCostMicros: run.candidates.reduce(0) { $0 + $1.estimatedCostMicros }
            )
        }
        return (queued + active).sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            if $0.kind != $1.kind { return $0.kind < $1.kind }
            return $0.id < $1.id
        }
    }

    @MainActor
    private func resolveProjectReference(
        _ reference: String,
        registerIfAvailable: Bool
    ) throws -> ProjectID {
        let candidate = URL(fileURLWithPath: reference, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            let descriptor = projectResolver.resolveProject(for: candidate)
            if registerIfAvailable, projectRegistry.record(for: descriptor.groupingID) == nil {
                try projectRegistry.recordOpen(descriptor, incrementOpenCount: false)
            }
            return descriptor.groupingID
        }
        let exactID = ProjectID(rawValue: reference)
        guard projectRegistry.record(for: exactID) != nil else {
            throw ProjectCLIRequestError.unknownProject(reference)
        }
        return exactID
    }

    @MainActor
    private func requireProjectRegistry() throws {
        if let error = projectRegistry.persistenceErrorDescription {
            throw ProjectCLIRequestError.registryUnavailable(error)
        }
    }

    @MainActor
    private func projectPayload(
        record: ProjectRecord,
        liveIDs: Set<String>
    ) -> ProjectCLIProjectPayload {
        let root = URL(fileURLWithPath: record.id.rawValue, isDirectory: true)
        var isDirectory: ObjCBool = false
        let available = FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
        return ProjectCLIProjectPayload(
            id: record.id.rawValue,
            name: projectDisplayName(for: record.id),
            path: record.id.rawValue,
            parentPath: root.deletingLastPathComponent().path,
            lastOpenedAt: record.lastOpenedAt,
            openCount: record.openCount,
            isPinned: record.isPinned,
            isCollapsed: record.isCollapsed,
            isLive: liveIDs.contains(record.id.rawValue),
            isAvailable: available,
            accent: record.accent,
            remoteOrigin: record.remoteOrigin,
            tags: record.tags,
            defaultBaseRef: record.defaultBaseRef,
            defaultAgents: record.defaultAgents
        )
    }

    @MainActor
    private func projectDisplayName(for projectID: ProjectID) -> String {
        auroraWorkspaceTitleStore.title(for: projectID.rawValue)
            ?? ProjectDescriptor.automaticName(
                for: URL(fileURLWithPath: projectID.rawValue, isDirectory: true)
            )
    }

    nonisolated private func encodeProjectCLI<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let result = String(data: try encoder.encode(value), encoding: .utf8) else {
            throw ProjectCLIRequestError.encodingFailed
        }
        return result
    }

    nonisolated private func projectSummary(_ projects: [ProjectCLIProjectPayload]) -> String {
        guard !projects.isEmpty else { return "No registered projects." }
        return projects.map { project in
            let state = project.isAvailable ? (project.isLive ? "live" : "dormant") : "unavailable"
            let pin = project.isPinned ? " pinned" : ""
            return "[\(state)\(pin)] \(project.name) - \(project.path)"
        }.joined(separator: "\n")
    }

    nonisolated private func projectTaskSummary(_ tasks: [ProjectCLITaskPayload]) -> String {
        guard !tasks.isEmpty else { return "No project tasks." }
        return tasks.map {
            "[\($0.status)] \($0.title) (\($0.kind), \($0.agentCount) agents)"
        }.joined(separator: "\n")
    }
}
