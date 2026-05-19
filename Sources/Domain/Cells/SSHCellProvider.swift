// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SSHCellProvider.swift - SSH-backed user-owned Cocxy Cells.

import Foundation

enum SSHCellProviderError: Error, Equatable, Sendable {
    case missingHost
    case invalidPort(String)
    case invalidStrictHostKeyChecking(String)
    case invalidBoolean(String, String)
    case sshCommandFailed(exitCode: Int32, stderr: String)
    case cellNotFound(UUID)
    case emptyCommand
}

final class SSHCellProvider: CellProvider, @unchecked Sendable {
    let kind: CellProviderKind

    private struct Record: Sendable {
        var cell: Cell
        let profile: RemoteConnectionProfile
    }

    private let multiplexer: any SSHMultiplexing
    private let executor: any ProcessExecutor
    private let clock: @Sendable () -> Date
    private let idGenerator: @Sendable () -> UUID
    private let records = LockedBox<[UUID: Record]>([:])

    init(
        kind: CellProviderKind = .ssh,
        multiplexer: any SSHMultiplexing = SSHMultiplexer(),
        executor: any ProcessExecutor = SystemProcessExecutor(),
        clock: @escaping @Sendable () -> Date = { Date() },
        idGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.kind = kind
        self.multiplexer = multiplexer
        self.executor = executor
        self.clock = clock
        self.idGenerator = idGenerator
    }

    func create(_ request: CellCreateRequest) async throws -> Cell {
        let cellID = idGenerator()
        let host = try Self.requiredHost(from: request.metadata)
        let user = request.metadata["user"]?.nilIfEmpty
        let port = try Self.port(from: request.metadata["port"])
        let identity = request.metadata["identity"]?.nilIfEmpty
            ?? request.metadata["identityFile"]?.nilIfEmpty
            ?? request.metadata["identity-file"]?.nilIfEmpty
        let knownHostsFile = request.metadata["known-hosts"]?.nilIfEmpty
            ?? request.metadata["known-hosts-file"]?.nilIfEmpty
        let strictHostKeyChecking = try Self.strictHostKeyChecking(
            from: request.metadata["strict-host-key-checking"]
        )
        let batchMode = try Self.bool(from: request.metadata["batch-mode"]) ?? true

        let profile = RemoteConnectionProfile(
            id: cellID,
            name: request.name,
            host: host,
            user: user,
            port: port,
            identityFile: identity,
            strictHostKeyChecking: strictHostKeyChecking,
            knownHostsFile: knownHostsFile,
            batchMode: batchMode,
            autoReconnect: false
        )

        try multiplexer.connect(profile: profile, executor: executor)

        let now = clock()
        var metadata = request.metadata
        metadata["host"] = host
        if let user { metadata["user"] = user }
        if let port { metadata["port"] = "\(port)" }
        if let identity { metadata["identity"] = identity }
        if let knownHostsFile { metadata["known-hosts"] = knownHostsFile }
        if let strictHostKeyChecking { metadata["strict-host-key-checking"] = strictHostKeyChecking }
        metadata["batch-mode"] = batchMode ? "true" : "false"
        metadata["displayTitle"] = profile.displayTitle

        let cell = Cell(
            id: cellID,
            name: request.name,
            provider: kind,
            status: .running,
            createdAt: now,
            updatedAt: now,
            metadata: metadata
        )
        setRecord(Record(cell: cell, profile: profile), for: cellID)
        return cell
    }

    func list() async throws -> [Cell] {
        records.withValue { records in
            records.values
                .map(\.cell)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    func status(cellID: UUID) async throws -> CellStatus {
        let record = try record(for: cellID)
        let alive = try await multiplexer.isAlive(profile: record.profile, executor: executor)
        let status: CellStatus = alive ? .running : .stopped
        updateCell(cellID: cellID) { cell in
            cell.status = status
            cell.updatedAt = clock()
        }
        return status
    }

    func exec(cellID: UUID, command: [String]) async throws -> String {
        guard !command.isEmpty else {
            throw SSHCellProviderError.emptyCommand
        }
        let record = try record(for: cellID)
        let remoteCommand = command.map(Self.shellToken).joined(separator: " ")
        let result = try await multiplexer.executeRemoteCommand(
            remoteCommand,
            on: record.profile,
            executor: executor
        )
        guard result.exitCode == 0 else {
            throw SSHCellProviderError.sshCommandFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        return result.stdout
    }

    func attachCommand(cellID: UUID) async throws -> CellAttachCommand {
        let record = try record(for: cellID)
        return CellAttachCommand(
            executable: "ssh",
            arguments: Self.attachArguments(for: record.profile),
            displayName: record.profile.displayTitle
        )
    }

    func logs(cellID: UUID) async throws -> String {
        _ = try record(for: cellID)
        return ""
    }

    func destroy(cellID: UUID, force: Bool) async throws {
        let record = try record(for: cellID)
        do {
            try multiplexer.disconnect(profile: record.profile, executor: executor)
        } catch {
            guard force else { throw error }
        }
        removeRecord(for: cellID)
    }

    private func record(for cellID: UUID) throws -> Record {
        let record = records.withValue { records in
            records[cellID]
        }
        guard let record else {
            throw SSHCellProviderError.cellNotFound(cellID)
        }
        return record
    }

    private func setRecord(_ record: Record, for cellID: UUID) {
        records.withValue { records in
            records[cellID] = record
        }
    }

    private func removeRecord(for cellID: UUID) {
        _ = records.withValue { records in
            records.removeValue(forKey: cellID)
        }
    }

    private func updateCell(cellID: UUID, _ update: (inout Cell) -> Void) {
        records.withValue { records in
            guard var record = records[cellID] else { return }
            update(&record.cell)
            records[cellID] = record
        }
    }

    private static func requiredHost(from metadata: [String: String]) throws -> String {
        guard let host = metadata["host"]?.nilIfEmpty else {
            throw SSHCellProviderError.missingHost
        }
        return host
    }

    private static func port(from rawValue: String?) throws -> Int? {
        guard let rawValue = rawValue?.nilIfEmpty else { return nil }
        guard let port = Int(rawValue), (1...65_535).contains(port) else {
            throw SSHCellProviderError.invalidPort(rawValue)
        }
        return port
    }

    private static func strictHostKeyChecking(from rawValue: String?) throws -> String? {
        guard let value = rawValue?.nilIfEmpty?.lowercased() else { return nil }
        let allowedValues = Set(["yes", "no", "ask", "accept-new", "off"])
        guard allowedValues.contains(value) else {
            throw SSHCellProviderError.invalidStrictHostKeyChecking(rawValue ?? "")
        }
        return value
    }

    private static func bool(from rawValue: String?) throws -> Bool? {
        guard let value = rawValue?.nilIfEmpty?.lowercased() else { return nil }
        switch value {
        case "true", "yes", "1", "on":
            return true
        case "false", "no", "0", "off":
            return false
        default:
            throw SSHCellProviderError.invalidBoolean("batch-mode", rawValue ?? "")
        }
    }

    private static func attachArguments(for profile: RemoteConnectionProfile) -> [String] {
        var arguments: [String] = []
        if let port = profile.port {
            arguments.append(contentsOf: ["-p", "\(port)"])
        }
        if let identityFile = profile.identityFile?.nilIfEmpty {
            arguments.append(contentsOf: ["-i", identityFile])
        }
        if !profile.jumpHosts.isEmpty {
            arguments.append(contentsOf: ["-J", profile.jumpHosts.joined(separator: ",")])
        }
        if let strictHostKeyChecking = profile.strictHostKeyChecking?.nilIfEmpty {
            arguments.append(contentsOf: ["-o", "StrictHostKeyChecking=\(strictHostKeyChecking)"])
        }
        if let knownHostsFile = profile.knownHostsFile?.nilIfEmpty {
            arguments.append(contentsOf: ["-o", "UserKnownHostsFile=\(knownHostsFile)"])
        }
        if let batchMode = profile.batchMode {
            arguments.append(contentsOf: ["-o", "BatchMode=\(batchMode ? "yes" : "no")"])
        }
        arguments.append(contentsOf: ["-o", "ServerAliveInterval=\(profile.keepAliveInterval)"])
        arguments.append("-tt")
        arguments.append(profile.user.map { "\($0)@\(profile.host)" } ?? profile.host)
        return arguments
    }

    private static func shellToken(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let safe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_+-./:@=~")
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
