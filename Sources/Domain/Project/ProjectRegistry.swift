// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectRegistry.swift - Durable app-wide project metadata.

import Combine
import Foundation

struct ProjectRecord: Codable, Equatable, Sendable, Identifiable {
    let id: ProjectID
    var lastOpenedAt: Date
    var openCount: Int
    var isPinned: Bool
    var isCollapsed: Bool
    var accent: String?
    var remoteOrigin: String?
    var tags: [String]
    var defaultBaseRef: String?
    var defaultAgents: [String]

    init(
        id: ProjectID,
        lastOpenedAt: Date = .distantPast,
        openCount: Int = 0,
        isPinned: Bool = false,
        isCollapsed: Bool = false,
        accent: String? = nil,
        remoteOrigin: String? = nil,
        tags: [String] = [],
        defaultBaseRef: String? = nil,
        defaultAgents: [String] = []
    ) {
        self.id = id
        self.lastOpenedAt = lastOpenedAt
        self.openCount = max(0, openCount)
        self.isPinned = isPinned
        self.isCollapsed = isCollapsed
        self.accent = accent
        self.remoteOrigin = remoteOrigin
        self.tags = tags
        self.defaultBaseRef = defaultBaseRef
        self.defaultAgents = defaultAgents
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case lastOpenedAt
        case openCount
        case isPinned
        case isCollapsed
        case accent
        case remoteOrigin
        case tags
        case defaultBaseRef
        case defaultAgents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(ProjectID.self, forKey: .id)
        guard id.rawValue.hasPrefix("/"), !id.rawValue.contains("\0") else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "Project ID must be an absolute local path"
            )
        }
        self.init(
            id: id,
            lastOpenedAt: try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
                ?? .distantPast,
            openCount: try container.decodeIfPresent(Int.self, forKey: .openCount) ?? 0,
            isPinned: try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false,
            isCollapsed: try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false,
            accent: try container.decodeIfPresent(String.self, forKey: .accent),
            remoteOrigin: try container.decodeIfPresent(String.self, forKey: .remoteOrigin),
            tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? [],
            defaultBaseRef: try container.decodeIfPresent(String.self, forKey: .defaultBaseRef),
            defaultAgents: try container.decodeIfPresent([String].self, forKey: .defaultAgents) ?? []
        )
    }
}

enum ProjectRegistryStoreError: Error, Equatable, CustomStringConvertible {
    case invalidRoot(String)
    case symbolicLinkRejected(String)
    case invalidRecord(String)
    case persistenceFailed(String)

    var description: String {
        switch self {
        case .invalidRoot(let path):
            return "Project registry root is not a directory: \(path)"
        case .symbolicLinkRejected(let path):
            return "Project registry rejected a symbolic link: \(path)"
        case .invalidRecord(let message):
            return "Project registry contains invalid data: \(message)"
        case .persistenceFailed(let message):
            return "Project registry persistence failed: \(message)"
        }
    }
}

struct ProjectRegistryStore: Sendable {
    let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/projects/registry.json", isDirectory: false),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL.standardizedFileURL
        self.fileManager = fileManager
    }

    func load() throws -> [ProjectRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        do {
            try validateRoot(createIfMissing: false)
            try rejectSymbolicLink(at: fileURL)
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                throw ProjectRegistryStoreError.invalidRecord("Registry is not a regular file")
            }
            let records = try Self.decoder.decode(
                [ProjectRecord].self,
                from: Data(contentsOf: fileURL, options: [.mappedIfSafe])
            )
            guard Set(records.map(\.id)).count == records.count else {
                throw ProjectRegistryStoreError.invalidRecord("Duplicate project IDs")
            }
            return records
        } catch let error as ProjectRegistryStoreError {
            throw error
        } catch {
            throw ProjectRegistryStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    func save(_ records: [ProjectRecord]) throws {
        do {
            guard Set(records.map(\.id)).count == records.count else {
                throw ProjectRegistryStoreError.invalidRecord("Duplicate project IDs")
            }
            try validateRoot(createIfMissing: true)
            if fileManager.fileExists(atPath: fileURL.path) {
                try rejectSymbolicLink(at: fileURL)
            }
            try Self.encoder.encode(records).write(to: fileURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: fileURL.path
            )
        } catch let error as ProjectRegistryStoreError {
            throw error
        } catch {
            throw ProjectRegistryStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    private func validateRoot(createIfMissing: Bool) throws {
        let root = fileURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) {
            try rejectSymbolicLink(at: root)
            guard isDirectory.boolValue else {
                throw ProjectRegistryStoreError.invalidRoot(root.path)
            }
        } else if createIfMissing {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
        } else {
            throw ProjectRegistryStoreError.invalidRoot(root.path)
        }
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: root.path
        )
    }

    private func rejectSymbolicLink(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw ProjectRegistryStoreError.symbolicLinkRejected(url.path)
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

enum ProjectRegistryError: Error, Equatable, CustomStringConvertible {
    case unavailableAfterLoadFailure(String)

    var description: String {
        switch self {
        case .unavailableAfterLoadFailure(let message):
            return "Project registry is read-only after a load failure: \(message)"
        }
    }
}

@MainActor
final class ProjectRegistry: ObservableObject {
    @Published private(set) var records: [ProjectRecord]
    @Published private(set) var persistenceErrorDescription: String?

    private let store: ProjectRegistryStore
    private let clock: () -> Date
    private var canPersist = true

    init(
        store: ProjectRegistryStore = ProjectRegistryStore(),
        clock: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.clock = clock
        do {
            records = try store.load()
            persistenceErrorDescription = nil
        } catch {
            records = []
            persistenceErrorDescription = String(describing: error)
            canPersist = false
        }
        records.sort(by: Self.sortRecords)
    }

    var pinned: [ProjectRecord] {
        records.filter(\.isPinned)
    }

    var recent: [ProjectRecord] {
        records.sorted(by: Self.sortRecords)
    }

    func recordOpen(
        _ descriptor: ProjectDescriptor,
        incrementOpenCount: Bool = true,
        remoteOrigin: String? = nil
    ) throws {
        try mutate { records in
            if let index = records.firstIndex(where: { $0.id == descriptor.groupingID }) {
                records[index].lastOpenedAt = clock()
                if incrementOpenCount {
                    records[index].openCount += 1
                }
                if let remoteOrigin {
                    records[index].remoteOrigin = remoteOrigin
                }
            } else {
                records.append(ProjectRecord(
                    id: descriptor.groupingID,
                    lastOpenedAt: clock(),
                    openCount: incrementOpenCount ? 1 : 0,
                    remoteOrigin: remoteOrigin
                ))
            }
        }
    }

    func setPinned(_ isPinned: Bool, projectID: ProjectID) throws {
        try update(projectID) { $0.isPinned = isPinned }
    }

    func setCollapsed(_ isCollapsed: Bool, projectID: ProjectID) throws {
        try update(projectID) { $0.isCollapsed = isCollapsed }
    }

    func updateConfiguration(
        projectID: ProjectID,
        accent: String?,
        tags: [String],
        defaultBaseRef: String?,
        defaultAgents: [String]
    ) throws {
        try update(projectID) { record in
            record.accent = accent
            record.tags = tags
            record.defaultBaseRef = defaultBaseRef
            record.defaultAgents = defaultAgents
        }
    }

    func forget(_ projectID: ProjectID) throws {
        try mutate { $0.removeAll { $0.id == projectID } }
    }

    func record(for projectID: ProjectID) -> ProjectRecord? {
        records.first { $0.id == projectID }
    }

    private func update(
        _ projectID: ProjectID,
        mutation: (inout ProjectRecord) -> Void
    ) throws {
        try mutate { records in
            guard let index = records.firstIndex(where: { $0.id == projectID }) else { return }
            mutation(&records[index])
        }
    }

    private func mutate(_ mutation: (inout [ProjectRecord]) -> Void) throws {
        guard canPersist else {
            throw ProjectRegistryError.unavailableAfterLoadFailure(
                persistenceErrorDescription ?? "Unknown load failure"
            )
        }
        var updated = records
        mutation(&updated)
        updated.sort(by: Self.sortRecords)
        do {
            try store.save(updated)
            records = updated
            persistenceErrorDescription = nil
        } catch {
            persistenceErrorDescription = String(describing: error)
            throw error
        }
    }

    private static func sortRecords(_ lhs: ProjectRecord, _ rhs: ProjectRecord) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        if lhs.lastOpenedAt != rhs.lastOpenedAt { return lhs.lastOpenedAt > rhs.lastOpenedAt }
        return lhs.id.rawValue.localizedStandardCompare(rhs.id.rawValue) == .orderedAscending
    }
}
