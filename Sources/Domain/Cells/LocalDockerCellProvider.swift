// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LocalDockerCellProvider.swift - Local Docker-backed user-owned Cells.

import Foundation

struct CellProcessResult: Equatable, Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

protocol CellProcessExecuting: Sendable {
    func run(_ executable: String, arguments: [String]) throws -> CellProcessResult
}

enum LocalDockerCellProviderError: Error, Equatable, Sendable {
    case dockerCommandFailed(exitCode: Int32, stderr: String)
    case containerNotFound(UUID)
    case invalidDockerOutput(String)
    case emptyCommand
}

struct ProcessCellExecutor: CellProcessExecuting {
    func run(_ executable: String, arguments: [String]) throws -> CellProcessResult {
        let process = Process()
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
        }
        process.environment = Self.commandEnvironment()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let stdoutData = LockedBox(Data())
        let stderrData = LockedBox(Data())
        let outputReaders = DispatchGroup()
        outputReaders.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            stdoutData.withValue { $0 = data }
            outputReaders.leave()
        }
        outputReaders.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            stderrData.withValue { $0 = data }
            outputReaders.leave()
        }

        try process.run()
        process.waitUntilExit()
        outputReaders.wait()

        return CellProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData.withValue { $0 }, as: UTF8.self),
            stderr: String(decoding: stderrData.withValue { $0 }, as: UTF8.self)
        )
    }

    static func commandEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        environment["PATH"] = commandPath(
            existing: base["PATH"],
            home: base["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        )
        return environment
    }

    static func commandPath(existing: String?, home: String) -> String {
        var seen = Set<String>()
        var components: [String] = []

        func append(_ path: String) {
            guard !path.isEmpty, seen.insert(path).inserted else { return }
            components.append(path)
        }

        append("/opt/homebrew/bin")
        append("\(home)/.local/bin")
        append("/usr/local/bin")
        for item in existing?.split(separator: ":").map(String.init) ?? [] {
            append(item)
        }
        append("/usr/bin")
        append("/bin")
        append("/usr/sbin")
        append("/sbin")
        return components.joined(separator: ":")
    }
}

final class LocalDockerCellProvider: CellProvider, @unchecked Sendable {
    let kind: CellProviderKind = .docker

    private let dockerExecutable: String
    private let defaultImage: String
    private let executor: any CellProcessExecuting
    private let clock: @Sendable () -> Date
    private let idGenerator: @Sendable () -> UUID

    init(
        dockerExecutable: String = "docker",
        defaultImage: String = "swift:6.0",
        executor: any CellProcessExecuting = ProcessCellExecutor(),
        clock: @escaping @Sendable () -> Date = { Date() },
        idGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.dockerExecutable = dockerExecutable
        self.defaultImage = defaultImage
        self.executor = executor
        self.clock = clock
        self.idGenerator = idGenerator
    }

    func create(_ request: CellCreateRequest) async throws -> Cell {
        let cellID = idGenerator()
        let image = request.metadata["image"] ?? defaultImage
        let dockerName = dockerContainerName(for: request.name, id: cellID)
        let result = try runDocker([
            "run", "-d",
            "--label", "dev.cocxy.cell=true",
            "--label", "dev.cocxy.cell.id=\(cellID.uuidString)",
            "--label", "dev.cocxy.cell.name=\(request.name)",
            "--name", dockerName,
            image,
            "tail", "-f", "/dev/null",
        ])
        let containerID = firstNonEmptyLine(in: result.stdout) ?? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !containerID.isEmpty else {
            throw LocalDockerCellProviderError.invalidDockerOutput("missing container id")
        }

        let now = clock()
        return Cell(
            id: cellID,
            name: request.name,
            provider: .docker,
            status: .running,
            createdAt: now,
            updatedAt: now,
            metadata: request.metadata.merging([
                "containerID": containerID,
                "dockerName": dockerName,
                "image": image,
            ]) { current, _ in current }
        )
    }

    func list() async throws -> [Cell] {
        let result = try runDocker([
            "ps", "-a",
            "--filter", "label=dev.cocxy.cell=true",
            "--format", "{{json .}}",
        ])
        return try result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { try cell(fromDockerPSLine: String($0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func status(cellID: UUID) async throws -> CellStatus {
        let containerID = try resolveContainerID(cellID: cellID)
        let result = try runDocker(["inspect", "--format", "{{.State.Status}}", containerID])
        return status(fromDockerState: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func exec(cellID: UUID, command: [String]) async throws -> String {
        guard !command.isEmpty else {
            throw LocalDockerCellProviderError.emptyCommand
        }
        let containerID = try resolveContainerID(cellID: cellID)
        let result = try runDocker(["exec", containerID] + command)
        return result.stdout
    }

    func attachCommand(cellID: UUID) async throws -> CellAttachCommand {
        let containerID = try resolveContainerID(cellID: cellID)
        return CellAttachCommand(
            executable: dockerExecutable,
            arguments: ["exec", "-it", containerID, "/bin/sh"],
            displayName: "Docker Cell"
        )
    }

    func logs(cellID: UUID) async throws -> String {
        let containerID = try resolveContainerID(cellID: cellID)
        let result = try runDocker(["logs", containerID])
        return result.stdout
    }

    func destroy(cellID: UUID, force: Bool) async throws {
        let containerID = try resolveContainerID(cellID: cellID)
        if force {
            _ = try runDocker(["rm", "-f", containerID])
        } else {
            _ = try runDocker(["stop", containerID])
            _ = try runDocker(["rm", containerID])
        }
    }

    private func runDocker(_ arguments: [String]) throws -> CellProcessResult {
        let result = try executor.run(dockerExecutable, arguments: arguments)
        guard result.exitCode == 0 else {
            throw LocalDockerCellProviderError.dockerCommandFailed(
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        return result
    }

    private func resolveContainerID(cellID: UUID) throws -> String {
        let result = try runDocker([
            "ps", "-aq",
            "--filter", "label=dev.cocxy.cell=true",
            "--filter", "label=dev.cocxy.cell.id=\(cellID.uuidString)",
        ])
        guard let containerID = firstNonEmptyLine(in: result.stdout) else {
            throw LocalDockerCellProviderError.containerNotFound(cellID)
        }
        return containerID
    }

    private func cell(fromDockerPSLine line: String) throws -> Cell? {
        let data = Data(line.utf8)
        let row = try JSONDecoder().decode(DockerPSRow.self, from: data)
        let labels = parseDockerLabels(row.labels ?? "")
        guard labels["dev.cocxy.cell"] == "true",
              let idValue = labels["dev.cocxy.cell.id"],
              let cellID = UUID(uuidString: idValue) else {
            return nil
        }
        let now = clock()
        return Cell(
            id: cellID,
            name: labels["dev.cocxy.cell.name"] ?? row.names ?? cellID.uuidString,
            provider: .docker,
            status: status(fromDockerState: row.state ?? ""),
            createdAt: now,
            updatedAt: now,
            metadata: [
                "containerID": row.id ?? "",
                "dockerName": row.names ?? "",
                "image": row.image ?? "",
            ]
        )
    }

    private func parseDockerLabels(_ labels: String) -> [String: String] {
        labels
            .split(separator: ",")
            .reduce(into: [String: String]()) { result, part in
                let pieces = part.split(separator: "=", maxSplits: 1)
                guard pieces.count == 2 else { return }
                result[String(pieces[0])] = String(pieces[1])
            }
    }

    private func dockerContainerName(for name: String, id: UUID) -> String {
        let sanitized = name
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber || character == "-" || character == "_" || character == "." {
                    return character
                }
                return "-"
            }
        let collapsed = String(sanitized)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        let suffix = id.uuidString.prefix(8).lowercased()
        return "cocxy-cell-\(collapsed.isEmpty ? "cell" : collapsed)-\(suffix)"
    }

    private func status(fromDockerState state: String) -> CellStatus {
        switch state.lowercased() {
        case "created", "restarting":
            return .creating
        case "running":
            return .running
        case "exited", "paused":
            return .stopped
        case "dead":
            return .failed
        case "removing":
            return .destroyed
        default:
            return .failed
        }
    }

    private func firstNonEmptyLine(in output: String) -> String? {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

private struct DockerPSRow: Decodable {
    let id: String?
    let names: String?
    let image: String?
    let state: String?
    let labels: String?

    private enum CodingKeys: String, CodingKey {
        case id = "ID"
        case names = "Names"
        case image = "Image"
        case state = "State"
        case labels = "Labels"
    }
}
