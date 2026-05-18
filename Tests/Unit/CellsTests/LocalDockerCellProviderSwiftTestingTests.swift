// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LocalDockerCellProviderSwiftTestingTests.swift - Local Docker Cells provider contracts.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Local Docker cell provider")
struct LocalDockerCellProviderSwiftTestingTests {
    @Test("create starts a labelled docker container and returns a running cell")
    func createStartsLabelledContainer() async throws {
        let cellID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let executor = RecordingCellProcessExecutor(responses: [
            CellProcessResult(exitCode: 0, stdout: "container-123\n", stderr: ""),
        ])
        let provider = LocalDockerCellProvider(
            executor: executor,
            clock: { now },
            idGenerator: { cellID }
        )

        let cell = try await provider.create(CellCreateRequest(
            name: "Swift Local",
            metadata: ["image": "alpine:3.20"]
        ))

        #expect(cell.id == cellID)
        #expect(cell.name == "Swift Local")
        #expect(cell.provider == .docker)
        #expect(cell.status == .running)
        #expect(cell.createdAt == now)
        #expect(cell.metadata["containerID"] == "container-123")
        #expect(executor.calls.count == 1)
        #expect(executor.calls[0].arguments.contains("--label"))
        #expect(executor.calls[0].arguments.contains("dev.cocxy.cell=true"))
        #expect(executor.calls[0].arguments.contains("dev.cocxy.cell.id=\(cellID.uuidString)"))
        #expect(executor.calls[0].arguments.suffix(4) == ["alpine:3.20", "tail", "-f", "/dev/null"])
    }

    @Test("list parses docker json lines into cells")
    func listParsesDockerJSONLines() async throws {
        let cellID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let line = """
        {"ID":"abc123","Names":"cocxy-cell-swift-local","Image":"swift:6.0","State":"running","Labels":"dev.cocxy.cell=true,dev.cocxy.cell.id=\(cellID.uuidString)"}
        """
        let executor = RecordingCellProcessExecutor(responses: [
            CellProcessResult(exitCode: 0, stdout: line + "\n", stderr: ""),
        ])
        let provider = LocalDockerCellProvider(executor: executor)

        let cells = try await provider.list()

        #expect(cells.count == 1)
        #expect(cells[0].id == cellID)
        #expect(cells[0].name == "cocxy-cell-swift-local")
        #expect(cells[0].status == .running)
        #expect(cells[0].metadata["containerID"] == "abc123")
        #expect(cells[0].metadata["image"] == "swift:6.0")
    }

    @Test("exec resolves the labelled container before running command argv")
    func execResolvesLabelledContainer() async throws {
        let cellID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let executor = RecordingCellProcessExecutor(responses: [
            CellProcessResult(exitCode: 0, stdout: "abc123\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "ok\n", stderr: ""),
        ])
        let provider = LocalDockerCellProvider(executor: executor)

        let output = try await provider.exec(cellID: cellID, command: ["echo", "ok"])

        #expect(output == "ok\n")
        #expect(executor.calls.count == 2)
        #expect(executor.calls[0].arguments == [
            "ps", "-aq",
            "--filter", "label=dev.cocxy.cell=true",
            "--filter", "label=dev.cocxy.cell.id=\(cellID.uuidString)",
        ])
        #expect(executor.calls[1].arguments == ["exec", "abc123", "echo", "ok"])
    }

    @Test("attach command resolves the labelled container and builds an interactive docker exec")
    func attachCommandBuildsInteractiveDockerExec() async throws {
        let cellID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let executor = RecordingCellProcessExecutor(responses: [
            CellProcessResult(exitCode: 0, stdout: "abc 123\n", stderr: ""),
        ])
        let provider = LocalDockerCellProvider(executor: executor)

        let command = try await provider.attachCommand(cellID: cellID)

        #expect(command.argv == ["docker", "exec", "-it", "abc 123", "/bin/sh"])
        #expect(command.shellCommand == "docker exec -it 'abc 123' /bin/sh")
        #expect(command.displayName == "Docker Cell")
        #expect(executor.calls.count == 1)
        #expect(executor.calls[0].arguments == [
            "ps", "-aq",
            "--filter", "label=dev.cocxy.cell=true",
            "--filter", "label=dev.cocxy.cell.id=\(cellID.uuidString)",
        ])
    }

    @Test("destroy only removes a resolved labelled container")
    func destroyOnlyRemovesResolvedLabelledContainer() async throws {
        let cellID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let executor = RecordingCellProcessExecutor(responses: [
            CellProcessResult(exitCode: 0, stdout: "abc123\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "", stderr: ""),
        ])
        let provider = LocalDockerCellProvider(executor: executor)

        try await provider.destroy(cellID: cellID, force: true)

        #expect(executor.calls.count == 2)
        #expect(executor.calls[1].arguments == ["rm", "-f", "abc123"])
    }

    @Test("process executor prefers modern Homebrew and local bins ahead of stale system paths")
    func processExecutorCommandPathPrefersModernHomebrew() {
        let path = ProcessCellExecutor.commandPath(
            existing: "/usr/local/bin:/usr/bin:/opt/homebrew/bin",
            home: "/Users/example"
        )

        #expect(path.split(separator: ":").prefix(4).map(String.init) == [
            "/opt/homebrew/bin",
            "/Users/example/.local/bin",
            "/usr/local/bin",
            "/usr/bin",
        ])
        #expect(path.split(separator: ":").filter { $0 == "/opt/homebrew/bin" }.count == 1)
    }
}

private final class RecordingCellProcessExecutor: CellProcessExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var queuedResponses: [CellProcessResult]
    private(set) var calls: [(executable: String, arguments: [String])] = []

    init(responses: [CellProcessResult]) {
        queuedResponses = responses
    }

    func run(_ executable: String, arguments: [String]) throws -> CellProcessResult {
        lock.lock()
        defer { lock.unlock() }
        calls.append((executable, arguments))
        guard !queuedResponses.isEmpty else {
            throw LocalDockerCellProviderError.dockerCommandFailed(exitCode: 1, stderr: "missing fake response")
        }
        return queuedResponses.removeFirst()
    }
}
