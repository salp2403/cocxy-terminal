// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandBackedCloudCellProviderSwiftTestingTests.swift - Cloud Cell provider contracts.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Command-backed cloud cell providers")
struct CommandBackedCloudCellProviderSwiftTestingTests {
    @Test("E2B create uses the user CLI without token arguments and records sandbox metadata")
    func e2bCreateUsesUserCLIWithoutTokenArguments() async throws {
        let cellID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let now = Date(timeIntervalSince1970: 1_800_000_300)
        let detachedOutput = """
        Use the following link to inspect this Sandbox live inside the E2B Dashboard:
        https://e2b.dev/dashboard/inspect/sandbox/sbx123456789012345678

        Sandbox created with ID sbx123456789012345678 using template base
        """
        let executor = RecordingCloudCellExecutor(responses: [
            CellProcessResult(exitCode: 0, stdout: detachedOutput, stderr: ""),
        ])
        let provider = E2BCellProvider(
            executor: executor,
            clock: { now },
            idGenerator: { cellID }
        )

        let cell = try await provider.create(CellCreateRequest(
            name: "E2B Lab",
            metadata: [
                "template": "base",
                "path": "/workspace",
                "token": "must-not-be-forwarded",
            ]
        ))

        #expect(cell.id == cellID)
        #expect(cell.provider == .e2b)
        #expect(cell.status == .running)
        #expect(cell.createdAt == now)
        #expect(cell.metadata["externalID"] == "sbx123456789012345678")
        #expect(cell.metadata["template"] == "base")
        #expect(cell.metadata["token"] == nil)
        #expect(executor.calls.count == 1)
        #expect(executor.calls[0].executable == "e2b")
        #expect(executor.calls[0].arguments == [
            "sandbox", "create", "--detach",
            "--path", "/workspace",
            "base",
        ])
        #expect(!executor.calls[0].arguments.contains("must-not-be-forwarded"))
    }

    @Test("E2B exec logs status and destroy target the recorded sandbox id")
    func e2bLifecycleTargetsRecordedSandboxID() async throws {
        let cellID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let executor = RecordingCloudCellExecutor(responses: [
            CellProcessResult(exitCode: 0, stdout: "sandbox id: sbx_456\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "ok\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "logs\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: #"[{"sandboxID":"sbx_456"}]"#, stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "", stderr: ""),
        ])
        let provider = E2BCellProvider(
            executor: executor,
            idGenerator: { cellID }
        )
        _ = try await provider.create(CellCreateRequest(name: "E2B Lifecycle"))

        let attach = try await provider.attachCommand(cellID: cellID)
        let output = try await provider.exec(cellID: cellID, command: ["echo", "ok"])
        let logs = try await provider.logs(cellID: cellID)
        let status = try await provider.status(cellID: cellID)
        try await provider.destroy(cellID: cellID, force: true)

        #expect(attach.argv == ["e2b", "sandbox", "connect", "sbx_456"])
        #expect(attach.displayName == "E2B Cell")
        #expect(output == "ok\n")
        #expect(logs == "logs\n")
        #expect(status == .running)
        #expect(executor.calls.map(\.arguments) == [
            ["sandbox", "create", "--detach"],
            ["sandbox", "exec", "sbx_456", "echo", "ok"],
            ["sandbox", "logs", "sbx_456"],
            ["sandbox", "list", "--format", "json"],
            ["sandbox", "kill", "sbx_456"],
        ])
        #expect(try await provider.list() == [])
    }

    @Test("Fly create runs a detached user-owned machine with scoped metadata")
    func flyCreateRunsDetachedMachineWithScopedMetadata() async throws {
        let cellID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        let now = Date(timeIntervalSince1970: 1_800_000_400)
        let executor = RecordingCloudCellExecutor(responses: [
            CellProcessResult(exitCode: 0, stdout: #"{"id":"fly-machine-123"}"#, stderr: ""),
        ])
        let provider = FlyCellProvider(
            executor: executor,
            clock: { now },
            idGenerator: { cellID }
        )

        let cell = try await provider.create(CellCreateRequest(
            name: "Fly Lab",
            metadata: [
                "image": "debian:bookworm-slim",
                "app": "cocxy-lab",
                "region": "iad",
                "vm-size": "shared-cpu-1x",
                "vm-memory": "1024",
                "token": "must-not-be-forwarded",
            ]
        ))

        #expect(cell.id == cellID)
        #expect(cell.provider == .fly)
        #expect(cell.status == .running)
        #expect(cell.createdAt == now)
        #expect(cell.metadata["externalID"] == "fly-machine-123")
        #expect(cell.metadata["app"] == "cocxy-lab")
        #expect(cell.metadata["token"] == nil)
        #expect(executor.calls.count == 1)
        #expect(executor.calls[0].executable == "fly")
        #expect(executor.calls[0].arguments == [
            "machine", "run",
            "--detach",
            "--name", "fly-lab",
            "--app", "cocxy-lab",
            "--region", "iad",
            "--vm-size", "shared-cpu-1x",
            "--vm-memory", "1024",
            "--metadata", "dev.cocxy.cell=true",
            "--metadata", "dev.cocxy.cell.id=\(cellID.uuidString)",
            "--metadata", "dev.cocxy.cell.name=Fly Lab",
            "debian:bookworm-slim",
            "sleep", "inf",
        ])
        #expect(!executor.calls[0].arguments.contains("must-not-be-forwarded"))
    }

    @Test("Fly lifecycle commands include app scope and machine id")
    func flyLifecycleCommandsIncludeAppScopeAndMachineID() async throws {
        let cellID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
        let executor = RecordingCloudCellExecutor(responses: [
            CellProcessResult(exitCode: 0, stdout: "Machine ID: fly-machine-456\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "ok\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "app logs\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "State: started\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "", stderr: ""),
        ])
        let provider = FlyCellProvider(
            executor: executor,
            idGenerator: { cellID }
        )
        _ = try await provider.create(CellCreateRequest(
            name: "Fly Lifecycle",
            metadata: ["image": "debian:bookworm-slim", "app": "cocxy-lab"]
        ))

        let attach = try await provider.attachCommand(cellID: cellID)
        let output = try await provider.exec(cellID: cellID, command: ["printf", "hello world"])
        let logs = try await provider.logs(cellID: cellID)
        let status = try await provider.status(cellID: cellID)
        try await provider.destroy(cellID: cellID, force: true)

        #expect(attach.argv == [
            "fly",
            "ssh", "console",
            "--app", "cocxy-lab",
            "--machine", "fly-machine-456",
        ])
        #expect(attach.displayName == "Fly Cell")
        #expect(output == "ok\n")
        #expect(logs == "app logs\n")
        #expect(status == .running)
        #expect(executor.calls.map(\.arguments) == [
            [
                "machine", "run",
                "--detach",
                "--name", "fly-lifecycle",
                "--app", "cocxy-lab",
                "--metadata", "dev.cocxy.cell=true",
                "--metadata", "dev.cocxy.cell.id=\(cellID.uuidString)",
                "--metadata", "dev.cocxy.cell.name=Fly Lifecycle",
                "debian:bookworm-slim",
                "sleep", "inf",
            ],
            ["machine", "exec", "--app", "cocxy-lab", "fly-machine-456", "printf 'hello world'"],
            ["logs", "--app", "cocxy-lab", "--no-tail", "--machine", "fly-machine-456"],
            ["machine", "status", "--app", "cocxy-lab", "fly-machine-456"],
            ["machine", "destroy", "--app", "cocxy-lab", "--force", "fly-machine-456"],
        ])
        #expect(try await provider.list() == [])
    }

    @Test("Fly create requires an image before making external calls")
    func flyCreateRequiresImageBeforeMakingExternalCalls() async {
        let executor = RecordingCloudCellExecutor(responses: [])
        let provider = FlyCellProvider(executor: executor)

        await #expect(throws: CommandBackedCloudCellProviderError.missingImage(provider: .fly)) {
            _ = try await provider.create(CellCreateRequest(name: "Missing Image"))
        }

        #expect(executor.calls.isEmpty)
    }

    @Test("AWS provider creates EC2 cells and uses SSM for exec attach and logs")
    func awsProviderUsesEC2AndSSMCommands() async throws {
        let cellID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let executor = RecordingCloudCellExecutor(responses: [
            CellProcessResult(exitCode: 0, stdout: "i-0abc1234def567890\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "cmd-123\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "ok\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "recent\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "running\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "", stderr: ""),
        ])
        let provider = AWSCellProvider(
            executor: executor,
            idGenerator: { cellID }
        )

        let cell = try await provider.create(CellCreateRequest(
            name: "AWS Lab",
            metadata: [
                "image": "ami-12345678",
                "vm-size": "t3.large",
                "region": "us-east-1",
                "cloud-profile": "dev",
                "subnet": "subnet-1",
                "security-group": "sg-1,sg-2",
                "key-name": "cocxy-key",
                "instance-profile": "cocxy-ssm-profile",
                "cloud-init": "file://cloud-init.yml",
            ]
        ))
        let attach = try await provider.attachCommand(cellID: cellID)
        let output = try await provider.exec(cellID: cellID, command: ["echo", "ok"])
        let logs = try await provider.logs(cellID: cellID)
        let status = try await provider.status(cellID: cellID)
        try await provider.destroy(cellID: cellID, force: true)

        #expect(cell.provider == .aws)
        #expect(cell.metadata["externalID"] == "i-0abc1234def567890")
        #expect(cell.metadata["cloud-init"] == nil)
        #expect(attach.argv == [
            "aws",
            "ssm", "start-session",
            "--region", "us-east-1",
            "--profile", "dev",
            "--target", "i-0abc1234def567890",
        ])
        #expect(output == "ok\n")
        #expect(logs == "recent\n")
        #expect(status == .running)
        #expect(executor.calls.map(\.arguments) == [
            [
                "ec2", "run-instances",
                "--region", "us-east-1",
                "--profile", "dev",
                "--image-id", "ami-12345678",
                "--instance-type", "t3.large",
                "--count", "1",
                "--subnet-id", "subnet-1",
                "--security-group-ids", "sg-1", "sg-2",
                "--key-name", "cocxy-key",
                "--iam-instance-profile", "Name=cocxy-ssm-profile",
                "--user-data", "file://cloud-init.yml",
                "--tag-specifications", "ResourceType=instance,Tags=[{Key=dev.cocxy.cell,Value=true},{Key=dev.cocxy.cell.id,Value=\(cellID.uuidString)},{Key=Name,Value=aws-lab}]",
                "--query", "Instances[0].InstanceId",
                "--output", "text",
            ],
            [
                "ssm", "send-command",
                "--region", "us-east-1",
                "--profile", "dev",
                "--instance-ids", "i-0abc1234def567890",
                "--document-name", "AWS-RunShellScript",
                "--parameters", "commands=echo ok",
                "--query", "Command.CommandId",
                "--output", "text",
            ],
            [
                "ssm", "wait", "command-executed",
                "--region", "us-east-1",
                "--profile", "dev",
                "--instance-id", "i-0abc1234def567890",
                "--command-id", "cmd-123",
            ],
            [
                "ssm", "get-command-invocation",
                "--region", "us-east-1",
                "--profile", "dev",
                "--instance-id", "i-0abc1234def567890",
                "--command-id", "cmd-123",
                "--query", "StandardOutputContent",
                "--output", "text",
            ],
            [
                "ssm", "list-command-invocations",
                "--region", "us-east-1",
                "--profile", "dev",
                "--instance-id", "i-0abc1234def567890",
                "--details",
                "--query", "CommandInvocations[*].CommandPlugins[*].Output",
                "--output", "text",
            ],
            [
                "ec2", "describe-instances",
                "--region", "us-east-1",
                "--profile", "dev",
                "--instance-ids", "i-0abc1234def567890",
                "--query", "Reservations[0].Instances[0].State.Name",
                "--output", "text",
            ],
            [
                "ec2", "terminate-instances",
                "--region", "us-east-1",
                "--profile", "dev",
                "--instance-ids", "i-0abc1234def567890",
            ],
        ])
        #expect(try await provider.list() == [])
    }

    @Test("GCP provider creates Compute Engine cells and exposes SSH attach")
    func gcpProviderUsesComputeCommands() async throws {
        let cellID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let executor = RecordingCloudCellExecutor(responses: [
            CellProcessResult(exitCode: 0, stdout: "", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "ok\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "serial\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "RUNNING\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "", stderr: ""),
        ])
        let provider = GCPCellProvider(
            executor: executor,
            idGenerator: { cellID }
        )

        let cell = try await provider.create(CellCreateRequest(
            name: "GCP Lab",
            metadata: [
                "image": "debian-12",
                "vm-size": "e2-standard-2",
                "zone": "us-central1-a",
                "project": "cocxy-dev",
                "network": "default",
                "subnet": "default-us",
                "cloud-init": "/tmp/cloud.yml",
                "user": "deploy",
                "identity": "/tmp/key",
                "strict-host-key-checking": "no",
            ]
        ))
        let attach = try await provider.attachCommand(cellID: cellID)
        let output = try await provider.exec(cellID: cellID, command: ["echo", "ok"])
        let logs = try await provider.logs(cellID: cellID)
        let status = try await provider.status(cellID: cellID)
        try await provider.destroy(cellID: cellID, force: true)

        #expect(cell.provider == .gcp)
        #expect(cell.metadata["externalID"] == "gcp-lab")
        #expect(cell.metadata["identity"] == nil)
        #expect(cell.metadata["cloud-init"] == nil)
        #expect(attach.argv == [
            "gcloud",
            "compute", "ssh", "deploy@gcp-lab",
            "--zone", "us-central1-a",
            "--project", "cocxy-dev",
            "--ssh-key-file", "/tmp/key",
            "--strict-host-key-checking", "no",
        ])
        #expect(output == "ok\n")
        #expect(logs == "serial\n")
        #expect(status == .running)
        #expect(executor.calls.map(\.arguments) == [
            [
                "compute", "instances", "create", "gcp-lab",
                "--image", "debian-12",
                "--machine-type", "e2-standard-2",
                "--metadata", "dev-cocxy-cell=true,dev-cocxy-cell-id=\(cellID.uuidString),dev-cocxy-cell-name=gcp-lab",
                "--zone", "us-central1-a",
                "--project", "cocxy-dev",
                "--network", "default",
                "--subnet", "default-us",
                "--metadata-from-file", "user-data=/tmp/cloud.yml",
            ],
            [
                "compute", "ssh", "deploy@gcp-lab",
                "--command", "echo ok",
                "--zone", "us-central1-a",
                "--project", "cocxy-dev",
                "--ssh-key-file", "/tmp/key",
                "--strict-host-key-checking", "no",
            ],
            [
                "compute", "instances", "get-serial-port-output", "gcp-lab",
                "--zone", "us-central1-a",
                "--project", "cocxy-dev",
            ],
            [
                "compute", "instances", "describe", "gcp-lab",
                "--zone", "us-central1-a",
                "--project", "cocxy-dev",
                "--format", "value(status)",
            ],
            [
                "compute", "instances", "delete", "gcp-lab",
                "--quiet",
                "--zone", "us-central1-a",
                "--project", "cocxy-dev",
            ],
        ])
        #expect(try await provider.list() == [])
    }

    @Test("process executor drains large stdout and stderr while the child is running")
    func processExecutorDrainsLargeOutputWithoutPipeDeadlock() throws {
        let script = #"print "o" x 200000; print STDERR "e" x 200000;"#
        let result = try ProcessCellExecutor().run(
            "/usr/bin/perl",
            arguments: ["-e", script]
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.count == 200_000)
        #expect(result.stderr.count == 200_000)
    }

    @Test("Azure provider creates VMs and uses run-command plus az ssh attach")
    func azureProviderUsesVMCommands() async throws {
        let cellID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let executor = RecordingCloudCellExecutor(responses: [
            CellProcessResult(exitCode: 0, stdout: "", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "ok\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "boot\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "VM running\n", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "", stderr: ""),
        ])
        let provider = AzureCellProvider(
            executor: executor,
            idGenerator: { cellID }
        )

        let cell = try await provider.create(CellCreateRequest(
            name: "Azure Lab",
            metadata: [
                "image": "Ubuntu2204",
                "resource-group": "rg-cocxy",
                "cloud-profile": "sub-1",
                "user": "azureuser",
                "identity": "~/.ssh/id_rsa.pub",
                "vm-size": "Standard_B2s",
                "region": "eastus",
                "cloud-init": "cloud-init.yml",
                "network": "vnet",
                "subnet": "subnet-a",
            ]
        ))
        let attach = try await provider.attachCommand(cellID: cellID)
        let output = try await provider.exec(cellID: cellID, command: ["echo", "ok"])
        let logs = try await provider.logs(cellID: cellID)
        let status = try await provider.status(cellID: cellID)
        try await provider.destroy(cellID: cellID, force: true)

        #expect(cell.provider == .azure)
        #expect(cell.metadata["externalID"] == "azure-lab")
        #expect(cell.metadata["identity"] == nil)
        #expect(cell.metadata["cloud-init"] == nil)
        #expect(attach.argv == [
            "az",
            "ssh", "vm",
            "--subscription", "sub-1",
            "--resource-group", "rg-cocxy",
            "--name", "azure-lab",
            "--local-user", "azureuser",
            "--private-key-file", "~/.ssh/id_rsa.pub",
        ])
        #expect(output == "ok\n")
        #expect(logs == "boot\n")
        #expect(status == .running)
        #expect(executor.calls.map(\.arguments) == [
            [
                "vm", "create",
                "--subscription", "sub-1",
                "--resource-group", "rg-cocxy",
                "--name", "azure-lab",
                "--image", "Ubuntu2204",
                "--admin-username", "azureuser",
                "--size", "Standard_B2s",
                "--location", "eastus",
                "--ssh-key-values", "~/.ssh/id_rsa.pub",
                "--custom-data", "cloud-init.yml",
                "--vnet-name", "vnet",
                "--subnet", "subnet-a",
                "--tags",
                "dev.cocxy.cell=true",
                "dev.cocxy.cell.id=\(cellID.uuidString)",
                "dev.cocxy.cell.name=azure-lab",
                "--query", "id",
                "--output", "tsv",
            ],
            [
                "vm", "boot-diagnostics", "enable",
                "--subscription", "sub-1",
                "--resource-group", "rg-cocxy",
                "--name", "azure-lab",
                "--output", "none",
            ],
            [
                "vm", "run-command", "invoke",
                "--subscription", "sub-1",
                "--resource-group", "rg-cocxy",
                "--name", "azure-lab",
                "--command-id", "RunShellScript",
                "--scripts", "echo ok",
                "--query", "value[0].message",
                "--output", "tsv",
            ],
            [
                "vm", "boot-diagnostics", "get-boot-log",
                "--subscription", "sub-1",
                "--resource-group", "rg-cocxy",
                "--name", "azure-lab",
            ],
            [
                "vm", "get-instance-view",
                "--subscription", "sub-1",
                "--resource-group", "rg-cocxy",
                "--name", "azure-lab",
                "--query", "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus | [0]",
                "--output", "tsv",
            ],
            [
                "vm", "delete",
                "--subscription", "sub-1",
                "--resource-group", "rg-cocxy",
                "--name", "azure-lab",
                "--yes",
            ],
        ])
        #expect(try await provider.list() == [])
    }

    @Test("Azure create uses a stable valid admin username when none is provided")
    func azureCreateUsesSafeDefaultAdminUsername() async throws {
        let cellID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let executor = RecordingCloudCellExecutor(responses: [
            CellProcessResult(exitCode: 0, stdout: "", stderr: ""),
            CellProcessResult(exitCode: 0, stdout: "", stderr: ""),
        ])
        let provider = AzureCellProvider(
            executor: executor,
            idGenerator: { cellID }
        )

        let cell = try await provider.create(CellCreateRequest(
            name: "Azure Default User",
            metadata: [
                "image": "Debian:debian-12:12:latest",
                "resource-group": "rg-cocxy",
            ]
        ))

        #expect(cell.metadata["user"] == "cocxy")
        #expect(executor.calls.first?.arguments.contains("--admin-username") == true)
        #expect(executor.calls.first?.arguments.contains("cocxy") == true)
        #expect(executor.calls.first?.arguments.contains("--size") == true)
        #expect(executor.calls.first?.arguments.contains("Standard_B1s") == true)
        #expect(executor.calls.dropFirst().first?.arguments.contains("boot-diagnostics") == true)
    }

    @Test("Azure create requires resource group before external calls")
    func azureCreateRequiresResourceGroupBeforeMakingExternalCalls() async {
        let executor = RecordingCloudCellExecutor(responses: [])
        let provider = AzureCellProvider(executor: executor)

        await #expect(throws: CommandBackedCloudCellProviderError.missingMetadata(provider: .azure, key: "resource-group")) {
            _ = try await provider.create(CellCreateRequest(
                name: "Missing Group",
                metadata: ["image": "Ubuntu2204"]
            ))
        }

        #expect(executor.calls.isEmpty)
    }
}

private final class RecordingCloudCellExecutor: CellProcessExecuting, @unchecked Sendable {
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
            throw CommandBackedCloudCellProviderError.commandFailed(
                provider: .e2b,
                exitCode: 1,
                stderr: "missing fake response"
            )
        }
        return queuedResponses.removeFirst()
    }
}
