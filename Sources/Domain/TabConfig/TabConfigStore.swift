// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabConfigStore.swift - Local TOML-backed reusable tab configurations.

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

// MARK: - Store Errors

enum TabConfigStoreError: Error, Equatable, LocalizedError {
    case invalidName(String)
    case invalidConfig(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidName(let name):
            return "Invalid tab config name: \(name)"
        case .invalidConfig(let message):
            return "Invalid tab config: \(message)"
        case .notFound(let name):
            return "Tab config not found: \(name)"
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
    let rootDirectory: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL = TabConfigStore.defaultRootDirectory,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.fileManager = fileManager
    }

    static var defaultRootDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy")
            .appendingPathComponent("tabs")
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
        let target = try fileURL(forName: name)
        guard fileManager.fileExists(atPath: target.path) else {
            throw TabConfigStoreError.notFound(name)
        }
        let source = try String(contentsOf: target, encoding: .utf8)
        return try TabConfigTOMLCodec.parse(source)
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
