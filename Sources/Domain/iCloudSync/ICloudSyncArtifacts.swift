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
