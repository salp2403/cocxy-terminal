// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DBCloudHelperModels.swift - Local DB/cloud helper catalog and command contracts.

import Foundation

enum DBCloudHelperKind: String, CaseIterable, Identifiable, Sendable {
    case database
    case cloud
    case container

    var id: String { rawValue }

    var title: String {
        switch self {
        case .database: return "Database"
        case .cloud: return "Cloud"
        case .container: return "Container"
        }
    }

    var systemImage: String {
        switch self {
        case .database: return "cylinder.split.1x2"
        case .cloud: return "cloud"
        case .container: return "shippingbox"
        }
    }
}

struct DBCloudHelperDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let description: String
    let kind: DBCloudHelperKind
    let manifest: PluginManifest
}

enum DBCloudHelperCatalog {
    private static let helperKinds: [String: DBCloudHelperKind] = [
        "cocxy-db-postgres": .database,
        "cocxy-db-mysql": .database,
        "cocxy-db-sqlite": .database,
        "cocxy-db-redis": .database,
        "cocxy-aws-cli-helper": .cloud,
        "cocxy-gcp-cli": .cloud,
        "cocxy-azure-cli": .cloud,
        "cocxy-cloudflare": .cloud,
        "cocxy-docker-helper": .container,
        "cocxy-kubernetes": .container,
    ]

    static func descriptors(from manifests: [PluginManifest]) -> [DBCloudHelperDescriptor] {
        manifests.compactMap { manifest in
            guard let kind = helperKinds[manifest.id] else { return nil }
            return DBCloudHelperDescriptor(
                id: manifest.id,
                name: manifest.name,
                description: manifest.description,
                kind: kind,
                manifest: manifest
            )
        }
        .sorted {
            if $0.kind.rawValue == $1.kind.rawValue {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return DBCloudHelperKind.allCases.firstIndex(of: $0.kind) ?? .max
                < DBCloudHelperKind.allCases.firstIndex(of: $1.kind) ?? .max
        }
    }
}

enum DBCloudHelperAction: Equatable, Sendable {
    case postgresQuery(database: String, sql: String)
    case sqliteQuery(databasePath: String, sql: String)
    case s3ListBuckets(profile: String?, region: String?)
}

enum DBCloudHelperError: Error, LocalizedError, Equatable {
    case emptyDatabase
    case emptyQuery
    case unsupportedHelper(String)

    var errorDescription: String? {
        switch self {
        case .emptyDatabase: return "Enter a database target."
        case .emptyQuery: return "Enter a query."
        case .unsupportedHelper(let id): return "\(id) does not have a local visual action yet."
        }
    }
}

struct DBCloudHelperCommand: Equatable, Sendable {
    let executable: String
    let arguments: [String]
    let redactedArguments: [Int: String]

    var redactedPreview: String {
        ([shellQuote(executable)] + arguments.enumerated().map { index, argument in
            shellQuote(redactedArguments[index] ?? argument)
        }).joined(separator: " ")
    }

    private func shellQuote(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:=<>"))
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct DBCloudHelperCommandBuilder {
    func command(for action: DBCloudHelperAction) throws -> DBCloudHelperCommand {
        switch action {
        case .postgresQuery(let database, let sql):
            let database = try requireNonEmpty(database, error: .emptyDatabase)
            let sql = try requireNonEmpty(sql, error: .emptyQuery)
            return DBCloudHelperCommand(
                executable: "psql",
                arguments: ["--dbname", database, "--command", sql],
                redactedArguments: [1: "<database>", 3: "<query>"]
            )
        case .sqliteQuery(let databasePath, let sql):
            let databasePath = try requireNonEmpty(databasePath, error: .emptyDatabase)
            let sql = try requireNonEmpty(sql, error: .emptyQuery)
            return DBCloudHelperCommand(
                executable: "sqlite3",
                arguments: [databasePath, sql],
                redactedArguments: [0: "<database>", 1: "<query>"]
            )
        case .s3ListBuckets(let profile, let region):
            var arguments = ["s3api", "list-buckets", "--output", "json"]
            if let profile = profile?.trimmingCharacters(in: .whitespacesAndNewlines), !profile.isEmpty {
                arguments += ["--profile", profile]
            }
            if let region = region?.trimmingCharacters(in: .whitespacesAndNewlines), !region.isEmpty {
                arguments += ["--region", region]
            }
            return DBCloudHelperCommand(executable: "aws", arguments: arguments, redactedArguments: [:])
        }
    }

    private func requireNonEmpty(_ value: String, error: DBCloudHelperError) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw error }
        return trimmed
    }
}

struct DBCloudHelperRunResult: Equatable, Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}
