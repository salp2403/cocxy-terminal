// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CellCLICommandServiceSwiftTestingTests.swift - Cell CLI service adapter coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Cell CLI command service")
struct CellCLICommandServiceSwiftTestingTests {
    @Test("create routes to requested provider and redacts metadata in payload")
    func createRoutesToRequestedProvider() async throws {
        let cellID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let provider = FakeCellProvider(cells: [
            Cell(
                id: cellID,
                name: "local-dev",
                provider: .docker,
                status: .running,
                metadata: ["token": "secret-token", "image": "swift:6.0"]
            ),
        ])
        let service = CellCLICommandService(providers: [.docker: provider])

        let result = await service.perform(kind: "create", params: [
            "provider": "docker",
            "profile": "local-dev",
            "image": "swift:6.0",
        ])

        #expect(result.success)
        #expect(result.data["status"] == "created")
        #expect(result.data["id"] == cellID.uuidString)
        #expect(result.data["metadata_image"] == "swift:6.0")
        #expect(result.data["metadata_token"] == "[redacted]")
        #expect(provider.createdRequests.first?.name == "local-dev")
        #expect(provider.createdRequests.first?.metadata["image"] == "swift:6.0")
    }

    @Test("create forwards SSH connection metadata to the SSH provider")
    func createForwardsSSHConnectionMetadata() async {
        let cellID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let provider = FakeCellProvider(kind: .ssh, cells: [
            Cell(
                id: cellID,
                name: "Lab",
                provider: .ssh,
                status: .running,
                metadata: ["host": "example.test"]
            ),
        ])
        let service = CellCLICommandService(providers: [.ssh: provider])

        let result = await service.perform(kind: "create", params: [
            "provider": "ssh",
            "profile": "Lab",
            "host": "example.test",
            "user": "deploy",
            "port": "2222",
            "identity": "~/.ssh/id_ed25519",
        ])

        #expect(result.success)
        #expect(result.data["provider"] == "ssh")
        #expect(provider.createdRequests.count == 1)
        #expect(provider.createdRequests[0].metadata["host"] == "example.test")
        #expect(provider.createdRequests[0].metadata["user"] == "deploy")
        #expect(provider.createdRequests[0].metadata["port"] == "2222")
        #expect(provider.createdRequests[0].metadata["identity"] == "~/.ssh/id_ed25519")
    }

    @Test("create forwards cloud account and network metadata to cloud providers")
    func createForwardsCloudAccountAndNetworkMetadata() async {
        let cellID = UUID(uuidString: "12121212-1212-1212-1212-121212121212")!
        let provider = FakeCellProvider(kind: .azure, cells: [
            Cell(
                id: cellID,
                name: "Azure Lab",
                provider: .azure,
                status: .running,
                metadata: ["resource-group": "rg-cocxy"]
            ),
        ])
        let service = CellCLICommandService(providers: [.azure: provider])

        let result = await service.perform(kind: "create", params: [
            "provider": "azure",
            "profile": "Azure Lab",
            "image": "Ubuntu2204",
            "cloud-profile": "sub-1",
            "project": "cocxy-dev",
            "zone": "us-central1-a",
            "resource-group": "rg-cocxy",
            "network": "vnet",
            "subnet": "subnet-a",
            "security-group": "sg-1",
            "key-name": "cocxy-key",
            "instance-profile": "cocxy-ssm-profile",
            "cloud-init": "cloud-init.yml",
        ])

        #expect(result.success)
        #expect(result.data["provider"] == "azure")
        #expect(provider.createdRequests.count == 1)
        #expect(provider.createdRequests[0].metadata["image"] == "Ubuntu2204")
        #expect(provider.createdRequests[0].metadata["cloud-profile"] == "sub-1")
        #expect(provider.createdRequests[0].metadata["project"] == "cocxy-dev")
        #expect(provider.createdRequests[0].metadata["zone"] == "us-central1-a")
        #expect(provider.createdRequests[0].metadata["resource-group"] == "rg-cocxy")
        #expect(provider.createdRequests[0].metadata["network"] == "vnet")
        #expect(provider.createdRequests[0].metadata["subnet"] == "subnet-a")
        #expect(provider.createdRequests[0].metadata["security-group"] == "sg-1")
        #expect(provider.createdRequests[0].metadata["key-name"] == "cocxy-key")
        #expect(provider.createdRequests[0].metadata["instance-profile"] == "cocxy-ssm-profile")
        #expect(provider.createdRequests[0].metadata["cloud-init"] == "cloud-init.yml")
    }

    @Test("exec decodes argv-json and returns stdout")
    func execDecodesArgvJSON() async throws {
        let cellID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let provider = FakeCellProvider(cells: [
            Cell(id: cellID, name: "local", provider: .docker, status: .running),
        ])
        provider.execOutput = "ok\n"
        let service = CellCLICommandService(providers: [.docker: provider])
        let argvJSON = String(decoding: try JSONEncoder().encode(["echo", "ok"]), as: UTF8.self)

        let result = await service.perform(kind: "exec", params: [
            "cell-id": cellID.uuidString,
            "argv-json": argvJSON,
        ])

        #expect(result.success)
        #expect(result.data["stdout"] == "ok\n")
        #expect(provider.execCalls.count == 1)
        #expect(provider.execCalls.first?.0 == cellID)
        #expect(provider.execCalls.first?.1 == ["echo", "ok"])
    }

    @Test("exec preserves owner provider errors instead of masking them as not found")
    func execPreservesOwnerProviderError() async throws {
        let cellID = UUID(uuidString: "23232323-2323-2323-2323-232323232323")!
        let dockerProvider = FakeCellProvider(cells: [])
        let flyProvider = FakeCellProvider(kind: .fly, cells: [
            Cell(id: cellID, name: "fly", provider: .fly, status: .running),
        ])
        flyProvider.execError = CommandBackedCloudCellProviderError.commandFailed(
            provider: .fly,
            exitCode: 1,
            stderr: "machine is not ready"
        )
        let sshProvider = FakeCellProvider(kind: .ssh, cells: [])
        let service = CellCLICommandService(providers: [
            .docker: dockerProvider,
            .fly: flyProvider,
            .ssh: sshProvider,
        ])
        let argvJSON = String(decoding: try JSONEncoder().encode(["printf", "ok"]), as: UTF8.self)

        let result = await service.perform(kind: "exec", params: [
            "cell-id": cellID.uuidString,
            "argv-json": argvJSON,
        ])

        #expect(!result.success)
        #expect(result.data["error"]?.contains("machine is not ready") == true)
        #expect(flyProvider.execCalls.count == 1)
        #expect(sshProvider.execCalls.isEmpty)
    }

    @Test("logs keep socket payload bounded and report truncation")
    func logsKeepSocketPayloadBounded() async {
        let cellID = UUID(uuidString: "45454545-4545-4545-4545-454545454545")!
        let provider = FakeCellProvider(cells: [
            Cell(id: cellID, name: "gcp", provider: .gcp, status: .running),
        ])
        provider.logsOutput = String(repeating: "x", count: 70_000)
        let service = CellCLICommandService(providers: [.gcp: provider])

        let result = await service.perform(kind: "logs", params: [
            "cell-id": cellID.uuidString,
            "provider": "gcp",
        ])

        #expect(result.success)
        #expect(result.data["status"] == "logs")
        #expect(result.data["stdout"]?.count == 48_000)
        #expect(result.data["stdout-bytes"] == "70000")
        #expect(result.data["stdout-truncated"] == "true")
        #expect(result.data["stdout-note"] == "truncated-to-socket-payload")
    }

    @Test("list flattens provider cells")
    func listFlattensProviderCells() async {
        let cellID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let provider = FakeCellProvider(cells: [
            Cell(id: cellID, name: "local", provider: .docker, status: .running),
        ])
        let service = CellCLICommandService(providers: [.docker: provider])

        let result = await service.perform(kind: "list", params: [:])

        #expect(result.success)
        #expect(result.data["count"] == "1")
        #expect(result.data["cell_0_id"] == cellID.uuidString)
        #expect(result.data["cell_0_provider"] == "docker")
    }

    @Test("list keeps available cells when one provider is unavailable")
    func listKeepsAvailableCellsWhenOneProviderIsUnavailable() async {
        let cellID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let dockerProvider = FakeCellProvider(cells: [])
        dockerProvider.listError = LocalDockerCellProviderError.dockerCommandFailed(
            exitCode: 127,
            stderr: "env: docker: No such file or directory"
        )
        let sshProvider = FakeCellProvider(kind: .ssh, cells: [
            Cell(id: cellID, name: "ssh-lab", provider: .ssh, status: .running),
        ])
        let service = CellCLICommandService(providers: [
            .docker: dockerProvider,
            .ssh: sshProvider,
        ])

        let result = await service.perform(kind: "list", params: [:])

        #expect(result.success)
        #expect(result.data["count"] == "1")
        #expect(result.data["cell_0_id"] == cellID.uuidString)
        #expect(result.data["cell_0_provider"] == "ssh")
        #expect(result.data["provider-error-count"] == "1")
        #expect(result.data["provider_error_0_provider"] == "docker")
        #expect(result.data["provider_error_0_message"]?.contains("docker") == true)
    }

    @Test("audits successful create exec status logs attach and destroy actions")
    func auditsSuccessfulCellActions() async throws {
        let cellID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let provider = FakeCellProvider(cells: [
            Cell(
                id: cellID,
                name: "local",
                provider: .docker,
                status: .running,
                metadata: ["token": "secret-token", "image": "swift:6.0"]
            ),
        ])
        provider.execOutput = "ok\n"
        let auditLog = RecordingCellAuditLog()
        let service = CellCLICommandService(
            providers: [.docker: provider],
            auditLog: auditLog,
            actorProvider: { "cells-test" },
            now: { Date(timeIntervalSince1970: 1_800_000_200) }
        )
        let argvJSON = String(decoding: try JSONEncoder().encode(["echo", "ok"]), as: UTF8.self)

        _ = await service.perform(kind: "create", params: ["provider": "docker", "profile": "local"])
        _ = await service.perform(kind: "exec", params: ["cell-id": cellID.uuidString, "argv-json": argvJSON])
        _ = await service.perform(kind: "status", params: ["cell-id": cellID.uuidString])
        _ = await service.perform(kind: "logs", params: ["cell-id": cellID.uuidString])
        _ = await service.perform(kind: "attach", params: ["cell-id": cellID.uuidString])
        _ = await service.perform(kind: "destroy", params: ["cell-id": cellID.uuidString, "force": "true"])

        #expect(auditLog.events.map(\.action) == [.create, .exec, .status, .logs, .attach, .destroy])
        #expect(auditLog.events.allSatisfy { $0.cellID == cellID })
        #expect(auditLog.events.allSatisfy { $0.actor == "cells-test" })
        #expect(auditLog.events[0].metadata["token"] == "[redacted]")
        #expect(auditLog.events[1].metadata["argv"] == "echo ok")
        #expect(provider.destroyCalls.count == 1)
        #expect(provider.destroyCalls[0].0 == cellID)
        #expect(provider.destroyCalls[0].1 == true)
    }

    @Test("attach returns single-use lease fields and provider PTY command without auditing the signature")
    func attachReturnsLeaseAndPTYCommand() async {
        let cellID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let provider = FakeCellProvider(cells: [
            Cell(id: cellID, name: "local", provider: .docker, status: .running),
        ])
        provider.attachCommandResult = CellAttachCommand(
            executable: "docker",
            arguments: ["exec", "-it", "container 123", "/bin/sh"],
            displayName: "Docker Cell"
        )
        let auditLog = RecordingCellAuditLog()
        let service = CellCLICommandService(
            providers: [.docker: provider],
            auditLog: auditLog,
            actorProvider: { "cells-test" }
        )

        let result = await service.perform(kind: "attach", params: ["cell-id": cellID.uuidString])

        #expect(result.success)
        #expect(result.data["status"] == "attach-ready")
        #expect(result.data["cell-id"] == cellID.uuidString)
        #expect(result.data["purpose"] == "attach-pty")
        #expect(result.data["pty-transport"] == "native-process")
        #expect(result.data["pty-command"] == "docker exec -it 'container 123' /bin/sh")
        #expect(result.data["pty-argv-json"] == #"["docker","exec","-it","container 123","/bin/sh"]"#)
        #expect(result.data["pty-title"] == "Docker Cell")
        #expect(result.data["lease-id"]?.isEmpty == false)
        #expect(result.data["lease-token"]?.contains(result.data["lease-id"] ?? "") == true)
        #expect(result.data["lease-signature"]?.isEmpty == false)
        #expect(result.data["issued-at"]?.isEmpty == false)
        #expect(result.data["issued-at-unix"]?.isEmpty == false)
        #expect(result.data["expires-at-unix"]?.isEmpty == false)
        #expect(service.consumeAttachLease(fields: result.data) == true)
        #expect(service.consumeAttachLease(fields: result.data) == false)
        #expect(provider.attachCalls == [cellID])
        #expect(auditLog.events.map(\.action) == [.attach])
        #expect(auditLog.events[0].metadata.keys.sorted() == ["lease-id"])
    }
}

private final class FakeCellProvider: CellProvider, @unchecked Sendable {
    let kind: CellProviderKind
    private var cells: [Cell]
    var createdRequests: [CellCreateRequest] = []
    var execOutput = ""
    var logsOutput = "logs"
    var execCalls: [(UUID, [String])] = []
    var attachCommandResult = CellAttachCommand(
        executable: "docker",
        arguments: ["exec", "-it", "container-123", "/bin/sh"],
        displayName: "Docker Cell"
    )
    var attachCalls: [UUID] = []
    var destroyCalls: [(UUID, Bool)] = []
    var listError: Error?
    var execError: Error?

    init(kind: CellProviderKind = .docker, cells: [Cell]) {
        self.kind = kind
        self.cells = cells
    }

    func create(_ request: CellCreateRequest) async throws -> Cell {
        createdRequests.append(request)
        return cells[0]
    }

    func list() async throws -> [Cell] {
        if let listError {
            throw listError
        }
        return cells
    }

    func status(cellID: UUID) async throws -> CellStatus {
        guard let cell = cells.first(where: { $0.id == cellID }) else {
            throw notFoundError(cellID)
        }
        return cell.status
    }

    func exec(cellID: UUID, command: [String]) async throws -> String {
        guard cells.contains(where: { $0.id == cellID }) else {
            throw notFoundError(cellID)
        }
        execCalls.append((cellID, command))
        if let execError {
            throw execError
        }
        return execOutput
    }

    func attachCommand(cellID: UUID) async throws -> CellAttachCommand {
        guard cells.contains(where: { $0.id == cellID }) else {
            throw notFoundError(cellID)
        }
        attachCalls.append(cellID)
        return attachCommandResult
    }

    func logs(cellID: UUID) async throws -> String {
        guard cells.contains(where: { $0.id == cellID }) else {
            throw notFoundError(cellID)
        }
        return logsOutput
    }

    func destroy(cellID: UUID, force: Bool) async throws {
        guard cells.contains(where: { $0.id == cellID }) else {
            throw notFoundError(cellID)
        }
        destroyCalls.append((cellID, force))
    }

    private func notFoundError(_ cellID: UUID) -> Error {
        switch kind {
        case .docker:
            return LocalDockerCellProviderError.containerNotFound(cellID)
        case .ssh, .selfHosted:
            return SSHCellProviderError.cellNotFound(cellID)
        case .e2b, .fly, .aws, .gcp, .azure:
            return CommandBackedCloudCellProviderError.cellNotFound(cellID)
        }
    }
}

private final class RecordingCellAuditLog: CellAuditLogging, @unchecked Sendable {
    private let eventsBox = LockedBox<[CellAuditEvent]>([])

    var events: [CellAuditEvent] {
        eventsBox.withValue { $0 }
    }

    func append(_ event: CellAuditEvent) throws {
        eventsBox.withValue { $0.append(event) }
    }
}
