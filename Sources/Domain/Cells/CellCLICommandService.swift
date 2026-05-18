// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CellCLICommandService.swift - Socket/CLI command adapter for Cocxy Cells.

import Foundation

final class CellCLICommandService: @unchecked Sendable {
    private static let maxSocketStdoutBytes = 48_000

    private let providers: [CellProviderKind: any CellProvider]
    private let leaseManager: CellLeaseManager
    private let auditLog: any CellAuditLogging
    private let actorProvider: @Sendable () -> String
    private let now: @Sendable () -> Date

    init(
        providers: [CellProviderKind: any CellProvider] = [
            .docker: LocalDockerCellProvider(),
            .ssh: SSHCellProvider(),
            .selfHosted: SSHCellProvider(kind: .selfHosted),
            .e2b: E2BCellProvider(),
            .fly: FlyCellProvider(),
            .aws: AWSCellProvider(),
            .gcp: GCPCellProvider(),
            .azure: AzureCellProvider(),
        ],
        leaseManager: CellLeaseManager = CellLeaseManager(),
        auditLog: any CellAuditLogging = CellAuditLog(),
        actorProvider: @escaping @Sendable () -> String = { NSUserName() },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.providers = providers
        self.leaseManager = leaseManager
        self.auditLog = auditLog
        self.actorProvider = actorProvider
        self.now = now
    }

    func perform(kind: String, params: [String: String]) async -> (success: Bool, data: [String: String]) {
        do {
            switch kind {
            case "create":
                return try await create(params: params)
            case "list":
                return try await list()
            case "exec":
                return try await exec(params: params)
            case "attach":
                return try await attach(params: params)
            case "destroy":
                return try await destroy(params: params)
            case "logs":
                return try await logs(params: params)
            case "status":
                return try await status(params: params)
            default:
                return (false, ["error": "Unknown cell action: \(kind)"])
            }
        } catch {
            return (false, ["error": Self.describe(error)])
        }
    }

    private func create(params: [String: String]) async throws -> (Bool, [String: String]) {
        guard let providerName = params["provider"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !providerName.isEmpty else {
            return (false, ["error": "Missing required param: provider"])
        }
        guard let providerKind = CellProviderKind(rawValue: providerName),
              let provider = providers[providerKind] else {
            return (false, ["error": "Unsupported cell provider: \(providerName)"])
        }

        let profile = params["profile"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = profile?.nilIfEmpty ?? params["host"]?.nilIfEmpty ?? "\(providerKind.rawValue)-cell"
        var metadata: [String: String] = [:]
        if let profile, !profile.isEmpty { metadata["profile"] = profile }
        for key in [
            "image",
            "host",
            "user",
            "port",
            "identity",
            "known-hosts",
            "known-hosts-file",
            "strict-host-key-checking",
            "batch-mode",
            "template",
            "app",
            "region",
            "vm-size",
            "vm-memory",
            "vm-cpus",
            "config",
            "path",
            "cloud-profile",
            "project",
            "zone",
            "resource-group",
            "network",
            "subnet",
            "security-group",
            "key-name",
            "instance-profile",
            "cloud-init",
        ] {
            if let value = params[key]?.nilIfEmpty {
                metadata[key] = value
            }
        }
        let cell = try await provider.create(CellCreateRequest(name: name, metadata: metadata))
        try audit(
            action: .create,
            cellID: cell.id,
            metadata: cell.metadata.merging([
                "name": cell.name,
                "provider": cell.provider.rawValue,
            ]) { current, _ in current }
        )
        return (true, Self.payload(status: "created", cell: cell))
    }

    private func list() async throws -> (Bool, [String: String]) {
        var cells: [Cell] = []
        var providerErrors: [(kind: CellProviderKind, error: String)] = []
        let orderedProviders = providers.sorted { $0.key.rawValue < $1.key.rawValue }

        for (kind, provider) in orderedProviders {
            do {
                cells.append(contentsOf: try await provider.list())
            } catch {
                providerErrors.append((kind, Self.describe(error)))
            }
        }
        cells.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        var data: [String: String] = [
            "status": "listed",
            "count": "\(cells.count)",
            "provider-error-count": "\(providerErrors.count)",
        ]
        for (index, cell) in cells.enumerated() {
            data.merge(Self.payload(prefix: "cell_\(index)_", cell: cell)) { current, _ in current }
        }
        for (index, providerError) in providerErrors.enumerated() {
            data["provider_error_\(index)_provider"] = providerError.kind.rawValue
            data["provider_error_\(index)_message"] = providerError.error
        }
        return (true, data)
    }

    private func exec(params: [String: String]) async throws -> (Bool, [String: String]) {
        let cellID = try Self.requiredCellID(params)
        let argv = try Self.argv(from: params)
        let output = try await withProvider(for: cellID, preferred: params["provider"]) { provider in
            try await provider.exec(cellID: cellID, command: argv)
        }
        try audit(action: .exec, cellID: cellID, metadata: ["argv": argv.joined(separator: " ")])
        return (true, [
            "status": "executed",
            "cell-id": cellID.uuidString,
            "stdout": output,
        ])
    }

    private func attach(params: [String: String]) async throws -> (Bool, [String: String]) {
        let cellID = try Self.requiredCellID(params)
        let attachCommand = try await withProvider(for: cellID, preferred: params["provider"]) { provider in
            try await provider.attachCommand(cellID: cellID)
        }
        let lease = try leaseManager.issueLease(cellID: cellID, purpose: .attachPTY)
        try audit(action: .attach, cellID: cellID, metadata: ["lease-id": lease.id.uuidString])
        return (true, [
            "status": "attach-ready",
            "cell-id": cellID.uuidString,
            "lease-id": lease.id.uuidString,
            "lease-token": Self.attachToken(for: lease),
            "lease-signature": lease.signature.base64EncodedString(),
            "purpose": lease.purpose.rawValue,
            "issued-at": ISO8601DateFormatter().string(from: lease.issuedAt),
            "issued-at-unix": Self.unixTimestamp(lease.issuedAt),
            "expires-at": ISO8601DateFormatter().string(from: lease.expiresAt),
            "expires-at-unix": Self.unixTimestamp(lease.expiresAt),
            "pty-transport": "native-process",
            "pty-command": attachCommand.shellCommand,
            "pty-argv-json": Self.jsonString(attachCommand.argv),
            "pty-title": attachCommand.displayName,
        ])
    }

    func consumeAttachLease(fields: [String: String]) -> Bool {
        guard let leaseIDValue = fields["lease-id"],
              let leaseID = UUID(uuidString: leaseIDValue),
              let cellIDValue = fields["cell-id"],
              let cellID = UUID(uuidString: cellIDValue),
              fields["purpose"] == CellLeasePurpose.attachPTY.rawValue,
              let issuedAt = Self.date(fromUnixField: fields["issued-at-unix"]),
              let expiresAt = Self.date(fromUnixField: fields["expires-at-unix"]),
              let signatureValue = fields["lease-signature"],
              let signature = Data(base64Encoded: signatureValue) else {
            return false
        }

        let lease = CellLease(
            id: leaseID,
            cellID: cellID,
            purpose: .attachPTY,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            signature: signature
        )
        return leaseManager.consumeLease(lease, cellID: cellID, purpose: .attachPTY)
    }

    private func destroy(params: [String: String]) async throws -> (Bool, [String: String]) {
        let cellID = try Self.requiredCellID(params)
        let force = params["force"] == "true"
        try await withProvider(for: cellID, preferred: params["provider"]) { provider in
            try await provider.destroy(cellID: cellID, force: force)
        }
        try audit(action: .destroy, cellID: cellID, metadata: ["force": "\(force)"])
        return (true, [
            "status": "destroyed",
            "cell-id": cellID.uuidString,
        ])
    }

    private func logs(params: [String: String]) async throws -> (Bool, [String: String]) {
        let cellID = try Self.requiredCellID(params)
        let output = try await withProvider(for: cellID, preferred: params["provider"]) { provider in
            try await provider.logs(cellID: cellID)
        }
        let boundedOutput = Self.socketBoundedOutput(output)
        try audit(action: .logs, cellID: cellID)
        var data = [
            "status": "logs",
            "cell-id": cellID.uuidString,
            "stdout": boundedOutput.stdout,
            "stdout-bytes": "\(boundedOutput.originalBytes)",
            "stdout-truncated": "\(boundedOutput.truncated)",
        ]
        if boundedOutput.truncated {
            data["stdout-note"] = "truncated-to-socket-payload"
        }
        return (true, data)
    }

    private func status(params: [String: String]) async throws -> (Bool, [String: String]) {
        let cellID = try Self.requiredCellID(params)
        let status = try await withProvider(for: cellID, preferred: params["provider"]) { provider in
            try await provider.status(cellID: cellID)
        }
        try audit(action: .status, cellID: cellID, metadata: ["status": status.rawValue])
        return (true, [
            "status": status.rawValue,
            "cell-id": cellID.uuidString,
        ])
    }

    private func withProvider<T>(
        for cellID: UUID,
        preferred rawProvider: String?,
        body: (any CellProvider) async throws -> T
    ) async throws -> T {
        if let rawProvider = rawProvider?.nilIfEmpty {
            guard let kind = CellProviderKind(rawValue: rawProvider),
                  let provider = providers[kind] else {
                throw CellCLICommandServiceError.unsupportedProvider(rawProvider)
            }
            return try await body(provider)
        }

        var lastNotFoundError: Error?
        var firstProviderError: Error?
        for provider in providers.values {
            do {
                return try await body(provider)
            } catch LocalDockerCellProviderError.containerNotFound {
                lastNotFoundError = LocalDockerCellProviderError.containerNotFound(cellID)
                continue
            } catch SSHCellProviderError.cellNotFound {
                lastNotFoundError = SSHCellProviderError.cellNotFound(cellID)
                continue
            } catch CommandBackedCloudCellProviderError.cellNotFound {
                lastNotFoundError = CommandBackedCloudCellProviderError.cellNotFound(cellID)
                continue
            } catch {
                if firstProviderError == nil {
                    firstProviderError = error
                }
                continue
            }
        }
        if let firstProviderError {
            throw firstProviderError
        }
        throw lastNotFoundError ?? CellCLICommandServiceError.cellNotFound(cellID)
    }

    private func audit(
        action: CellAuditAction,
        cellID: UUID,
        metadata: [String: String] = [:]
    ) throws {
        try auditLog.append(CellAuditEvent(
            cellID: cellID,
            action: action,
            actor: actorProvider(),
            metadata: metadata,
            createdAt: now()
        ))
    }

    private static func payload(status: String, cell: Cell) -> [String: String] {
        var data = payload(cell: cell)
        data["status"] = status
        return data
    }

    private static func payload(prefix: String = "", cell: Cell) -> [String: String] {
        var data: [String: String] = [
            "\(prefix)id": cell.id.uuidString,
            "\(prefix)name": cell.name,
            "\(prefix)provider": cell.provider.rawValue,
            "\(prefix)cell-status": cell.status.rawValue,
        ]
        for (key, value) in cell.safeMetadata.sorted(by: { $0.key < $1.key }) {
            data["\(prefix)metadata_\(key)"] = value
        }
        return data
    }

    private static func requiredCellID(_ params: [String: String]) throws -> UUID {
        guard let raw = params["cell-id"]?.nilIfEmpty else {
            throw CellCLICommandServiceError.missingParam("cell-id")
        }
        guard let id = UUID(uuidString: raw) else {
            throw CellCLICommandServiceError.invalidCellID(raw)
        }
        return id
    }

    private static func argv(from params: [String: String]) throws -> [String] {
        guard let raw = params["argv-json"]?.nilIfEmpty else {
            throw CellCLICommandServiceError.missingParam("argv-json")
        }
        let argv = try JSONDecoder().decode([String].self, from: Data(raw.utf8))
        guard !argv.isEmpty else {
            throw CellCLICommandServiceError.emptyCommand
        }
        return argv
    }

    private static func jsonString(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\\/", with: "/")
    }

    private static func attachToken(for lease: CellLease) -> String {
        "\(lease.id.uuidString).\(base64URL(lease.signature))"
    }

    private static func socketBoundedOutput(_ output: String) -> (
        stdout: String,
        truncated: Bool,
        originalBytes: Int
    ) {
        let bytes = output.utf8
        guard bytes.count > maxSocketStdoutBytes else {
            return (output, false, bytes.count)
        }
        let data = Data(bytes.prefix(maxSocketStdoutBytes))
        return (String(decoding: data, as: UTF8.self), true, bytes.count)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func unixTimestamp(_ date: Date) -> String {
        String(format: "%.6f", date.timeIntervalSince1970)
    }

    private static func date(fromUnixField value: String?) -> Date? {
        guard let value, let seconds = Double(value) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case let error as CellCLICommandServiceError:
            return error.description
        case let error as LocalDockerCellProviderError:
            return error.description
        case let error as SSHCellProviderError:
            return error.description
        case let error as CommandBackedCloudCellProviderError:
            return error.description
        default:
            return error.localizedDescription
        }
    }
}

private extension CommandBackedCloudCellProviderError {
    var description: String {
        switch self {
        case .missingImage(let provider):
            return "Missing required image for \(provider.rawValue) cell"
        case .missingMetadata(let provider, let key):
            return "Missing required \(key) for \(provider.rawValue) cell"
        case .commandFailed(let provider, let exitCode, let stderr):
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty
                ? "\(provider.rawValue) command failed with exit code \(exitCode)"
                : "\(provider.rawValue) command failed with exit code \(exitCode): \(message)"
        case .missingExternalIdentifier(let provider, let output):
            let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty
                ? "\(provider.rawValue) command did not return a cell identifier"
                : "\(provider.rawValue) command did not return a cell identifier: \(message)"
        case .cellNotFound(let id):
            return "Cell not found: \(id.uuidString)"
        case .emptyCommand:
            return "Missing command argv"
        case .attachUnsupported(let provider):
            return "\(provider.rawValue) attach PTY is not supported by the verified local CLI provider"
        }
    }
}

private extension SSHCellProviderError {
    var description: String {
        switch self {
        case .missingHost:
            return "Missing required SSH host"
        case .invalidPort(let value):
            return "Invalid SSH port: \(value)"
        case .invalidStrictHostKeyChecking(let value):
            return "Invalid StrictHostKeyChecking value: \(value)"
        case .invalidBoolean(let key, let value):
            return "Invalid boolean for \(key): \(value)"
        case .sshCommandFailed(let exitCode, let stderr):
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty
                ? "SSH command failed with exit code \(exitCode)"
                : "SSH command failed with exit code \(exitCode): \(message)"
        case .cellNotFound(let id):
            return "Cell not found: \(id.uuidString)"
        case .emptyCommand:
            return "Missing command argv"
        }
    }
}

enum CellCLICommandServiceError: Error, Equatable, Sendable {
    case missingParam(String)
    case invalidCellID(String)
    case unsupportedProvider(String)
    case cellNotFound(UUID)
    case emptyCommand

    var description: String {
        switch self {
        case .missingParam(let name):
            return "Missing required param: \(name)"
        case .invalidCellID(let value):
            return "Invalid cell id: \(value)"
        case .unsupportedProvider(let provider):
            return "Unsupported cell provider: \(provider)"
        case .cellNotFound(let id):
            return "Cell not found: \(id.uuidString)"
        case .emptyCommand:
            return "Missing command argv"
        }
    }
}

private extension LocalDockerCellProviderError {
    var description: String {
        switch self {
        case .dockerCommandFailed(let exitCode, let stderr):
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty
                ? "Docker command failed with exit code \(exitCode)"
                : "Docker command failed with exit code \(exitCode): \(message)"
        case .containerNotFound(let id):
            return "Cell not found: \(id.uuidString)"
        case .invalidDockerOutput(let message):
            return "Invalid Docker output: \(message)"
        case .emptyCommand:
            return "Missing command argv"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
