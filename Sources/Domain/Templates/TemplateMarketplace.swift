// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TemplateMarketplace.swift - Decentralized local template source and install domain.

import Foundation

struct ProjectTemplateMarketplaceSource: Identifiable, Codable, Equatable, Sendable {
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

struct ProjectTemplateSourceStore {
    let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy/templates/sources.json"),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> [ProjectTemplateMarketplaceSource] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ProjectTemplateMarketplaceSource].self, from: data)
    }

    func save(_ sources: [ProjectTemplateMarketplaceSource]) throws {
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

    func add(_ source: ProjectTemplateMarketplaceSource) throws {
        try ProjectTemplateMarketplaceValidator.validateSourceURL(source.url)
        var sources = try load()
        sources.removeAll { $0.id == source.id }
        sources.append(source)
        try save(sources.sorted { lhs, rhs in
            lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        })
    }
}

enum ProjectTemplateMarketplaceError: Error, Equatable, Sendable {
    case invalidSourceScheme(String?)
    case unsafeTemplateID(String)
    case unsafeSourceName(String)
    case unsupportedLocalSource(String)
    case templateAlreadyInstalled(String)
    case templateNotInstalled(String)
    case missingTemplateManifest(String)
    case gitCloneFailed(Int32)
}

struct ProjectTemplateMarketplaceValidator: Sendable {
    static func validateSourceURL(_ url: URL) throws {
        let scheme = url.scheme?.lowercased()
        let allowedSchemes: Set<String> = ["file", "git", "https", "ssh"]
        guard let scheme, allowedSchemes.contains(scheme) else {
            throw ProjectTemplateMarketplaceError.invalidSourceScheme(scheme)
        }
    }

    static func validateTemplateID(_ id: String) throws {
        guard ProjectTemplateLoader.isValidIdentifier(id), !id.contains("..") else {
            throw ProjectTemplateMarketplaceError.unsafeTemplateID(id)
        }
    }
}

struct ProjectTemplateInstallReceipt: Equatable, Sendable {
    let templateID: String
    let installedURL: URL
    let template: ProjectTemplate
}

struct ProjectTemplateMarketplaceInstaller {
    let templatesDirectory: URL
    private let fileManager: FileManager
    private let loader: ProjectTemplateLoader

    init(
        templatesDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy/templates", isDirectory: true),
        fileManager: FileManager = .default,
        loader: ProjectTemplateLoader = ProjectTemplateLoader()
    ) {
        self.templatesDirectory = templatesDirectory
        self.fileManager = fileManager
        self.loader = loader
    }

    func install(from sourceURL: URL, replaceExisting: Bool = false) throws -> ProjectTemplateInstallReceipt {
        try ProjectTemplateMarketplaceValidator.validateSourceURL(sourceURL)
        let sourceName = try Self.templateIDCandidate(from: sourceURL)
        try fileManager.createDirectory(
            at: templatesDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let stagingRoot = templatesDirectory
            .appendingPathComponent(".installing-\(UUID().uuidString)", isDirectory: true)
        let stagedTemplate = stagingRoot.appendingPathComponent(sourceName, isDirectory: true)
        try fileManager.createDirectory(
            at: stagingRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? fileManager.removeItem(at: stagingRoot) }

        try materialize(sourceURL: sourceURL, at: stagedTemplate)
        guard let template = try loader.loadTemplate(from: stagedTemplate, source: .user) else {
            throw ProjectTemplateMarketplaceError.missingTemplateManifest(stagedTemplate.path)
        }
        try ProjectTemplateMarketplaceValidator.validateTemplateID(template.id)

        let finalURL = templatesDirectory.appendingPathComponent(template.id, isDirectory: true)
        if fileManager.fileExists(atPath: finalURL.path) {
            guard replaceExisting else {
                throw ProjectTemplateMarketplaceError.templateAlreadyInstalled(template.id)
            }
            try fileManager.removeItem(at: finalURL)
        }

        try fileManager.moveItem(at: stagedTemplate, to: finalURL)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: finalURL.path)

        let installedTemplate = try loader.loadTemplate(from: finalURL, source: .user)
        guard let installedTemplate else {
            throw ProjectTemplateMarketplaceError.missingTemplateManifest(finalURL.path)
        }
        return ProjectTemplateInstallReceipt(
            templateID: installedTemplate.id,
            installedURL: finalURL,
            template: installedTemplate
        )
    }

    func uninstall(id: String) throws {
        try ProjectTemplateMarketplaceValidator.validateTemplateID(id)
        let templateURL = templatesDirectory.appendingPathComponent(id, isDirectory: true)
        guard fileManager.fileExists(atPath: templateURL.path) else {
            throw ProjectTemplateMarketplaceError.templateNotInstalled(id)
        }
        try fileManager.removeItem(at: templateURL)
    }

    static func templateIDCandidate(from sourceURL: URL) throws -> String {
        let rawName: String
        if sourceURL.isFileURL {
            rawName = sourceURL.lastPathComponent
        } else {
            rawName = sourceURL.deletingPathExtension().lastPathComponent
        }
        let name = rawName.hasSuffix(".git") ? String(rawName.dropLast(4)) : rawName
        guard !name.isEmpty else {
            throw ProjectTemplateMarketplaceError.unsafeSourceName(sourceURL.absoluteString)
        }
        try ProjectTemplateMarketplaceValidator.validateTemplateID(name)
        return name
    }

    private func materialize(sourceURL: URL, at destination: URL) throws {
        if sourceURL.isFileURL {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw ProjectTemplateMarketplaceError.unsupportedLocalSource(sourceURL.path)
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
            throw ProjectTemplateMarketplaceError.gitCloneFailed(process.terminationStatus)
        }
    }
}
