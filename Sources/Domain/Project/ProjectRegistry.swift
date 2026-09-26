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
        let rawID = try container.decode(String.self, forKey: .id)
        guard rawID.hasPrefix("/"), !rawID.contains("\0") else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "Project ID must be an absolute local path"
            )
        }
        self.init(
            id: ProjectID(rawValue: rawID),
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
    @Published private(set) var recoveryDiagnostic: ProjectRegistryRecoveryDiagnostic?
    let recordsDidChange = PassthroughSubject<[ProjectRecord], Never>()
    /// Receives the durable incoming snapshot before `@Published` emits in `willSet`.
    var recordsWillPublish: (([ProjectRecord]) -> Void)?

    private let store: ProjectRegistryStore
    private let clock: () -> Date
    private var canPersist: Bool

    init(
        store: ProjectRegistryStore = ProjectRegistryStore(),
        clock: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.clock = clock
        let outcome = Self.loadOutcome(from: store)
        records = outcome.records
        persistenceErrorDescription = outcome.persistenceErrorDescription
        recoveryDiagnostic = outcome.recoveryDiagnostic
        canPersist = outcome.canPersist
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
        if !canPersist {
            reloadAfterLoadFailure()
        }
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
            recordsWillPublish?(updated)
            records = updated
            persistenceErrorDescription = nil
            recordsDidChange.send(updated)
        } catch {
            persistenceErrorDescription = String(describing: error)
            throw error
        }
    }

    /// A registry that could not be read or repaired stays read-only
    /// until the file loads cleanly again; each write attempt retries.
    private func reloadAfterLoadFailure() {
        let outcome = Self.loadOutcome(from: store)
        guard outcome.canPersist else { return }
        recordsWillPublish?(outcome.records)
        records = outcome.records
        persistenceErrorDescription = outcome.persistenceErrorDescription
        recoveryDiagnostic = outcome.recoveryDiagnostic
        canPersist = true
        recordsDidChange.send(outcome.records)
    }

    private struct LoadOutcome {
        let records: [ProjectRecord]
        let persistenceErrorDescription: String?
        let recoveryDiagnostic: ProjectRegistryRecoveryDiagnostic?
        let canPersist: Bool
    }

    private static func loadOutcome(from store: ProjectRegistryStore) -> LoadOutcome {
        let report: ProjectRegistryStoreLoadReport
        do {
            report = try store.loadReport()
        } catch {
            return LoadOutcome(
                records: [],
                persistenceErrorDescription: String(describing: error),
                recoveryDiagnostic: nil,
                canPersist: false
            )
        }
        var diagnostic: ProjectRegistryRecoveryDiagnostic?
        if let quarantineFileURL = report.quarantineFileURL, !report.discardedRecords.isEmpty {
            diagnostic = ProjectRegistryRecoveryDiagnostic(
                discardedRecordCount: report.discardedRecordCount,
                discardedRecordIdentities: report.discardedRecords.map(\.identity),
                discardedRecordReasons: report.discardedRecords.map(\.reason),
                quarantineFileURL: quarantineFileURL,
                recoveredWholeDocument: report.recoveredWholeDocument
            )
        }
        return LoadOutcome(
            records: report.records.sorted(by: sortRecords),
            persistenceErrorDescription: report.repairFailure.map { String(describing: $0) },
            recoveryDiagnostic: diagnostic,
            canPersist: report.allowsPersistence
        )
    }

    private static func sortRecords(_ lhs: ProjectRecord, _ rhs: ProjectRecord) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        if lhs.lastOpenedAt != rhs.lastOpenedAt { return lhs.lastOpenedAt > rhs.lastOpenedAt }
        return lhs.id.rawValue.localizedStandardCompare(rhs.id.rawValue) == .orderedAscending
    }
}
