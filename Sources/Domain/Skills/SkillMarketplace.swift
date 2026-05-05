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
    case skillNotInstalled(String)
    case missingSkillFile(String)
    case gitCloneFailed(Int32)
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
}

struct SkillMarketplaceInstaller {
    let skillsDirectory: URL
    private let fileManager: FileManager
    private let loader: SkillLoader

    init(
        skillsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy/skills", isDirectory: true),
        fileManager: FileManager = .default,
        loader: SkillLoader = SkillLoader()
    ) {
        self.skillsDirectory = skillsDirectory.standardizedFileURL
        self.fileManager = fileManager
        self.loader = loader
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
        if fileManager.fileExists(atPath: finalURL.path) {
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
            skill: installed
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

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["clone", "--depth", "1", sourceURL.absoluteString, destination.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SkillMarketplaceError.gitCloneFailed(process.terminationStatus)
        }
    }
}
