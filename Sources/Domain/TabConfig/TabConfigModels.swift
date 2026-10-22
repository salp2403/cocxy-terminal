// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabConfigModels.swift - Reusable tab configuration models and startup security.

import CryptoKit
import Foundation

/// Shareable terminal setup saved under `~/.cocxy/tabs/<name>.toml`.
struct TabConfig: Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let name: String
    let workingDirectory: String
    let command: String?
    let environment: [String: String]
    let theme: String?
    let layout: TabConfigLayout?

    init(
        schemaVersion: Int = TabConfig.currentSchemaVersion,
        name: String,
        workingDirectory: String,
        command: String? = nil,
        environment: [String: String] = [:],
        theme: String? = nil,
        layout: TabConfigLayout? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.workingDirectory = workingDirectory
        self.command = command
        self.environment = environment
        self.theme = theme
        self.layout = layout
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
            workingDirectory: ProjectPathCanonicalizer.canonicalURL(workingDirectory).path,
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
