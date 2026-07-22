// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SkillMarketplace.swift - Decentralized local skill source and install domain.

import Foundation

struct SkillMarketplaceSource: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let url: URL
    let displayName: String?
    let addedAt: Date

    init(url: URL, displayName: String? = nil, addedAt: Date = Date()) {
        self.url = url
        self.displayName = displayName
        self.addedAt = addedAt
        self.id = url.absoluteString.lowercased()
    }
}

struct SkillSourceStore {
    let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy/skills/sources.json"),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> [SkillMarketplaceSource] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SkillMarketplaceSource].self, from: data)
    }

    func save(_ sources: [SkillMarketplaceSource]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(sources).write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func add(_ source: SkillMarketplaceSource) throws {
        try SkillMarketplaceValidator.validateSourceURL(source.url)
        var sources = try load()
        sources.removeAll { $0.id == source.id }
        sources.append(source)
        try save(sources.sorted { lhs, rhs in
            lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        })
    }
}

enum SkillMarketplaceError: Error, Equatable, Sendable {
    case invalidSourceScheme(String?)
    case unsafeSkillID(String)
    case unsafeSourceName(String)
    case unsupportedLocalSource(String)
    case skillAlreadyInstalled(String)
    case skillNamespaceCollision(id: String, source: SkillSource)
    case skillNotInstalled(String)
    case missingSkillFile(String)
    case gitCloneFailed(Int32)
    case gitCloneTimedOut(TimeInterval)
}

extension SkillMarketplaceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidSourceScheme(let scheme):
            return "Unsupported skill source scheme: \(scheme ?? "none")"
        case .unsafeSkillID(let id):
            return "Unsafe skill id: \(id)"
        case .unsafeSourceName(let source):
            return "Unsafe skill source name: \(source)"
        case .unsupportedLocalSource(let path):
            return "Local skill source is not a directory: \(path)"
        case .skillAlreadyInstalled(let id):
            return "Skill '\(id)' is already installed. Use --replace to replace it."
        case .skillNamespaceCollision(let id, let source):
            return "Skill '\(id)' conflicts with a \(source.rawValue) skill. Use --replace to acknowledge the override."
        case .skillNotInstalled(let id):
            return "Skill '\(id)' is not installed."
        case .missingSkillFile(let path):
            return "Missing SKILL.md in skill source: \(path)"
        case .gitCloneFailed(let status):
            return "Skill source clone failed with status \(status)."
        case .gitCloneTimedOut(let seconds):
            return "Skill source clone timed out after \(Self.formatted(seconds)) seconds."
        }
    }

    private static func formatted(_ seconds: TimeInterval) -> String {
        seconds.rounded() == seconds
            ? String(format: "%.0f", seconds)
            : String(format: "%.1f", seconds)
    }
}

struct SkillMarketplaceValidator: Sendable {
    static func validateSourceURL(_ url: URL) throws {
        let scheme = url.scheme?.lowercased()
        let allowedSchemes: Set<String> = ["file", "git", "https", "ssh"]
        guard let scheme, allowedSchemes.contains(scheme) else {
            throw SkillMarketplaceError.invalidSourceScheme(scheme)
        }
    }

    static func validateSkillID(_ id: String) throws {
        guard SkillLoader.isValidIdentifier(id), !id.contains("..") else {
            throw SkillMarketplaceError.unsafeSkillID(id)
        }
    }
}

struct SkillInstallReceipt: Equatable, Sendable {
    let skillID: String
    let installedURL: URL
    let skill: Skill
    let replacedSkillIdentity: SkillIdentity?
}

struct SkillMarketplaceInstaller {
    let skillsDirectory: URL
    private let fileManager: FileManager
    private let loader: SkillLoader
    private let protectedSkillDirectories: [SkillDirectory]
    private let gitProcessRunner: MarketplaceGitProcessRunner

    init(
        skillsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy/skills", isDirectory: true),
        fileManager: FileManager = .default,
        loader: SkillLoader = SkillLoader(),
        protectedSkillDirectories: [SkillDirectory]? = nil,
        gitProcessRunner: MarketplaceGitProcessRunner = MarketplaceGitProcessRunner()
    ) {
        self.skillsDirectory = skillsDirectory.standardizedFileURL
        self.fileManager = fileManager
        self.loader = loader
        self.gitProcessRunner = gitProcessRunner
        if let protectedSkillDirectories {
            self.protectedSkillDirectories = protectedSkillDirectories
        } else if let bundledDirectory = BuiltInSkills.bundledDirectory() {
            self.protectedSkillDirectories = [
                SkillDirectory(url: bundledDirectory, source: .builtIn),
            ]
        } else {
            self.protectedSkillDirectories = []
        }
    }

    func install(from sourceURL: URL, replaceExisting: Bool = false) throws -> SkillInstallReceipt {
        try SkillMarketplaceValidator.validateSourceURL(sourceURL)
        let sourceName = try Self.skillIDCandidate(from: sourceURL)
        try fileManager.createDirectory(
            at: skillsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let stagingRoot = skillsDirectory
            .appendingPathComponent(".installing-\(UUID().uuidString)", isDirectory: true)
        let stagedSkill = stagingRoot.appendingPathComponent(sourceName, isDirectory: true)
        try fileManager.createDirectory(
            at: stagingRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? fileManager.removeItem(at: stagingRoot) }

        try materialize(sourceURL: sourceURL, at: stagedSkill)
        guard fileManager.fileExists(
            atPath: stagedSkill.appendingPathComponent("SKILL.md").path
        ) else {
            throw SkillMarketplaceError.missingSkillFile(sourceURL.isFileURL ? sourceURL.path : stagedSkill.path)
        }
        guard let staged = try loader.loadSkill(from: stagedSkill, source: .user) else {
            throw SkillMarketplaceError.missingSkillFile(sourceURL.isFileURL ? sourceURL.path : stagedSkill.path)
        }
        try SkillMarketplaceValidator.validateSkillID(staged.id)

        let finalURL = skillsDirectory.appendingPathComponent(staged.id, isDirectory: true)
        let userSkillExists = fileManager.fileExists(atPath: finalURL.path)
        let protectedCollision = try protectedSkillCollision(id: staged.id)
        let replacedSkillIdentity: SkillIdentity?
        if userSkillExists {
            replacedSkillIdentity = SkillIdentity(id: staged.id, source: .user)
        } else {
            replacedSkillIdentity = protectedCollision?.identity
        }

        if let protectedCollision, !userSkillExists, !replaceExisting {
            throw SkillMarketplaceError.skillNamespaceCollision(
                id: staged.id,
                source: protectedCollision.source
            )
        }
        if userSkillExists {
            guard replaceExisting else {
                throw SkillMarketplaceError.skillAlreadyInstalled(staged.id)
            }
            try fileManager.removeItem(at: finalURL)
        }

        try fileManager.moveItem(at: stagedSkill, to: finalURL)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: finalURL.path)

        guard let installed = try loader.loadSkill(from: finalURL, source: .user) else {
            throw SkillMarketplaceError.missingSkillFile(finalURL.path)
        }
        return SkillInstallReceipt(
            skillID: installed.id,
            installedURL: finalURL,
            skill: installed,
            replacedSkillIdentity: replacedSkillIdentity
        )
    }

    func uninstall(id: String) throws {
        try SkillMarketplaceValidator.validateSkillID(id)
        let skillURL = skillsDirectory.appendingPathComponent(id, isDirectory: true)
        guard fileManager.fileExists(atPath: skillURL.path) else {
            throw SkillMarketplaceError.skillNotInstalled(id)
        }
        try fileManager.removeItem(at: skillURL)
    }

    static func skillIDCandidate(from sourceURL: URL) throws -> String {
        let rawName: String
        if sourceURL.isFileURL {
            rawName = sourceURL.lastPathComponent
        } else {
            rawName = sourceURL.deletingPathExtension().lastPathComponent
        }
        let name = rawName.hasSuffix(".git") ? String(rawName.dropLast(4)) : rawName
        guard !name.isEmpty else {
            throw SkillMarketplaceError.unsafeSourceName(sourceURL.absoluteString)
        }
        try SkillMarketplaceValidator.validateSkillID(name)
        return name
    }

    private func protectedSkillCollision(id: String) throws -> Skill? {
        guard !protectedSkillDirectories.isEmpty else { return nil }
        return try SkillRegistry(directories: protectedSkillDirectories, loader: loader)
            .loadSkills()
            .first { $0.id == id }
    }

    private func materialize(sourceURL: URL, at destination: URL) throws {
        if sourceURL.isFileURL {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw SkillMarketplaceError.unsupportedLocalSource(sourceURL.path)
            }
            try fileManager.copyItem(at: sourceURL, to: destination)
            return
        }

        let result = try gitProcessRunner.clone(
            sourceURL: sourceURL,
            destinationURL: destination
        )
        if result.timedOut {
            throw SkillMarketplaceError.gitCloneTimedOut(gitProcessRunner.timeoutSeconds)
        }
        guard result.exitCode == 0 else {
            throw SkillMarketplaceError.gitCloneFailed(result.exitCode)
        }
    }
}
