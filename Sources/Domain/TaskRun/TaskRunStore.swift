// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskRunStore.swift - Durable project-scoped task run persistence.

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

struct TaskRunStore: Sendable {
    static let fileSuffix = ".run.json"
    static let maximumFileBytes = 1_048_576

    let rootDirectory: URL
    private let fileManager: FileManager
    private let retentionPolicy: TaskRunRetentionPolicy

    init(
        rootDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/task-runs", isDirectory: true),
        fileManager: FileManager = .default,
        retentionPolicy: TaskRunRetentionPolicy = .default
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.fileManager = fileManager
        self.retentionPolicy = retentionPolicy
    }

    func save(_ run: TaskRun) throws {
        do {
            try Self.validate(run)
            try ensureDirectory(rootDirectory)
            let projectDirectory = rootDirectory.appendingPathComponent(
                run.projectID.storageKey,
                isDirectory: true
            )
            try ensureDirectory(projectDirectory)
            let destination = fileURL(for: run)
            if fileManager.fileExists(atPath: destination.path) {
                try rejectSymbolicLink(at: destination)
            }
            let data = try Self.makeEncoder().encode(run)
            guard data.count <= Self.maximumFileBytes else {
                throw TaskRunStoreError.invalidRun("Encoded run exceeds the storage limit")
            }
            try data.write(to: destination, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: destination.path
            )
            let maintenance = try enforceRetention(in: projectDirectory)
            if let failure = maintenance.failures.first {
                throw TaskRunStoreError.persistenceFailed(
                    "Snapshot retention failed for \(failure.path): \(failure.reason)"
                )
            }
        } catch let error as TaskRunStoreError {
            throw error
        } catch {
            throw TaskRunStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    func remove(_ run: TaskRun) throws {
        do {
            try Self.validate(run)
            guard fileManager.fileExists(atPath: rootDirectory.path) else { return }
            try rejectDirectoryIfUnsafe(rootDirectory)
            let projectDirectory = rootDirectory.appendingPathComponent(
                run.projectID.storageKey,
                isDirectory: true
            )
            guard fileManager.fileExists(atPath: projectDirectory.path) else { return }
            try rejectDirectoryIfUnsafe(projectDirectory)
            try removeSnapshot(at: fileURL(for: run))
            try removeDirectoryIfEmpty(projectDirectory)
        } catch let error as TaskRunStoreError {
            throw error
        } catch {
            throw TaskRunStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    func loadAll() throws -> TaskRunStoreLoadReport {
        guard fileManager.fileExists(atPath: rootDirectory.path) else {
            return TaskRunStoreLoadReport(runs: [], rejectedFiles: [])
        }

        do {
            try ensureDirectory(rootDirectory)
            let projectDirectories = try fileManager.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }

            var runs: [TaskRun] = []
            var rejectedFiles: [TaskRunStoreRejectedFile] = []
            var maintenanceFailures: [TaskRunStoreRejectedFile] = []
            var prunedSnapshotCount = 0
            var loadedIDs: Set<String> = []
            for projectDirectory in projectDirectories {
                do {
                    let values = try projectDirectory.resourceValues(
                        forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                    )
                    guard values.isSymbolicLink != true else {
                        throw TaskRunStoreError.symbolicLinkRejected(projectDirectory.path)
                    }
                    guard values.isDirectory == true else { continue }
                    let report = try loadProjectDirectory(
                        projectDirectory,
                        loadedIDs: &loadedIDs
                    )
                    runs.append(contentsOf: report.runs)
                    rejectedFiles.append(contentsOf: report.rejectedFiles)
                    maintenanceFailures.append(contentsOf: report.maintenanceFailures)
                    prunedSnapshotCount += report.prunedSnapshotCount
                } catch {
                    rejectedFiles.append(TaskRunStoreRejectedFile(
                        path: projectDirectory.path,
                        reason: String(describing: error)
                    ))
                }
            }
            runs.sort {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id < $1.id
            }
            return TaskRunStoreLoadReport(
                runs: runs,
                rejectedFiles: rejectedFiles,
                maintenanceFailures: maintenanceFailures,
                prunedSnapshotCount: prunedSnapshotCount
            )
        } catch let error as TaskRunStoreError {
            throw error
        } catch {
            throw TaskRunStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    func fileURL(for run: TaskRun) -> URL {
        rootDirectory
            .appendingPathComponent(run.projectID.storageKey, isDirectory: true)
            .appendingPathComponent(run.id + Self.fileSuffix, isDirectory: false)
    }

    private func loadProjectDirectory(
        _ directory: URL,
        loadedIDs: inout Set<String>
    ) throws -> TaskRunStoreLoadReport {
        let report = try loadProjectDirectoryWithoutRetention(
            directory,
            loadedIDs: &loadedIDs
        )
        let maintenance = try enforceRetention(on: report.runs, in: directory)
        let prunedIDs = Set(maintenance.prunedRuns.map(\.id))
        return TaskRunStoreLoadReport(
            runs: report.runs.filter { !prunedIDs.contains($0.id) },
            rejectedFiles: report.rejectedFiles,
            maintenanceFailures: maintenance.failures,
            prunedSnapshotCount: maintenance.prunedRuns.count
        )
    }

    private func enforceRetention(
        in directory: URL
    ) throws -> (prunedRuns: [TaskRun], failures: [TaskRunStoreRejectedFile]) {
        var loadedIDs: Set<String> = []
        let report = try loadProjectDirectoryWithoutRetention(
            directory,
            loadedIDs: &loadedIDs
        )
        return try enforceRetention(on: report.runs, in: directory)
    }

    private func loadProjectDirectoryWithoutRetention(
        _ directory: URL,
        loadedIDs: inout Set<String>
    ) throws -> TaskRunStoreLoadReport {
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.lastPathComponent.hasSuffix(Self.fileSuffix) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var runs: [TaskRun] = []
        var rejectedFiles: [TaskRunStoreRejectedFile] = []
        for url in urls {
            do {
                let run = try loadRun(at: url, projectDirectory: directory)
                guard loadedIDs.insert(run.id).inserted else {
                    throw TaskRunStoreError.invalidRun("Duplicate task run id: \(run.id)")
                }
                runs.append(run)
            } catch {
                rejectedFiles.append(TaskRunStoreRejectedFile(
                    path: url.path,
                    reason: String(describing: error)
                ))
            }
        }
        return TaskRunStoreLoadReport(runs: runs, rejectedFiles: rejectedFiles)
    }

    private func enforceRetention(
        on runs: [TaskRun],
        in directory: URL
    ) throws -> (prunedRuns: [TaskRun], failures: [TaskRunStoreRejectedFile]) {
        let finished = runs.filter(\.status.isFinished).sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id < rhs.id
        }
        let prunable = finished.dropFirst(retentionPolicy.maximumFinishedRunsPerProject)
        var prunedRuns: [TaskRun] = []
        var failures: [TaskRunStoreRejectedFile] = []
        for run in prunable {
            let url = directory.appendingPathComponent(
                run.id + Self.fileSuffix,
                isDirectory: false
            )
            do {
                try removeSnapshot(at: url)
                prunedRuns.append(run)
            } catch {
                failures.append(TaskRunStoreRejectedFile(
                    path: url.path,
                    reason: String(describing: error)
                ))
            }
        }
        return (prunedRuns, failures)
    }

    private func loadRun(at url: URL, projectDirectory: URL) throws -> TaskRun {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard values.isSymbolicLink != true else {
            throw TaskRunStoreError.symbolicLinkRejected(url.path)
        }
        guard values.isRegularFile == true else {
            throw TaskRunStoreError.invalidRun("Run snapshot is not a regular file")
        }
        guard (values.fileSize ?? 0) <= Self.maximumFileBytes else {
            throw TaskRunStoreError.invalidRun("Run snapshot exceeds the storage limit")
        }
        let run = try Self.makeDecoder().decode(
            TaskRun.self,
            from: Data(contentsOf: url, options: [.mappedIfSafe])
        )
        try Self.validate(run)
        guard projectDirectory.lastPathComponent == run.projectID.storageKey else {
            throw TaskRunStoreError.invalidRun("Project directory does not match origin")
        }
        guard url.lastPathComponent == run.id + Self.fileSuffix else {
            throw TaskRunStoreError.invalidRun("Snapshot filename does not match run id")
        }
        return run
    }

    private func rejectDirectoryIfUnsafe(_ directory: URL) throws {
        let values = try directory.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard values.isSymbolicLink != true else {
            throw TaskRunStoreError.symbolicLinkRejected(directory.path)
        }
        guard values.isDirectory == true else {
            throw TaskRunStoreError.invalidRoot(directory.path)
        }
    }

    private func removeSnapshot(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values.isSymbolicLink != true else {
            throw TaskRunStoreError.symbolicLinkRejected(url.path)
        }
        guard values.isRegularFile == true else {
            throw TaskRunStoreError.invalidRun("Run snapshot is not a regular file")
        }
        try fileManager.removeItem(at: url)
    }

    private func removeDirectoryIfEmpty(_ directory: URL) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        )
        guard contents.isEmpty else { return }
        try rejectDirectoryIfUnsafe(directory)
        try fileManager.removeItem(at: directory)
    }

    private func ensureDirectory(_ directory: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            try rejectSymbolicLink(at: directory)
            guard isDirectory.boolValue else {
                throw TaskRunStoreError.invalidRoot(directory.path)
            }
        } else {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
        }
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: directory.path
        )
    }

    private func rejectSymbolicLink(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw TaskRunStoreError.symbolicLinkRejected(url.path)
        }
    }

    private static func validate(_ run: TaskRun) throws {
        guard !run.id.isEmpty, run.id == AgentTeamConfig.slug(run.id) else {
            throw TaskRunStoreError.invalidRun("Invalid task run id")
        }
        guard run.originRepoPath.path.hasPrefix("/"),
              !run.originRepoPath.path.contains("\0") else {
            throw TaskRunStoreError.invalidRun("Origin repository must be an absolute local path")
        }
        guard !run.baseCommit.isEmpty, !run.baseCommit.contains("\0") else {
            throw TaskRunStoreError.invalidRun("Invalid base commit")
        }
        guard Set(run.candidates.map(\.id)).count == run.candidates.count,
              Set(run.candidates.map(\.teamID)).count == run.candidates.count else {
            throw TaskRunStoreError.invalidRun("Duplicate candidate identity")
        }
        for candidate in run.candidates {
            guard !candidate.id.isEmpty, !candidate.teamID.isEmpty else {
                throw TaskRunStoreError.invalidRun("Empty candidate identity")
            }
            if let path = candidate.worktree?.path.path,
               !path.hasPrefix("/") || path.contains("\0") {
                throw TaskRunStoreError.invalidRun("Worktree path must be absolute")
            }
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum TaskRunPersistenceEvent: Sendable, Equatable {
    case saved(runID: String)
    case failed(runID: String, message: String)
}

final class TaskRunPersistenceCoordinator: @unchecked Sendable {
    private struct PendingRun {
        let run: TaskRun
        let generation: UInt64
    }

    typealias SaveOperation = @Sendable (TaskRun) throws -> Void
    typealias EventHandler = @Sendable (TaskRunPersistenceEvent) -> Void

    private let queue: DispatchQueue
    private let lock = NSLock()
    private let saveOperation: SaveOperation
    private let eventHandler: EventHandler
    private let maximumRetryAttempts: Int
    private let retryDelay: TimeInterval
    private var pendingRuns: [String: PendingRun] = [:]
    private var suppressionCounts: [String: Int] = [:]
    private var nextGeneration: UInt64 = 0
    private var drainScheduled = false

    init(
        store: TaskRunStore,
        label: String = "dev.cocxy.task-run-persistence",
        maximumRetryAttempts: Int = 3,
        retryDelay: TimeInterval = 0.05,
        eventHandler: @escaping EventHandler = { _ in }
    ) {
        self.queue = DispatchQueue(label: label, qos: .utility)
        self.saveOperation = { try store.save($0) }
        self.eventHandler = eventHandler
        self.maximumRetryAttempts = max(1, maximumRetryAttempts)
        self.retryDelay = max(0, retryDelay)
    }

    init(
        label: String = "dev.cocxy.task-run-persistence",
        maximumRetryAttempts: Int = 3,
        retryDelay: TimeInterval = 0.05,
        saveOperation: @escaping SaveOperation,
        eventHandler: @escaping EventHandler = { _ in }
    ) {
        self.queue = DispatchQueue(label: label, qos: .utility)
        self.saveOperation = saveOperation
        self.eventHandler = eventHandler
        self.maximumRetryAttempts = max(1, maximumRetryAttempts)
        self.retryDelay = max(0, retryDelay)
    }

    func enqueue(_ run: TaskRun) {
        let shouldSchedule = lock.withLock { () -> Bool in
            nextGeneration &+= 1
            pendingRuns[run.id] = PendingRun(run: run, generation: nextGeneration)
            guard suppressionCounts[run.id] == nil else { return false }
            guard !drainScheduled else { return false }
            drainScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        queue.async { [self] in
            drainPendingRuns()
        }
    }

    func suppress(runID: String) {
        lock.withLock {
            let count = suppressionCounts[runID, default: 0]
            suppressionCounts[runID] = count + 1
            if count == 0 {
                pendingRuns.removeValue(forKey: runID)
            }
        }
    }

    func resume(runID: String, replaying fallbackRun: TaskRun? = nil) {
        let shouldSchedule = lock.withLock { () -> Bool in
            guard let count = suppressionCounts[runID] else { return false }
            if pendingRuns[runID] == nil, let fallbackRun {
                nextGeneration &+= 1
                pendingRuns[runID] = PendingRun(
                    run: fallbackRun,
                    generation: nextGeneration
                )
            }
            if count > 1 {
                suppressionCounts[runID] = count - 1
                return false
            }
            suppressionCounts.removeValue(forKey: runID)
            guard pendingRuns[runID] != nil, !drainScheduled else { return false }
            drainScheduled = true
            return true
        }
        if shouldSchedule {
            queue.async { [self] in drainPendingRuns() }
        }
    }

    func discard(runID: String) {
        lock.withLock {
            suppressionCounts.removeValue(forKey: runID)
            pendingRuns.removeValue(forKey: runID)
        }
    }

    func flush() {
        queue.sync { [self] in
            drainPendingRuns()
        }
    }

    func performExclusive(_ operation: @escaping @Sendable () throws -> Void) throws {
        try queue.sync(execute: operation)
    }

    func performExclusiveSave(_ run: TaskRun) throws {
        try queue.sync { [saveOperation] in
            try saveOperation(run)
        }
    }

    private func drainPendingRuns() {
        while true {
            let pending = lock.withLock { () -> PendingRun? in
                guard let next = pendingRuns.values.sorted(by: {
                    if $0.run.id != $1.run.id { return $0.run.id < $1.run.id }
                    return $0.generation < $1.generation
                }).first(where: { suppressionCounts[$0.run.id] == nil }) else {
                    drainScheduled = false
                    return nil
                }
                if pendingRuns[next.run.id]?.generation == next.generation {
                    pendingRuns.removeValue(forKey: next.run.id)
                }
                return next
            }
            guard let pending else { return }

            var finalError: Error?
            for attempt in 1...maximumRetryAttempts {
                do {
                    try saveOperation(pending.run)
                    finalError = nil
                    break
                } catch {
                    finalError = error
                    if attempt < maximumRetryAttempts, retryDelay > 0 {
                        Thread.sleep(forTimeInterval: retryDelay)
                    }
                }
            }

            let shouldReport = lock.withLock {
                guard suppressionCounts[pending.run.id] == nil else { return false }
                return (pendingRuns[pending.run.id]?.generation ?? pending.generation)
                    <= pending.generation
            }
            guard shouldReport else { continue }
            if let finalError {
                eventHandler(.failed(
                    runID: pending.run.id,
                    message: String(describing: finalError)
                ))
            } else {
                eventHandler(.saved(runID: pending.run.id))
            }
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
