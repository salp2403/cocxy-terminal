// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CLICommandTests.swift - Tests for CLI argument parsing, request building, and output formatting.

import XCTest
import CocxyShared
@testable import CocxyCLILib

// MARK: - Argument Parser Tests

/// Tests for `CLIArgumentParser`: all subcommands, flags, and error cases.
///
/// Each test verifies a specific parsing scenario in isolation.
final class CLIArgumentParserTests: XCTestCase {

    // MARK: - 1. Empty arguments produce help

    func testEmptyArgumentsProduceHelp() throws {
        let result = try CLIArgumentParser.parse([])
        XCTAssertEqual(result, .help)
    }

    // MARK: - 2. --help flag

    func testDashDashHelpProducesHelp() throws {
        XCTAssertEqual(try CLIArgumentParser.parse(["--help"]), .help)
    }

    func testDashHProducesHelp() throws {
        XCTAssertEqual(try CLIArgumentParser.parse(["-h"]), .help)
    }

    func testHelpSubcommandProducesHelp() throws {
        XCTAssertEqual(try CLIArgumentParser.parse(["help"]), .help)
    }

    // MARK: - 3. --version flag

    func testDashDashVersionProducesVersion() throws {
        XCTAssertEqual(try CLIArgumentParser.parse(["--version"]), .version)
    }

    func testDashVProducesVersion() throws {
        XCTAssertEqual(try CLIArgumentParser.parse(["-v"]), .version)
    }

    // MARK: - 4. Notify command

    func testNotifyWithSingleWordMessage() throws {
        let result = try CLIArgumentParser.parse(["notify", "Hello"])
        XCTAssertEqual(result, .notify(message: "Hello"))
    }

    func testNotifyWithMultiWordMessage() throws {
        let result = try CLIArgumentParser.parse(["notify", "Build", "complete"])
        XCTAssertEqual(result, .notify(message: "Build complete"))
    }

    func testNotifyWithoutMessageThrowsMissingArgument() {
        XCTAssertThrowsError(try CLIArgumentParser.parse(["notify"])) { error in
            guard let cliError = error as? CLIError else {
                XCTFail("Expected CLIError, got \(error)")
                return
            }
            XCTAssertEqual(
                cliError,
                .missingArgument(command: "notify", argument: "message")
            )
        }
    }

    // MARK: - 5. New-tab command

    func testNewTabWithoutOptions() throws {
        let result = try CLIArgumentParser.parse(["new-tab"])
        XCTAssertEqual(result, .newTab(directory: nil, engine: nil))
    }

    func testNewTabWithDirectory() throws {
        let result = try CLIArgumentParser.parse(["new-tab", "--dir", "/tmp/project"])
        XCTAssertEqual(result, .newTab(directory: "/tmp/project", engine: nil))
    }

    func testNewTabWithEnginePreference() throws {
        let result = try CLIArgumentParser.parse(["new-tab", "--engine", "daemon"])
        XCTAssertEqual(result, .newTab(directory: nil, engine: "daemon"))
    }

    func testEnginePreferenceAliasesAreAcceptedByEngineCommands() throws {
        let aliases = [
            "system", "default", "auto",
            "in-process", "inprocess", "cocxycore", "core",
            "daemon", "pty-daemon", "ptydaemon",
        ]

        for alias in aliases {
            XCTAssertNotNil(
                TerminalEnginePreference(cliValue: alias),
                "Alias \(alias) should stay valid in the shared engine parser"
            )
            XCTAssertEqual(
                try CLIArgumentParser.parse(["new-tab", "--engine", alias]),
                .newTab(directory: nil, engine: alias)
            )
            XCTAssertEqual(
                try CLIArgumentParser.parse(["window", "new", "--engine", alias]),
                .windowNew(engine: alias)
            )
        }
    }

    func testNewTabWithInvalidEngineThrowsInvalidArgument() {
        XCTAssertThrowsError(
            try CLIArgumentParser.parse(["new-tab", "--engine", "invalid"])
        ) { error in
            guard let cliError = error as? CLIError else {
                XCTFail("Expected CLIError, got \(error)")
                return
            }
            XCTAssertEqual(
                cliError,
                .invalidArgument(
                    command: "new-tab",
                    argument: "invalid",
                    reason: "Engine must be system, in-process, or daemon"
                )
            )
        }
    }

    func testNewTabWithDirFlagButNoValueThrowsMissingArgument() {
        XCTAssertThrowsError(
            try CLIArgumentParser.parse(["new-tab", "--dir"])
        ) { error in
            guard let cliError = error as? CLIError else {
                XCTFail("Expected CLIError, got \(error)")
                return
            }
            XCTAssertEqual(
                cliError,
                .missingArgument(command: "new-tab", argument: "path")
            )
        }
    }

    // MARK: - 6. List-tabs command

    func testListTabs() throws {
        let result = try CLIArgumentParser.parse(["list-tabs"])
        XCTAssertEqual(result, .listTabs)
    }

    // MARK: - 7. Focus-tab command

    func testFocusTabWithID() throws {
        let uuid = "550e8400-e29b-41d4-a716-446655440000"
        let result = try CLIArgumentParser.parse(["focus-tab", uuid])
        XCTAssertEqual(result, .focusTab(id: uuid))
    }

    func testFocusTabWithoutIDThrowsMissingArgument() {
        XCTAssertThrowsError(
            try CLIArgumentParser.parse(["focus-tab"])
        ) { error in
            guard let cliError = error as? CLIError else {
                XCTFail("Expected CLIError, got \(error)")
                return
            }
            XCTAssertEqual(
                cliError,
                .missingArgument(command: "focus-tab", argument: "id")
            )
        }
    }

    // MARK: - 8. Close-tab command

    func testCloseTabWithID() throws {
        let result = try CLIArgumentParser.parse(["close-tab", "abc-123"])
        XCTAssertEqual(result, .closeTab(id: "abc-123"))
    }

    func testCloseTabWithoutIDThrowsMissingArgument() {
        XCTAssertThrowsError(
            try CLIArgumentParser.parse(["close-tab"])
        ) { error in
            guard let cliError = error as? CLIError else {
                XCTFail("Expected CLIError, got \(error)")
                return
            }
            XCTAssertEqual(
                cliError,
                .missingArgument(command: "close-tab", argument: "id")
            )
        }
    }

    // MARK: - 9. Split command

    func testSplitWithoutOptions() throws {
        let result = try CLIArgumentParser.parse(["split"])
        XCTAssertEqual(result, .split(direction: nil))
    }

    func testSplitWithHorizontalDirection() throws {
        let result = try CLIArgumentParser.parse(["split", "--dir", "h"])
        XCTAssertEqual(result, .split(direction: .horizontal))
    }

    func testSplitWithVerticalDirection() throws {
        let result = try CLIArgumentParser.parse(["split", "--dir", "v"])
        XCTAssertEqual(result, .split(direction: .vertical))
    }

    func testSplitWithInvalidDirectionThrowsInvalidArgument() {
        XCTAssertThrowsError(
            try CLIArgumentParser.parse(["split", "--dir", "x"])
        ) { error in
            guard let cliError = error as? CLIError else {
                XCTFail("Expected CLIError, got \(error)")
                return
            }
            if case .invalidArgument(let command, let argument, _) = cliError {
                XCTAssertEqual(command, "split")
                XCTAssertEqual(argument, "x")
            } else {
                XCTFail("Expected .invalidArgument, got \(cliError)")
            }
        }
    }

    // MARK: - 10. Status command

    func testStatus() throws {
        let result = try CLIArgumentParser.parse(["status"])
        XCTAssertEqual(result, .status)
    }

    func testCoreResetParses() throws {
        let result = try CLIArgumentParser.parse(["core", "reset"])
        XCTAssertEqual(result, .coreReset)
    }

    func testCoreSignalParses() throws {
        let result = try CLIArgumentParser.parse(["core", "signal", "term"])
        XCTAssertEqual(result, .coreSignal(signal: "term"))
    }

    func testCoreProcessParses() throws {
        let result = try CLIArgumentParser.parse(["core", "process"])
        XCTAssertEqual(result, .coreProcess)
    }

    func testCoreModesParses() throws {
        let result = try CLIArgumentParser.parse(["core", "modes"])
        XCTAssertEqual(result, .coreModes)
    }

    func testCoreSearchParses() throws {
        let result = try CLIArgumentParser.parse(["core", "search"])
        XCTAssertEqual(result, .coreSearch)
    }

    func testCoreLigaturesParses() throws {
        let result = try CLIArgumentParser.parse(["core", "ligatures"])
        XCTAssertEqual(result, .coreLigatures)
    }

    func testCoreProtocolParses() throws {
        let result = try CLIArgumentParser.parse(["core", "protocol"])
        XCTAssertEqual(result, .coreProtocol)
    }

    func testCoreSemanticParsesLimit() throws {
        let result = try CLIArgumentParser.parse(["core", "semantic", "--limit", "7"])
        XCTAssertEqual(result, .coreSemantic(limit: 7))
    }

    func testBlockListParsesLimit() throws {
        let result = try CLIArgumentParser.parse(["block", "list", "--limit", "5"])
        XCTAssertEqual(result, .blockList(limit: 5))
    }

    func testBlockOutputsParsesLimit() throws {
        let result = try CLIArgumentParser.parse(["block", "outputs", "--limit", "5"])
        XCTAssertEqual(result, .blockOutputs(limit: 5))
    }

    func testBlockCopyParsesField() throws {
        let result = try CLIArgumentParser.parse(["block", "copy", "42", "--field", "both"])
        XCTAssertEqual(result, .blockCopy(id: 42, field: "both"))
    }

    func testBlockRerunParsesID() throws {
        let result = try CLIArgumentParser.parse(["block", "rerun", "42"])
        XCTAssertEqual(result, .blockRerun(id: 42))
    }

    // MARK: - 11. Unknown command

    func testUnknownCommandThrowsError() {
        XCTAssertThrowsError(
            try CLIArgumentParser.parse(["foobar"])
        ) { error in
            guard let cliError = error as? CLIError else {
                XCTFail("Expected CLIError, got \(error)")
                return
            }
            XCTAssertEqual(cliError, .unknownCommand("foobar"))
        }
    }

    // MARK: - 12. Help text

    func testHelpTextContainsAllCommands() {
        let helpText = CLIArgumentParser.helpText()

        XCTAssertTrue(helpText.contains("notify"))
        XCTAssertTrue(helpText.contains("new-tab"))
        XCTAssertTrue(helpText.contains("list-tabs"))
        XCTAssertTrue(helpText.contains("focus-tab"))
        XCTAssertTrue(helpText.contains("close-tab"))
        XCTAssertTrue(helpText.contains("split"))
        XCTAssertTrue(helpText.contains("status"))
        XCTAssertTrue(helpText.contains("--help"))
        XCTAssertTrue(helpText.contains("--version"))
        XCTAssertTrue(helpText.contains("ENGINE VALUES:"))
        XCTAssertTrue(helpText.contains("aliases: default, auto, inprocess, core, cocxycore, pty-daemon, ptydaemon"))
    }

    // MARK: - 13. Version text

    func testVersionTextContainsVersionNumber() {
        let versionText = CLIArgumentParser.versionText()
        // `CLIArgumentParser.version` resolves dynamically from the
        // enclosing app bundle's Info.plist when present, with a
        // hardcoded fallback in tests and standalone builds. Assert
        // against the resolved value rather than a pinned literal.
        XCTAssertEqual(versionText, "cocxy \(CLIArgumentParser.version)")
    }
    // MARK: - SSH Parsing

    func testParseSSHWithDestination() throws {
        let result = try CLIArgumentParser.parse(["ssh", "user@host"])
        XCTAssertEqual(result, .ssh(destination: "user@host", port: nil, identityFile: nil))
    }

    func testParseSSHWithPortAndIdentity() throws {
        let result = try CLIArgumentParser.parse(["ssh", "user@host", "-p", "2222", "-i", "~/.ssh/key"])
        XCTAssertEqual(result, .ssh(destination: "user@host", port: 2222, identityFile: "~/.ssh/key"))
    }

    func testParseSSHWithBareHost() throws {
        let result = try CLIArgumentParser.parse(["ssh", "myserver"])
        XCTAssertEqual(result, .ssh(destination: "myserver", port: nil, identityFile: nil))
    }

    func testParseSSHWithoutDestinationThrows() {
        XCTAssertThrowsError(try CLIArgumentParser.parse(["ssh"]))
    }

    func testParseWebStartWithOptions() throws {
        let result = try CLIArgumentParser.parse([
            "web", "start",
            "--bind", "0.0.0.0",
            "--port", "9000",
            "--token", "secret",
            "--fps", "30"
        ])
        XCTAssertEqual(
            result,
            .webStart(bindAddress: "0.0.0.0", port: 9000, token: "secret", fps: 30)
        )
    }

    func testParseWebStatus() throws {
        XCTAssertEqual(try CLIArgumentParser.parse(["web", "status"]), .webStatus)
    }

    func testParseStreamList() throws {
        XCTAssertEqual(try CLIArgumentParser.parse(["stream", "list"]), .streamList)
    }

    func testParseStreamCurrentWithID() throws {
        XCTAssertEqual(try CLIArgumentParser.parse(["stream", "current", "7"]), .streamCurrent(id: 7))
    }

    func testParseProtocolCapabilities() throws {
        XCTAssertEqual(try CLIArgumentParser.parse(["protocol", "capabilities"]), .protocolCapabilities)
    }

    func testParseProtocolViewportWithRequestID() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse(["protocol", "viewport", "--request-id", "req-42"]),
            .protocolViewport(requestID: "req-42")
        )
    }

    func testParseProtocolSend() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse(["protocol", "send", "--type", "agent.status", "--json", "{\"ok\":true}"]),
            .protocolSend(type: "agent.status", json: "{\"ok\":true}")
        )
    }

    func testParseImageList() throws {
        XCTAssertEqual(try CLIArgumentParser.parse(["image", "list"]), .imageList)
    }

    func testParseImageDeleteWithID() throws {
        XCTAssertEqual(try CLIArgumentParser.parse(["image", "delete", "9"]), .imageDelete(id: 9))
    }

    func testParseImageClear() throws {
        XCTAssertEqual(try CLIArgumentParser.parse(["image", "clear"]), .imageClear)
    }

    func testParseNotebookImportWithOutputAndForce() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse([
                "notebook", "import", "/tmp/source.ipynb",
                "--output", "/tmp/result.cocxynb",
                "--force",
            ]),
            .notebookImport(
                inputPath: "/tmp/source.ipynb",
                outputPath: "/tmp/result.cocxynb",
                force: true
            )
        )
    }

    func testParseNotebookExportWithShortOutputFlag() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse([
                "notebook", "export", "/tmp/source.cocxynb",
                "-o", "/tmp/result.ipynb",
            ]),
            .notebookExport(
                inputPath: "/tmp/source.cocxynb",
                outputPath: "/tmp/result.ipynb",
                force: false
            )
        )
    }

    func testParseNotebookRunWithExecutionOptions() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse([
                "notebook", "run", "/tmp/source.cocxynb",
                "--output", "/tmp/result.cocxynb",
                "--cwd", "/tmp/project",
                "--timeout", "15",
                "--continue-on-failure",
            ]),
            .notebookRun(
                inputPath: "/tmp/source.cocxynb",
                outputPath: "/tmp/result.cocxynb",
                workingDirectory: "/tmp/project",
                timeoutSeconds: 15,
                continueOnFailure: true
            )
        )
    }

    func testParseWorkflowRunWithWorkingDirectory() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse([
                "workflow", "run", "/tmp/workflow.toml",
                "--cwd", "/tmp/project",
            ]),
            .workflowRun(
                inputPath: "/tmp/workflow.toml",
                workingDirectory: "/tmp/project"
            )
        )
    }

    func testParseNotebookImportWithoutOutputThrowsMissingArgument() {
        XCTAssertThrowsError(
            try CLIArgumentParser.parse(["notebook", "import", "/tmp/source.ipynb"])
        ) { error in
            guard let cliError = error as? CLIError else {
                XCTFail("Expected CLIError, got \(error)")
                return
            }
            XCTAssertEqual(
                cliError,
                .missingArgument(command: "notebook import", argument: "output")
            )
        }
    }

    func testParseSkillList() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse(["skill", "list"]),
            .skillList
        )
    }

    func testParseSkillListRejectsUnexpectedArgument() {
        XCTAssertThrowsError(
            try CLIArgumentParser.parse(["skill", "list", "--remote"])
        ) { error in
            guard let cliError = error as? CLIError else {
                XCTFail("Expected CLIError, got \(error)")
                return
            }
            XCTAssertEqual(
                cliError,
                .invalidArgument(
                    command: "skill list",
                    argument: "--remote",
                    reason: "`skill list` takes no arguments."
                )
            )
        }
    }

    func testParseWindowNewWithoutEngine() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse(["window", "new"]),
            .windowNew(engine: nil)
        )
    }

    func testParseWindowNewWithEnginePreference() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse(["window", "new", "--engine", "daemon"]),
            .windowNew(engine: "daemon")
        )
    }

    func testParseWindowNewWithInvalidEngineThrowsInvalidArgument() {
        XCTAssertThrowsError(
            try CLIArgumentParser.parse(["window", "new", "--engine", "invalid"])
        ) { error in
            guard let cliError = error as? CLIError else {
                XCTFail("Expected CLIError, got \(error)")
                return
            }
            XCTAssertEqual(
                cliError,
                .invalidArgument(
                    command: "window new",
                    argument: "invalid",
                    reason: "Engine must be system, in-process, or daemon"
                )
            )
        }
    }
}

// MARK: - Request Builder Tests

/// Tests for `CommandRunner.buildRequest`: verify correct socket request
/// construction for each parsed command.
final class RequestBuilderTests: XCTestCase {

    private let runner = CommandRunner(
        socketClient: SocketClient(socketPath: "/tmp/test.sock")
    )

    // MARK: - 14. Notify request

    func testBuildNotifyRequest() {
        let request = runner.buildRequest(from: .notify(message: "hello"))

        XCTAssertEqual(request.command, "notify")
        XCTAssertEqual(request.params?["message"], "hello")
        XCTAssertFalse(request.id.isEmpty)
    }

    // MARK: - 15. New-tab request without directory

    func testBuildNewTabRequestWithoutDirectory() {
        let request = runner.buildRequest(from: .newTab(directory: nil, engine: nil))

        XCTAssertEqual(request.command, "new-tab")
        XCTAssertNil(request.params)
    }

    // MARK: - 16. New-tab request with directory

    func testBuildNewTabRequestWithDirectory() {
        let request = runner.buildRequest(from: .newTab(directory: "/tmp", engine: nil))

        XCTAssertEqual(request.command, "new-tab")
        XCTAssertEqual(request.params?["dir"], "/tmp")
    }

    func testBuildNewTabRequestWithEnginePreference() {
        let request = runner.buildRequest(from: .newTab(directory: "/tmp", engine: "daemon"))

        XCTAssertEqual(request.command, "new-tab")
        XCTAssertEqual(request.params?["dir"], "/tmp")
        XCTAssertEqual(request.params?["engine"], "daemon")
    }

    func testBuildWindowNewRequestWithEnginePreference() {
        let request = runner.buildRequest(from: .windowNew(engine: "daemon"))

        XCTAssertEqual(request.command, "window-new")
        XCTAssertEqual(request.params?["engine"], "daemon")
    }

    // MARK: - 17. List-tabs request

    func testBuildListTabsRequest() {
        let request = runner.buildRequest(from: .listTabs)

        XCTAssertEqual(request.command, "list-tabs")
        XCTAssertNil(request.params)
    }

    // MARK: - 18. Focus-tab request

    func testBuildFocusTabRequest() {
        let request = runner.buildRequest(from: .focusTab(id: "abc-123"))

        XCTAssertEqual(request.command, "focus-tab")
        XCTAssertEqual(request.params?["id"], "abc-123")
    }

    // MARK: - 19. Close-tab request

    func testBuildCloseTabRequest() {
        let request = runner.buildRequest(from: .closeTab(id: "xyz-789"))

        XCTAssertEqual(request.command, "close-tab")
        XCTAssertEqual(request.params?["id"], "xyz-789")
    }

    // MARK: - 20. Split request with direction

    func testBuildSplitRequestWithDirection() {
        let request = runner.buildRequest(from: .split(direction: .horizontal))

        XCTAssertEqual(request.command, "split")
        XCTAssertEqual(request.params?["direction"], "horizontal")
    }

    // MARK: - 21. Split request without direction

    func testBuildSplitRequestWithoutDirection() {
        let request = runner.buildRequest(from: .split(direction: nil))

        XCTAssertEqual(request.command, "split")
        XCTAssertNil(request.params)
    }

    // MARK: - 22. Status request

    func testBuildStatusRequest() {
        let request = runner.buildRequest(from: .status)

        XCTAssertEqual(request.command, "status")
        XCTAssertNil(request.params)
    }

    func testBuildWebStartRequest() {
        let request = runner.buildRequest(
            from: .webStart(bindAddress: "127.0.0.1", port: 7770, token: "abc", fps: 60)
        )

        XCTAssertEqual(request.command, "web-start")
        XCTAssertEqual(request.params?["bind"], "127.0.0.1")
        XCTAssertEqual(request.params?["port"], "7770")
        XCTAssertEqual(request.params?["token"], "abc")
        XCTAssertEqual(request.params?["fps"], "60")
    }

    func testBuildStreamListRequest() {
        let request = runner.buildRequest(from: .streamList)
        XCTAssertEqual(request.command, "stream-list")
        XCTAssertNil(request.params)
    }

    func testBuildStreamCurrentRequest() {
        let request = runner.buildRequest(from: .streamCurrent(id: 4))
        XCTAssertEqual(request.command, "stream-current")
        XCTAssertEqual(request.params?["id"], "4")
    }

    func testBuildProtocolCapabilitiesRequest() {
        let request = runner.buildRequest(from: .protocolCapabilities)
        XCTAssertEqual(request.command, "protocol-capabilities")
        XCTAssertNil(request.params)
    }

    func testBuildProtocolViewportRequest() {
        let request = runner.buildRequest(from: .protocolViewport(requestID: "req-1"))
        XCTAssertEqual(request.command, "protocol-viewport")
        XCTAssertEqual(request.params?["request_id"], "req-1")
    }

    func testBuildProtocolSendRequest() {
        let request = runner.buildRequest(from: .protocolSend(type: "agent.status", json: "{\"ok\":true}"))
        XCTAssertEqual(request.command, "protocol-send")
        XCTAssertEqual(request.params?["type"], "agent.status")
        XCTAssertEqual(request.params?["json"], "{\"ok\":true}")
    }

    func testBuildImageListRequest() {
        let request = runner.buildRequest(from: .imageList)
        XCTAssertEqual(request.command, "image-list")
        XCTAssertNil(request.params)
    }

    func testBuildImageDeleteRequest() {
        let request = runner.buildRequest(from: .imageDelete(id: 12))
        XCTAssertEqual(request.command, "image-delete")
        XCTAssertEqual(request.params?["id"], "12")
    }

    func testBuildImageClearRequest() {
        let request = runner.buildRequest(from: .imageClear)
        XCTAssertEqual(request.command, "image-clear")
        XCTAssertNil(request.params)
    }

    func testBuildCoreSignalRequest() {
        let request = runner.buildRequest(from: .coreSignal(signal: "int"))
        XCTAssertEqual(request.command, "core-signal")
        XCTAssertEqual(request.params?["signal"], "int")
    }

    func testBuildCoreProcessRequest() {
        let request = runner.buildRequest(from: .coreProcess)
        XCTAssertEqual(request.command, "core-process")
        XCTAssertNil(request.params)
    }

    func testBuildCoreModesRequest() {
        let request = runner.buildRequest(from: .coreModes)
        XCTAssertEqual(request.command, "core-modes")
        XCTAssertNil(request.params)
    }

    func testBuildCoreSearchRequest() {
        let request = runner.buildRequest(from: .coreSearch)
        XCTAssertEqual(request.command, "core-search")
        XCTAssertNil(request.params)
    }

    func testBuildCoreLigaturesRequest() {
        let request = runner.buildRequest(from: .coreLigatures)
        XCTAssertEqual(request.command, "core-ligatures")
        XCTAssertNil(request.params)
    }

    func testBuildCoreProtocolRequest() {
        let request = runner.buildRequest(from: .coreProtocol)
        XCTAssertEqual(request.command, "core-protocol")
        XCTAssertNil(request.params)
    }

    func testBuildCoreSemanticRequest() {
        let request = runner.buildRequest(from: .coreSemantic(limit: 6))
        XCTAssertEqual(request.command, "core-semantic")
        XCTAssertEqual(request.params?["limit"], "6")
    }

    func testBuildBlockListRequest() {
        let request = runner.buildRequest(from: .blockList(limit: 6))
        XCTAssertEqual(request.command, "block-list")
        XCTAssertEqual(request.params?["limit"], "6")
    }

    func testBuildBlockOutputsRequest() {
        let request = runner.buildRequest(from: .blockOutputs(limit: 6))
        XCTAssertEqual(request.command, "block-outputs")
        XCTAssertEqual(request.params?["limit"], "6")
    }

    func testBuildBlockCopyRequest() {
        let request = runner.buildRequest(from: .blockCopy(id: 42, field: "command"))
        XCTAssertEqual(request.command, "block-copy")
        XCTAssertEqual(request.params?["id"], "42")
        XCTAssertEqual(request.params?["field"], "command")
    }

    func testBuildBlockRerunRequest() {
        let request = runner.buildRequest(from: .blockRerun(id: 42))
        XCTAssertEqual(request.command, "block-rerun")
        XCTAssertEqual(request.params?["id"], "42")
    }

    func testBuildNotebookImportRequest() {
        let request = runner.buildRequest(from: .notebookImport(
            inputPath: "/tmp/source.ipynb",
            outputPath: "/tmp/result.cocxynb",
            force: true
        ))

        XCTAssertEqual(request.command, "notebook-import")
        XCTAssertEqual(request.params?["input"], "/tmp/source.ipynb")
        XCTAssertEqual(request.params?["output"], "/tmp/result.cocxynb")
        XCTAssertEqual(request.params?["force"], "true")
    }

    func testBuildNotebookExportRequest() {
        let request = runner.buildRequest(from: .notebookExport(
            inputPath: "/tmp/source.cocxynb",
            outputPath: "/tmp/result.ipynb",
            force: false
        ))

        XCTAssertEqual(request.command, "notebook-export")
        XCTAssertEqual(request.params?["input"], "/tmp/source.cocxynb")
        XCTAssertEqual(request.params?["output"], "/tmp/result.ipynb")
        XCTAssertEqual(request.params?["force"], "false")
    }

    func testBuildNotebookRunRequest() {
        let request = runner.buildRequest(from: .notebookRun(
            inputPath: "/tmp/source.cocxynb",
            outputPath: "/tmp/result.cocxynb",
            workingDirectory: "/tmp/project",
            timeoutSeconds: 15,
            continueOnFailure: true
        ))

        XCTAssertEqual(request.command, "notebook-run")
        XCTAssertEqual(request.params?["input"], "/tmp/source.cocxynb")
        XCTAssertEqual(request.params?["output"], "/tmp/result.cocxynb")
        XCTAssertEqual(request.params?["cwd"], "/tmp/project")
        XCTAssertEqual(request.params?["timeout"], "15.0")
        XCTAssertEqual(request.params?["continue-on-failure"], "true")
    }

    func testBuildWorkflowRunRequest() {
        let request = runner.buildRequest(from: .workflowRun(
            inputPath: "/tmp/workflow.toml",
            workingDirectory: "/tmp/project"
        ))

        XCTAssertEqual(request.command, "workflow-run")
        XCTAssertEqual(request.params?["input"], "/tmp/workflow.toml")
        XCTAssertEqual(request.params?["cwd"], "/tmp/project")
    }

    func testBuildSkillListRequest() {
        let request = runner.buildRequest(from: .skillList)

        XCTAssertEqual(request.command, "skill-list")
        XCTAssertNil(request.params)
    }
}

// MARK: - Output Formatter Tests

/// Tests for `OutputFormatter`: verify correct output for each command type.
final class OutputFormatterTests: XCTestCase {

    // MARK: - 23. Notify success message

    func testFormatNotifySuccess() {
        let response = CLISocketResponse(
            id: "r-1", success: true, data: nil, error: nil
        )
        let output = OutputFormatter.formatSuccess(
            command: .notify(message: "test"),
            response: response
        )
        XCTAssertEqual(output, "Notification sent.")
    }

    // MARK: - 24. New-tab success message

    func testFormatNewTabSuccess() {
        let response = CLISocketResponse(
            id: "r-2", success: true, data: nil, error: nil
        )
        let output = OutputFormatter.formatSuccess(
            command: .newTab(directory: nil, engine: nil),
            response: response
        )
        XCTAssertEqual(output, "Tab opened.")
    }

    // MARK: - 25. Focus-tab success message

    func testFormatFocusTabSuccess() {
        let response = CLISocketResponse(
            id: "r-3", success: true, data: nil, error: nil
        )
        let output = OutputFormatter.formatSuccess(
            command: .focusTab(id: "abc"),
            response: response
        )
        XCTAssertEqual(output, "Tab focused.")
    }

    // MARK: - 26. Close-tab success message

    func testFormatCloseTabSuccess() {
        let response = CLISocketResponse(
            id: "r-4", success: true, data: nil, error: nil
        )
        let output = OutputFormatter.formatSuccess(
            command: .closeTab(id: "abc"),
            response: response
        )
        XCTAssertEqual(output, "Tab closed.")
    }

    // MARK: - 27. Split success message

    func testFormatSplitSuccess() {
        let response = CLISocketResponse(
            id: "r-5", success: true, data: nil, error: nil
        )
        let output = OutputFormatter.formatSuccess(
            command: .split(direction: .horizontal),
            response: response
        )
        XCTAssertEqual(output, "Pane split.")
    }

    // MARK: - 28. Status formatting

    func testFormatStatusWithAllFields() {
        let response = CLISocketResponse(
            id: "r-6",
            success: true,
            data: [
                "version": "2.0.0",
                "tabs": "5 (3 idle, 1 working, 1 waiting)",
                "active": "~/projects/cocxy-terminal (main)",
                "socket": "~/.config/cocxy/cocxy.sock"
            ],
            error: nil
        )
        let output = OutputFormatter.formatSuccess(
            command: .status,
            response: response
        )

        XCTAssertTrue(output.contains("Cocxy Terminal v2.0.0"))
        XCTAssertTrue(output.contains("Tabs: 5"))
        XCTAssertTrue(output.contains("Active:"))
        XCTAssertTrue(output.contains("Socket:"))
    }

    // MARK: - 29. Status formatting with no data

    func testFormatStatusWithNoData() {
        let response = CLISocketResponse(
            id: "r-7", success: true, data: nil, error: nil
        )
        let output = OutputFormatter.formatSuccess(
            command: .status,
            response: response
        )
        XCTAssertEqual(output, "Cocxy Terminal - status unavailable")
    }

    func testFormatStatusIncludesLaunchTimingDiagnostics() {
        let response = CLISocketResponse(
            id: "r-7a",
            success: true,
            data: [
                "version": "0.1.92",
                "tabs": "12",
                "launch_critical_path_ms": "37.50",
                "launch_critical_path_budget_ms": "50",
                "launch_slowest_step": "Main window",
                "launch_slowest_step_ms": "14.25",
                "launch_deferred_completed": "3",
                "launch_deferred_pending": "2"
            ],
            error: nil
        )

        let output = OutputFormatter.formatSuccess(command: .status, response: response)

        XCTAssertTrue(output.contains("Launch: critical 37.50ms / 50ms, slowest Main window 14.25ms, warmup 3 done / 2 pending"))
    }

    func testFormatNotebookImportUsesServerSummary() {
        let response = CLISocketResponse(
            id: "notebook-1",
            success: true,
            data: ["summary": "Imported notebook to /tmp/result.cocxynb."],
            error: nil
        )

        let output = OutputFormatter.formatSuccess(
            command: .notebookImport(
                inputPath: "/tmp/source.ipynb",
                outputPath: "/tmp/result.cocxynb",
                force: false
            ),
            response: response
        )

        XCTAssertEqual(output, "Imported notebook to /tmp/result.cocxynb.")
    }

    func testFormatNotebookExportUsesServerSummary() {
        let response = CLISocketResponse(
            id: "notebook-2",
            success: true,
            data: ["summary": "Exported notebook to /tmp/result.ipynb."],
            error: nil
        )

        let output = OutputFormatter.formatSuccess(
            command: .notebookExport(
                inputPath: "/tmp/source.cocxynb",
                outputPath: "/tmp/result.ipynb",
                force: false
            ),
            response: response
        )

        XCTAssertEqual(output, "Exported notebook to /tmp/result.ipynb.")
    }

    func testFormatNotebookRunUsesServerSummary() {
        let response = CLISocketResponse(
            id: "notebook-3",
            success: true,
            data: ["summary": "Executed 2 notebook cells."],
            error: nil
        )

        let output = OutputFormatter.formatSuccess(
            command: .notebookRun(
                inputPath: "/tmp/source.cocxynb",
                outputPath: nil,
                workingDirectory: nil,
                timeoutSeconds: nil,
                continueOnFailure: false
            ),
            response: response
        )

        XCTAssertEqual(output, "Executed 2 notebook cells.")
    }

    func testFormatWorkflowRunUsesServerSummary() {
        let response = CLISocketResponse(
            id: "workflow-1",
            success: true,
            data: ["summary": "Workflow ci completed after 1 step."],
            error: nil
        )

        let output = OutputFormatter.formatSuccess(
            command: .workflowRun(
                inputPath: "/tmp/workflow.toml",
                workingDirectory: nil
            ),
            response: response
        )

        XCTAssertEqual(output, "Workflow ci completed after 1 step.")
    }

    func testFormatSkillListResponseAsJSONContent() {
        let content = """
        {"count":1,"skills":[{"id":"review-pr","name":"Review PR","description":"Review a local pull request diff.","source":"built-in"}]}
        """
        let response = CLISocketResponse(
            id: "skill-list",
            success: true,
            data: ["content": content],
            error: nil
        )

        let output = OutputFormatter.formatSuccess(command: .skillList, response: response)
        XCTAssertTrue(output.contains("\"id\" : \"review-pr\""))
        XCTAssertTrue(output.contains("\"source\" : \"built-in\""))
    }

    func testFormatStatusIncludesCoreDiagnostics() {
        let response = CLISocketResponse(
            id: "r-7b",
            success: true,
            data: [
                "version": "0.1.47",
                "search_mode": "gpu",
                "search_indexed_rows": "420",
                "protocol_v2_observed": "true",
                "protocol_v2_capabilities_requested": "true",
                "current_stream_id": "3",
                "cursor_visible": "true",
                "app_cursor_mode": "false",
                "bracketed_paste_mode": "true",
                "mouse_tracking_mode": "6",
                "kitty_keyboard_mode": "1",
                "alt_screen": "false",
                "cursor_shape": "5",
                "preedit_active": "false",
                "semantic_block_count": "4",
                "child_pid": "81234",
                "process_alive": "true",
                "font_cell_width": "8.50",
                "font_cell_height": "17.00",
                "font_ascent": "12.20",
                "font_descent": "3.10",
                "font_leading": "1.70",
                "selection_active": "true",
                "selection_start_row": "10",
                "selection_start_col": "2",
                "selection_end_row": "10",
                "selection_end_col": "7",
                "selection_text_bytes": "5",
                "semantic_state_name": "command_running",
                "semantic_current_block_name": "command_output",
                "semantic_prompt_blocks": "3",
                "semantic_command_input_blocks": "2",
                "semantic_command_output_blocks": "5",
                "semantic_error_blocks": "1",
                "semantic_tool_blocks": "4",
                "semantic_agent_blocks": "2",
                "color_space": "display-p3",
                "wide_gamut": "true",
                "high_contrast": "true",
                "icc_profile_configured": "true",
                "icc_profile_path": "/tmp/cocxy-display.icc",
                "shell_preexec_avg_ns": "120000000",
                "shell_preexec_max_ns": "180000000",
                "shell_preexec_warnings": "1",
                "shell_osc7_retries": "2",
                "shell_detected_p10k": "true",
                "shell_detected_tmux": "true",
                "shell_detected_screen": "true",
                "ligatures_enabled": "true",
                "ligature_cache_hits": "12",
                "ligature_cache_misses": "2",
                "image_count": "4",
                "image_memory_used_mib": "8",
                "image_memory_limit_mib": "256",
                "image_sixel_enabled": "true",
                "image_kitty_enabled": "true",
                "image_iterm2_enabled": "true",
                "image_disk_cache_enabled": "true",
                "image_disk_cache_used_mib": "2",
                "image_disk_cache_limit_mib": "512",
                "image_atlas_width": "1024",
                "image_atlas_height": "1024",
                "image_atlas_generation": "7",
                "image_atlas_dirty": "false",
                "stream_count": "2",
                "web_running": "true",
                "web_bind": "127.0.0.1",
                "web_port": "7770",
                "web_connections": "1"
            ],
            error: nil
        )
        let output = OutputFormatter.formatSuccess(command: .status, response: response)

        XCTAssertTrue(output.contains("Search: gpu (420 indexed rows)"))
        XCTAssertTrue(output.contains("Protocol v2: observed on, capabilities on, current stream 3"))
        XCTAssertTrue(output.contains("Modes: cursor on, app cursor off, alt screen off, bracketed paste on"))
        XCTAssertTrue(output.contains("Input: mouse mode 6, kitty keyboard 1, preedit off, cursor shape 5, semantic blocks 4"))
        XCTAssertTrue(output.contains("Color: display-p3, wide gamut on, high contrast on, ICC on"))
        XCTAssertFalse(output.contains("/tmp/cocxy-display.icc"))
        XCTAssertTrue(output.contains("Process: pid 81234, alive on"))
        XCTAssertTrue(output.contains("Font: cell 8.50x17.00, ascent 12.20, descent 3.10, leading 1.70"))
        XCTAssertTrue(output.contains("Selection: on (10:2 -> 10:7, 5 bytes)"))
        XCTAssertTrue(output.contains("Semantic: state command_running, current command_output, prompt 3, input 2, output 5, error 1, tool 4, agent 2"))
        XCTAssertTrue(output.contains("Shell integration: preexec avg 120000000ns, max 180000000ns, warnings 1, stale cwd retries 2, p10k on, tmux on, screen on"))
        XCTAssertTrue(output.contains("Ligatures: on (hits 12, misses 2)"))
        XCTAssertTrue(output.contains("Images: 4 loaded (8/256 MiB, sixel on, kitty on, iTerm2 on, disk 2/512 MiB)"))
        XCTAssertTrue(output.contains("Image atlas: 1024x1024 gen 7, dirty off"))
        XCTAssertTrue(output.contains("Streams: 2"))
        XCTAssertTrue(output.contains("Web terminal: running on 127.0.0.1:7770 (1 clients)"))
    }

    func testFormatCoreSemanticSuccessFallsBackToStructuredData() {
        let response = CLISocketResponse(
            id: "r-core-sem",
            success: true,
            data: ["content": "{\"state\":\"idle\"}"],
            error: nil
        )
        let output = OutputFormatter.formatSuccess(
            command: .coreSemantic(limit: 4),
            response: response
        )
        XCTAssertTrue(output.contains("\"state\""))
    }

    func testFormatCoreSnapshotCommandsFallBackToStructuredData() {
        let response = CLISocketResponse(
            id: "r-core-snap",
            success: true,
            data: ["content": "{\"ok\":true}"],
            error: nil
        )

        let commands: [ParsedCommand] = [
            .coreProcess,
            .coreModes,
            .coreSearch,
            .coreLigatures,
            .coreProtocol
        ]

        for command in commands {
            let output = OutputFormatter.formatSuccess(command: command, response: response)
            XCTAssertTrue(output.contains("\"ok\""), "Expected structured output for \(command)")
        }
    }

    func testFormatImageDeleteSuccess() {
        let response = CLISocketResponse(
            id: "r-img-del",
            success: true,
            data: ["image_id": "7"],
            error: nil
        )
        let output = OutputFormatter.formatSuccess(
            command: .imageDelete(id: 7),
            response: response
        )
        XCTAssertEqual(output, "Inline image deleted.")
    }

    func testFormatImageListSuccessFallsBackToStructuredData() {
        let response = CLISocketResponse(
            id: "r-img-list",
            success: true,
            data: [
                "count": "1",
                "image_0_id": "7",
                "image_0_width": "1",
                "image_0_height": "1"
            ],
            error: nil
        )
        let output = OutputFormatter.formatSuccess(
            command: .imageList,
            response: response
        )
        XCTAssertTrue(output.contains("\"count\""))
        XCTAssertTrue(output.contains("\"image_0_id\""))
    }

    func testFormatBlockListSuccessFallsBackToStructuredData() {
        let response = CLISocketResponse(
            id: "r-block-list",
            success: true,
            data: ["content": "{\"count\":1,\"blocks\":[{\"id\":42,\"command\":\"echo hi\"}]}"],
            error: nil
        )
        let output = OutputFormatter.formatSuccess(
            command: .blockList(limit: 5),
            response: response
        )
        XCTAssertTrue(output.contains("\"blocks\""))
        XCTAssertTrue(output.contains("\"command\""))
    }

    func testFormatBlockOutputsPrintsCleanOutput() {
        let response = CLISocketResponse(
            id: "r-block-outputs",
            success: true,
            data: ["output": "first block\nsecond block"],
            error: nil
        )
        let output = OutputFormatter.formatSuccess(
            command: .blockOutputs(limit: 5),
            response: response
        )
        XCTAssertEqual(output, "first block\nsecond block")
    }

    func testFormatBlockCopyAndRerunSuccess() {
        XCTAssertEqual(
            OutputFormatter.formatSuccess(
                command: .blockCopy(id: 42, field: "output"),
                response: CLISocketResponse(id: "r-copy", success: true, data: ["id": "42"], error: nil)
            ),
            "Block 42 copied."
        )

        XCTAssertEqual(
            OutputFormatter.formatSuccess(
                command: .blockRerun(id: 42),
                response: CLISocketResponse(id: "r-rerun", success: true, data: ["id": "42"], error: nil)
            ),
            "Block 42 sent to terminal."
        )
    }

    // MARK: - 30. List-tabs formatting with no data

    func testFormatListTabsWithNoData() {
        let response = CLISocketResponse(
            id: "r-8", success: true, data: nil, error: nil
        )
        let output = OutputFormatter.formatSuccess(
            command: .listTabs,
            response: response
        )
        XCTAssertEqual(output, "[]")
    }

    func testFormatTabConfigExportSuccess() {
        let response = CLISocketResponse(
            id: "r-tab-config-export",
            success: true,
            data: ["path": "/tmp/shared-api.toml"],
            error: nil
        )
        let output = OutputFormatter.formatSuccess(
            command: .tabConfigExport(name: "api", output: "/tmp/shared-api.toml", force: false),
            response: response
        )
        XCTAssertEqual(output, "Tab config exported: /tmp/shared-api.toml")
    }

    // MARK: - 31. Error formatting

    func testFormatUnknownCommandError() {
        let output = OutputFormatter.formatError(.unknownCommand("foobar"))
        XCTAssertEqual(
            output,
            "Error: Unknown command 'foobar'. Run 'cocxy --help' for usage."
        )
    }
}

// MARK: - Command Runner Tests

/// Tests for `CommandRunner`: verify end-to-end behavior for help, version,
/// and error cases (without a real server).
final class CommandRunnerTests: XCTestCase {

    // MARK: - 32. Help command returns exit code 0

    func testHelpCommandReturnsExitCodeZero() {
        let runner = CommandRunner(
            socketClient: SocketClient(socketPath: "/tmp/nonexistent.sock")
        )
        let result = runner.run(arguments: ["--help"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("cocxy"))
        XCTAssertTrue(result.stderr.isEmpty)
    }

    // MARK: - 33. Version command returns exit code 0

    func testVersionCommandReturnsExitCodeZero() {
        let runner = CommandRunner(
            socketClient: SocketClient(socketPath: "/tmp/nonexistent.sock")
        )
        let result = runner.run(arguments: ["--version"])

        XCTAssertEqual(result.exitCode, 0)
        // Version is resolved dynamically from the app bundle Info.plist
        // when bundled; falls back to a hardcoded value otherwise. Match
        // whatever the parser actually exposes so the assertion does not
        // drift on release bumps.
        XCTAssertEqual(result.stdout, "cocxy \(CLIArgumentParser.version)")
        XCTAssertTrue(result.stderr.isEmpty)
    }

    // MARK: - 34. Unknown command returns exit code 1

    func testUnknownCommandReturnsExitCodeOne() {
        let runner = CommandRunner(
            socketClient: SocketClient(socketPath: "/tmp/nonexistent.sock")
        )
        let result = runner.run(arguments: ["xyzzy"])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stdout.isEmpty)
        XCTAssertTrue(result.stderr.contains("Unknown command"))
    }

    // MARK: - 35. Server not running returns exit code 1

    func testServerNotRunningReturnsExitCodeOne() {
        let runner = CommandRunner(
            socketClient: SocketClient(
                socketPath: "/tmp/cocxy-test-nonexistent-\(UUID().uuidString.prefix(8)).sock",
                timeoutSeconds: 1
            )
        )
        let result = runner.run(arguments: ["status"])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stdout.isEmpty)
        XCTAssertTrue(result.stderr.contains("not running"))
    }
}

// MARK: - CLI Error Tests

/// Tests for `CLIError` user-facing messages.
final class CLIErrorTests: XCTestCase {

    // MARK: - 36. All error messages are non-empty and start with "Error:"

    func testAllErrorMessagesStartWithError() {
        let errors: [CLIError] = [
            .appNotRunning,
            .permissionDenied,
            .timeout,
            .unknownCommand("test"),
            .missingArgument(command: "test", argument: "arg"),
            .invalidArgument(command: "test", argument: "arg", reason: "reason"),
            .serverError("Server error"),
            .payloadTooLarge(size: 100, maximum: 50),
            .malformedResponse(reason: "Bad data"),
            .connectionFailed(reason: "Network error"),
        ]

        for error in errors {
            XCTAssertTrue(
                error.userMessage.hasPrefix("Error:"),
                "'\(error)' should produce a message starting with 'Error:', got: \(error.userMessage)"
            )
        }
    }

    // MARK: - 37. CLIError Equatable conformance

    func testCLIErrorEquatableConformance() {
        XCTAssertEqual(CLIError.appNotRunning, CLIError.appNotRunning)
        XCTAssertNotEqual(CLIError.appNotRunning, CLIError.timeout)
        XCTAssertEqual(
            CLIError.unknownCommand("foo"),
            CLIError.unknownCommand("foo")
        )
        XCTAssertNotEqual(
            CLIError.unknownCommand("foo"),
            CLIError.unknownCommand("bar")
        )
    }
}

// MARK: - CLI Command Definition Tests

/// Tests for `CLICommand` enum metadata.
final class CLICommandDefinitionTests: XCTestCase {

    // MARK: - 43. All commands exist (current catalog size)

    func testAllCommandsExist() {
        // Keep this explicit so new socket-facing verbs update help,
        // descriptions, parser coverage, and formatter coverage together.
        XCTAssertEqual(CLICommand.allCases.count, 129)
    }

    // MARK: - 39. Raw values match server protocol

    func testRawValuesMatchServerProtocol() {
        XCTAssertEqual(CLICommand.notify.rawValue, "notify")
        XCTAssertEqual(CLICommand.newTab.rawValue, "new-tab")
        XCTAssertEqual(CLICommand.listTabs.rawValue, "list-tabs")
        XCTAssertEqual(CLICommand.focusTab.rawValue, "focus-tab")
        XCTAssertEqual(CLICommand.closeTab.rawValue, "close-tab")
        XCTAssertEqual(CLICommand.split.rawValue, "split")
        XCTAssertEqual(CLICommand.status.rawValue, "status")
    }

    // MARK: - 40. All commands have non-empty help descriptions

    func testAllCommandsHaveHelpDescriptions() {
        for command in CLICommand.allCases {
            XCTAssertFalse(
                command.helpDescription.isEmpty,
                "\(command) should have a help description"
            )
        }
    }

    // MARK: - 41. All commands have usage examples

    func testAllCommandsHaveUsageExamples() {
        for command in CLICommand.allCases {
            XCTAssertTrue(
                command.usageExample.hasPrefix("cocxy"),
                "\(command) usage example should start with 'cocxy'"
            )
        }
    }

    func testBrowserUsageExamplesMatchPublicParserShape() throws {
        XCTAssertEqual(CLICommand.browserNavigate.usageExample, "cocxy browser navigate <url>")
        XCTAssertEqual(CLICommand.browserBack.usageExample, "cocxy browser back")
        XCTAssertEqual(CLICommand.browserForward.usageExample, "cocxy browser forward")
        XCTAssertEqual(CLICommand.browserReload.usageExample, "cocxy browser reload")
        XCTAssertEqual(CLICommand.browserGetState.usageExample, "cocxy browser state")
        XCTAssertEqual(CLICommand.browserEval.usageExample, "cocxy browser eval <script>")
        XCTAssertEqual(CLICommand.browserGetText.usageExample, "cocxy browser text")
        XCTAssertEqual(CLICommand.browserListTabs.usageExample, "cocxy browser tabs")

        guard case .browserNavigate(let url) = try CLIArgumentParser.parse(["browser", "navigate", "https://example.com"]) else {
            return XCTFail("browser navigate should parse through the public CLI shape")
        }
        XCTAssertEqual(url, "https://example.com")

        guard case .browserEval(let script) = try CLIArgumentParser.parse(["browser", "eval", "document.title"]) else {
            return XCTFail("browser eval should parse through the public CLI shape")
        }
        XCTAssertEqual(script, "document.title")

        XCTAssertNoThrow(try CLIArgumentParser.parse(["browser", "state"]))
        XCTAssertNoThrow(try CLIArgumentParser.parse(["browser", "tabs"]))
        XCTAssertNoThrow(try CLIArgumentParser.parse(["browser", "text"]))
    }

    func testWorktreeFocusUsageMatchesPublicParserShape() throws {
        XCTAssertEqual(CLICommand.worktreeFocus.usageExample, "cocxy worktree focus <id>")
        XCTAssertEqual(
            try CLIArgumentParser.parse(["worktree", "focus", "abc123"]),
            .worktreeFocus(id: "abc123")
        )
    }

    func testTabConfigExportUsageMatchesPublicParserShape() throws {
        XCTAssertEqual(
            CLICommand.tabConfigExport.usageExample,
            "cocxy tab config export <name> --output <path> [--force]"
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse([
                "tab", "config", "export", "api",
                "--output", "/tmp/shared-api.toml",
            ]),
            .tabConfigExport(name: "api", output: "/tmp/shared-api.toml", force: false)
        )
    }
}

// MARK: - CLISocketRequest Codable Tests

/// Tests for `CLISocketRequest` Codable round-trip.
final class CLISocketRequestTests: XCTestCase {

    // MARK: - 42. Codable round-trip with params

    func testCodableRoundTripWithParams() throws {
        let request = CLISocketRequest(
            id: "rt-1",
            command: "notify",
            params: ["message": "hello"]
        )
        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CLISocketRequest.self, from: encoded)
        XCTAssertEqual(decoded, request)
    }

    // MARK: - 43. Codable round-trip without params

    func testCodableRoundTripWithoutParams() throws {
        let request = CLISocketRequest(id: "rt-2", command: "status", params: nil)
        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CLISocketRequest.self, from: encoded)
        XCTAssertEqual(decoded, request)
    }
}
