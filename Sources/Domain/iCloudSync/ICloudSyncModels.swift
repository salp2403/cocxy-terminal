// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ICloudSyncModels.swift - Local-only iCloud Drive sync domain models.

import Foundation

enum ICloudSyncArtifactKind: String, Codable, Sendable, Equatable, CaseIterable, Comparable {
    case notebooks
    case workflows
    case skills
    case settings
    case themes

    static func < (lhs: ICloudSyncArtifactKind, rhs: ICloudSyncArtifactKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ICloudSyncConflictPolicy: String, Codable, Sendable, Equatable {
    case manual
}

struct ICloudSyncConfig: Codable, Sendable, Equatable {
    static let defaultSyncDirectoryName = "Cocxy"
    static let defaultArtifactKinds = ICloudSyncArtifactKind.allCases

    let enabled: Bool
    let syncDirectoryName: String
    let encryptionRequired: Bool
    let artifactKinds: [ICloudSyncArtifactKind]
    let conflictPolicy: ICloudSyncConflictPolicy

    static var defaults: ICloudSyncConfig {
        ICloudSyncConfig(
            enabled: false,
            syncDirectoryName: defaultSyncDirectoryName,
            encryptionRequired: true,
            artifactKinds: defaultArtifactKinds,
            conflictPolicy: .manual
        )
    }

    init(
        enabled: Bool = false,
        syncDirectoryName: String = defaultSyncDirectoryName,
        encryptionRequired: Bool = true,
        artifactKinds: [ICloudSyncArtifactKind] = defaultArtifactKinds,
        conflictPolicy: ICloudSyncConflictPolicy = .manual
    ) {
        self.enabled = enabled
        self.syncDirectoryName = Self.normalizedSyncDirectoryName(syncDirectoryName)
        self.encryptionRequired = encryptionRequired
        self.artifactKinds = Self.normalizedArtifactKinds(artifactKinds)
        self.conflictPolicy = conflictPolicy
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case syncDirectoryName
        case encryptionRequired
        case artifactKinds
        case conflictPolicy
    }

    init(from decoder: Decoder) throws {
        let defaults = Self.defaults
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled,
            syncDirectoryName: try container.decodeIfPresent(String.self, forKey: .syncDirectoryName)
                ?? defaults.syncDirectoryName,
            encryptionRequired: try container.decodeIfPresent(Bool.self, forKey: .encryptionRequired)
                ?? defaults.encryptionRequired,
            artifactKinds: try container.decodeIfPresent(
                [ICloudSyncArtifactKind].self,
                forKey: .artifactKinds
            ) ?? defaults.artifactKinds,
            conflictPolicy: try container.decodeIfPresent(
                ICloudSyncConflictPolicy.self,
                forKey: .conflictPolicy
            ) ?? defaults.conflictPolicy
        )
    }

    static func normalizedSyncDirectoryName(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              trimmed != ".",
              trimmed != "..",
              !trimmed.hasPrefix(".")
        else {
            return Self.defaultSyncDirectoryName
        }
        return trimmed
    }

    static func normalizedArtifactKinds(_ rawKinds: [ICloudSyncArtifactKind]) -> [ICloudSyncArtifactKind] {
        var seen = Set<ICloudSyncArtifactKind>()
        let kinds = rawKinds.filter { seen.insert($0).inserted }
        return kinds.isEmpty ? Self.defaultArtifactKinds : kinds
    }
}

struct ICloudSyncManifestEntry: Codable, Sendable, Equatable, Hashable {
    let kind: ICloudSyncArtifactKind
    let relativePath: String
    let contentHash: String
    let modifiedAt: Date

    var key: ICloudSyncArtifactKey {
        ICloudSyncArtifactKey(kind: kind, relativePath: relativePath)
    }
}

struct ICloudSyncArtifactKey: Codable, Sendable, Equatable, Hashable, Comparable {
    let kind: ICloudSyncArtifactKind
    let relativePath: String

    static func < (lhs: ICloudSyncArtifactKey, rhs: ICloudSyncArtifactKey) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind < rhs.kind
        }
        return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
    }
}

enum ICloudSyncPlanOperation: Sendable, Equatable {
    case upload(ICloudSyncManifestEntry)
    case download(ICloudSyncManifestEntry)
    case conflict(local: ICloudSyncManifestEntry, remote: ICloudSyncManifestEntry)
}

struct ICloudSyncPlan: Sendable, Equatable {
    let operations: [ICloudSyncPlanOperation]

    static let empty = ICloudSyncPlan(operations: [])
}

struct ICloudSyncPlanner: Sendable {
    let conflictPolicy: ICloudSyncConflictPolicy

    init(conflictPolicy: ICloudSyncConflictPolicy) {
        self.conflictPolicy = conflictPolicy
    }

    func plan(
        local localEntries: [ICloudSyncManifestEntry],
        remote remoteEntries: [ICloudSyncManifestEntry]
    ) -> ICloudSyncPlan {
        let localByKey = Dictionary(uniqueKeysWithValues: localEntries.map { ($0.key, $0) })
        let remoteByKey = Dictionary(uniqueKeysWithValues: remoteEntries.map { ($0.key, $0) })
        let keys = Set(localByKey.keys).union(remoteByKey.keys).sorted()

        let operations = keys.compactMap { key -> ICloudSyncPlanOperation? in
            switch (localByKey[key], remoteByKey[key]) {
            case (.some(let local), .none):
                return .upload(local)
            case (.none, .some(let remote)):
                return .download(remote)
            case (.some(let local), .some(let remote)) where local.contentHash != remote.contentHash:
                return .conflict(local: local, remote: remote)
            default:
                return nil
            }
        }

        return ICloudSyncPlan(operations: operations)
    }
}
