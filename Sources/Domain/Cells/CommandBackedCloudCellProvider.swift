// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandBackedCloudCellProvider.swift - User-owned cloud Cells via local CLIs.

import Foundation

enum CommandBackedCloudCellProviderError: Error, Equatable, Sendable {
    case missingImage(provider: CellProviderKind)
    case missingMetadata(provider: CellProviderKind, key: String)
    case commandFailed(provider: CellProviderKind, exitCode: Int32, stderr: String)
    case missingExternalIdentifier(provider: CellProviderKind, output: String)
    case cellNotFound(UUID)
    case emptyCommand
    case attachUnsupported(provider: CellProviderKind)
}

final class E2BCellProvider: CellProvider, @unchecked Sendable {
    let kind: CellProviderKind = .e2b

    private struct Record: Sendable {
        var cell: Cell
        let externalID: String
    }

    private let executable: String
    private let executor: any CellProcessExecuting
    private let clock: @Sendable () -> Date
    private let idGenerator: @Sendable () -> UUID
    private let records = LockedBox<[UUID: Record]>([:])

    init(
        executable: String = "e2b",
        executor: any CellProcessExecuting = ProcessCellExecutor(),
        clock: @escaping @Sendable () -> Date = { Date() },
        idGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.executable = executable
        self.executor = executor
        self.clock = clock
        self.idGenerator = idGenerator
    }

    func create(_ request: CellCreateRequest) async throws -> Cell {
        let cellID = idGenerator()
        let result = try run(arguments: buildCreateArguments(from: request))
        guard let externalID = CloudCellCommandOutput.externalID(from: result.stdout) else {
            throw CommandBackedCloudCellProviderError.missingExternalIdentifier(
                provider: kind,
                output: result.stdout
            )
        }

        let now = clock()
        var metadata = Self.safeMetadata(from: request.metadata)
        metadata["externalID"] = externalID
        if let template = request.metadata["template"]?.nilIfEmpty {
            metadata["template"] = template
        }

        let cell = Cell(
            id: cellID,
            name: request.name,
            provider: kind,
            status: .running,
            createdAt: now,
            updatedAt: now,
            metadata: metadata
        )
        setRecord(Record(cell: cell, externalID: externalID), for: cellID)
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
        let result = try run(arguments: ["sandbox", "list", "--format", "json"])
        let status: CellStatus = result.stdout.contains(record.externalID) ? .running : .stopped
        updateCell(cellID: cellID) { cell in
            cell.status = status
            cell.updatedAt = clock()
        }
        return status
    }

    func exec(cellID: UUID, command: [String]) async throws -> String {
        guard !command.isEmpty else {
            throw CommandBackedCloudCellProviderError.emptyCommand
        }
        let record = try record(for: cellID)
        return try run(arguments: ["sandbox", "exec", record.externalID] + command).stdout
    }

    func attachCommand(cellID: UUID) async throws -> CellAttachCommand {
        let record = try record(for: cellID)
        return CellAttachCommand(
            executable: executable,
            arguments: ["sandbox", "connect", record.externalID],
            displayName: "E2B Cell"
        )
    }

    func logs(cellID: UUID) async throws -> String {
        let record = try record(for: cellID)
        return try run(arguments: ["sandbox", "logs", record.externalID]).stdout
    }

    func destroy(cellID: UUID, force: Bool) async throws {
        let record = try record(for: cellID)
        _ = try run(arguments: ["sandbox", "kill", record.externalID])
        removeRecord(for: cellID)
    }

    private func buildCreateArguments(from request: CellCreateRequest) -> [String] {
        var arguments = ["sandbox", "create", "--detach"]
        if let path = request.metadata["path"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--path", path])
        }
        if let config = request.metadata["config"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--config", config])
        }
        if let template = request.metadata["template"]?.nilIfEmpty {
            arguments.append(template)
        }
        return arguments
    }

    private func run(arguments: [String]) throws -> CellProcessResult {
        let result = try executor.run(executable, arguments: arguments)
        guard result.exitCode == 0 else {
            throw CommandBackedCloudCellProviderError.commandFailed(
                provider: kind,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        return result
    }

    private static func safeMetadata(from metadata: [String: String]) -> [String: String] {
        var safe = metadata
        for key in metadata.keys where CellMetadataRedactor.redacted([key: metadata[key] ?? ""])[key] == CellMetadataRedactor.redactedValue {
            safe.removeValue(forKey: key)
        }
        return safe
    }

    private func record(for cellID: UUID) throws -> Record {
        guard let record = records.withValue({ $0[cellID] }) else {
            throw CommandBackedCloudCellProviderError.cellNotFound(cellID)
        }
        return record
    }

    private func setRecord(_ record: Record, for cellID: UUID) {
        records.withValue { $0[cellID] = record }
    }

    private func removeRecord(for cellID: UUID) {
        _ = records.withValue { $0.removeValue(forKey: cellID) }
    }

    private func updateCell(cellID: UUID, _ update: (inout Cell) -> Void) {
        records.withValue { records in
            guard var record = records[cellID] else { return }
            update(&record.cell)
            records[cellID] = record
        }
    }
}

final class FlyCellProvider: CellProvider, @unchecked Sendable {
    let kind: CellProviderKind = .fly

    private struct Record: Sendable {
        var cell: Cell
        let externalID: String
        let app: String?
    }

    private let executable: String
    private let executor: any CellProcessExecuting
    private let clock: @Sendable () -> Date
    private let idGenerator: @Sendable () -> UUID
    private let records = LockedBox<[UUID: Record]>([:])

    init(
        executable: String = "fly",
        executor: any CellProcessExecuting = ProcessCellExecutor(),
        clock: @escaping @Sendable () -> Date = { Date() },
        idGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.executable = executable
        self.executor = executor
        self.clock = clock
        self.idGenerator = idGenerator
    }

    func create(_ request: CellCreateRequest) async throws -> Cell {
        let cellID = idGenerator()
        guard let image = request.metadata["image"]?.nilIfEmpty else {
            throw CommandBackedCloudCellProviderError.missingImage(provider: kind)
        }

        let result = try run(arguments: buildCreateArguments(
            request: request,
            cellID: cellID,
            image: image
        ))
        guard let externalID = CloudCellCommandOutput.externalID(from: result.stdout) else {
            throw CommandBackedCloudCellProviderError.missingExternalIdentifier(
                provider: kind,
                output: result.stdout
            )
        }

        let now = clock()
        var metadata = Self.safeMetadata(from: request.metadata)
        metadata["externalID"] = externalID
        metadata["image"] = image

        let cell = Cell(
            id: cellID,
            name: request.name,
            provider: kind,
            status: .running,
            createdAt: now,
            updatedAt: now,
            metadata: metadata
        )
        setRecord(Record(
            cell: cell,
            externalID: externalID,
            app: request.metadata["app"]?.nilIfEmpty
        ), for: cellID)
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
        let result = try run(arguments: ["machine", "status"] + scopedArguments(app: record.app) + [record.externalID])
        let status = Self.status(from: result.stdout)
        updateCell(cellID: cellID) { cell in
            cell.status = status
            cell.updatedAt = clock()
        }
        return status
    }

    func exec(cellID: UUID, command: [String]) async throws -> String {
        guard !command.isEmpty else {
            throw CommandBackedCloudCellProviderError.emptyCommand
        }
        let record = try record(for: cellID)
        return try run(arguments: [
            "machine", "exec",
        ] + scopedArguments(app: record.app) + [
            record.externalID,
            Self.shellCommand(from: command),
        ]).stdout
    }

    func attachCommand(cellID: UUID) async throws -> CellAttachCommand {
        let record = try record(for: cellID)
        return CellAttachCommand(
            executable: executable,
            arguments: ["ssh", "console"] + scopedArguments(app: record.app) + ["--machine", record.externalID],
            displayName: "Fly Cell"
        )
    }

    func logs(cellID: UUID) async throws -> String {
        let record = try record(for: cellID)
        return try run(arguments: ["logs"] + scopedArguments(app: record.app) + [
            "--no-tail",
            "--machine", record.externalID,
        ]).stdout
    }

    func destroy(cellID: UUID, force: Bool) async throws {
        let record = try record(for: cellID)
        var arguments = ["machine", "destroy"] + scopedArguments(app: record.app)
        if force {
            arguments.append("--force")
        }
        arguments.append(record.externalID)
        _ = try run(arguments: arguments)
        removeRecord(for: cellID)
    }

    private func buildCreateArguments(
        request: CellCreateRequest,
        cellID: UUID,
        image: String
    ) -> [String] {
        var arguments = [
            "machine", "run",
            "--detach",
            "--name", Self.machineName(from: request.name),
        ]
        arguments.append(contentsOf: scopedArguments(app: request.metadata["app"]?.nilIfEmpty))
        if let region = request.metadata["region"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--region", region])
        }
        if let vmSize = request.metadata["vm-size"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--vm-size", vmSize])
        }
        if let vmMemory = request.metadata["vm-memory"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--vm-memory", vmMemory])
        }
        if let vmCPUs = request.metadata["vm-cpus"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--vm-cpus", vmCPUs])
        }
        arguments.append(contentsOf: [
            "--metadata", "dev.cocxy.cell=true",
            "--metadata", "dev.cocxy.cell.id=\(cellID.uuidString)",
            "--metadata", "dev.cocxy.cell.name=\(request.name)",
            image,
            "sleep", "inf",
        ])
        return arguments
    }

    private func scopedArguments(app: String?) -> [String] {
        guard let app else { return [] }
        return ["--app", app]
    }

    private func run(arguments: [String]) throws -> CellProcessResult {
        let result = try executor.run(executable, arguments: arguments)
        guard result.exitCode == 0 else {
            throw CommandBackedCloudCellProviderError.commandFailed(
                provider: kind,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        return result
    }

    private static func safeMetadata(from metadata: [String: String]) -> [String: String] {
        var safe = metadata
        for key in metadata.keys where CellMetadataRedactor.redacted([key: metadata[key] ?? ""])[key] == CellMetadataRedactor.redactedValue {
            safe.removeValue(forKey: key)
        }
        return safe
    }

    private static func machineName(from name: String) -> String {
        let sanitized = name
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber || character == "-" {
                    return character
                }
                return "-"
            }
        let collapsed = String(sanitized)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "cocxy-cell" : collapsed
    }

    private static func status(from output: String) -> CellStatus {
        let lowercased = output.lowercased()
        if lowercased.contains("destroy") {
            return .destroyed
        }
        if lowercased.contains("stop") || lowercased.contains("suspend") {
            return .stopped
        }
        if lowercased.contains("fail") {
            return .failed
        }
        return .running
    }

    private static func shellCommand(from argv: [String]) -> String {
        argv.map(shellToken).joined(separator: " ")
    }

    private static func shellToken(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let safeScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-./:=,@%")
        if value.unicodeScalars.allSatisfy({ safeScalars.contains($0) }) {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func record(for cellID: UUID) throws -> Record {
        guard let record = records.withValue({ $0[cellID] }) else {
            throw CommandBackedCloudCellProviderError.cellNotFound(cellID)
        }
        return record
    }

    private func setRecord(_ record: Record, for cellID: UUID) {
        records.withValue { $0[cellID] = record }
    }

    private func removeRecord(for cellID: UUID) {
        _ = records.withValue { $0.removeValue(forKey: cellID) }
    }

    private func updateCell(cellID: UUID, _ update: (inout Cell) -> Void) {
        records.withValue { records in
            guard var record = records[cellID] else { return }
            update(&record.cell)
            records[cellID] = record
        }
    }
}

final class AWSCellProvider: CellProvider, @unchecked Sendable {
    let kind: CellProviderKind = .aws

    private struct Record: Sendable {
        var cell: Cell
        let externalID: String
        let metadata: [String: String]
    }

    private let executable: String
    private let executor: any CellProcessExecuting
    private let clock: @Sendable () -> Date
    private let idGenerator: @Sendable () -> UUID
    private let records = LockedBox<[UUID: Record]>([:])

    init(
        executable: String = "aws",
        executor: any CellProcessExecuting = ProcessCellExecutor(),
        clock: @escaping @Sendable () -> Date = { Date() },
        idGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.executable = executable
        self.executor = executor
        self.clock = clock
        self.idGenerator = idGenerator
    }

    func create(_ request: CellCreateRequest) async throws -> Cell {
        let cellID = idGenerator()
        let image = try CloudCellProviderUtilities.requiredImage(kind: kind, metadata: request.metadata)
        let result = try run(arguments: buildCreateArguments(request: request, cellID: cellID, image: image))
        guard let externalID = CloudCellCommandOutput.externalID(from: result.stdout) else {
            throw CommandBackedCloudCellProviderError.missingExternalIdentifier(
                provider: kind,
                output: result.stdout
            )
        }

        let now = clock()
        var metadata = CloudCellProviderUtilities.safeMetadata(from: request.metadata)
        metadata["externalID"] = externalID
        metadata["image"] = image
        let cell = Cell(
            id: cellID,
            name: request.name,
            provider: kind,
            status: .running,
            createdAt: now,
            updatedAt: now,
            metadata: metadata
        )
        setRecord(Record(
            cell: cell,
            externalID: externalID,
            metadata: CloudCellProviderUtilities.operationalMetadata(from: request.metadata)
        ), for: cellID)
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
        let result = try run(arguments: [
            "ec2", "describe-instances",
        ] + scopedArguments(record.metadata) + [
            "--instance-ids", record.externalID,
            "--query", "Reservations[0].Instances[0].State.Name",
            "--output", "text",
        ])
        let status = CloudCellProviderUtilities.awsStatus(from: result.stdout)
        updateCell(cellID: cellID) { cell in
            cell.status = status
            cell.updatedAt = clock()
        }
        return status
    }

    func exec(cellID: UUID, command: [String]) async throws -> String {
        guard !command.isEmpty else {
            throw CommandBackedCloudCellProviderError.emptyCommand
        }
        let record = try record(for: cellID)
        let commandLine = CloudCellProviderUtilities.shellCommand(command)
        let sendResult = try run(arguments: [
            "ssm", "send-command",
        ] + scopedArguments(record.metadata) + [
            "--instance-ids", record.externalID,
            "--document-name", "AWS-RunShellScript",
            "--parameters", "commands=\(commandLine)",
            "--query", "Command.CommandId",
            "--output", "text",
        ])
        guard let commandID = CloudCellProviderUtilities.firstNonEmptyLine(in: sendResult.stdout) else {
            throw CommandBackedCloudCellProviderError.missingExternalIdentifier(
                provider: kind,
                output: sendResult.stdout
            )
        }
        _ = try run(arguments: [
            "ssm", "wait", "command-executed",
        ] + scopedArguments(record.metadata) + [
            "--instance-id", record.externalID,
            "--command-id", commandID,
        ])
        return try run(arguments: [
            "ssm", "get-command-invocation",
        ] + scopedArguments(record.metadata) + [
            "--instance-id", record.externalID,
            "--command-id", commandID,
            "--query", "StandardOutputContent",
            "--output", "text",
        ]).stdout
    }

    func attachCommand(cellID: UUID) async throws -> CellAttachCommand {
        let record = try record(for: cellID)
        return CellAttachCommand(
            executable: executable,
            arguments: ["ssm", "start-session"] + scopedArguments(record.metadata) + ["--target", record.externalID],
            displayName: "AWS Cell"
        )
    }

    func logs(cellID: UUID) async throws -> String {
        let record = try record(for: cellID)
        return try run(arguments: [
            "ssm", "list-command-invocations",
        ] + scopedArguments(record.metadata) + [
            "--instance-id", record.externalID,
            "--details",
            "--query", "CommandInvocations[*].CommandPlugins[*].Output",
            "--output", "text",
        ]).stdout
    }

    func destroy(cellID: UUID, force: Bool) async throws {
        let record = try record(for: cellID)
        _ = try run(arguments: [
            "ec2", "terminate-instances",
        ] + scopedArguments(record.metadata) + [
            "--instance-ids", record.externalID,
        ])
        removeRecord(for: cellID)
    }

    private func buildCreateArguments(
        request: CellCreateRequest,
        cellID: UUID,
        image: String
    ) -> [String] {
        let tagName = CloudCellProviderUtilities.cloudName(from: request.name)
        var arguments = [
            "ec2", "run-instances",
        ] + scopedArguments(request.metadata) + [
            "--image-id", image,
            "--instance-type", request.metadata["vm-size"]?.nilIfEmpty ?? "t3.micro",
            "--count", "1",
        ]
        if let subnet = request.metadata["subnet"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--subnet-id", subnet])
        }
        if let securityGroup = request.metadata["security-group"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--security-group-ids"] + CloudCellProviderUtilities.splitList(securityGroup))
        }
        if let keyName = request.metadata["key-name"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--key-name", keyName])
        }
        if let instanceProfile = request.metadata["instance-profile"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--iam-instance-profile", "Name=\(instanceProfile)"])
        }
        if let cloudInit = request.metadata["cloud-init"],
           !cloudInit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--user-data", cloudInit])
        }
        arguments.append(contentsOf: [
            "--tag-specifications",
            "ResourceType=instance,Tags=[{Key=dev.cocxy.cell,Value=true},{Key=dev.cocxy.cell.id,Value=\(cellID.uuidString)},{Key=Name,Value=\(tagName)}]",
            "--query", "Instances[0].InstanceId",
            "--output", "text",
        ])
        return arguments
    }

    private func scopedArguments(_ metadata: [String: String]) -> [String] {
        var arguments: [String] = []
        if let region = metadata["region"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--region", region])
        }
        if let cloudProfile = metadata["cloud-profile"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--profile", cloudProfile])
        }
        return arguments
    }

    private func run(arguments: [String]) throws -> CellProcessResult {
        let result = try executor.run(executable, arguments: arguments)
        guard result.exitCode == 0 else {
            throw CommandBackedCloudCellProviderError.commandFailed(
                provider: kind,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        return result
    }

    private func record(for cellID: UUID) throws -> Record {
        guard let record = records.withValue({ $0[cellID] }) else {
            throw CommandBackedCloudCellProviderError.cellNotFound(cellID)
        }
        return record
    }

    private func setRecord(_ record: Record, for cellID: UUID) {
        records.withValue { $0[cellID] = record }
    }

    private func removeRecord(for cellID: UUID) {
        _ = records.withValue { $0.removeValue(forKey: cellID) }
    }

    private func updateCell(cellID: UUID, _ update: (inout Cell) -> Void) {
        records.withValue { records in
            guard var record = records[cellID] else { return }
            update(&record.cell)
            records[cellID] = record
        }
    }
}

final class GCPCellProvider: CellProvider, @unchecked Sendable {
    let kind: CellProviderKind = .gcp

    private struct Record: Sendable {
        var cell: Cell
        let externalID: String
        let metadata: [String: String]
    }

    private let executable: String
    private let executor: any CellProcessExecuting
    private let clock: @Sendable () -> Date
    private let idGenerator: @Sendable () -> UUID
    private let records = LockedBox<[UUID: Record]>([:])

    init(
        executable: String = "gcloud",
        executor: any CellProcessExecuting = ProcessCellExecutor(),
        clock: @escaping @Sendable () -> Date = { Date() },
        idGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.executable = executable
        self.executor = executor
        self.clock = clock
        self.idGenerator = idGenerator
    }

    func create(_ request: CellCreateRequest) async throws -> Cell {
        let cellID = idGenerator()
        let image = try CloudCellProviderUtilities.requiredImage(kind: kind, metadata: request.metadata)
        let instanceName = CloudCellProviderUtilities.cloudName(from: request.name)
        _ = try run(arguments: buildCreateArguments(
            request: request,
            cellID: cellID,
            image: image,
            instanceName: instanceName
        ))

        let now = clock()
        var metadata = CloudCellProviderUtilities.safeMetadata(from: request.metadata)
        metadata["externalID"] = instanceName
        metadata["image"] = image
        let cell = Cell(
            id: cellID,
            name: request.name,
            provider: kind,
            status: .running,
            createdAt: now,
            updatedAt: now,
            metadata: metadata
        )
        setRecord(Record(
            cell: cell,
            externalID: instanceName,
            metadata: CloudCellProviderUtilities.operationalMetadata(from: request.metadata)
        ), for: cellID)
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
        let result = try run(arguments: [
            "compute", "instances", "describe", record.externalID,
        ] + scopedArguments(record.metadata) + [
            "--format", "value(status)",
        ])
        let status = CloudCellProviderUtilities.gcpStatus(from: result.stdout)
        updateCell(cellID: cellID) { cell in
            cell.status = status
            cell.updatedAt = clock()
        }
        return status
    }

    func exec(cellID: UUID, command: [String]) async throws -> String {
        guard !command.isEmpty else {
            throw CommandBackedCloudCellProviderError.emptyCommand
        }
        let record = try record(for: cellID)
        return try run(arguments: [
            "compute", "ssh", sshTarget(record),
            "--command", CloudCellProviderUtilities.shellCommand(command),
        ] + scopedArguments(record.metadata) + sshArguments(record.metadata)).stdout
    }

    func attachCommand(cellID: UUID) async throws -> CellAttachCommand {
        let record = try record(for: cellID)
        return CellAttachCommand(
            executable: executable,
            arguments: ["compute", "ssh", sshTarget(record)] + scopedArguments(record.metadata) + sshArguments(record.metadata),
            displayName: "GCP Cell"
        )
    }

    func logs(cellID: UUID) async throws -> String {
        let record = try record(for: cellID)
        return try run(arguments: [
            "compute", "instances", "get-serial-port-output", record.externalID,
        ] + scopedArguments(record.metadata)).stdout
    }

    func destroy(cellID: UUID, force: Bool) async throws {
        let record = try record(for: cellID)
        _ = try run(arguments: [
            "compute", "instances", "delete", record.externalID,
            "--quiet",
        ] + scopedArguments(record.metadata))
        removeRecord(for: cellID)
    }

    private func buildCreateArguments(
        request: CellCreateRequest,
        cellID: UUID,
        image: String,
        instanceName: String
    ) -> [String] {
        var arguments = [
            "compute", "instances", "create", instanceName,
            "--image", image,
            "--machine-type", request.metadata["vm-size"]?.nilIfEmpty ?? "e2-micro",
            "--metadata", "dev-cocxy-cell=true,dev-cocxy-cell-id=\(cellID.uuidString),dev-cocxy-cell-name=\(CloudCellProviderUtilities.cloudName(from: request.name))",
        ] + scopedArguments(request.metadata)
        if let network = request.metadata["network"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--network", network])
        }
        if let subnet = request.metadata["subnet"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--subnet", subnet])
        }
        if let cloudInit = request.metadata["cloud-init"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--metadata-from-file", "user-data=\(cloudInit)"])
        }
        return arguments
    }

    private func scopedArguments(_ metadata: [String: String]) -> [String] {
        var arguments: [String] = []
        if let zone = metadata["zone"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--zone", zone])
        }
        if let project = metadata["project"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--project", project])
        }
        return arguments
    }

    private func sshArguments(_ metadata: [String: String]) -> [String] {
        var arguments: [String] = []
        if let identity = metadata["identity"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--ssh-key-file", identity])
        }
        if let strictHostKeyChecking = metadata["strict-host-key-checking"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--strict-host-key-checking", strictHostKeyChecking])
        }
        return arguments
    }

    private func sshTarget(_ record: Record) -> String {
        if let user = record.metadata["user"]?.nilIfEmpty {
            return "\(user)@\(record.externalID)"
        }
        return record.externalID
    }

    private func run(arguments: [String]) throws -> CellProcessResult {
        let result = try executor.run(executable, arguments: arguments)
        guard result.exitCode == 0 else {
            throw CommandBackedCloudCellProviderError.commandFailed(
                provider: kind,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        return result
    }

    private func record(for cellID: UUID) throws -> Record {
        guard let record = records.withValue({ $0[cellID] }) else {
            throw CommandBackedCloudCellProviderError.cellNotFound(cellID)
        }
        return record
    }

    private func setRecord(_ record: Record, for cellID: UUID) {
        records.withValue { $0[cellID] = record }
    }

    private func removeRecord(for cellID: UUID) {
        _ = records.withValue { $0.removeValue(forKey: cellID) }
    }

    private func updateCell(cellID: UUID, _ update: (inout Cell) -> Void) {
        records.withValue { records in
            guard var record = records[cellID] else { return }
            update(&record.cell)
            records[cellID] = record
        }
    }
}

final class AzureCellProvider: CellProvider, @unchecked Sendable {
    let kind: CellProviderKind = .azure

    private struct Record: Sendable {
        var cell: Cell
        let externalID: String
        let metadata: [String: String]
    }

    private let executable: String
    private let executor: any CellProcessExecuting
    private let clock: @Sendable () -> Date
    private let idGenerator: @Sendable () -> UUID
    private let records = LockedBox<[UUID: Record]>([:])

    init(
        executable: String = "az",
        executor: any CellProcessExecuting = ProcessCellExecutor(),
        clock: @escaping @Sendable () -> Date = { Date() },
        idGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.executable = executable
        self.executor = executor
        self.clock = clock
        self.idGenerator = idGenerator
    }

    func create(_ request: CellCreateRequest) async throws -> Cell {
        let cellID = idGenerator()
        let image = try CloudCellProviderUtilities.requiredImage(kind: kind, metadata: request.metadata)
        let resourceGroup = try CloudCellProviderUtilities.requiredMetadata(
            kind: kind,
            metadata: request.metadata,
            key: "resource-group"
        )
        let vmName = CloudCellProviderUtilities.cloudName(from: request.name)
        let adminUsername = Self.adminUsername(from: request.metadata)
        _ = try run(arguments: buildCreateArguments(
            request: request,
            cellID: cellID,
            image: image,
            resourceGroup: resourceGroup,
            vmName: vmName,
            adminUsername: adminUsername
        ))
        do {
            _ = try run(arguments: buildEnableBootDiagnosticsArguments(
                metadata: request.metadata,
                resourceGroup: resourceGroup,
                vmName: vmName
            ))
        } catch {
            _ = try? run(arguments: buildDeleteArguments(
                metadata: request.metadata,
                resourceGroup: resourceGroup,
                vmName: vmName
            ))
            throw error
        }

        let now = clock()
        var metadata = CloudCellProviderUtilities.safeMetadata(from: request.metadata)
        metadata["externalID"] = vmName
        metadata["image"] = image
        metadata["resource-group"] = resourceGroup
        metadata["user"] = adminUsername
        var recordMetadata = request.metadata
        recordMetadata.removeValue(forKey: "cloud-init")
        recordMetadata["user"] = adminUsername
        let cell = Cell(
            id: cellID,
            name: request.name,
            provider: kind,
            status: .running,
            createdAt: now,
            updatedAt: now,
            metadata: metadata
        )
        setRecord(Record(cell: cell, externalID: vmName, metadata: recordMetadata), for: cellID)
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
        let result = try run(arguments: [
            "vm", "get-instance-view",
        ] + scopedArguments(record.metadata) + [
            "--resource-group", try resourceGroup(record),
            "--name", record.externalID,
            "--query", "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus | [0]",
            "--output", "tsv",
        ])
        let status = CloudCellProviderUtilities.azureStatus(from: result.stdout)
        updateCell(cellID: cellID) { cell in
            cell.status = status
            cell.updatedAt = clock()
        }
        return status
    }

    func exec(cellID: UUID, command: [String]) async throws -> String {
        guard !command.isEmpty else {
            throw CommandBackedCloudCellProviderError.emptyCommand
        }
        let record = try record(for: cellID)
        return try run(arguments: [
            "vm", "run-command", "invoke",
        ] + scopedArguments(record.metadata) + [
            "--resource-group", try resourceGroup(record),
            "--name", record.externalID,
            "--command-id", "RunShellScript",
            "--scripts", CloudCellProviderUtilities.shellCommand(command),
            "--query", "value[0].message",
            "--output", "tsv",
        ]).stdout
    }

    func attachCommand(cellID: UUID) async throws -> CellAttachCommand {
        let record = try record(for: cellID)
        return CellAttachCommand(
            executable: executable,
            arguments: [
                "ssh", "vm",
            ] + scopedArguments(record.metadata) + [
                "--resource-group", try resourceGroup(record),
                "--name", record.externalID,
            ] + sshArguments(record.metadata),
            displayName: "Azure Cell"
        )
    }

    func logs(cellID: UUID) async throws -> String {
        let record = try record(for: cellID)
        return try run(arguments: [
            "vm", "boot-diagnostics", "get-boot-log",
        ] + scopedArguments(record.metadata) + [
            "--resource-group", try resourceGroup(record),
            "--name", record.externalID,
        ]).stdout
    }

    func destroy(cellID: UUID, force: Bool) async throws {
        let record = try record(for: cellID)
        _ = try run(arguments: [
            "vm", "delete",
        ] + scopedArguments(record.metadata) + [
            "--resource-group", try resourceGroup(record),
            "--name", record.externalID,
            "--yes",
        ])
        removeRecord(for: cellID)
    }

    private func buildCreateArguments(
        request: CellCreateRequest,
        cellID: UUID,
        image: String,
        resourceGroup: String,
        vmName: String,
        adminUsername: String
    ) -> [String] {
        var arguments = [
            "vm", "create",
        ] + scopedArguments(request.metadata) + [
            "--resource-group", resourceGroup,
            "--name", vmName,
            "--image", image,
            "--admin-username", adminUsername,
            "--size", request.metadata["vm-size"]?.nilIfEmpty ?? Self.defaultVMSize,
        ]
        if let region = request.metadata["region"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--location", region])
        }
        if let identity = request.metadata["identity"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--ssh-key-values", identity])
        }
        if let cloudInit = request.metadata["cloud-init"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--custom-data", cloudInit])
        }
        if let network = request.metadata["network"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--vnet-name", network])
        }
        if let subnet = request.metadata["subnet"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--subnet", subnet])
        }
        arguments.append(contentsOf: [
            "--tags",
            "dev.cocxy.cell=true",
            "dev.cocxy.cell.id=\(cellID.uuidString)",
            "dev.cocxy.cell.name=\(CloudCellProviderUtilities.cloudName(from: request.name))",
            "--query", "id",
            "--output", "tsv",
        ])
        return arguments
    }

    private func buildEnableBootDiagnosticsArguments(
        metadata: [String: String],
        resourceGroup: String,
        vmName: String
    ) -> [String] {
        var arguments = [
            "vm", "boot-diagnostics", "enable",
        ] + scopedArguments(metadata) + [
            "--resource-group", resourceGroup,
            "--name", vmName,
        ]
        if let storage = metadata["boot-diagnostics-storage"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--storage", storage])
        }
        arguments.append(contentsOf: ["--output", "none"])
        return arguments
    }

    private func buildDeleteArguments(
        metadata: [String: String],
        resourceGroup: String,
        vmName: String
    ) -> [String] {
        [
            "vm", "delete",
        ] + scopedArguments(metadata) + [
            "--resource-group", resourceGroup,
            "--name", vmName,
            "--yes",
        ]
    }

    private static func adminUsername(from metadata: [String: String]) -> String {
        metadata["user"]?.nilIfEmpty ?? "cocxy"
    }

    private static let defaultVMSize = "Standard_B1s"

    private func scopedArguments(_ metadata: [String: String]) -> [String] {
        guard let subscription = metadata["cloud-profile"]?.nilIfEmpty else {
            return []
        }
        return ["--subscription", subscription]
    }

    private func sshArguments(_ metadata: [String: String]) -> [String] {
        var arguments: [String] = []
        if let user = metadata["user"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--local-user", user])
        }
        if let identity = metadata["identity"]?.nilIfEmpty {
            arguments.append(contentsOf: ["--private-key-file", identity])
        }
        return arguments
    }

    private func resourceGroup(_ record: Record) throws -> String {
        try CloudCellProviderUtilities.requiredMetadata(
            kind: kind,
            metadata: record.metadata,
            key: "resource-group"
        )
    }

    private func run(arguments: [String]) throws -> CellProcessResult {
        let result = try executor.run(executable, arguments: arguments)
        guard result.exitCode == 0 else {
            throw CommandBackedCloudCellProviderError.commandFailed(
                provider: kind,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        return result
    }

    private func record(for cellID: UUID) throws -> Record {
        guard let record = records.withValue({ $0[cellID] }) else {
            throw CommandBackedCloudCellProviderError.cellNotFound(cellID)
        }
        return record
    }

    private func setRecord(_ record: Record, for cellID: UUID) {
        records.withValue { $0[cellID] = record }
    }

    private func removeRecord(for cellID: UUID) {
        _ = records.withValue { $0.removeValue(forKey: cellID) }
    }

    private func updateCell(cellID: UUID, _ update: (inout Cell) -> Void) {
        records.withValue { records in
            guard var record = records[cellID] else { return }
            update(&record.cell)
            records[cellID] = record
        }
    }
}

private enum CloudCellProviderUtilities {
    static func requiredImage(
        kind: CellProviderKind,
        metadata: [String: String]
    ) throws -> String {
        guard let image = metadata["image"]?.nilIfEmpty else {
            throw CommandBackedCloudCellProviderError.missingImage(provider: kind)
        }
        return image
    }

    static func requiredMetadata(
        kind: CellProviderKind,
        metadata: [String: String],
        key: String
    ) throws -> String {
        guard let value = metadata[key]?.nilIfEmpty else {
            throw CommandBackedCloudCellProviderError.missingMetadata(provider: kind, key: key)
        }
        return value
    }

    static func safeMetadata(from metadata: [String: String]) -> [String: String] {
        var safe = metadata
        for key in metadata.keys where CellMetadataRedactor.redacted([key: metadata[key] ?? ""])[key] == CellMetadataRedactor.redactedValue {
            safe.removeValue(forKey: key)
        }
        return safe
    }

    static func operationalMetadata(from metadata: [String: String]) -> [String: String] {
        var operational = metadata
        operational.removeValue(forKey: "cloud-init")
        return operational
    }

    static func cloudName(from name: String) -> String {
        let sanitized = name
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber || character == "-" {
                    return character
                }
                return "-"
            }
        let collapsed = String(sanitized)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "cocxy-cell" : String(collapsed.prefix(63))
    }

    static func splitList(_ value: String) -> [String] {
        value
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func shellCommand(_ command: [String]) -> String {
        command.map(shellToken).joined(separator: " ")
    }

    static func firstNonEmptyLine(in output: String) -> String? {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    static func awsStatus(from output: String) -> CellStatus {
        switch output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pending":
            return .creating
        case "running":
            return .running
        case "stopping", "stopped":
            return .stopped
        case "shutting-down", "terminated":
            return .destroyed
        default:
            return .failed
        }
    }

    static func gcpStatus(from output: String) -> CellStatus {
        switch output.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "PROVISIONING", "STAGING":
            return .creating
        case "RUNNING":
            return .running
        case "STOPPING", "TERMINATED", "SUSPENDED":
            return .stopped
        case "DELETING":
            return .destroyed
        default:
            return .failed
        }
    }

    static func azureStatus(from output: String) -> CellStatus {
        let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("running") {
            return .running
        }
        if normalized.contains("creating") || normalized.contains("starting") {
            return .creating
        }
        if normalized.contains("stopped") || normalized.contains("deallocated") || normalized.contains("stopping") {
            return .stopped
        }
        if normalized.contains("deleting") || normalized.contains("deleted") {
            return .destroyed
        }
        return .failed
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

private enum CloudCellCommandOutput {
    static func externalID(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let jsonID = externalIDFromJSON(trimmed) {
            return jsonID
        }
        if let labelled = labelledExternalID(from: trimmed) {
            return labelled
        }
        if let sentenceID = sentenceExternalID(from: trimmed) {
            return sentenceID
        }
        let whitespaceTokens = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`,")) }
            .filter { !$0.isEmpty }
        if let token = whitespaceTokens.first(where: isExternalIDToken) {
            return token
        }
        let tokens = trimmed
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return tokens.first(where: isExternalIDToken)
    }

    private static func externalIDFromJSON(_ output: String) -> String? {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return findExternalID(in: json)
    }

    private static func findExternalID(in json: Any) -> String? {
        let keys = ["sandboxID", "sandbox_id", "machineID", "machine_id", "id", "ID"]
        if let object = json as? [String: Any] {
            for key in keys {
                if let value = object[key] as? String, !value.isEmpty {
                    return value
                }
            }
            for value in object.values {
                if let nested = findExternalID(in: value) {
                    return nested
                }
            }
        }
        if let array = json as? [Any] {
            for value in array {
                if let nested = findExternalID(in: value) {
                    return nested
                }
            }
        }
        return nil
    }

    private static func labelledExternalID(from output: String) -> String? {
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(whereSeparator: { $0 == ":" || $0 == "=" })
            guard parts.count >= 2 else { continue }
            let label = parts[0].lowercased()
            guard label.contains("id") else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func sentenceExternalID(from output: String) -> String? {
        let pattern = #"(?i)\bwith\s+ID\s+([A-Za-z0-9_-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              match.numberOfRanges >= 2,
              let idRange = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return String(output[idRange])
    }

    private static func isExternalIDToken(_ token: String) -> Bool {
        token.contains("_") || token.contains("-") || token.count >= 8
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
