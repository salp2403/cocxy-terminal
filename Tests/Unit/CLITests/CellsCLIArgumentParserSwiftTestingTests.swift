// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CellsCLIArgumentParserSwiftTestingTests.swift - Cocxy Cells CLI contract coverage.

import XCTest
@testable import CocxyCLILib

final class CellsCLIArgumentParserSwiftTestingTests: XCTestCase {
    private let runner = CommandRunner(socketClient: SocketClient(socketPath: "/tmp/test.sock"))

    func testCellCreateParsesProviderAndProfileAndBuildsSocketRequest() throws {
        let parsed = try CLIArgumentParser.parse([
            "cell", "create",
            "--provider", "docker",
            "--profile", "local-dev",
            "--image", "alpine:3.20",
        ])

        XCTAssertEqual(
            parsed,
            .cellCreate(CellCreateCLIOptions(provider: "docker", profile: "local-dev", image: "alpine:3.20"))
        )

        let request = runner.buildRequest(from: parsed)
        XCTAssertEqual(request.command, "cell-create")
        XCTAssertEqual(request.params?["provider"], "docker")
        XCTAssertEqual(request.params?["profile"], "local-dev")
        XCTAssertEqual(request.params?["image"], "alpine:3.20")
    }

    func testCellCreateParsesSSHConnectionOptions() throws {
        let parsed = try CLIArgumentParser.parse([
            "cell", "create",
            "--provider", "ssh",
            "--profile", "lab",
            "--host", "example.test",
            "--user", "deploy",
            "--port", "2222",
            "--identity", "~/.ssh/id_ed25519",
            "--known-hosts", "/tmp/cocxy-known-hosts",
            "--strict-host-key-checking", "NO",
        ])

        XCTAssertEqual(
            parsed,
            .cellCreate(CellCreateCLIOptions(
                provider: "ssh",
                profile: "lab",
                host: "example.test",
                user: "deploy",
                port: 2222,
                identity: "~/.ssh/id_ed25519",
                knownHostsFile: "/tmp/cocxy-known-hosts",
                strictHostKeyChecking: "no"
            ))
        )

        let request = runner.buildRequest(from: parsed)
        XCTAssertEqual(request.command, "cell-create")
        XCTAssertEqual(request.params?["provider"], "ssh")
        XCTAssertEqual(request.params?["profile"], "lab")
        XCTAssertEqual(request.params?["host"], "example.test")
        XCTAssertEqual(request.params?["user"], "deploy")
        XCTAssertEqual(request.params?["port"], "2222")
        XCTAssertEqual(request.params?["identity"], "~/.ssh/id_ed25519")
        XCTAssertEqual(request.params?["known-hosts"], "/tmp/cocxy-known-hosts")
        XCTAssertEqual(request.params?["strict-host-key-checking"], "no")
    }

    func testCellCreateParsesCloudProviderOptions() throws {
        let parsed = try CLIArgumentParser.parse([
            "cell", "create",
            "--provider", "fly",
            "--profile", "lab",
            "--image", "debian:bookworm-slim",
            "--app", "cocxy-lab",
            "--region", "iad",
            "--vm-size", "shared-cpu-1x",
            "--vm-memory", "1024",
            "--vm-cpus", "2",
        ])

        XCTAssertEqual(
            parsed,
            .cellCreate(CellCreateCLIOptions(
                provider: "fly",
                profile: "lab",
                image: "debian:bookworm-slim",
                app: "cocxy-lab",
                region: "iad",
                vmSize: "shared-cpu-1x",
                vmMemory: "1024",
                vmCPUs: 2
            ))
        )

        let request = runner.buildRequest(from: parsed)
        XCTAssertEqual(request.command, "cell-create")
        XCTAssertEqual(request.params?["provider"], "fly")
        XCTAssertEqual(request.params?["app"], "cocxy-lab")
        XCTAssertEqual(request.params?["region"], "iad")
        XCTAssertEqual(request.params?["vm-size"], "shared-cpu-1x")
        XCTAssertEqual(request.params?["vm-memory"], "1024")
        XCTAssertEqual(request.params?["vm-cpus"], "2")
    }

    func testCellCreateParsesCloudAccountAndNetworkOptions() throws {
        let parsed = try CLIArgumentParser.parse([
            "cell", "create",
            "--provider", "azure",
            "--profile", "team-lab",
            "--image", "Ubuntu2204",
            "--cloud-profile", "sub-1",
            "--project", "cocxy-dev",
            "--zone", "us-central1-a",
            "--resource-group", "rg-cocxy",
            "--network", "vnet",
            "--subnet", "subnet-a",
            "--security-group", "sg-1",
            "--key-name", "cocxy-key",
            "--instance-profile", "cocxy-ssm-profile",
            "--cloud-init", "cloud-init.yml",
        ])

        XCTAssertEqual(
            parsed,
            .cellCreate(CellCreateCLIOptions(
                provider: "azure",
                profile: "team-lab",
                image: "Ubuntu2204",
                cloudProfile: "sub-1",
                project: "cocxy-dev",
                zone: "us-central1-a",
                resourceGroup: "rg-cocxy",
                network: "vnet",
                subnet: "subnet-a",
                securityGroup: "sg-1",
                keyName: "cocxy-key",
                instanceProfile: "cocxy-ssm-profile",
                cloudInit: "cloud-init.yml"
            ))
        )

        let request = runner.buildRequest(from: parsed)
        XCTAssertEqual(request.command, "cell-create")
        XCTAssertEqual(request.params?["cloud-profile"], "sub-1")
        XCTAssertEqual(request.params?["project"], "cocxy-dev")
        XCTAssertEqual(request.params?["zone"], "us-central1-a")
        XCTAssertEqual(request.params?["resource-group"], "rg-cocxy")
        XCTAssertEqual(request.params?["network"], "vnet")
        XCTAssertEqual(request.params?["subnet"], "subnet-a")
        XCTAssertEqual(request.params?["security-group"], "sg-1")
        XCTAssertEqual(request.params?["key-name"], "cocxy-key")
        XCTAssertEqual(request.params?["instance-profile"], "cocxy-ssm-profile")
        XCTAssertEqual(request.params?["cloud-init"], "cloud-init.yml")
    }

    func testCellCreateParsesE2BTemplateOptions() throws {
        let parsed = try CLIArgumentParser.parse([
            "cell", "create",
            "--provider", "e2b",
            "--profile", "sandbox",
            "--template", "base",
            "--path", "/workspace",
            "--config", "e2b.toml",
        ])

        XCTAssertEqual(
            parsed,
            .cellCreate(CellCreateCLIOptions(
                provider: "e2b",
                profile: "sandbox",
                template: "base",
                config: "e2b.toml",
                path: "/workspace"
            ))
        )

        let request = runner.buildRequest(from: parsed)
        XCTAssertEqual(request.command, "cell-create")
        XCTAssertEqual(request.params?["provider"], "e2b")
        XCTAssertEqual(request.params?["template"], "base")
        XCTAssertEqual(request.params?["path"], "/workspace")
        XCTAssertEqual(request.params?["config"], "e2b.toml")
    }

    func testCellListStatusLogsAttachDestroyParseAndBuildRequests() throws {
        XCTAssertEqual(try CLIArgumentParser.parse(["cell", "list"]), .cellList)
        XCTAssertEqual(try CLIArgumentParser.parse(["cell", "status", "cell-1"]), .cellStatus(cellID: "cell-1", provider: nil))
        XCTAssertEqual(try CLIArgumentParser.parse(["cell", "logs", "cell-1"]), .cellLogs(cellID: "cell-1", provider: nil))
        XCTAssertEqual(try CLIArgumentParser.parse(["cell", "attach", "cell-1"]), .cellAttach(cellID: "cell-1", provider: nil))
        XCTAssertEqual(
            try CLIArgumentParser.parse(["cell", "destroy", "cell-1", "--force"]),
            .cellDestroy(cellID: "cell-1", provider: nil, force: true)
        )

        XCTAssertEqual(runner.buildRequest(from: .cellList).command, "cell-list")
        XCTAssertEqual(runner.buildRequest(from: .cellStatus(cellID: "cell-1", provider: nil)).params?["cell-id"], "cell-1")
        XCTAssertEqual(runner.buildRequest(from: .cellLogs(cellID: "cell-1", provider: nil)).params?["cell-id"], "cell-1")
        XCTAssertEqual(runner.buildRequest(from: .cellAttach(cellID: "cell-1", provider: nil)).params?["cell-id"], "cell-1")

        let destroy = runner.buildRequest(from: .cellDestroy(cellID: "cell-1", provider: nil, force: true))
        XCTAssertEqual(destroy.command, "cell-destroy")
        XCTAssertEqual(destroy.params?["cell-id"], "cell-1")
        XCTAssertEqual(destroy.params?["force"], "true")
    }

    func testCellLifecycleCommandsParseOptionalProviderScope() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse(["cell", "status", "cell-1", "--provider", "fly"]),
            .cellStatus(cellID: "cell-1", provider: "fly")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["cell", "logs", "cell-1", "--provider", "gcp"]),
            .cellLogs(cellID: "cell-1", provider: "gcp")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["cell", "attach", "cell-1", "--provider", "e2b"]),
            .cellAttach(cellID: "cell-1", provider: "e2b")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["cell", "destroy", "cell-1", "--provider", "aws", "--force"]),
            .cellDestroy(cellID: "cell-1", provider: "aws", force: true)
        )

        let status = runner.buildRequest(from: .cellStatus(cellID: "cell-1", provider: "fly"))
        XCTAssertEqual(status.params?["cell-id"], "cell-1")
        XCTAssertEqual(status.params?["provider"], "fly")
    }

    func testCellExecPreservesArgvAfterSeparator() throws {
        let parsed = try CLIArgumentParser.parse([
            "cell", "exec", "cell-1",
            "--",
            "swift", "test", "--filter", "Cells",
        ])

        XCTAssertEqual(
            parsed,
            .cellExec(cellID: "cell-1", provider: nil, command: ["swift", "test", "--filter", "Cells"])
        )

        let request = runner.buildRequest(from: parsed)
        XCTAssertEqual(request.command, "cell-exec")
        XCTAssertEqual(request.params?["cell-id"], "cell-1")
        let argvJSON = try XCTUnwrap(request.params?["argv-json"])
        let argv = try JSONDecoder().decode([String].self, from: Data(argvJSON.utf8))
        XCTAssertEqual(argv, ["swift", "test", "--filter", "Cells"])
    }

    func testCellExecParsesOptionalProviderBeforeSeparator() throws {
        let parsed = try CLIArgumentParser.parse([
            "cell", "exec", "cell-1",
            "--provider", "fly",
            "--",
            "printf", "ok",
        ])

        XCTAssertEqual(
            parsed,
            .cellExec(cellID: "cell-1", provider: "fly", command: ["printf", "ok"])
        )

        let request = runner.buildRequest(from: parsed)
        XCTAssertEqual(request.params?["cell-id"], "cell-1")
        XCTAssertEqual(request.params?["provider"], "fly")
    }

    func testCellCreateRequiresProvider() {
        XCTAssertThrowsError(try CLIArgumentParser.parse(["cell", "create"])) { error in
            XCTAssertEqual(
                error as? CLIError,
                .missingArgument(command: "cell create", argument: "--provider <provider>")
            )
        }
    }

    func testCellExecRequiresSeparatorAndCommand() {
        XCTAssertThrowsError(try CLIArgumentParser.parse(["cell", "exec", "cell-1", "swift", "test"])) { error in
            XCTAssertEqual(
                error as? CLIError,
                .missingArgument(command: "cell exec", argument: "-- <command>")
            )
        }
    }
}
