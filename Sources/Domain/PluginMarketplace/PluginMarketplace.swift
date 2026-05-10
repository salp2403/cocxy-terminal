// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginMarketplace.swift - Decentralized plugin source, validation, and install domain.

import Foundation
import CocxyCommandSignatures

// MARK: - Plugin Source URL Resolver

enum PluginSourceURLResolver {
    static func resolve(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded = (trimmed as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        if let sshURL = resolveSCPStyleGitURL(trimmed) {
            return sshURL
        }

        return URL(fileURLWithPath: expanded)
    }

    private static func resolveSCPStyleGitURL(_ rawValue: String) -> URL? {
        guard let separator = rawValue.firstIndex(of: ":"),
              rawValue[..<separator].contains("@")
        else {
            return nil
        }

        let host = rawValue[..<separator]
        let path = rawValue[rawValue.index(after: separator)...]
        guard !host.isEmpty, !path.isEmpty else { return nil }
        return URL(string: "ssh://\(host)/\(path)")
    }
}

// MARK: - Plugin Source

/// A user-managed decentralized plugin source URL.
struct PluginSource: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let url: URL
    let displayName: String?
    let addedAt: Date

    init(url: URL, displayName: String? = nil, addedAt: Date = Date()) {
        self.url = url
        self.displayName = displayName
        self.addedAt = addedAt
        self.id = Self.stableID(for: url)
    }

    private static func stableID(for url: URL) -> String {
        url.absoluteString.lowercased()
    }
}

// MARK: - Plugin Source Store

/// Persists the user's decentralized plugin source list.
struct PluginSourceStore {
    let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy/plugins/sources.json"),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> [PluginSource] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([PluginSource].self, from: data)
    }

    func save(_ sources: [PluginSource]) throws {
        let parent = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sources)
        try data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func add(_ source: PluginSource) throws {
        try PluginValidator.validateSourceURL(source.url)
        var sources = try load()
        sources.removeAll { $0.id == source.id }
        sources.append(source)
        try save(sources)
    }
}

// MARK: - Plugin Registry

/// Reads installed plugin manifests from a local plugin directory.
struct PluginRegistry {
    let pluginsDirectory: URL
    private let fileManager: FileManager

    init(
        pluginsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy/plugins"),
        fileManager: FileManager = .default
    ) {
        self.pluginsDirectory = pluginsDirectory
        self.fileManager = fileManager
    }

    func installedManifests() throws -> [PluginManifest] {
        guard fileManager.fileExists(atPath: pluginsDirectory.path) else { return [] }
        let entries = try fileManager.contentsOfDirectory(
            at: pluginsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return entries.compactMap { entry in
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return try? Self.loadManifest(from: entry, fileManager: fileManager)
        }
    }

    static func loadManifest(from pluginDirectory: URL, fileManager: FileManager = .default) throws -> PluginManifest {
        for fileName in [
            PluginManifest.marketplaceManifestFileName,
            PluginManifest.legacyManifestFileName,
        ] {
            let manifestURL = pluginDirectory.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: manifestURL.path) {
                return try PluginManifestParser.parse(
                    filePath: manifestURL.path,
                    directoryPath: pluginDirectory.path
                )
            }
        }
        throw PluginInstallerError.missingManifest(pluginDirectory.path)
    }
}

// MARK: - Plugin Validator

enum PluginSignatureStatus: Equatable, Sendable {
    case verified
    case unsignedAllowed
    case presentButUnverified
    case invalid
}

enum PluginValidationWarning: Equatable, Sendable {
    case unsignedPlugin
    case signaturePresentButUnverified
    case invalidSignature
}

enum PluginValidationError: Error, Equatable {
    case invalidSourceScheme(String?)
    case unsafePluginID(String)
}

struct PluginValidationReport: Equatable, Sendable {
    let signatureStatus: PluginSignatureStatus
    let warnings: Set<PluginValidationWarning>

    var isInstallable: Bool { signatureStatus != .invalid }
}

/// Validates decentralized plugin metadata before registration.
struct PluginValidator: Sendable {
    let trustedAuthors: TrustedAuthorRegistry

    init(trustedAuthors: TrustedAuthorRegistry = TrustedAuthorRegistry()) {
        self.trustedAuthors = trustedAuthors
    }

    func validate(
        manifest: PluginManifest,
        sourceURL: URL,
        pluginDirectory: URL
    ) throws -> PluginValidationReport {
        try Self.validateSourceURL(sourceURL)
        try Self.validatePluginID(manifest.id)

        if let signature = manifest.signature, !signature.value.isEmpty {
            guard let artifact = signature.signedArtifact(),
                  let publicKey = trustedAuthors.publicKey(for: artifact.keyID)
            else {
                return PluginValidationReport(
                    signatureStatus: .presentButUnverified,
                    warnings: [.signaturePresentButUnverified]
                )
            }

            let manifestURL = pluginDirectory.appendingPathComponent(manifest.manifestFileName)
            guard let manifestContent = try? String(contentsOf: manifestURL, encoding: .utf8) else {
                return PluginValidationReport(
                    signatureStatus: .presentButUnverified,
                    warnings: [.signaturePresentButUnverified]
                )
            }
            let verification = SignatureVerifier().verify(
                payload: PluginSignaturePayload.canonicalManifestPayload(from: manifestContent),
                artifact: artifact,
                publicKey: publicKey
            )
            guard verification == .valid else {
                return PluginValidationReport(
                    signatureStatus: .invalid,
                    warnings: [.invalidSignature]
                )
            }

            return PluginValidationReport(
                signatureStatus: .verified,
                warnings: []
            )
        }

        return PluginValidationReport(
            signatureStatus: .unsignedAllowed,
            warnings: [.unsignedPlugin]
        )
    }

    static func validateSourceURL(_ url: URL) throws {
        let scheme = url.scheme?.lowercased()
        let allowedSchemes: Set<String> = ["file", "https", "ssh", "git"]
        guard let scheme, allowedSchemes.contains(scheme) else {
            throw PluginValidationError.invalidSourceScheme(scheme)
        }
    }

    static func validatePluginID(_ id: String) throws {
        let range = id.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#,
            options: .regularExpression
        )
        guard range != nil, !id.contains("..") else {
            throw PluginValidationError.unsafePluginID(id)
        }
    }
}

enum PluginSignaturePayload {
    private static let signatureKeys: Set<String> = [
        "signature",
        "signature-algorithm",
        "signature-key-id",
        "signature-author",
        "signature-timestamp",
        "signature-payload-sha256",
    ]

    static func canonicalManifestPayload(from content: String) -> Data {
        var lines = content.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let separator = trimmed.firstIndex(of: "=") else { return true }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            return !signatureKeys.contains(key)
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}

// MARK: - Plugin Installer

enum PluginInstallerError: Error, Equatable {
    case missingManifest(String)
    case pluginAlreadyInstalled(String)
    case pluginNotInstalled(String)
    case invalidSignature(String)
    case unsafeSourceName(String)
    case unsupportedLocalSource(String)
    case gitCloneFailed(Int32)
}

struct PluginInstallReceipt: Equatable, Sendable {
    let pluginID: String
    let installedURL: URL
    let manifest: PluginManifest
    let signatureStatus: PluginSignatureStatus
}

/// Installs decentralized plugin repos into the local plugin registry.
struct PluginInstaller {
    let pluginsDirectory: URL
    private let fileManager: FileManager
    private let validator: PluginValidator

    init(
        pluginsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy/plugins"),
        fileManager: FileManager = .default,
        validator: PluginValidator = PluginValidator()
    ) {
        self.pluginsDirectory = pluginsDirectory
        self.fileManager = fileManager
        self.validator = validator
    }

    func install(from sourceURL: URL, replaceExisting: Bool = false) throws -> PluginInstallReceipt {
        try PluginValidator.validateSourceURL(sourceURL)
        let sourceName = try Self.pluginIDCandidate(from: sourceURL)
        try fileManager.createDirectory(
            at: pluginsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let stagingRoot = pluginsDirectory
            .appendingPathComponent(".installing-\(UUID().uuidString)", isDirectory: true)
        let stagedPlugin = stagingRoot.appendingPathComponent(sourceName, isDirectory: true)

        try fileManager.createDirectory(
            at: stagingRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? fileManager.removeItem(at: stagingRoot) }

        try materialize(sourceURL: sourceURL, at: stagedPlugin)

        let stagedManifest = try PluginRegistry.loadManifest(
            from: stagedPlugin,
            fileManager: fileManager
        )
        let report = try validator.validate(
            manifest: stagedManifest,
            sourceURL: sourceURL,
            pluginDirectory: stagedPlugin
        )
        guard report.isInstallable else {
            throw PluginInstallerError.invalidSignature(stagedManifest.id)
        }

        let finalURL = pluginsDirectory.appendingPathComponent(stagedManifest.id, isDirectory: true)
        if fileManager.fileExists(atPath: finalURL.path) {
            guard replaceExisting else {
                throw PluginInstallerError.pluginAlreadyInstalled(stagedManifest.id)
            }
            try fileManager.removeItem(at: finalURL)
        }

        try fileManager.moveItem(at: stagedPlugin, to: finalURL)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: finalURL.path)

        let installedManifest = stagedManifest.relocated(to: finalURL.path)
        return PluginInstallReceipt(
            pluginID: installedManifest.id,
            installedURL: finalURL,
            manifest: installedManifest,
            signatureStatus: report.signatureStatus
        )
    }

    func uninstall(id: String) throws {
        try PluginValidator.validatePluginID(id)
        let pluginURL = pluginsDirectory.appendingPathComponent(id, isDirectory: true)
        guard fileManager.fileExists(atPath: pluginURL.path) else {
            throw PluginInstallerError.pluginNotInstalled(id)
        }
        try fileManager.removeItem(at: pluginURL)
        try removeEnabledState(for: id)
    }

    private func materialize(sourceURL: URL, at destination: URL) throws {
        if sourceURL.isFileURL {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                throw PluginInstallerError.unsupportedLocalSource(sourceURL.path)
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
            throw PluginInstallerError.gitCloneFailed(process.terminationStatus)
        }
    }

    static func pluginIDCandidate(from sourceURL: URL) throws -> String {
        let rawName: String
        if sourceURL.isFileURL {
            rawName = sourceURL.lastPathComponent
        } else {
            rawName = sourceURL.deletingPathExtension().lastPathComponent
        }

        let name = rawName.hasSuffix(".git") ? String(rawName.dropLast(4)) : rawName
        guard !name.isEmpty else {
            throw PluginInstallerError.unsafeSourceName(sourceURL.absoluteString)
        }
        try PluginValidator.validatePluginID(name)
        return name
    }

    private func removeEnabledState(for id: String) throws {
        let stateURL = pluginsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("plugins.json")
        guard fileManager.fileExists(atPath: stateURL.path) else { return }

        let data = try Data(contentsOf: stateURL)
        let enabledIDs = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        let updatedIDs = enabledIDs.filter { $0 != id }
        guard updatedIDs.count != enabledIDs.count else { return }

        let encoded = try JSONEncoder().encode(updatedIDs.sorted())
        try encoded.write(to: stateURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }
}
