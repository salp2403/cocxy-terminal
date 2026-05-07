// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BackupModels.swift - Local backup configuration and manifest models.

import Foundation

enum BackupArtifactKind: String, Codable, Sendable, Equatable, CaseIterable, Comparable {
    case settings
    case notebooks
    case workflows
    case skills
    case notes
    case macros
    case themes
    case encryptedSSHHosts = "encrypted-ssh-hosts"
    case aiConversations = "ai-conversations"

    static func < (lhs: BackupArtifactKind, rhs: BackupArtifactKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var backupFolderName: String {
        rawValue
    }
}

struct BackupConfig: Codable, Sendable, Equatable {
    static let defaultStorageDirectory = "~/Library/Backups/Cocxy"
    static let defaultArtifactKinds: [BackupArtifactKind] = [
        .settings,
        .notebooks,
        .workflows,
        .skills,
        .notes,
        .macros,
        .themes,
        .encryptedSSHHosts,
    ]

    let enabled: Bool
    let storageDirectory: String
    let dailyRetentionCount: Int
    let monthlyRetentionCount: Int
    let artifactKinds: [BackupArtifactKind]

    static var defaults: BackupConfig {
        BackupConfig()
    }

    init(
        enabled: Bool = true,
        storageDirectory: String = Self.defaultStorageDirectory,
        dailyRetentionCount: Int = 30,
        monthlyRetentionCount: Int = 12,
        artifactKinds: [BackupArtifactKind] = Self.defaultArtifactKinds
    ) {
        self.enabled = enabled
        let trimmedStorage = storageDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        self.storageDirectory = trimmedStorage.isEmpty
            ? Self.defaultStorageDirectory
            : trimmedStorage
        self.dailyRetentionCount = max(1, dailyRetentionCount)
        self.monthlyRetentionCount = max(0, monthlyRetentionCount)
        self.artifactKinds = Self.normalizedArtifactKinds(artifactKinds)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case storageDirectory
        case dailyRetentionCount
        case monthlyRetentionCount
        case artifactKinds
    }

    init(from decoder: Decoder) throws {
        let defaults = Self.defaults
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled,
            storageDirectory: try container.decodeIfPresent(String.self, forKey: .storageDirectory)
                ?? defaults.storageDirectory,
            dailyRetentionCount: try container.decodeIfPresent(Int.self, forKey: .dailyRetentionCount)
                ?? defaults.dailyRetentionCount,
            monthlyRetentionCount: try container.decodeIfPresent(Int.self, forKey: .monthlyRetentionCount)
                ?? defaults.monthlyRetentionCount,
            artifactKinds: try container.decodeIfPresent([BackupArtifactKind].self, forKey: .artifactKinds)
                ?? defaults.artifactKinds
        )
    }

    static func normalizedArtifactKinds(_ rawKinds: [BackupArtifactKind]) -> [BackupArtifactKind] {
        var seen = Set<BackupArtifactKind>()
        let kinds = rawKinds.filter { seen.insert($0).inserted }
        return kinds.isEmpty ? Self.defaultArtifactKinds : kinds
    }
}

struct BackupArtifactRoots: Sendable, Equatable {
    let settings: URL
    let notebooks: URL
    let workflows: URL
    let skills: URL
    let notes: URL
    let macros: URL
    let themes: URL
    let encryptedSSHHosts: URL
    let aiConversations: URL

    init(
        settings: URL,
        notebooks: URL,
        workflows: URL,
        skills: URL,
        notes: URL,
        macros: URL,
        themes: URL,
        encryptedSSHHosts: URL,
        aiConversations: URL
    ) {
        self.settings = settings.standardizedFileURL
        self.notebooks = notebooks.standardizedFileURL
        self.workflows = workflows.standardizedFileURL
        self.skills = skills.standardizedFileURL
        self.notes = notes.standardizedFileURL
        self.macros = macros.standardizedFileURL
        self.themes = themes.standardizedFileURL
        self.encryptedSSHHosts = encryptedSSHHosts.standardizedFileURL
        self.aiConversations = aiConversations.standardizedFileURL
    }

    static func defaults(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> BackupArtifactRoots {
        BackupArtifactRoots(
            settings: homeDirectory.appendingPathComponent(".config/cocxy/config.toml", isDirectory: false),
            notebooks: homeDirectory.appendingPathComponent(".cocxy/notebooks", isDirectory: true),
            workflows: homeDirectory.appendingPathComponent(".cocxy/workflows", isDirectory: true),
            skills: homeDirectory.appendingPathComponent(".cocxy/skills", isDirectory: true),
            notes: homeDirectory.appendingPathComponent(".config/cocxy/notes", isDirectory: true),
            macros: homeDirectory.appendingPathComponent(".cocxy/snippets.json", isDirectory: false),
            themes: homeDirectory.appendingPathComponent(".config/cocxy/themes", isDirectory: true),
            encryptedSSHHosts: homeDirectory.appendingPathComponent(".config/cocxy/ssh/hosts.enc"),
            aiConversations: homeDirectory.appendingPathComponent(".config/cocxy/agent/conversations", isDirectory: true)
        )
    }

    func sourceURL(for kind: BackupArtifactKind) -> URL {
        switch kind {
        case .settings: return settings
        case .notebooks: return notebooks
        case .workflows: return workflows
        case .skills: return skills
        case .notes: return notes
        case .macros: return macros
        case .themes: return themes
        case .encryptedSSHHosts: return encryptedSSHHosts
        case .aiConversations: return aiConversations
        }
    }
}

struct BackupManifest: Codable, Sendable, Equatable {
    let version: Int
    let createdAt: Date
    let artifacts: [BackupManifestEntry]

    init(
        version: Int = 1,
        createdAt: Date,
        artifacts: [BackupManifestEntry]
    ) {
        self.version = version
        self.createdAt = createdAt
        self.artifacts = artifacts
    }
}

struct BackupManifestEntry: Codable, Sendable, Equatable {
    let kind: BackupArtifactKind
    let path: String
    let fileCount: Int
}

struct BackupCreateResult: Sendable, Equatable {
    let backupURL: URL
    let manifest: BackupManifest
}

struct BackupSnapshotSummary: Identifiable, Sendable, Equatable {
    let backupURL: URL
    let manifest: BackupManifest

    var id: String {
        backupURL.standardizedFileURL.path
    }

    var createdAt: Date {
        manifest.createdAt
    }

    var artifacts: [BackupManifestEntry] {
        manifest.artifacts
    }

    var totalFileCount: Int {
        artifacts.reduce(0) { $0 + $1.fileCount }
    }
}

struct BackupRestoreResult: Sendable, Equatable {
    let kind: BackupArtifactKind
    let restoredFiles: Int
}

struct BackupPruneResult: Sendable, Equatable {
    let deletedCount: Int
}
