// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabConfigStore.swift - Local TOML-backed reusable tab configurations.

import CryptoKit
import Darwin
import Foundation

// MARK: - Tab Config

/// Shareable terminal tab setup saved under `~/.cocxy/tabs/<name>.toml`.
///
/// The schema is intentionally small and local-only:
/// - working directory
/// - optional shell command to run after the tab opens
/// - optional environment overrides for that command
/// - optional terminal theme override for the created surface
struct TabConfig: Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let name: String
    let workingDirectory: String
    let command: String?
    let environment: [String: String]
    let theme: String?

    init(
        schemaVersion: Int = TabConfig.currentSchemaVersion,
        name: String,
        workingDirectory: String,
        command: String? = nil,
        environment: [String: String] = [:],
        theme: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.workingDirectory = workingDirectory
        self.command = command
        self.environment = environment
        self.theme = theme
    }
}

struct TabConfigSnapshot: Equatable, Sendable {
    let config: TabConfig
    let sourceData: Data
    let sourceDigest: String
}

enum TabConfigLaunchOrigin: Equatable, Sendable {
    case localSocket
    case userInterface
}

struct TabConfigStartupAuthorizationRequest: Equatable, Sendable {
    let id: UUID
    let configName: String
    let sourceDigest: String
    let workingDirectory: String
    let destinationTabID: TabID
    let launchOrigin: TabConfigLaunchOrigin
    let command: String?
    let environment: [String: String]
    let startupInput: String
    let expiresAt: Date
}

enum TabConfigStartupSecurity {
    static let authorizationLifetime: TimeInterval = 60

    static func makeAuthorizationRequest(
        snapshot: TabConfigSnapshot,
        workingDirectory: URL,
        destinationTabID: TabID,
        launchOrigin: TabConfigLaunchOrigin,
        now: Date = Date()
    ) -> TabConfigStartupAuthorizationRequest? {
        guard launchOrigin == .userInterface else { return nil }
        guard let startupInput = startupInput(for: snapshot.config) else { return nil }
        return TabConfigStartupAuthorizationRequest(
            id: UUID(),
            configName: snapshot.config.name,
            sourceDigest: snapshot.sourceDigest,
            workingDirectory: workingDirectory.standardizedFileURL.path,
            destinationTabID: destinationTabID,
            launchOrigin: launchOrigin,
            command: snapshot.config.command?.trimmingCharacters(in: .whitespacesAndNewlines),
            environment: snapshot.config.environment,
            startupInput: startupInput,
            expiresAt: now.addingTimeInterval(authorizationLifetime)
        )
    }

    static func startupInput(for config: TabConfig) -> String? {
        let assignments = config.environment
            .keys
            .sorted()
            .compactMap { key -> String? in
                guard let value = config.environment[key],
                      TabConfigTOMLCodec.isValidEnvironmentKey(key) else {
                    return nil
                }
                return "\(key)=\(shellSingleQuoted(value))"
            }

        if let command = config.command?.trimmingCharacters(in: .whitespacesAndNewlines),
           !command.isEmpty {
            return (assignments + [command]).joined(separator: " ") + "\r"
        }

        guard !assignments.isEmpty else { return nil }
        return "export \(assignments.joined(separator: " "))\r"
    }

    static func approvalPreview(_ request: TabConfigStartupAuthorizationRequest) -> String {
        escapedPreview(
            request.startupInput,
            preservingTerminalLineBreaks: true,
            maximumScalars: nil
        )
    }

    static func sourceDigest(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func approvalMetadataPreview(_ value: String) -> String {
        escapedPreview(
            value,
            preservingTerminalLineBreaks: false,
            maximumScalars: 512
        )
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func escapedPreview(
        _ value: String,
        preservingTerminalLineBreaks: Bool,
        maximumScalars: Int?
    ) -> String {
        var preview = ""
        var scalarCount = 0
        for scalar in value.unicodeScalars {
            if let maximumScalars, scalarCount >= maximumScalars {
                preview += "..."
                break
            }
            scalarCount += 1

            if scalar == "\\" {
                preview += "\\\\"
            } else if preservingTerminalLineBreaks, scalar == "\t" {
                preview += "\\t"
            } else if preservingTerminalLineBreaks, scalar == "\n" {
                preview += "\\n\n"
            } else if preservingTerminalLineBreaks, scalar == "\r" {
                preview += "\\r"
            } else {
                switch scalar.properties.generalCategory {
                case .control, .format, .lineSeparator, .paragraphSeparator:
                    preview += String(format: "\\u{%04X}", scalar.value)
                default:
                    preview.unicodeScalars.append(scalar)
                }
            }
        }
        return preview
    }
}

// MARK: - Store Errors

enum TabConfigStoreError: Error, Equatable, LocalizedError {
    case invalidName(String)
    case invalidConfig(String)
    case notFound(String)
    case destinationExists(String)

    var errorDescription: String? {
        switch self {
        case .invalidName(let name):
            return "Invalid tab config name: \(name)"
        case .invalidConfig(let message):
            return "Invalid tab config: \(message)"
        case .notFound(let name):
            return "Tab config not found: \(name)"
        case .destinationExists(let path):
            return "Destination already exists: \(path)"
        }
    }
}

// MARK: - TOML Codec

enum TabConfigTOMLCodec {
    private static let parser = TOMLParser()

    static func parse(_ source: String) throws -> TabConfig {
        let parsed: [String: TOMLValue]
        do {
            parsed = try parser.parse(source)
        } catch {
            throw TabConfigStoreError.invalidConfig(error.localizedDescription)
        }

        let version = intValue(parsed["schema-version"]) ?? TabConfig.currentSchemaVersion
        guard version == TabConfig.currentSchemaVersion else {
            throw TabConfigStoreError.invalidConfig("unsupported schema-version \(version)")
        }

        guard let name = stringValue(parsed["name"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            throw TabConfigStoreError.invalidConfig("missing name")
        }
        guard let workingDirectory = stringValue(parsed["working-directory"])?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !workingDirectory.isEmpty else {
            throw TabConfigStoreError.invalidConfig("missing working-directory")
        }

        let command = nonEmptyString(parsed["command"])
        let theme = nonEmptyString(parsed["theme"])
        let environment = try environmentValue(parsed["env"])

        return TabConfig(
            schemaVersion: version,
            name: name,
            workingDirectory: workingDirectory,
            command: command,
            environment: environment,
            theme: theme
        )
    }

    static func render(_ config: TabConfig) -> String {
        var lines: [String] = [
            "# Cocxy reusable tab configuration",
            "schema-version = \(config.schemaVersion)",
            "name = \"\(escape(config.name))\"",
            "working-directory = \"\(escape(config.workingDirectory))\"",
        ]

        if let command = config.command?.trimmingCharacters(in: .whitespacesAndNewlines),
           !command.isEmpty {
            lines.append("command = \"\(escape(command))\"")
        }

        if let theme = config.theme?.trimmingCharacters(in: .whitespacesAndNewlines),
           !theme.isEmpty {
            lines.append("theme = \"\(escape(theme))\"")
        }

        if !config.environment.isEmpty {
            lines.append("")
            lines.append("[env]")
            for key in config.environment.keys.sorted() {
                guard let value = config.environment[key] else { continue }
                lines.append("\(key) = \"\(escape(value))\"")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func environmentValue(_ value: TOMLValue?) throws -> [String: String] {
        guard case .table(let table)? = value else { return [:] }

        var result: [String: String] = [:]
        for (key, rawValue) in table {
            guard isValidEnvironmentKey(key) else {
                throw TabConfigStoreError.invalidConfig("invalid env key \(key)")
            }
            guard let value = stringValue(rawValue) else {
                throw TabConfigStoreError.invalidConfig("env \(key) must be a string")
            }
            result[key] = value
        }
        return result
    }

    static func isValidEnvironmentKey(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first,
              first == "_" || CharacterSet.letters.contains(first) else {
            return false
        }
        return key.unicodeScalars.allSatisfy {
            $0 == "_" || CharacterSet.alphanumerics.contains($0)
        }
    }

    private static func nonEmptyString(_ value: TOMLValue?) -> String? {
        guard let value = stringValue(value)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func stringValue(_ value: TOMLValue?) -> String? {
        guard case .string(let value)? = value else { return nil }
        return value
    }

    private static func intValue(_ value: TOMLValue?) -> Int? {
        guard case .integer(let value)? = value else { return nil }
        return value
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

// MARK: - Tab Config Store

struct TabConfigStore {
    private static let maximumConfigBytes = 1_048_576

    let rootDirectory: URL
    let socketExportDirectory: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL = TabConfigStore.defaultRootDirectory,
        socketExportDirectory: URL = TabConfigStore.defaultSocketExportDirectory,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.socketExportDirectory = socketExportDirectory.standardizedFileURL
        self.fileManager = fileManager
    }

    static var defaultRootDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy")
            .appendingPathComponent("tabs")
    }

    static var defaultSocketExportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy")
            .appendingPathComponent("exports")
            .appendingPathComponent("tab-configs")
    }

    static func validatedSocketExportLeafName(_ rawName: String) throws -> String {
        guard rawName == rawName.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawName.isEmpty,
              rawName.utf8.count <= 128,
              rawName.hasSuffix(".toml"),
              rawName.first != ".",
              !rawName.contains(".."),
              !rawName.contains("/"),
              !rawName.contains("\\"),
              !rawName.contains("\0") else {
            throw TabConfigStoreError.invalidName(rawName)
        }

        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
        )
        guard rawName.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw TabConfigStoreError.invalidName(rawName)
        }
        return rawName
    }

    static func suggestedName(from displayTitle: String) -> String {
        let lowercased = displayTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        var result = ""
        var previousWasSeparator = false

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-")
        for scalar in lowercased.unicodeScalars {
            let isAllowed = allowed.contains(scalar)
            if isAllowed {
                result.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                result.append("-")
                previousWasSeparator = true
            }
        }

        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return trimmed.isEmpty ? "tab" : trimmed
    }

    func save(_ config: TabConfig) throws {
        let target = try fileURL(forName: config.name)
        try ensureRootDirectory()
        try TabConfigTOMLCodec.render(config).write(
            to: target,
            atomically: true,
            encoding: .utf8
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: target.path
        )
    }

    func load(named name: String) throws -> TabConfig {
        try loadSnapshot(named: name).config
    }

    func loadSnapshot(named name: String) throws -> TabConfigSnapshot {
        let data = try readSourceData(named: name)
        guard let source = String(data: data, encoding: .utf8) else {
            throw TabConfigStoreError.invalidConfig("source is not bounded UTF-8 TOML")
        }
        return TabConfigSnapshot(
            config: try TabConfigTOMLCodec.parse(source),
            sourceData: data,
            sourceDigest: TabConfigStartupSecurity.sourceDigest(for: data)
        )
    }

    func export(named name: String, to destinationURL: URL, overwrite: Bool = false) throws -> URL {
        let source = try fileURL(forName: name)
        guard fileManager.fileExists(atPath: source.path) else {
            throw TabConfigStoreError.notFound(name)
        }

        let target = try exportDestination(for: source, requestedDestination: destinationURL)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: target.path, isDirectory: &isDirectory) {
            guard !isDirectory.boolValue else {
                throw TabConfigStoreError.invalidConfig("export destination is a directory")
            }
            guard overwrite else {
                throw TabConfigStoreError.destinationExists(target.path)
            }
            try fileManager.removeItem(at: target)
        }

        try fileManager.copyItem(at: source, to: target)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: target.path
        )
        return target.standardizedFileURL
    }

    /// Publishes a socket-requested export beneath a fixed owner-only root.
    /// The caller supplies only a validated leaf name; descriptor-relative
    /// publication prevents parent and final-component symlink redirection.
    func exportForSocket(named name: String, fileName: String, overwrite: Bool = false) throws -> URL {
        let leafName = try Self.validatedSocketExportLeafName(fileName)
        let data = try loadSnapshot(named: name).sourceData

        do {
            let writer = try ProjectTemplateSecureDestinationWriter(
                destinationURL: socketExportDirectory,
                policy: .ownerOnlyPrivateFiles
            )
            try writer.write(data, relativePath: leafName, overwrite: overwrite)
        } catch ProjectTemplateError.destinationExists {
            throw TabConfigStoreError.destinationExists(
                socketExportDirectory.appendingPathComponent(leafName).path
            )
        } catch {
            throw TabConfigStoreError.invalidConfig("socket export destination is unsafe")
        }

        return socketExportDirectory.appendingPathComponent(leafName).standardizedFileURL
    }

    func listNames() throws -> [String] {
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return [] }
        let entries = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return entries
            .filter { $0.pathExtension == "toml" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    private func exportDestination(for source: URL, requestedDestination: URL) throws -> URL {
        let destination = requestedDestination.standardizedFileURL
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return destination.appendingPathComponent(source.lastPathComponent).standardizedFileURL
        }

        if destination.hasDirectoryPath {
            try fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            return destination.appendingPathComponent(source.lastPathComponent).standardizedFileURL
        }

        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return destination
    }

    private func readSourceData(named name: String) throws -> Data {
        let source = try fileURL(forName: name)
        let descriptor = source.path.withCString {
            Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        if descriptor < 0, errno == ENOENT {
            throw TabConfigStoreError.notFound(name)
        }
        guard descriptor >= 0 else {
            throw TabConfigStoreError.invalidConfig("source path is unsafe")
        }
        defer { Darwin.close(descriptor) }

        var initialMetadata = stat()
        guard Darwin.fstat(descriptor, &initialMetadata) == 0,
              Self.isRegularFile(initialMetadata),
              initialMetadata.st_uid == geteuid(),
              initialMetadata.st_nlink == 1,
              initialMetadata.st_size >= 0,
              initialMetadata.st_size <= off_t(Self.maximumConfigBytes),
              initialMetadata.st_mode & mode_t(S_IWGRP | S_IWOTH) == 0 else {
            throw TabConfigStoreError.invalidConfig("source file is unsafe")
        }

        var data = Data()
        data.reserveCapacity(Int(initialMetadata.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else {
                throw TabConfigStoreError.invalidConfig("source file could not be read")
            }
            if count == 0 { break }
            guard count <= Self.maximumConfigBytes - data.count else {
                throw TabConfigStoreError.invalidConfig("source file exceeds the size limit")
            }
            data.append(contentsOf: buffer.prefix(count))
        }

        var finalMetadata = stat()
        guard Darwin.fstat(descriptor, &finalMetadata) == 0,
              Self.sameSourceVersion(initialMetadata, finalMetadata),
              data.count == Int(finalMetadata.st_size) else {
            throw TabConfigStoreError.invalidConfig("source file changed while reading")
        }
        return data
    }

    private static func sameSourceVersion(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev
            && lhs.st_ino == rhs.st_ino
            && lhs.st_size == rhs.st_size
            && lhs.st_mode == rhs.st_mode
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    private static func isRegularFile(_ metadata: stat) -> Bool {
        metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
    }

    func fileURL(forName name: String) throws -> URL {
        let normalized = try normalizedName(name)
        let target = rootDirectory.appendingPathComponent(normalized)
            .appendingPathExtension("toml")
            .standardizedFileURL
        guard target.path.hasPrefix(rootDirectory.path + "/") else {
            throw TabConfigStoreError.invalidName(name)
        }
        return target
    }

    private func ensureRootDirectory() throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func normalizedName(_ rawName: String) throws -> String {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasSuffix(".toml") {
            name = String(name.dropLast(5))
        }
        guard !name.isEmpty else {
            throw TabConfigStoreError.invalidName(rawName)
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              !name.contains("..") else {
            throw TabConfigStoreError.invalidName(rawName)
        }
        return name
    }
}
