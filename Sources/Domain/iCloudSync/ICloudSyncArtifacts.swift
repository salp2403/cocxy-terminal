// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ICloudSyncArtifacts.swift - Local artifact discovery and encrypted export.

import CryptoKit
import Foundation

struct ICloudSyncArtifactRoots: Sendable, Equatable {
    let notebooks: URL
    let workflows: URL
    let skills: URL
    let settings: URL
    let themes: URL

    init(
        notebooks: URL,
        workflows: URL,
        skills: URL,
        settings: URL,
        themes: URL
    ) {
        self.notebooks = notebooks.standardizedFileURL
        self.workflows = workflows.standardizedFileURL
        self.skills = skills.standardizedFileURL
        self.settings = settings.standardizedFileURL
        self.themes = themes.standardizedFileURL
    }

    static func defaults(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> ICloudSyncArtifactRoots {
        ICloudSyncArtifactRoots(
            notebooks: NotebookFileStore.defaultDirectory(),
            workflows: WorkflowRegistry.defaultDirectory(),
            skills: homeDirectory.appendingPathComponent(".cocxy/skills", isDirectory: true),
            settings: homeDirectory.appendingPathComponent(".config/cocxy/config.toml", isDirectory: false),
            themes: homeDirectory.appendingPathComponent(".cocxy/themes", isDirectory: true)
        )
    }
}

struct ICloudSyncLocalArtifact: Sendable, Equatable {
    let entry: ICloudSyncManifestEntry
    let sourceURL: URL
}

enum ICloudSyncArtifactScannerError: Error, Sendable, Equatable {
    case escapedRoot(URL)
}

struct ICloudSyncArtifactScanner: Sendable {
    init() {}

    func scan(
        roots: ICloudSyncArtifactRoots,
        kinds: [ICloudSyncArtifactKind]
    ) throws -> [ICloudSyncLocalArtifact] {
        var artifacts: [ICloudSyncLocalArtifact] = []
        for kind in ICloudSyncConfig.normalizedArtifactKinds(kinds) {
            switch kind {
            case .notebooks:
                artifacts.append(contentsOf: try scanDirectory(
                    kind: .notebooks,
                    root: roots.notebooks,
                    allowedExtensions: ["cocxynb"]
                ))
            case .workflows:
                artifacts.append(contentsOf: try scanDirectory(
                    kind: .workflows,
                    root: roots.workflows,
                    allowedExtensions: ["toml"]
                ))
            case .skills:
                artifacts.append(contentsOf: try scanDirectory(
                    kind: .skills,
                    root: roots.skills,
                    allowedExtensions: nil
                ))
            case .settings:
                if let artifact = try scanFile(
                    kind: .settings,
                    fileURL: roots.settings,
                    relativePath: roots.settings.lastPathComponent
                ) {
                    artifacts.append(artifact)
                }
            case .themes:
                artifacts.append(contentsOf: try scanDirectory(
                    kind: .themes,
                    root: roots.themes,
                    allowedExtensions: ["toml"]
                ))
            }
        }
        return artifacts
    }

    private func scanDirectory(
        kind: ICloudSyncArtifactKind,
        root: URL,
        allowedExtensions: Set<String>?
    ) throws -> [ICloudSyncLocalArtifact] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let root = root.standardizedFileURL
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var artifacts: [ICloudSyncLocalArtifact] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                continue
            }
            if let allowedExtensions,
               !allowedExtensions.contains(url.pathExtension.lowercased()) {
                continue
            }
            let relativePath = try Self.relativePath(for: url, under: root)
            if let artifact = try scanFile(kind: kind, fileURL: url, relativePath: relativePath) {
                artifacts.append(artifact)
            }
        }

        return artifacts.sorted {
            $0.entry.relativePath.localizedStandardCompare($1.entry.relativePath) == .orderedAscending
        }
    }

    private func scanFile(
        kind: ICloudSyncArtifactKind,
        fileURL: URL,
        relativePath: String
    ) throws -> ICloudSyncLocalArtifact? {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ICloudSyncLocalArtifact(
            entry: ICloudSyncManifestEntry(
                kind: kind,
                relativePath: relativePath,
                contentHash: digest,
                modifiedAt: values.contentModificationDate ?? Date(timeIntervalSince1970: 0)
            ),
            sourceURL: fileURL.standardizedFileURL
        )
    }

    private static func relativePath(for url: URL, under root: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else {
            throw ICloudSyncArtifactScannerError.escapedRoot(url)
        }
        return String(filePath.dropFirst(prefix.count))
    }
}

struct ICloudSyncManifest: Codable, Sendable, Equatable {
    let version: Int
    let generatedAt: Date
    let entries: [ICloudSyncManifestEntry]

    init(
        version: Int = 1,
        generatedAt: Date = Date(),
        entries: [ICloudSyncManifestEntry]
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.entries = entries
    }
}

struct ICloudSyncExportResult: Sendable, Equatable {
    let rootURL: URL
    let manifest: ICloudSyncManifest
    let manifestURL: URL
    let writtenArtifactURLs: [URL]
}

enum ICloudSyncExportOutcome: Sendable, Equatable {
    case disabled
    case unavailable
    case exported(ICloudSyncExportResult)
}

enum ICloudSyncExportRunError: Error, Sendable, Equatable {
    case masterPasswordUnavailable
}

extension ICloudSyncExportRunError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .masterPasswordUnavailable:
            return "iCloud Sync master password is not saved."
        }
    }
}

protocol ICloudSyncExporting: Sendable {
    func exportLocalArtifacts(
        config: ICloudSyncConfig,
        roots: ICloudSyncArtifactRoots,
        password: String
    ) throws -> ICloudSyncExportOutcome
}

struct ICloudSyncExportService: Sendable {
    private let rootResolver: ICloudSyncRootResolver
    private let scanner: ICloudSyncArtifactScanner
    private let exporter: ICloudSyncEncryptedExporter

    init(
        rootResolver: ICloudSyncRootResolver = ICloudSyncRootResolver(),
        scanner: ICloudSyncArtifactScanner = ICloudSyncArtifactScanner(),
        exporter: ICloudSyncEncryptedExporter = ICloudSyncEncryptedExporter()
    ) {
        self.rootResolver = rootResolver
        self.scanner = scanner
        self.exporter = exporter
    }

    func exportLocalArtifacts(
        config: ICloudSyncConfig,
        roots: ICloudSyncArtifactRoots = .defaults(),
        password: String
    ) throws -> ICloudSyncExportOutcome {
        switch rootResolver.resolveRoot(for: config) {
        case .disabled:
            return .disabled
        case .unavailable:
            return .unavailable
        case .available(let rootURL):
            let artifacts = try scanner.scan(roots: roots, kinds: config.artifactKinds)
            let result = try exporter.export(artifacts, to: rootURL, password: password)
            return .exported(result)
        }
    }
}

extension ICloudSyncExportService: ICloudSyncExporting {}

struct ICloudSyncEncryptedExporter: Sendable {
    private let encryption: ICloudSyncEncryption

    init(
        encryption: ICloudSyncEncryption = ICloudSyncEncryption()
    ) {
        self.encryption = encryption
    }

    func export(
        _ artifacts: [ICloudSyncLocalArtifact],
        to rootURL: URL,
        password: String
    ) throws -> ICloudSyncExportResult {
        try ensurePrivateDirectory(rootURL)

        var writtenURLs: [URL] = []
        for artifact in artifacts {
            let destination = encryptedURL(for: artifact.entry, rootURL: rootURL)
            try ensurePrivateDirectory(destination.deletingLastPathComponent())
            let plaintext = try Data(contentsOf: artifact.sourceURL)
            let encrypted = try encryption.seal(plaintext, password: password)
            try encrypted.write(to: destination, options: .atomic)
            try setPrivateFilePermissions(destination)
            writtenURLs.append(destination)
        }

        let manifest = ICloudSyncManifest(entries: artifacts.map(\.entry))
        let manifestURL = rootURL.appendingPathComponent("manifest.json", isDirectory: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        try setPrivateFilePermissions(manifestURL)

        return ICloudSyncExportResult(
            rootURL: rootURL,
            manifest: manifest,
            manifestURL: manifestURL,
            writtenArtifactURLs: writtenURLs
        )
    }

    private func encryptedURL(for entry: ICloudSyncManifestEntry, rootURL: URL) -> URL {
        rootURL
            .appendingPathComponent(entry.kind.rawValue, isDirectory: true)
            .appendingPathComponent(entry.relativePath + ".cocxyenc", isDirectory: false)
    }

    private func ensurePrivateDirectory(_ url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func setPrivateFilePermissions(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

struct ICloudSyncImportConflict: Sendable, Equatable {
    let local: ICloudSyncManifestEntry
    let remote: ICloudSyncManifestEntry
}

struct ICloudSyncImportResult: Sendable, Equatable {
    let rootURL: URL
    let manifest: ICloudSyncManifest
    let importedArtifactURLs: [URL]
    let conflicts: [ICloudSyncImportConflict]
}

enum ICloudSyncImportOutcome: Sendable, Equatable {
    case disabled
    case unavailable
    case imported(ICloudSyncImportResult)
}

enum ICloudSyncImportError: Error, Sendable, Equatable {
    case manifestMissing(URL)
    case invalidManifestPath(String)
    case encryptedArtifactMissing(URL)
    case destinationAlreadyExists(URL)
}

struct ICloudSyncImportService: Sendable {
    private let rootResolver: ICloudSyncRootResolver
    private let scanner: ICloudSyncArtifactScanner
    private let importer: ICloudSyncEncryptedImporter

    init(
        rootResolver: ICloudSyncRootResolver = ICloudSyncRootResolver(),
        scanner: ICloudSyncArtifactScanner = ICloudSyncArtifactScanner(),
        importer: ICloudSyncEncryptedImporter = ICloudSyncEncryptedImporter()
    ) {
        self.rootResolver = rootResolver
        self.scanner = scanner
        self.importer = importer
    }

    func importRemoteArtifacts(
        config: ICloudSyncConfig,
        roots: ICloudSyncArtifactRoots = .defaults(),
        password: String
    ) throws -> ICloudSyncImportOutcome {
        switch rootResolver.resolveRoot(for: config) {
        case .disabled:
            return .disabled
        case .unavailable:
            return .unavailable
        case .available(let rootURL):
            let manifest = try readManifest(from: rootURL)
            let localEntries = try scanner.scan(roots: roots, kinds: config.artifactKinds).map(\.entry)
            let allowedKinds = Set(config.artifactKinds)
            let remoteEntries = manifest.entries.filter { allowedKinds.contains($0.kind) }
            let plan = ICloudSyncPlanner(conflictPolicy: config.conflictPolicy).plan(
                local: localEntries,
                remote: remoteEntries
            )
            let result = try importer.importRemoteArtifacts(
                plan: plan,
                manifest: manifest,
                from: rootURL,
                into: roots,
                password: password
            )
            return .imported(result)
        }
    }

    private func readManifest(from rootURL: URL) throws -> ICloudSyncManifest {
        let manifestURL = rootURL.appendingPathComponent("manifest.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ICloudSyncImportError.manifestMissing(manifestURL)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ICloudSyncManifest.self, from: Data(contentsOf: manifestURL))
    }
}

struct ICloudSyncEncryptedImporter: Sendable {
    private let encryption: ICloudSyncEncryption

    init(encryption: ICloudSyncEncryption = ICloudSyncEncryption()) {
        self.encryption = encryption
    }

    func importRemoteArtifacts(
        plan: ICloudSyncPlan,
        manifest: ICloudSyncManifest,
        from rootURL: URL,
        into roots: ICloudSyncArtifactRoots,
        password: String
    ) throws -> ICloudSyncImportResult {
        var importedURLs: [URL] = []
        var conflicts: [ICloudSyncImportConflict] = []

        for operation in plan.operations {
            switch operation {
            case .download(let entry):
                let remoteURL = try encryptedURL(for: entry, rootURL: rootURL)
                guard FileManager.default.fileExists(atPath: remoteURL.path) else {
                    throw ICloudSyncImportError.encryptedArtifactMissing(remoteURL)
                }
                let destination = try localURL(for: entry, roots: roots)
                guard !FileManager.default.fileExists(atPath: destination.path) else {
                    throw ICloudSyncImportError.destinationAlreadyExists(destination)
                }
                let plaintext = try encryption.open(Data(contentsOf: remoteURL), password: password)
                try ensurePrivateDirectory(destination.deletingLastPathComponent())
                try plaintext.write(to: destination, options: .atomic)
                try setPrivateFilePermissions(destination)
                importedURLs.append(destination.standardizedFileURL)
            case .conflict(let local, let remote):
                conflicts.append(ICloudSyncImportConflict(local: local, remote: remote))
            case .upload:
                continue
            }
        }

        return ICloudSyncImportResult(
            rootURL: rootURL,
            manifest: manifest,
            importedArtifactURLs: importedURLs,
            conflicts: conflicts
        )
    }

    private func encryptedURL(for entry: ICloudSyncManifestEntry, rootURL: URL) throws -> URL {
        let relativePath = try Self.validatedRelativePath(entry.relativePath)
        return rootURL
            .appendingPathComponent(entry.kind.rawValue, isDirectory: true)
            .appendingPathComponent(relativePath + ".cocxyenc", isDirectory: false)
    }

    private func localURL(for entry: ICloudSyncManifestEntry, roots: ICloudSyncArtifactRoots) throws -> URL {
        let relativePath = try Self.validatedRelativePath(entry.relativePath)
        switch entry.kind {
        case .notebooks:
            return try Self.url(for: relativePath, under: roots.notebooks)
        case .workflows:
            return try Self.url(for: relativePath, under: roots.workflows)
        case .skills:
            return try Self.url(for: relativePath, under: roots.skills)
        case .settings:
            guard relativePath == roots.settings.lastPathComponent else {
                throw ICloudSyncImportError.invalidManifestPath(relativePath)
            }
            return roots.settings.standardizedFileURL
        case .themes:
            return try Self.url(for: relativePath, under: roots.themes)
        }
    }

    private static func url(for relativePath: String, under root: URL) throws -> URL {
        let destination = root.appendingPathComponent(relativePath, isDirectory: false).standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard destination.path.hasPrefix(prefix) else {
            throw ICloudSyncImportError.invalidManifestPath(relativePath)
        }
        return destination
    }

    private static func validatedRelativePath(_ relativePath: String) throws -> String {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        let isSafe = !relativePath.isEmpty
            && !relativePath.hasPrefix("/")
            && !relativePath.contains("\\")
            && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
        guard isSafe else {
            throw ICloudSyncImportError.invalidManifestPath(relativePath)
        }
        return relativePath
    }

    private func ensurePrivateDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func setPrivateFilePermissions(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
