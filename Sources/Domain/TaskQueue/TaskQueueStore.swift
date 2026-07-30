// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskQueueStore.swift - Owner-only atomic persistence for scheduled tasks.

import Foundation

enum TaskQueueStoreError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidRoot(String)
    case symbolicLinkRejected(String)
    case persistenceFailed(String)

    var description: String {
        switch self {
        case .invalidRoot(let path):
            return "Task queue root is not a directory: \(path)"
        case .symbolicLinkRejected(let path):
            return "Task queue persistence rejected a symbolic link: \(path)"
        case .persistenceFailed(let message):
            return "Task queue persistence failed: \(message)"
        }
    }
}

struct TaskQueueStoreRejectedFile: Sendable, Equatable {
    let path: String
    let reason: String
}

struct TaskQueueStoreLoadReport: Sendable, Equatable {
    let items: [TaskQueueItem]
    let rejectedFiles: [TaskQueueStoreRejectedFile]
}

struct TaskQueueStore: Sendable {
    static let fileSuffix = ".task.json"

    let rootDirectory: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/queue", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.fileManager = fileManager
    }

    func save(_ item: TaskQueueItem) throws {
        do {
            try ensureRootDirectory()
            let destination = fileURL(taskID: item.id)
            if fileManager.fileExists(atPath: destination.path) {
                let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard values.isSymbolicLink != true else {
                    throw TaskQueueStoreError.symbolicLinkRejected(destination.path)
                }
            }

            let data = try Self.makeEncoder().encode(item)
            try data.write(to: destination, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: destination.path
            )
        } catch let error as TaskQueueStoreError {
            throw error
        } catch {
            throw TaskQueueStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    func loadAll() throws -> TaskQueueStoreLoadReport {
        do {
            guard fileManager.fileExists(atPath: rootDirectory.path) else {
                return TaskQueueStoreLoadReport(items: [], rejectedFiles: [])
            }
            try ensureRootDirectory()
            let urls = try fileManager.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.lastPathComponent.hasSuffix(Self.fileSuffix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

            var items: [TaskQueueItem] = []
            var rejected: [TaskQueueStoreRejectedFile] = []
            var loadedIDs: Set<String> = []
            for url in urls {
                do {
                    let values = try url.resourceValues(
                        forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                    )
                    guard values.isSymbolicLink != true else {
                        throw TaskQueueStoreError.symbolicLinkRejected(url.path)
                    }
                    guard values.isRegularFile == true else {
                        throw TaskQueueStoreError.persistenceFailed("Not a regular file")
                    }
                    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                    let item = try Self.makeDecoder().decode(TaskQueueItem.self, from: data)
                    try item.validatePersistedState()
                    guard loadedIDs.insert(item.id).inserted else {
                        throw TaskQueueStoreError.persistenceFailed(
                            "Duplicate queued task id: \(item.id)"
                        )
                    }
                    items.append(item)
                } catch {
                    rejected.append(TaskQueueStoreRejectedFile(
                        path: url.path,
                        reason: String(describing: error)
                    ))
                }
            }
            return TaskQueueStoreLoadReport(items: items, rejectedFiles: rejected)
        } catch let error as TaskQueueStoreError {
            throw error
        } catch {
            throw TaskQueueStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    func remove(taskID: String) throws {
        let url = fileURL(taskID: taskID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw TaskQueueStoreError.symbolicLinkRejected(url.path)
            }
            try fileManager.removeItem(at: url)
        } catch let error as TaskQueueStoreError {
            throw error
        } catch {
            throw TaskQueueStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    func fileURL(taskID: String) -> URL {
        let normalized = AgentTeamConfig.slug(taskID)
        return rootDirectory.appendingPathComponent(normalized + Self.fileSuffix, isDirectory: false)
    }

    private func ensureRootDirectory() throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: rootDirectory.path, isDirectory: &isDirectory) {
            let values = try rootDirectory.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw TaskQueueStoreError.symbolicLinkRejected(rootDirectory.path)
            }
            guard isDirectory.boolValue else {
                throw TaskQueueStoreError.invalidRoot(rootDirectory.path)
            }
        } else {
            try fileManager.createDirectory(
                at: rootDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
        }
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: rootDirectory.path
        )
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
