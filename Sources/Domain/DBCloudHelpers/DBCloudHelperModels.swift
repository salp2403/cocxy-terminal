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

    func localizedTitle(using localizer: AppLocalizer) -> String {
        switch self {
        case .database:
            return localizer.string("dbCloud.kind.database", fallback: title)
        case .cloud:
            return localizer.string("dbCloud.kind.cloud", fallback: title)
        case .container:
            return localizer.string("dbCloud.kind.container", fallback: title)
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
    case queryTooLarge(limitBytes: Int)
    case invalidPostgreSQLDatabaseTarget
    case unsupportedPostgreSQLCredentialFormat
    case unsupportedHelper(String)

    var errorDescription: String? {
        switch self {
        case .emptyDatabase: return "Enter a database target."
        case .emptyQuery: return "Enter a query."
        case .queryTooLarge(let limitBytes):
            let size = ByteCountFormatter.string(
                fromByteCount: Int64(limitBytes),
                countStyle: .file
            )
            return "The query exceeds the \(size) input limit."
        case .invalidPostgreSQLDatabaseTarget:
            return "Enter a valid PostgreSQL URL or service name."
        case .unsupportedPostgreSQLCredentialFormat:
            return "Use a PostgreSQL URL or protected service credentials; inline password fields are not supported."
        case .unsupportedHelper(let id): return "\(id) does not have a local visual action yet."
        }
    }
}

enum DBCloudHelperCredentialMaterial: Equatable, Sendable {
    case postgreSQLPassfile(Data)
}

struct DBCloudHelperCommand: Equatable, Sendable {
    static let maximumStandardInputBytes = 4 * 1_024 * 1_024

    let executable: String
    let arguments: [String]
    let redactedArguments: [Int: String]
    let standardInput: Data?
    let credentialMaterial: DBCloudHelperCredentialMaterial?

    init(
        executable: String,
        arguments: [String],
        redactedArguments: [Int: String],
        standardInput: Data? = nil,
        credentialMaterial: DBCloudHelperCredentialMaterial? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.redactedArguments = redactedArguments
        self.standardInput = standardInput
        self.credentialMaterial = credentialMaterial
    }

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
            let input = try standardInput(for: sql)
            let connection = try PostgreSQLConnectionPreparation.prepare(database)
            return DBCloudHelperCommand(
                executable: "psql",
                arguments: ["--no-password", "--dbname", connection.databaseArgument, "--file", "-"],
                redactedArguments: [2: "<database>"],
                standardInput: input,
                credentialMaterial: connection.credentialMaterial
            )
        case .sqliteQuery(let databasePath, let sql):
            let databasePath = try requireNonEmpty(databasePath, error: .emptyDatabase)
            let sql = try requireNonEmpty(sql, error: .emptyQuery)
            return DBCloudHelperCommand(
                executable: "sqlite3",
                arguments: [databasePath],
                redactedArguments: [0: "<database>"],
                standardInput: try standardInput(for: sql)
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

    private func standardInput(for query: String) throws -> Data {
        let data = Data(query.utf8)
        guard data.count <= DBCloudHelperCommand.maximumStandardInputBytes else {
            throw DBCloudHelperError.queryTooLarge(limitBytes: DBCloudHelperCommand.maximumStandardInputBytes)
        }
        return data
    }
}

struct DBCloudHelperRunResult: Equatable, Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let stdoutBytesRead: Int64
    let stderrBytesRead: Int64
    let stdoutTruncated: Bool
    let stderrTruncated: Bool

    init(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        stdoutBytesRead: Int64? = nil,
        stderrBytesRead: Int64? = nil,
        stdoutTruncated: Bool = false,
        stderrTruncated: Bool = false
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.stdoutBytesRead = stdoutBytesRead ?? Int64(stdout.utf8.count)
        self.stderrBytesRead = stderrBytesRead ?? Int64(stderr.utf8.count)
        self.stdoutTruncated = stdoutTruncated
        self.stderrTruncated = stderrTruncated
    }

    var succeeded: Bool { exitCode == 0 }
    var outputWasTruncated: Bool { stdoutTruncated || stderrTruncated }
}
