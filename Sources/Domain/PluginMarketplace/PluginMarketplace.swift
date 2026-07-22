// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginMarketplace.swift - Decentralized plugin source, validation, and install domain.

import Darwin
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

    init(trustedAuthors: TrustedAuthorRegistry = TrustedAuthorRegistry.loadDefault()) {
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

            let payload: Data
            do {
                payload = try PluginPackageSignaturePayload.payload(
                    at: pluginDirectory,
                    manifestFileName: manifest.manifestFileName
                )
            } catch {
                return PluginValidationReport(
                    signatureStatus: .invalid,
                    warnings: [.invalidSignature]
                )
            }
            let verification = SignatureVerifier().verify(
                payload: payload,
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

// MARK: - Plugin Installer

enum PluginInstallerError: Error, Equatable {
    case missingManifest(String)
    case legacyManifestRequiresMigration(String)
    case pluginAlreadyInstalled(String)
    case pluginNotInstalled(String)
    case invalidSignature(String)
    case unsafeSourceName(String)
    case unsupportedLocalSource(String)
    case gitCloneFailed(Int32)
    case gitCloneTimedOut(TimeInterval)
    case repositoryMetadataPresent(String)
    case packageChangedDuringInstall(String)
    case atomicPromotionFailed(String, Int32)
    case atomicRollbackFailed(String, Int32)
}

extension PluginInstallerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingManifest(let path):
            return "Plugin manifest not found in \(path)."
        case .legacyManifestRequiresMigration(let pluginID):
            return "Plugin \(pluginID) uses legacy manifest.toml. Add cocxy-plugin.toml with explicit capabilities before installing it."
        case .pluginAlreadyInstalled(let pluginID):
            return "Plugin \(pluginID) is already installed. Enable replacement to install different code."
        case .pluginNotInstalled(let pluginID):
            return "Plugin \(pluginID) is not installed."
        case .invalidSignature(let pluginID):
            return "Plugin \(pluginID) has an invalid signature."
        case .unsafeSourceName(let source):
            return "Plugin source has an unsafe name: \(source)."
        case .unsupportedLocalSource(let path):
            return "Plugin source is not a readable local directory: \(path)."
        case .gitCloneFailed(let status):
            return "Plugin source clone failed with exit code \(status)."
        case .gitCloneTimedOut(let seconds):
            return "Plugin source clone timed out after \(Self.formatted(seconds)) seconds."
        case .repositoryMetadataPresent(let pluginID):
            return "Plugin \(pluginID) still contains repository control metadata."
        case .packageChangedDuringInstall(let pluginID):
            return "Plugin \(pluginID) changed while it was being installed."
        case .atomicPromotionFailed(let pluginID, let code):
            return "Plugin \(pluginID) could not be published atomically (error \(code))."
        case .atomicRollbackFailed(let pluginID, let code):
            return "Plugin \(pluginID) could not be restored after a failed installation (error \(code))."
        }
    }

    private static func formatted(_ seconds: TimeInterval) -> String {
        seconds.rounded() == seconds
            ? String(format: "%.0f", seconds)
            : String(format: "%.1f", seconds)
    }
}

struct PluginInstallReceipt: Equatable, Sendable {
    let pluginID: String
    let installedURL: URL
    let manifest: PluginManifest
    let signatureStatus: PluginSignatureStatus
    let packageTreeSHA256: String
}

enum PluginRegistryFileLockError: Error, Equatable {
    case unavailable(Int32)
}

private enum PluginRegistryLockMode: Equatable {
    case shared
    case exclusive
}

private final class PluginRegistryProcessLock: @unchecked Sendable {
    private var lock = pthread_rwlock_t()

    init() {
        precondition(pthread_rwlock_init(&lock, nil) == 0)
    }

    deinit {
        pthread_rwlock_destroy(&lock)
    }

    func withLock<T>(
        mode: PluginRegistryLockMode,
        _ operation: () throws -> T
    ) rethrows -> T {
        switch mode {
        case .shared:
            pthread_rwlock_rdlock(&lock)
        case .exclusive:
            pthread_rwlock_wrlock(&lock)
        }
        defer { pthread_rwlock_unlock(&lock) }
        return try operation()
    }

    func withExclusiveLockIfAvailable<T>(
        _ operation: () throws -> T
    ) rethrows -> T? {
        guard pthread_rwlock_trywrlock(&lock) == 0 else { return nil }
        defer { pthread_rwlock_unlock(&lock) }
        return try operation()
    }
}

/// Serializes registry mutations both within this process and across Cocxy
/// processes that point at the same plugin directory.
final class PluginRegistrySynchronization: @unchecked Sendable {
    static let shared = PluginRegistrySynchronization()

    private let processLocksLock = NSLock()
    private var processLocks: [String: PluginRegistryProcessLock] = [:]

    private init() {}

    func withProcessLock<T>(
        pluginsDirectory: URL,
        _ operation: () throws -> T
    ) rethrows -> T {
        try processLock(for: pluginsDirectory).withLock(
            mode: .exclusive,
            operation
        )
    }

    func withProcessReadLock<T>(
        pluginsDirectory: URL,
        _ operation: () throws -> T
    ) rethrows -> T {
        try processLock(for: pluginsDirectory).withLock(
            mode: .shared,
            operation
        )
    }

    func withProcessLockIfAvailable<T>(
        pluginsDirectory: URL,
        _ operation: () throws -> T
    ) rethrows -> T? {
        try processLock(for: pluginsDirectory)
            .withExclusiveLockIfAvailable(operation)
    }

    func withFileLock<T>(
        pluginsDirectory: URL,
        fileManager: FileManager = .default,
        _ operation: () throws -> T
    ) throws -> T {
        guard let result = try withFileLock(
            pluginsDirectory: pluginsDirectory,
            fileManager: fileManager,
            mode: .exclusive,
            blocking: true,
            operation
        ) else {
            throw PluginRegistryFileLockError.unavailable(EWOULDBLOCK)
        }
        return result
    }

    func withSharedFileLock<T>(
        pluginsDirectory: URL,
        fileManager: FileManager = .default,
        _ operation: () throws -> T
    ) throws -> T {
        guard let result = try withFileLock(
            pluginsDirectory: pluginsDirectory,
            fileManager: fileManager,
            mode: .shared,
            blocking: true,
            operation
        ) else {
            throw PluginRegistryFileLockError.unavailable(EWOULDBLOCK)
        }
        return result
    }

    func withFileLockIfAvailable<T>(
        pluginsDirectory: URL,
        fileManager: FileManager = .default,
        _ operation: () throws -> T
    ) throws -> T? {
        try withFileLock(
            pluginsDirectory: pluginsDirectory,
            fileManager: fileManager,
            mode: .exclusive,
            blocking: false,
            operation
        )
    }

    private func withFileLock<T>(
        pluginsDirectory: URL,
        fileManager: FileManager,
        mode: PluginRegistryLockMode,
        blocking: Bool,
        _ operation: () throws -> T
    ) throws -> T? {
        let pluginsDirectory = Self.canonicalDirectoryURL(pluginsDirectory)
        try fileManager.createDirectory(
            at: pluginsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let lockURL = pluginsDirectory.appendingPathComponent(
            ".plugin-registry.lock",
            isDirectory: false
        )
        let descriptor = lockURL.path.withCString {
            Darwin.open($0, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        }
        guard descriptor >= 0 else {
            throw PluginRegistryFileLockError.unavailable(errno)
        }
        defer { Darwin.close(descriptor) }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              metadata.st_uid == geteuid(),
              metadata.st_nlink == 1,
              Darwin.fchmod(descriptor, 0o600) == 0 else {
            throw PluginRegistryFileLockError.unavailable(errno)
        }
        let requestedLock = mode == .shared ? LOCK_SH : LOCK_EX
        let lockOperation = blocking ? requestedLock : requestedLock | LOCK_NB
        while flock(descriptor, lockOperation) != 0 {
            if !blocking, errno == EWOULDBLOCK {
                return nil
            }
            guard errno == EINTR else {
                throw PluginRegistryFileLockError.unavailable(errno)
            }
        }
        defer {
            _ = flock(descriptor, LOCK_UN)
        }

        return try operation()
    }

    private func processLock(for pluginsDirectory: URL) -> PluginRegistryProcessLock {
        let key = Self.canonicalDirectoryURL(pluginsDirectory).path
        return processLocksLock.withLock {
            if let existing = processLocks[key] { return existing }
            let created = PluginRegistryProcessLock()
            processLocks[key] = created
            return created
        }
    }

    static func canonicalDirectoryURL(_ directory: URL) -> URL {
        directory.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }
}

/// Binds a receipt to every installed regular file. The signed package payload
/// already covers all runtime files; the exact manifest and optional signature
/// sidecar are added because signature canonicalization intentionally excludes
/// their self-referential fields.
enum PluginInstalledTreeDigest {
    private static let signatureSidecarName = ".cocxy-signature.json"

    static func sha256(
        at pluginDirectory: URL,
        manifestFileName: String,
        fileManager: FileManager = .default
    ) throws -> String {
        let pluginID = pluginDirectory.lastPathComponent
        let gitMetadata = pluginDirectory.appendingPathComponent(".git", isDirectory: false)
        var gitMetadataState = stat()
        if Darwin.lstat(gitMetadata.path, &gitMetadataState) == 0 || errno != ENOENT {
            throw PluginInstallerError.repositoryMetadataPresent(pluginID)
        }

        let packagePayload = try PluginPackageSignaturePayload.payload(
            at: pluginDirectory,
            manifestFileName: manifestFileName,
            fileManager: fileManager
        )
        let manifestData = try readRegularFile(
            at: pluginDirectory.appendingPathComponent(manifestFileName),
            relativePath: manifestFileName
        )
        let sidecarURL = pluginDirectory.appendingPathComponent(signatureSidecarName)
        let sidecarData = try optionalRegularFile(
            at: sidecarURL,
            relativePath: signatureSidecarName
        )

        let descriptor = [
            "cocxy-installed-plugin-tree-v1",
            "package-size:\(packagePayload.count)",
            "package-sha256:\(SignatureDigest.sha256Hex(packagePayload))",
            "manifest-size:\(manifestData.count)",
            "manifest-sha256:\(SignatureDigest.sha256Hex(manifestData))",
            "sidecar-present:\(sidecarData == nil ? 0 : 1)",
            "sidecar-size:\(sidecarData?.count ?? 0)",
            "sidecar-sha256:\(sidecarData.map(SignatureDigest.sha256Hex) ?? "-")",
        ].joined(separator: "\n") + "\n"
        return SignatureDigest.sha256Hex(Data(descriptor.utf8))
    }

    private static func optionalRegularFile(
        at url: URL,
        relativePath: String
    ) throws -> Data? {
        var metadata = stat()
        if Darwin.lstat(url.path, &metadata) != 0 {
            guard errno == ENOENT else {
                throw PluginPackageSignaturePayloadError.unreadableFile(relativePath)
            }
            return nil
        }
        return try readRegularFile(at: url, relativePath: relativePath)
    }

    private static func readRegularFile(
        at url: URL,
        relativePath: String
    ) throws -> Data {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw PluginPackageSignaturePayloadError.unreadableFile(relativePath)
        }
        defer { Darwin.close(descriptor) }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              metadata.st_size >= 0,
              metadata.st_size <= off_t(PluginPackageSignaturePayload.maxPayloadBytes)
        else {
            throw PluginPackageSignaturePayloadError.unreadableFile(relativePath)
        }

        var data = Data()
        data.reserveCapacity(Int(metadata.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else {
                throw PluginPackageSignaturePayloadError.unreadableFile(relativePath)
            }
            if count == 0 { break }
            guard count <= PluginPackageSignaturePayload.maxPayloadBytes - data.count else {
                throw PluginPackageSignaturePayloadError.payloadTooLarge(
                    PluginPackageSignaturePayload.maxPayloadBytes
                )
            }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}

/// Installs decentralized plugin repos into the local plugin registry.
struct PluginInstaller: @unchecked Sendable {
    typealias PrePromotionAction = @Sendable (_ stagedPlugin: URL) throws -> Void

    let pluginsDirectory: URL
    private let fileManager: FileManager
    private let validator: PluginValidator
    private let capabilityGrantStore: PluginCapabilityGrantStore
    private let updateSourceStore: PluginUpdateSourceStore
    private let gitProcessRunner: MarketplaceGitProcessRunner
    private let prePromotionAction: PrePromotionAction

    init(
        pluginsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy/plugins"),
        fileManager: FileManager = .default,
        validator: PluginValidator = PluginValidator(),
        capabilityGrantStore: PluginCapabilityGrantStore = PluginCapabilityGrantStore(),
        updateSourceStore: PluginUpdateSourceStore? = nil,
        gitProcessRunner: MarketplaceGitProcessRunner = MarketplaceGitProcessRunner(),
        prePromotionAction: @escaping PrePromotionAction = { _ in }
    ) {
        let canonicalPluginsDirectory = PluginRegistrySynchronization
            .canonicalDirectoryURL(pluginsDirectory)
        self.pluginsDirectory = canonicalPluginsDirectory
        self.fileManager = fileManager
        self.validator = validator
        self.capabilityGrantStore = capabilityGrantStore
        self.updateSourceStore = updateSourceStore
            ?? PluginUpdateSourceStore(pluginsDirectory: canonicalPluginsDirectory)
        self.gitProcessRunner = gitProcessRunner
        self.prePromotionAction = prePromotionAction
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
        try removeRepositoryMetadata(from: stagedPlugin)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: stagedPlugin.path
        )

        let stagedManifest = try PluginRegistry.loadManifest(
            from: stagedPlugin,
            fileManager: fileManager
        )
        guard stagedManifest.manifestFileName == PluginManifest.marketplaceManifestFileName else {
            throw PluginInstallerError.legacyManifestRequiresMigration(stagedManifest.id)
        }
        let stagedTreeSHA256 = try PluginInstalledTreeDigest.sha256(
            at: stagedPlugin,
            manifestFileName: stagedManifest.manifestFileName,
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
        return try PluginRegistrySynchronization.shared.withProcessLock(
            pluginsDirectory: pluginsDirectory
        ) {
            try PluginRegistrySynchronization.shared.withFileLock(
                pluginsDirectory: pluginsDirectory,
                fileManager: fileManager
            ) {
                let destinationExists = Self.entryExists(at: finalURL)
                guard !destinationExists || replaceExisting else {
                    throw PluginInstallerError.pluginAlreadyInstalled(stagedManifest.id)
                }
                let previousUpdateSource = try updateSourceStore.source(for: stagedManifest.id)

                // Authorization is bound to an installation generation, never
                // merely to a reusable manifest ID. This also clears orphaned
                // state when a prior directory was removed out of band.
                try resetAuthorization(for: stagedManifest.id)
                try prePromotionAction(stagedPlugin)

                let promotion = try promote(
                    stagedPlugin: stagedPlugin,
                    finalURL: finalURL,
                    replaceExisting: replaceExisting,
                    pluginID: stagedManifest.id
                )
                do {
                    let installedManifest = try PluginRegistry.loadManifest(
                        from: finalURL,
                        fileManager: fileManager
                    )
                    let installedReport = try validator.validate(
                        manifest: installedManifest,
                        sourceURL: sourceURL,
                        pluginDirectory: finalURL
                    )
                    let installedTreeSHA256 = try PluginInstalledTreeDigest.sha256(
                        at: finalURL,
                        manifestFileName: installedManifest.manifestFileName,
                        fileManager: fileManager
                    )
                    guard installedManifest == stagedManifest.relocated(to: finalURL.path),
                          installedReport.isInstallable,
                          installedReport.signatureStatus == report.signatureStatus,
                          installedTreeSHA256 == stagedTreeSHA256
                    else {
                        throw PluginInstallerError.packageChangedDuringInstall(stagedManifest.id)
                    }

                    if installedReport.signatureStatus == .verified,
                       let updateSource = PluginUpdateSource.remoteRepository(sourceURL) {
                        try updateSourceStore.save(updateSource, for: installedManifest.id)
                    } else {
                        try updateSourceStore.removeSource(for: installedManifest.id)
                    }

                    return PluginInstallReceipt(
                        pluginID: installedManifest.id,
                        installedURL: finalURL,
                        manifest: installedManifest,
                        signatureStatus: installedReport.signatureStatus,
                        packageTreeSHA256: installedTreeSHA256
                    )
                } catch {
                    do {
                        try rollback(
                            promotion,
                            stagedPlugin: stagedPlugin,
                            finalURL: finalURL,
                            pluginID: stagedManifest.id
                        )
                    } catch {
                        try? restoreUpdateSource(previousUpdateSource, for: stagedManifest.id)
                        throw error
                    }
                    try? restoreUpdateSource(previousUpdateSource, for: stagedManifest.id)
                    throw error
                }
            }
        }
    }

    func uninstall(id: String) throws {
        try PluginValidator.validatePluginID(id)
        try PluginRegistrySynchronization.shared.withProcessLock(
            pluginsDirectory: pluginsDirectory
        ) {
            try PluginRegistrySynchronization.shared.withFileLock(
                pluginsDirectory: pluginsDirectory,
                fileManager: fileManager
            ) {
                let pluginURL = pluginsDirectory.appendingPathComponent(id, isDirectory: true)
                guard Self.entryExists(at: pluginURL) else {
                    throw PluginInstallerError.pluginNotInstalled(id)
                }
                try resetAuthorization(for: id)
                try updateSourceStore.removeSource(for: id)
                try fileManager.removeItem(at: pluginURL)
            }
        }
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

        let result = try gitProcessRunner.clone(
            sourceURL: sourceURL,
            destinationURL: destination
        )
        if result.timedOut {
            throw PluginInstallerError.gitCloneTimedOut(gitProcessRunner.timeoutSeconds)
        }
        guard result.exitCode == 0 else {
            throw PluginInstallerError.gitCloneFailed(result.exitCode)
        }
    }

    private func removeRepositoryMetadata(from pluginDirectory: URL) throws {
        let gitMetadata = pluginDirectory.appendingPathComponent(".git", isDirectory: true)
        guard fileManager.fileExists(atPath: gitMetadata.path) else { return }
        try fileManager.removeItem(at: gitMetadata)
    }

    private enum Promotion {
        case inserted
        case swapped
    }

    private func promote(
        stagedPlugin: URL,
        finalURL: URL,
        replaceExisting: Bool,
        pluginID: String
    ) throws -> Promotion {
        for _ in 0..<4 {
            if Self.entryExists(at: finalURL) {
                guard replaceExisting else {
                    throw PluginInstallerError.pluginAlreadyInstalled(pluginID)
                }
                let result = Self.rename(
                    stagedPlugin,
                    finalURL,
                    flags: UInt32(RENAME_SWAP)
                )
                if result == 0 { return .swapped }
                if errno == ENOENT { continue }
                throw PluginInstallerError.atomicPromotionFailed(pluginID, errno)
            }

            let result = Self.rename(
                stagedPlugin,
                finalURL,
                flags: UInt32(RENAME_EXCL)
            )
            if result == 0 { return .inserted }
            if errno == EEXIST { continue }
            throw PluginInstallerError.atomicPromotionFailed(pluginID, errno)
        }
        throw PluginInstallerError.atomicPromotionFailed(pluginID, EBUSY)
    }

    private func rollback(
        _ promotion: Promotion,
        stagedPlugin: URL,
        finalURL: URL,
        pluginID: String
    ) throws {
        switch promotion {
        case .inserted:
            do {
                try fileManager.removeItem(at: finalURL)
            } catch {
                throw PluginInstallerError.atomicRollbackFailed(pluginID, errno)
            }
        case .swapped:
            let result = Self.rename(
                stagedPlugin,
                finalURL,
                flags: UInt32(RENAME_SWAP)
            )
            guard result == 0 else {
                throw PluginInstallerError.atomicRollbackFailed(pluginID, errno)
            }
        }
    }

    private func restoreUpdateSource(
        _ source: PluginUpdateSource?,
        for pluginID: String
    ) throws {
        if let source {
            try updateSourceStore.save(source, for: pluginID)
        } else {
            try updateSourceStore.removeSource(for: pluginID)
        }
    }

    private static func entryExists(at url: URL) -> Bool {
        var metadata = stat()
        return Darwin.lstat(url.path, &metadata) == 0
    }

    private static func rename(_ source: URL, _ destination: URL, flags: UInt32) -> Int32 {
        source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                Darwin.renameatx_np(
                    AT_FDCWD,
                    sourcePath,
                    AT_FDCWD,
                    destinationPath,
                    flags
                )
            }
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

    private func resetAuthorization(for id: String) throws {
        try removeEnabledState(for: id)
        try capabilityGrantStore.revokeAll(for: id)
        NotificationCenter.default.post(
            name: .cocxyPluginAuthorizationDidReset,
            object: nil,
            userInfo: [
                "pluginID": id,
                "pluginsDirectory": PluginRegistrySynchronization
                    .canonicalDirectoryURL(pluginsDirectory).path,
            ]
        )
    }
}
