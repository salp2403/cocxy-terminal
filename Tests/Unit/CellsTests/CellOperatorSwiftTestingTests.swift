// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CellOperatorSwiftTestingTests.swift - Self-hosted Cells Operator control-plane contracts.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Cells Operator control plane")
struct CellOperatorSwiftTestingTests {
    @Test("routes lifecycle operations to the owning provider across multiple cells")
    func routesLifecycleOperationsToOwningProvider() async throws {
        let dockerID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let sshID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let docker = OperatorRecordingCellProvider(kind: .docker, ids: [dockerID])
        let ssh = OperatorRecordingCellProvider(kind: .ssh, ids: [sshID])
        let controlPlane = CellOperatorControlPlane(providers: [
            .docker: docker,
            .ssh: ssh,
        ])

        let dockerCell = try await controlPlane.create(
            provider: .docker,
            request: CellCreateRequest(name: "Docker Build", metadata: ["image": "swift:6.0"])
        )
        let sshCell = try await controlPlane.create(
            provider: .ssh,
            request: CellCreateRequest(name: "SSH Lab", metadata: ["host": "lab.example.test"])
        )
        let cells = try await controlPlane.list()
        let snapshot = try await controlPlane.snapshot()
        let output = try await controlPlane.exec(cellID: dockerID, command: ["echo", "ok"])
        let attach = try await controlPlane.attachCommand(cellID: sshID)
        try await controlPlane.destroy(cellID: dockerID, force: true)

        #expect(dockerCell.id == dockerID)
        #expect(sshCell.id == sshID)
        #expect(cells.map(\.id) == [dockerID, sshID])
        #expect(snapshot.providerCount == 2)
        #expect(snapshot.runningCount == 2)
        #expect(snapshot.cells.map(\.id) == [dockerID, sshID])
        #expect(output == "docker: echo ok")
        #expect(attach.argv == ["ssh", "attach", sshID.uuidString])
        #expect(docker.execCalls.map(\.id) == [dockerID])
        #expect(docker.execCalls.map(\.command) == [["echo", "ok"]])
        #expect(ssh.execCalls.isEmpty)
        #expect(docker.destroyCalls.map(\.id) == [dockerID])
        #expect(docker.destroyCalls.map(\.force) == [true])
    }

    @Test("recovers cell ownership from provider lists after an operator restart")
    func recoversCellOwnershipFromProviderLists() async throws {
        let existingID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let docker = OperatorRecordingCellProvider(kind: .docker)
        let ssh = OperatorRecordingCellProvider(kind: .ssh, initialCells: [
            Cell(id: existingID, name: "Existing SSH", provider: .ssh, status: .running),
        ])
        let controlPlane = CellOperatorControlPlane(providers: [
            .docker: docker,
            .ssh: ssh,
        ])

        let status = try await controlPlane.status(cellID: existingID)
        let logs = try await controlPlane.logs(cellID: existingID)

        #expect(status == .running)
        #expect(logs == "ssh logs for \(existingID.uuidString)")
        #expect(docker.statusCalls.isEmpty)
        #expect(ssh.statusCalls == [existingID])
    }

    @Test("rejects unsupported providers and empty exec commands before provider side effects")
    func rejectsUnsafeRequestsBeforeProviderSideEffects() async throws {
        let cellID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let docker = OperatorRecordingCellProvider(kind: .docker, ids: [cellID])
        let controlPlane = CellOperatorControlPlane(providers: [.docker: docker])
        _ = try await controlPlane.create(provider: .docker, request: CellCreateRequest(name: "Docker"))

        do {
            _ = try await controlPlane.create(provider: .azure, request: CellCreateRequest(name: "Azure"))
            Issue.record("Expected unsupported provider error")
        } catch let error as CellOperatorError {
            #expect(error == .unsupportedProvider(.azure))
        }

        do {
            _ = try await controlPlane.exec(cellID: cellID, command: [])
            Issue.record("Expected empty command error")
        } catch let error as CellOperatorError {
            #expect(error == .emptyCommand)
        }

        #expect(docker.execCalls.isEmpty)
    }
}

private final class OperatorRecordingCellProvider: CellProvider, @unchecked Sendable {
    let kind: CellProviderKind

    private struct State: Sendable {
        var ids: [UUID]
        var cells: [UUID: Cell]
        var createRequests: [CellCreateRequest] = []
        var execCalls: [OperatorExecCall] = []
        var statusCalls: [UUID] = []
        var destroyCalls: [OperatorDestroyCall] = []
    }

    private let state: LockedBox<State>

    init(
        kind: CellProviderKind,
        ids: [UUID] = [],
        initialCells: [Cell] = []
    ) {
        self.kind = kind
        self.state = LockedBox(State(
            ids: ids,
            cells: Dictionary(uniqueKeysWithValues: initialCells.map { ($0.id, $0) })
        ))
    }

    var execCalls: [OperatorExecCall] {
        state.withValue(\.execCalls)
    }

    var statusCalls: [UUID] {
        state.withValue(\.statusCalls)
    }

    var destroyCalls: [OperatorDestroyCall] {
        state.withValue(\.destroyCalls)
    }

    func create(_ request: CellCreateRequest) async throws -> Cell {
        state.withValue { state in
            let id = state.ids.isEmpty ? UUID() : state.ids.removeFirst()
            let now = Date(timeIntervalSince1970: 1_800_000_300)
            let cell = Cell(
                id: id,
                name: request.name,
                provider: kind,
                status: .running,
                createdAt: now,
                updatedAt: now,
                metadata: request.metadata
            )
            state.createRequests.append(request)
            state.cells[id] = cell
            return cell
        }
    }

    func list() async throws -> [Cell] {
        state.withValue { state in
            state.cells.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    func status(cellID: UUID) async throws -> CellStatus {
        guard let cell = state.withValue({ $0.cells[cellID] }) else {
            throw CellOperatorError.cellNotFound(cellID)
        }
        state.withValue { state in
            state.statusCalls.append(cellID)
        }
        return cell.status
    }

    func exec(cellID: UUID, command: [String]) async throws -> String {
        guard state.withValue({ $0.cells[cellID] != nil }) else {
            throw CellOperatorError.cellNotFound(cellID)
        }
        state.withValue { state in
            state.execCalls.append(OperatorExecCall(id: cellID, command: command))
        }
        return "\(kind.rawValue): \(command.joined(separator: " "))"
    }

    func attachCommand(cellID: UUID) async throws -> CellAttachCommand {
        guard state.withValue({ $0.cells[cellID] != nil }) else {
            throw CellOperatorError.cellNotFound(cellID)
        }
        return CellAttachCommand(
            executable: kind.rawValue,
            arguments: ["attach", cellID.uuidString],
            displayName: "\(kind.rawValue) Cell"
        )
    }

    func logs(cellID: UUID) async throws -> String {
        guard state.withValue({ $0.cells[cellID] != nil }) else {
            throw CellOperatorError.cellNotFound(cellID)
        }
        return "\(kind.rawValue) logs for \(cellID.uuidString)"
    }

    func destroy(cellID: UUID, force: Bool) async throws {
        let removed = state.withValue { state in
            state.cells.removeValue(forKey: cellID)
        }
        guard removed != nil else {
            throw CellOperatorError.cellNotFound(cellID)
        }
        state.withValue { state in
            state.destroyCalls.append(OperatorDestroyCall(id: cellID, force: force))
        }
    }
}

private struct OperatorExecCall: Equatable, Sendable {
    let id: UUID
    let command: [String]
}

private struct OperatorDestroyCall: Equatable, Sendable {
    let id: UUID
    let force: Bool
}
