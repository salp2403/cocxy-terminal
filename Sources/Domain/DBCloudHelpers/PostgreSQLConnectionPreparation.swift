// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PostgreSQLConnectionPreparation.swift - Process-safe PostgreSQL credential transport.

import Foundation

struct PostgreSQLConnectionPreparation: Equatable, Sendable {
    private static let unsupportedSecretParameterNames: Set<String> = [
        "oauth_client_secret",
        "scram_client_key",
        "scram_server_key",
        "sslpassword",
    ]

    let databaseArgument: String
    let credentialMaterial: DBCloudHelperCredentialMaterial?

    static func prepare(_ database: String) throws -> PostgreSQLConnectionPreparation {
        let trimmed = database.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DBCloudHelperError.emptyDatabase
        }

        let lowercased = trimmed.lowercased()
        let isPostgreSQLURI = lowercased.hasPrefix("postgres://")
            || lowercased.hasPrefix("postgresql://")
        let hasPostgreSQLScheme = lowercased.hasPrefix("postgres:")
            || lowercased.hasPrefix("postgresql:")

        guard isPostgreSQLURI else {
            if hasPostgreSQLScheme {
                throw DBCloudHelperError.invalidPostgreSQLDatabaseTarget
            }
            if containsSensitiveCredentialAssignment(trimmed) {
                throw DBCloudHelperError.unsupportedPostgreSQLCredentialFormat
            }
            return PostgreSQLConnectionPreparation(
                databaseArgument: trimmed,
                credentialMaterial: nil
            )
        }

        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "postgres" || scheme == "postgresql",
              components.fragment == nil else {
            throw DBCloudHelperError.invalidPostgreSQLDatabaseTarget
        }

        let queryItems = components.queryItems ?? []
        if queryItems.contains(where: {
            Self.unsupportedSecretParameterNames.contains($0.name.lowercased())
                && !($0.value ?? "").isEmpty
        }) {
            throw DBCloudHelperError.unsupportedPostgreSQLCredentialFormat
        }
        let queryPassword = try uniqueQueryValue(named: "password", in: queryItems)
        if components.password != nil, queryPassword != nil {
            throw DBCloudHelperError.invalidPostgreSQLDatabaseTarget
        }

        guard let password = components.password ?? queryPassword else {
            return PostgreSQLConnectionPreparation(
                databaseArgument: trimmed,
                credentialMaterial: nil
            )
        }

        let user = nonEmpty(try uniqueQueryValue(named: "user", in: queryItems))
            ?? nonEmpty(components.user)
        let queryHost = nonEmpty(try uniqueQueryValue(named: "host", in: queryItems))
        let componentHost = nonEmpty(components.host)
        let queryHostAddress = nonEmpty(try uniqueQueryValue(named: "hostaddr", in: queryItems))
        let host = normalizedHost(queryHost ?? componentHost ?? queryHostAddress ?? "localhost")
        let queryPort = nonEmpty(try uniqueQueryValue(named: "port", in: queryItems))
        let port = try normalizedPort(queryPort, componentsPort: components.port)
        let pathDatabase = components.path.drop(while: { $0 == "/" })
        let databaseName = nonEmpty(try uniqueQueryValue(named: "dbname", in: queryItems))
            ?? (pathDatabase.isEmpty ? user : String(pathDatabase))

        guard let user, !user.isEmpty,
              let host, !host.isEmpty,
              !host.hasPrefix("/"),
              !host.contains(","),
              let databaseName, !databaseName.isEmpty else {
            throw DBCloudHelperError.invalidPostgreSQLDatabaseTarget
        }

        let fields = [host, port, databaseName, user, password]
        guard fields.allSatisfy(isValidPassfileField) else {
            throw DBCloudHelperError.invalidPostgreSQLDatabaseTarget
        }

        components.password = nil
        let sanitizedQueryItems = queryItems.filter { $0.name.lowercased() != "password" }
        components.queryItems = sanitizedQueryItems.isEmpty ? nil : sanitizedQueryItems
        guard let sanitizedDatabase = components.string,
              !sanitizedDatabase.isEmpty else {
            throw DBCloudHelperError.invalidPostgreSQLDatabaseTarget
        }

        let passfileLine = fields.map(escapePassfileField).joined(separator: ":") + "\n"
        return PostgreSQLConnectionPreparation(
            databaseArgument: sanitizedDatabase,
            credentialMaterial: .postgreSQLPassfile(Data(passfileLine.utf8))
        )
    }

    private static func uniqueQueryValue(
        named name: String,
        in items: [URLQueryItem]
    ) throws -> String? {
        let values = items
            .filter { $0.name.lowercased() == name }
            .map { $0.value ?? "" }
        guard let first = values.first else { return nil }
        guard values.dropFirst().allSatisfy({ $0 == first }) else {
            throw DBCloudHelperError.invalidPostgreSQLDatabaseTarget
        }
        return first
    }

    private static func normalizedHost(_ host: String?) -> String? {
        guard let host else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") {
            return String(host.dropFirst().dropLast())
        }
        return host
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func normalizedPort(
        _ queryPort: String?,
        componentsPort: Int?
    ) throws -> String {
        let value = queryPort ?? componentsPort.map(String.init) ?? "5432"
        guard let port = Int(value), (1...65_535).contains(port), value == String(port) else {
            throw DBCloudHelperError.invalidPostgreSQLDatabaseTarget
        }
        return value
    }

    private static func isValidPassfileField(_ value: String) -> Bool {
        !value.unicodeScalars.contains { scalar in
            scalar.value == 0 || scalar.value == 10 || scalar.value == 13
        }
    }

    private static func escapePassfileField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ":", with: "\\:")
    }

    private static func containsSensitiveCredentialAssignment(_ value: String) -> Bool {
        let names = unsupportedSecretParameterNames.union(["password"])
            .sorted()
            .joined(separator: "|")
        return value.range(
            of: "(?i)(?:^|\\s)(?:\(names))\\s*=",
            options: .regularExpression
        ) != nil
    }
}
