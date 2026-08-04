// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

enum TaskRunStoreError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidRoot(String)
    case symbolicLinkRejected(String)
    case invalidRun(String)
    case persistenceFailed(String)

    var description: String {
        switch self {
        case .invalidRoot(let path):
            return "Task run root is not a directory: \(path)"
        case .symbolicLinkRejected(let path):
            return "Task run persistence rejected a symbolic link: \(path)"
        case .invalidRun(let reason):
            return "Task run persistence contains invalid data: \(reason)"
        case .persistenceFailed(let message):
            return "Task run persistence failed: \(message)"
        }
    }
}

struct TaskRunStoreRejectedFile: Sendable, Equatable {
    let path: String
    let reason: String
}

struct TaskRunRetentionPolicy: Sendable, Equatable {
    static let `default` = TaskRunRetentionPolicy(maximumFinishedRunsPerProject: 32)

    let maximumFinishedRunsPerProject: Int

    init(maximumFinishedRunsPerProject: Int) {
        self.maximumFinishedRunsPerProject = max(0, maximumFinishedRunsPerProject)
    }
}

struct TaskRunStoreLoadReport: Sendable, Equatable {
    let runs: [TaskRun]
    let rejectedFiles: [TaskRunStoreRejectedFile]
    let maintenanceFailures: [TaskRunStoreRejectedFile]
    let prunedSnapshotCount: Int

    init(
        runs: [TaskRun],
        rejectedFiles: [TaskRunStoreRejectedFile],
        maintenanceFailures: [TaskRunStoreRejectedFile] = [],
        prunedSnapshotCount: Int = 0
    ) {
        self.runs = runs
        self.rejectedFiles = rejectedFiles
        self.maintenanceFailures = maintenanceFailures
        self.prunedSnapshotCount = prunedSnapshotCount
    }
}
