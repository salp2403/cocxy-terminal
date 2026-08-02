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

struct TaskRunStoreLoadReport: Sendable, Equatable {
    let runs: [TaskRun]
    let rejectedFiles: [TaskRunStoreRejectedFile]
}

struct TaskRunStore: Sendable {
    static let fileSuffix = ".run.json"
    static let maximumFileBytes = 1_048_576

    let rootDirectory: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/task-runs", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.fileManager = fileManager
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
            let data = try Self.encoder.encode(run)
            guard data.count <= Self.maximumFileBytes else {
                throw TaskRunStoreError.invalidRun("Encoded run exceeds the storage limit")
            }
            try data.write(to: destination, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: destination.path
            )
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
            return TaskRunStoreLoadReport(runs: runs, rejectedFiles: rejectedFiles)
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
                let run = try Self.decoder.decode(
                    TaskRun.self,
                    from: Data(contentsOf: url, options: [.mappedIfSafe])
                )
                try Self.validate(run)
                guard directory.lastPathComponent == run.projectID.storageKey else {
                    throw TaskRunStoreError.invalidRun("Project directory does not match origin")
                }
                guard url.lastPathComponent == run.id + Self.fileSuffix else {
                    throw TaskRunStoreError.invalidRun("Snapshot filename does not match run id")
                }
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

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

final class TaskRunPersistenceCoordinator: @unchecked Sendable {
    typealias SaveOperation = @Sendable (TaskRun) throws -> Void
    typealias FailureHandler = @Sendable (String) -> Void

    private let queue: DispatchQueue
    private let lock = NSLock()
    private let saveOperation: SaveOperation
    private let failureHandler: FailureHandler
    private var pendingRuns: [String: TaskRun] = [:]
    private var drainScheduled = false

    init(
        store: TaskRunStore,
        label: String = "dev.cocxy.task-run-persistence",
        failureHandler: @escaping FailureHandler = { _ in }
    ) {
        self.queue = DispatchQueue(label: label, qos: .utility)
        self.saveOperation = { try store.save($0) }
        self.failureHandler = failureHandler
    }

    init(
        label: String = "dev.cocxy.task-run-persistence",
        saveOperation: @escaping SaveOperation,
        failureHandler: @escaping FailureHandler = { _ in }
    ) {
        self.queue = DispatchQueue(label: label, qos: .utility)
        self.saveOperation = saveOperation
        self.failureHandler = failureHandler
    }

    func enqueue(_ run: TaskRun) {
        let shouldSchedule = lock.withLock { () -> Bool in
            pendingRuns[run.id] = run
            guard !drainScheduled else { return false }
            drainScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        queue.async { [self] in
            drainPendingRuns()
        }
    }

    func flush() {
        queue.sync { [self] in
            drainPendingRuns()
        }
    }

    private func drainPendingRuns() {
        while true {
            let runs = lock.withLock { () -> [TaskRun] in
                guard !pendingRuns.isEmpty else {
                    drainScheduled = false
                    return []
                }
                let snapshot = pendingRuns.values.sorted { $0.id < $1.id }
                pendingRuns.removeAll(keepingCapacity: true)
                return snapshot
            }
            guard !runs.isEmpty else { return }
            for run in runs {
                do {
                    try saveOperation(run)
                } catch {
                    failureHandler(String(describing: error))
                }
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
