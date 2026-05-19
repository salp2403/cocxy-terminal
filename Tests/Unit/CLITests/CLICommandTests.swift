// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CLICommandTests.swift - Tests for CLI argument parsing, request building, and output formatting.

import XCTest
import Darwin
import CocxyShared
@testable import CocxyCommandSignatures
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

    func testClassifyCommandJoinsInputWords() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse(["classify", "what", "is", "the", "weather"]),
            .classify(input: "what is the weather")
        )
    }

    func testClassifyWithoutInputThrowsMissingArgument() {
        XCTAssertThrowsError(try CLIArgumentParser.parse(["classify"])) { error in
            guard let cliError = error as? CLIError else {
                XCTFail("Expected CLIError, got \(error)")
                return
            }
            XCTAssertEqual(
                cliError,
                .missingArgument(command: "classify", argument: "input")
            )
        }
    }

    func testSignatureCommandsParse() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse(["keys", "generate", "--author", "Cocxy"]),
            .keysGenerate(author: "Cocxy")
        )
        XCTAssertEqual(try CLIArgumentParser.parse(["keys", "list"]), .keysList)
        XCTAssertEqual(
            try CLIArgumentParser.parse(["keys", "export-public", "abc", "--output", "/tmp/key.json"]),
            .keysExportPublic(keyID: "abc", outputPath: "/tmp/key.json")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["keys", "import", "/tmp/key.json"]),
            .keysImport(path: "/tmp/key.json")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["sign", "template", "/tmp/template", "--key", "abc", "--author", "Cocxy"]),
            .signArtifact(kind: "template", path: "/tmp/template", keyID: "abc", author: "Cocxy")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["verify", "template", "/tmp/template"]),
            .verifyArtifact(kind: "template", path: "/tmp/template", publicKeyPath: nil)
        )
    }

    func testKeysGenerateWithoutAuthorThrowsMissingArgument() {
        XCTAssertThrowsError(try CLIArgumentParser.parse(["keys", "generate"])) { error in
            XCTAssertEqual(
                error as? CLIError,
                .missingArgument(command: "keys generate", argument: "author")
            )
        }
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

    func testParseNotebookExportHTMLWithForce() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse([
                "notebook", "export-html", "/tmp/source.cocxynb",
                "--output", "/tmp/result.html",
                "--force",
            ]),
            .notebookExportHTML(
                inputPath: "/tmp/source.cocxynb",
                outputPath: "/tmp/result.html",
                force: true
            )
        )
    }

    func testParseNotebookTemplateList() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse(["notebook", "template", "list"]),
            .notebookTemplateList
        )
    }

    func testParseNotebookTemplateCreateWithForce() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse([
                "notebook", "template", "create", "python-analysis",
                "--output", "/tmp/analysis.cocxynb",
                "--force",
            ]),
            .notebookTemplateCreate(
                templateID: "python-analysis",
                outputPath: "/tmp/analysis.cocxynb",
                force: true
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
                "--sandbox", "workspace",
                "--continue-on-failure",
            ]),
            .notebookRun(
                inputPath: "/tmp/source.cocxynb",
                outputPath: "/tmp/result.cocxynb",
                workingDirectory: "/tmp/project",
                timeoutSeconds: 15,
                sandbox: "workspace",
                continueOnFailure: true
            )
        )
    }

    func testParseNotebookRunRejectsInvalidSandboxMode() {
        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "notebook", "run", "/tmp/source.cocxynb",
            "--sandbox", "cloud",
        ])) { error in
            XCTAssertTrue(String(describing: error).contains("Sandbox must be one of: workspace, none"))
        }
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

    func testTmuxCompatParsesCommonAliases() throws {
        XCTAssertEqual(try CLIArgumentParser.parse(["tmux", "new", "-s", "work"]), .newTab(directory: nil, engine: nil))
        XCTAssertEqual(try CLIArgumentParser.parse(["tmux", "split-window", "-h"]), .split(direction: .horizontal))
        XCTAssertEqual(try CLIArgumentParser.parse(["tmux", "split-window", "-v"]), .split(direction: .vertical))
        XCTAssertEqual(try CLIArgumentParser.parse(["tmux", "list-sessions"]), .splitList)
        XCTAssertEqual(try CLIArgumentParser.parse(["tmux", "attach", "-t", "abc"]), .focusTab(id: "abc"))
        XCTAssertEqual(try CLIArgumentParser.parse(["tmux", "kill-session", "-t", "abc"]), .closeTab(id: "abc"))
        XCTAssertEqual(try CLIArgumentParser.parse(["tmux", "send-keys", "echo hello", "Enter"]), .send(text: "echo hello\n"))
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

    func testBuildBrowserAutomationV2Requests() {
        let dblClick = runner.buildRequest(from: .browserDblClick(ref: "button-1"))
        XCTAssertEqual(dblClick.command, "browser-dblclick")
        XCTAssertEqual(dblClick.params?["ref"], "button-1")

        let hover = runner.buildRequest(from: .browserHover(ref: "menu-1"))
        XCTAssertEqual(hover.command, "browser-hover")
        XCTAssertEqual(hover.params?["ref"], "menu-1")

        let focus = runner.buildRequest(from: .browserFocus(ref: "input-1"))
        XCTAssertEqual(focus.command, "browser-focus")
        XCTAssertEqual(focus.params?["ref"], "input-1")

        let timedClick = runner.buildRequest(from: .browserClick(ref: "button-1", timeoutMilliseconds: 1_250))
        XCTAssertEqual(timedClick.command, "browser-click")
        XCTAssertEqual(timedClick.params?["ref"], "button-1")
        XCTAssertEqual(timedClick.params?["timeout"], "1250")

        let pageHTML = runner.buildRequest(from: .browserGetHTML(ref: nil))
        XCTAssertEqual(pageHTML.command, "browser-get-html")
        XCTAssertNil(pageHTML.params)

        let elementHTML = runner.buildRequest(from: .browserGetHTML(ref: "card-1"))
        XCTAssertEqual(elementHTML.command, "browser-get-html")
        XCTAssertEqual(elementHTML.params?["ref"], "card-1")

        let value = runner.buildRequest(from: .browserGetValue(ref: "input-1"))
        XCTAssertEqual(value.command, "browser-get-value")
        XCTAssertEqual(value.params?["ref"], "input-1")

        let type = runner.buildRequest(from: .browserType(ref: "input-1", text: "hello"))
        XCTAssertEqual(type.command, "browser-type")
        XCTAssertEqual(type.params?["ref"], "input-1")
        XCTAssertEqual(type.params?["text"], "hello")

        let typeFocused = runner.buildRequest(from: .browserType(ref: nil, text: "hello"))
        XCTAssertEqual(typeFocused.command, "browser-type")
        XCTAssertNil(typeFocused.params?["ref"])
        XCTAssertEqual(typeFocused.params?["text"], "hello")

        let timedFill = runner.buildRequest(from: .browserFill(
            ref: "input-1",
            text: "hello",
            timeoutMilliseconds: 2_500
        ))
        XCTAssertEqual(timedFill.command, "browser-fill")
        XCTAssertEqual(timedFill.params?["ref"], "input-1")
        XCTAssertEqual(timedFill.params?["text"], "hello")
        XCTAssertEqual(timedFill.params?["timeout"], "2500")

        let upload = runner.buildRequest(from: .browserUpload(
            ref: "file-1",
            path: "/tmp/cocxy-upload.txt",
            timeoutMilliseconds: 3_000
        ))
        XCTAssertEqual(upload.command, "browser-upload")
        XCTAssertEqual(upload.params?["ref"], "file-1")
        XCTAssertEqual(upload.params?["path"], "/tmp/cocxy-upload.txt")
        XCTAssertEqual(upload.params?["timeout"], "3000")

        let press = runner.buildRequest(from: .browserPress(key: "Enter"))
        XCTAssertEqual(press.command, "browser-press")
        XCTAssertEqual(press.params?["key"], "Enter")

        let keyDown = runner.buildRequest(from: .browserKeyDown(key: "Shift"))
        XCTAssertEqual(keyDown.command, "browser-keydown")
        XCTAssertEqual(keyDown.params?["key"], "Shift")

        let keyUp = runner.buildRequest(from: .browserKeyUp(key: "Shift"))
        XCTAssertEqual(keyUp.command, "browser-keyup")
        XCTAssertEqual(keyUp.params?["key"], "Shift")

        let attr = runner.buildRequest(from: .browserGetAttr(ref: "link-1", name: "href"))
        XCTAssertEqual(attr.command, "browser-get-attr")
        XCTAssertEqual(attr.params?["ref"], "link-1")
        XCTAssertEqual(attr.params?["name"], "href")

        let title = runner.buildRequest(from: .browserGetTitle)
        XCTAssertEqual(title.command, "browser-get-title")
        XCTAssertNil(title.params)

        let stateSave = runner.buildRequest(from: .browserStateSave(path: "/tmp/cocxy-state.json"))
        XCTAssertEqual(stateSave.command, "browser-state-save")
        XCTAssertEqual(stateSave.params?["path"], "/tmp/cocxy-state.json")

        let stateLoad = runner.buildRequest(from: .browserStateLoad(path: "/tmp/cocxy-state.json"))
        XCTAssertEqual(stateLoad.command, "browser-state-load")
        XCTAssertEqual(stateLoad.params?["path"], "/tmp/cocxy-state.json")

        let addScript = runner.buildRequest(from: .browserAddScript(script: "window.ready = true"))
        XCTAssertEqual(addScript.command, "browser-add-script")
        XCTAssertEqual(addScript.params?["script"], "window.ready = true")

        let addStyle = runner.buildRequest(from: .browserAddStyle(css: "body { color: red; }"))
        XCTAssertEqual(addStyle.command, "browser-add-style")
        XCTAssertEqual(addStyle.params?["css"], "body { color: red; }")

        let initScriptAdd = runner.buildRequest(from: .browserInitScriptAdd(script: "window.ready = true"))
        XCTAssertEqual(initScriptAdd.command, "browser-init-script-add")
        XCTAssertEqual(initScriptAdd.params?["script"], "window.ready = true")

        let initScriptsList = runner.buildRequest(from: .browserInitScriptsList)
        XCTAssertEqual(initScriptsList.command, "browser-init-scripts-list")
        XCTAssertNil(initScriptsList.params)

        let dialogs = runner.buildRequest(from: .browserDialogs)
        XCTAssertEqual(dialogs.command, "browser-dialogs")
        XCTAssertNil(dialogs.params)

        let dialogAccept = runner.buildRequest(from: .browserDialogAccept(id: "dialog-1", promptText: "ok"))
        XCTAssertEqual(dialogAccept.command, "browser-dialog-accept")
        XCTAssertEqual(dialogAccept.params?["id"], "dialog-1")
        XCTAssertEqual(dialogAccept.params?["promptText"], "ok")

        let dialogDismiss = runner.buildRequest(from: .browserDialogDismiss(id: nil))
        XCTAssertEqual(dialogDismiss.command, "browser-dialog-dismiss")
        XCTAssertNil(dialogDismiss.params)

        let count = runner.buildRequest(from: .browserGetCount(selector: ".item"))
        XCTAssertEqual(count.command, "browser-get-count")
        XCTAssertEqual(count.params?["selector"], ".item")

        let box = runner.buildRequest(from: .browserGetBox(ref: "card-1"))
        XCTAssertEqual(box.command, "browser-get-box")
        XCTAssertEqual(box.params?["ref"], "card-1")

        let styles = runner.buildRequest(from: .browserGetStyles(ref: "card-1", names: ["color", "display"]))
        XCTAssertEqual(styles.command, "browser-get-styles")
        XCTAssertEqual(styles.params?["ref"], "card-1")
        XCTAssertEqual(styles.params?["names"], "color,display")

        let check = runner.buildRequest(from: .browserCheck(ref: "agree-1"))
        XCTAssertEqual(check.command, "browser-check")
        XCTAssertEqual(check.params?["ref"], "agree-1")

        let uncheck = runner.buildRequest(from: .browserUncheck(ref: "agree-1"))
        XCTAssertEqual(uncheck.command, "browser-uncheck")
        XCTAssertEqual(uncheck.params?["ref"], "agree-1")

        let select = runner.buildRequest(from: .browserSelect(ref: "country-1", value: "Honduras"))
        XCTAssertEqual(select.command, "browser-select")
        XCTAssertEqual(select.params?["ref"], "country-1")
        XCTAssertEqual(select.params?["value"], "Honduras")

        let scroll = runner.buildRequest(from: .browserScroll(x: 120, y: -24))
        XCTAssertEqual(scroll.command, "browser-scroll")
        XCTAssertEqual(scroll.params?["x"], "120")
        XCTAssertEqual(scroll.params?["y"], "-24")

        let timedScroll = runner.buildRequest(from: .browserScroll(
            x: 120,
            y: -24,
            timeoutMilliseconds: 1_500
        ))
        XCTAssertEqual(timedScroll.command, "browser-scroll")
        XCTAssertEqual(timedScroll.params?["x"], "120")
        XCTAssertEqual(timedScroll.params?["y"], "-24")
        XCTAssertEqual(timedScroll.params?["timeout"], "1500")

        let scrollIntoView = runner.buildRequest(from: .browserScrollIntoView(ref: "footer-1"))
        XCTAssertEqual(scrollIntoView.command, "browser-scroll-into-view")
        XCTAssertEqual(scrollIntoView.params?["ref"], "footer-1")

        let visible = runner.buildRequest(from: .browserIsVisible(ref: "card-1"))
        XCTAssertEqual(visible.command, "browser-is-visible")
        XCTAssertEqual(visible.params?["ref"], "card-1")

        let enabled = runner.buildRequest(from: .browserIsEnabled(ref: "button-1"))
        XCTAssertEqual(enabled.command, "browser-is-enabled")
        XCTAssertEqual(enabled.params?["ref"], "button-1")

        let checked = runner.buildRequest(from: .browserIsChecked(ref: "agree-1"))
        XCTAssertEqual(checked.command, "browser-is-checked")
        XCTAssertEqual(checked.params?["ref"], "agree-1")

        let findRole = runner.buildRequest(from: .browserFindRole(role: "button", name: "Save"))
        XCTAssertEqual(findRole.command, "browser-find-role")
        XCTAssertEqual(findRole.params?["role"], "button")
        XCTAssertEqual(findRole.params?["name"], "Save")

        let findText = runner.buildRequest(from: .browserFindText(text: "Deploy"))
        XCTAssertEqual(findText.command, "browser-find-text")
        XCTAssertEqual(findText.params?["text"], "Deploy")

        let findLabel = runner.buildRequest(from: .browserFindLabel(text: "Email"))
        XCTAssertEqual(findLabel.command, "browser-find-label")
        XCTAssertEqual(findLabel.params?["text"], "Email")

        let findPlaceholder = runner.buildRequest(from: .browserFindPlaceholder(text: "Search"))
        XCTAssertEqual(findPlaceholder.command, "browser-find-placeholder")
        XCTAssertEqual(findPlaceholder.params?["text"], "Search")

        let findAlt = runner.buildRequest(from: .browserFindAlt(text: "Logo"))
        XCTAssertEqual(findAlt.command, "browser-find-alt")
        XCTAssertEqual(findAlt.params?["text"], "Logo")

        let findTitle = runner.buildRequest(from: .browserFindTitle(text: "Help"))
        XCTAssertEqual(findTitle.command, "browser-find-title")
        XCTAssertEqual(findTitle.params?["text"], "Help")

        let findTestID = runner.buildRequest(from: .browserFindTestID(id: "submit-button"))
        XCTAssertEqual(findTestID.command, "browser-find-testid")
        XCTAssertEqual(findTestID.params?["id"], "submit-button")

        let findFirst = runner.buildRequest(from: .browserFindFirst(selector: ".row"))
        XCTAssertEqual(findFirst.command, "browser-find-first")
        XCTAssertEqual(findFirst.params?["selector"], ".row")

        let findLast = runner.buildRequest(from: .browserFindLast(selector: ".row"))
        XCTAssertEqual(findLast.command, "browser-find-last")
        XCTAssertEqual(findLast.params?["selector"], ".row")

        let findNth = runner.buildRequest(from: .browserFindNth(index: 1, selector: ".row"))
        XCTAssertEqual(findNth.command, "browser-find-nth")
        XCTAssertEqual(findNth.params?["index"], "1")
        XCTAssertEqual(findNth.params?["selector"], ".row")

        let storageList = runner.buildRequest(from: .browserStorageList(area: .local))
        XCTAssertEqual(storageList.command, "browser-storage-list")
        XCTAssertEqual(storageList.params?["area"], "local")

        let storageGet = runner.buildRequest(from: .browserStorageGet(area: .session, key: "draft"))
        XCTAssertEqual(storageGet.command, "browser-storage-get")
        XCTAssertEqual(storageGet.params?["area"], "session")
        XCTAssertEqual(storageGet.params?["key"], "draft")

        let storageSet = runner.buildRequest(from: .browserStorageSet(area: .local, key: "theme", value: "dark"))
        XCTAssertEqual(storageSet.command, "browser-storage-set")
        XCTAssertEqual(storageSet.params?["area"], "local")
        XCTAssertEqual(storageSet.params?["key"], "theme")
        XCTAssertEqual(storageSet.params?["value"], "dark")

        let storageDelete = runner.buildRequest(from: .browserStorageDelete(area: .local, key: "theme"))
        XCTAssertEqual(storageDelete.command, "browser-storage-delete")
        XCTAssertEqual(storageDelete.params?["area"], "local")
        XCTAssertEqual(storageDelete.params?["key"], "theme")

        let frames = runner.buildRequest(from: .browserFrames)
        XCTAssertEqual(frames.command, "browser-frames")
        XCTAssertNil(frames.params)

        let downloads = runner.buildRequest(from: .browserDownloads)
        XCTAssertEqual(downloads.command, "browser-downloads")
        XCTAssertNil(downloads.params)

        let context = runner.buildRequest(from: .browserContext(
            targetRef: "card-1",
            around: 2,
            consoleTail: 5,
            networkTail: 8
        ))
        XCTAssertEqual(context.command, "browser-context")
        XCTAssertEqual(context.params?["target"], "card-1")
        XCTAssertEqual(context.params?["around"], "2")
        XCTAssertEqual(context.params?["console"], "5")
        XCTAssertEqual(context.params?["network"], "8")
    }

    func testBuildBrowserActionRequestAddsEvidenceDirectoryFromEnvironment() {
        let environmentKey = "COCXY_BROWSER_ACTION_EVIDENCE_DIR"
        let previousValue = getenv(environmentKey).map { String(cString: $0) }
        defer {
            if let previousValue {
                setenv(environmentKey, previousValue, 1)
            } else {
                unsetenv(environmentKey)
            }
        }
        setenv(environmentKey, "/tmp/cocxy-browser-evidence", 1)

        let click = runner.buildRequest(from: .browserClick(ref: "save", timeoutMilliseconds: 500))

        XCTAssertEqual(click.command, "browser-click")
        XCTAssertEqual(click.params?["ref"], "save")
        XCTAssertEqual(click.params?["timeout"], "500")
        XCTAssertEqual(click.params?["screenshotDir"], "/tmp/cocxy-browser-evidence")

        let typed = runner.buildRequest(from: .browserType(ref: "field", text: "Hello", timeoutMilliseconds: nil))
        XCTAssertEqual(typed.command, "browser-type")
        XCTAssertEqual(typed.params?["ref"], "field")
        XCTAssertEqual(typed.params?["text"], "Hello")
        XCTAssertEqual(typed.params?["screenshotDir"], "/tmp/cocxy-browser-evidence")
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

    func testBuildNotebookExportHTMLRequest() {
        let request = runner.buildRequest(from: .notebookExportHTML(
            inputPath: "/tmp/source.cocxynb",
            outputPath: "/tmp/result.html",
            force: true
        ))

        XCTAssertEqual(request.command, "notebook-export-html")
        XCTAssertEqual(request.params?["input"], "/tmp/source.cocxynb")
        XCTAssertEqual(request.params?["output"], "/tmp/result.html")
        XCTAssertEqual(request.params?["force"], "true")
    }

    func testBuildNotebookTemplateListRequest() {
        let request = runner.buildRequest(from: .notebookTemplateList)

        XCTAssertEqual(request.command, "notebook-template-list")
        XCTAssertNil(request.params)
    }

    func testBuildNotebookTemplateCreateRequest() {
        let request = runner.buildRequest(from: .notebookTemplateCreate(
            templateID: "swift-script",
            outputPath: "/tmp/script.cocxynb",
            force: false
        ))

        XCTAssertEqual(request.command, "notebook-template-create")
        XCTAssertEqual(request.params?["template"], "swift-script")
        XCTAssertEqual(request.params?["output"], "/tmp/script.cocxynb")
        XCTAssertEqual(request.params?["force"], "false")
    }

    func testBuildNotebookRunRequest() {
        let request = runner.buildRequest(from: .notebookRun(
            inputPath: "/tmp/source.cocxynb",
            outputPath: "/tmp/result.cocxynb",
            workingDirectory: "/tmp/project",
            timeoutSeconds: 15,
            sandbox: "workspace",
            continueOnFailure: true
        ))

        XCTAssertEqual(request.command, "notebook-run")
        XCTAssertEqual(request.params?["input"], "/tmp/source.cocxynb")
        XCTAssertEqual(request.params?["output"], "/tmp/result.cocxynb")
        XCTAssertEqual(request.params?["cwd"], "/tmp/project")
        XCTAssertEqual(request.params?["timeout"], "15.0")
        XCTAssertEqual(request.params?["sandbox"], "workspace")
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

    func testFormatCellCreateUsesCanonicalID() {
        let response = CLISocketResponse(
            id: "cell-create",
            success: true,
            data: ["id": "55555555-5555-5555-5555-555555555555"],
            error: nil
        )
        let output = OutputFormatter.formatSuccess(
            command: .cellCreate(CellCreateCLIOptions(provider: "ssh")),
            response: response
        )

        XCTAssertEqual(output, "Cell created: 55555555-5555-5555-5555-555555555555")
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
                "launch_critical_slowest_step": "Socket server",
                "launch_critical_slowest_step_ms": "9.75",
                "launch_deferred_completed": "3",
                "launch_deferred_pending": "2"
            ],
            error: nil
        )

        let output = OutputFormatter.formatSuccess(command: .status, response: response)

        XCTAssertTrue(output.contains("Launch: critical 37.50ms / 50ms, slowest Main window 14.25ms, critical slowest Socket server 9.75ms, warmup 3 done / 2 pending"))
    }

    func testFormatStatusOmitsCriticalSlowestWhenUnavailable() {
        let response = CLISocketResponse(
            id: "r-7b",
            success: true,
            data: [
                "version": "0.1.91",
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
        XCTAssertFalse(output.contains("critical slowest unknown"))
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

    func testFormatNotebookExportHTMLUsesServerSummary() {
        let response = CLISocketResponse(
            id: "notebook-2b",
            success: true,
            data: ["summary": "Exported notebook HTML to /tmp/result.html."],
            error: nil
        )

        let output = OutputFormatter.formatSuccess(
            command: .notebookExportHTML(
                inputPath: "/tmp/source.cocxynb",
                outputPath: "/tmp/result.html",
                force: false
            ),
            response: response
        )

        XCTAssertEqual(output, "Exported notebook HTML to /tmp/result.html.")
    }

    func testFormatNotebookTemplateCreateUsesServerSummary() {
        let response = CLISocketResponse(
            id: "notebook-template-1",
            success: true,
            data: ["summary": "Created notebook from template swift-script at /tmp/script.cocxynb."],
            error: nil
        )

        let output = OutputFormatter.formatSuccess(
            command: .notebookTemplateCreate(
                templateID: "swift-script",
                outputPath: "/tmp/script.cocxynb",
                force: false
            ),
            response: response
        )

        XCTAssertEqual(output, "Created notebook from template swift-script at /tmp/script.cocxynb.")
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
                sandbox: "workspace",
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

    func testClassifyCommandReturnsJSONWithoutServer() throws {
        let runner = CommandRunner(
            socketClient: SocketClient(socketPath: "/tmp/nonexistent.sock")
        )

        let result = runner.run(arguments: ["classify", "rm", "-rf", "/"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.isEmpty)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["category"] as? String, "dangerous-command")
        XCTAssertEqual(json["shouldWarnBeforeExecution"] as? Bool, true)
        XCTAssertNotNil(json["dangerReason"])
    }

    func testCorrectCommandReturnsJSONWithoutServer() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse(["correct", "gti", "status"]),
            .correct(input: "gti status")
        )

        let runner = CommandRunner(
            socketClient: SocketClient(socketPath: "/tmp/nonexistent.sock")
        )

        let result = runner.run(arguments: ["correct", "gti", "status"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.isEmpty)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["command"] as? String, "gti status")
        let suggestions = try XCTUnwrap(json["suggestions"] as? [[String: Any]])
        XCTAssertEqual(suggestions.first?["suggestion"] as? String, "git status")
    }

    func testSignatureCommandsRoundTripWithoutServer() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-cli-signature-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let payloadURL = tempDirectory.appendingPathComponent("template.json")
        try #"{"id":"demo"}"#.write(to: payloadURL, atomically: true, encoding: .utf8)
        let keyStore = SignatureKeychainStore(backend: MemorySignatureKeyValueStore())
        let registryURL = tempDirectory.appendingPathComponent("trusted-authors.json")
        let runner = CommandRunner(
            socketClient: SocketClient(socketPath: tempDirectory.appendingPathComponent("missing.sock").path),
            signatureKeyStore: keyStore,
            trustedAuthorRegistryURL: registryURL
        )

        let generate = runner.run(arguments: ["keys", "generate", "--author", "Cocxy"])
        XCTAssertEqual(generate.exitCode, 0, generate.stderr)
        let keyID = try XCTUnwrap(Self.jsonObject(from: generate.stdout)["keyID"] as? String)

        let sign = runner.run(arguments: [
            "sign", "template", payloadURL.path,
            "--key", keyID,
            "--author", "Cocxy",
        ])
        XCTAssertEqual(sign.exitCode, 0, sign.stderr)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: payloadURL.path + ".cocxy-signature.json"
        ))

        let verify = runner.run(arguments: ["verify", "template", payloadURL.path])
        XCTAssertEqual(verify.exitCode, 0, verify.stderr)
        XCTAssertEqual(try Self.jsonObject(from: verify.stdout)["status"] as? String, "valid")
    }

    func testBrowserActionTimeoutExtendsSocketDeadline() {
        let runner = CommandRunner(
            socketClient: SocketClient(socketPath: "/tmp/nonexistent.sock")
        )

        XCTAssertEqual(
            runner.socketClient(for: .browserClick(ref: "button-1")).timeoutSeconds,
            8
        )
        XCTAssertEqual(
            runner.socketClient(for: .browserClick(ref: "button-1", timeoutMilliseconds: 250)).timeoutSeconds,
            SocketClient.defaultTimeoutSeconds
        )
        XCTAssertEqual(
            runner.socketClient(for: .browserClick(ref: "button-1", timeoutMilliseconds: 60_000)).timeoutSeconds,
            63
        )

        let alreadyExtended = CommandRunner(
            socketClient: SocketClient(socketPath: "/tmp/nonexistent.sock", timeoutSeconds: 90)
        )
        XCTAssertEqual(
            alreadyExtended.socketClient(for: .browserClick(ref: "button-1", timeoutMilliseconds: 60_000)).timeoutSeconds,
            90
        )
    }

    func testCellCommandsExtendSocketDeadlineForCloudLifecycle() {
        let runner = CommandRunner(
            socketClient: SocketClient(socketPath: "/tmp/nonexistent.sock")
        )

        XCTAssertEqual(
            runner.socketClient(for: .cellCreate(.init(provider: "gcp"))).timeoutSeconds,
            300
        )
        XCTAssertEqual(
            runner.socketClient(for: .cellDestroy(cellID: "cell-1", provider: nil, force: true)).timeoutSeconds,
            300
        )

        let alreadyExtended = CommandRunner(
            socketClient: SocketClient(socketPath: "/tmp/nonexistent.sock", timeoutSeconds: 600)
        )
        XCTAssertEqual(
            alreadyExtended.socketClient(for: .cellCreate(.init(provider: "aws"))).timeoutSeconds,
            600
        )
    }

    private static func jsonObject(from text: String) throws -> [String: Any] {
        let data = Data(text.utf8)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
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
        XCTAssertEqual(CLICommand.allCases.count, 230)
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
        XCTAssertEqual(CLICommand.identify.rawValue, "identify")
        XCTAssertEqual(CLICommand.capabilities.rawValue, "capabilities")
        XCTAssertEqual(CLICommand.tmux.rawValue, "tmux")
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
        XCTAssertEqual(CLICommand.browserStateSave.usageExample, "cocxy browser state save <path>")
        XCTAssertEqual(CLICommand.browserStateLoad.usageExample, "cocxy browser state load <path>")
        XCTAssertEqual(CLICommand.browserEval.usageExample, "cocxy browser eval <script>")
        XCTAssertEqual(CLICommand.browserAddScript.usageExample, "cocxy browser add script <script>")
        XCTAssertEqual(CLICommand.browserAddStyle.usageExample, "cocxy browser add style <css>")
        XCTAssertEqual(CLICommand.browserInitScriptAdd.usageExample, "cocxy browser init scripts add <script>")
        XCTAssertEqual(CLICommand.browserInitScriptsList.usageExample, "cocxy browser init scripts list")
        XCTAssertEqual(CLICommand.browserDialogs.usageExample, "cocxy browser dialogs")
        XCTAssertEqual(CLICommand.browserDialogAccept.usageExample, "cocxy browser dialog accept [id] [--text <text>]")
        XCTAssertEqual(CLICommand.browserDialogDismiss.usageExample, "cocxy browser dialog dismiss [id]")
        XCTAssertEqual(CLICommand.browserGetText.usageExample, "cocxy browser text")
        XCTAssertEqual(CLICommand.browserListTabs.usageExample, "cocxy browser tabs")
        XCTAssertEqual(CLICommand.browserSnapshot.usageExample, "cocxy browser snapshot")
        XCTAssertEqual(
            CLICommand.browserContext.usageExample,
            "cocxy browser context [--target <ref>] [--around <n>] [--console <n>] [--network <n>]"
        )
        XCTAssertEqual(CLICommand.browserClick.usageExample, "cocxy browser click <ref> [--timeout <ms>]")
        XCTAssertEqual(CLICommand.browserDblClick.usageExample, "cocxy browser dblclick <ref> [--timeout <ms>]")
        XCTAssertEqual(CLICommand.browserHover.usageExample, "cocxy browser hover <ref> [--timeout <ms>]")
        XCTAssertEqual(CLICommand.browserFocus.usageExample, "cocxy browser focus <ref> [--timeout <ms>]")
        XCTAssertEqual(CLICommand.browserFill.usageExample, "cocxy browser fill <ref> <text> [--timeout <ms>]")
        XCTAssertEqual(CLICommand.browserUpload.usageExample, "cocxy browser upload <ref> <path> [--timeout <ms>]")
        XCTAssertEqual(CLICommand.browserType.usageExample, "cocxy browser type [ref] <text> [--timeout <ms>]")
        XCTAssertEqual(CLICommand.browserPress.usageExample, "cocxy browser press <key> [--timeout <ms>]")
        XCTAssertEqual(CLICommand.browserKeyDown.usageExample, "cocxy browser keydown <key> [--timeout <ms>]")
        XCTAssertEqual(CLICommand.browserKeyUp.usageExample, "cocxy browser keyup <key> [--timeout <ms>]")
        XCTAssertEqual(CLICommand.browserCheck.usageExample, "cocxy browser check <ref> [--timeout <ms>]")
        XCTAssertEqual(CLICommand.browserUncheck.usageExample, "cocxy browser uncheck <ref> [--timeout <ms>]")
        XCTAssertEqual(CLICommand.browserSelect.usageExample, "cocxy browser select <ref> <value> [--timeout <ms>]")
        XCTAssertEqual(CLICommand.browserScroll.usageExample, "cocxy browser scroll --x <px> --y <px> [--timeout <ms>]")
        XCTAssertEqual(CLICommand.browserScrollIntoView.usageExample, "cocxy browser scroll-into-view <ref> [--timeout <ms>]")
        XCTAssertEqual(CLICommand.browserGetHTML.usageExample, "cocxy browser get html [ref]")
        XCTAssertEqual(CLICommand.browserGetValue.usageExample, "cocxy browser get value <ref>")
        XCTAssertEqual(CLICommand.browserGetAttr.usageExample, "cocxy browser get attr <ref> <name>")
        XCTAssertEqual(CLICommand.browserGetTitle.usageExample, "cocxy browser get title")
        XCTAssertEqual(CLICommand.browserGetCount.usageExample, "cocxy browser get count <selector>")
        XCTAssertEqual(CLICommand.browserGetBox.usageExample, "cocxy browser get box <ref>")
        XCTAssertEqual(CLICommand.browserGetStyles.usageExample, "cocxy browser get styles <ref> [names...]")
        XCTAssertEqual(CLICommand.browserIsVisible.usageExample, "cocxy browser is visible <ref>")
        XCTAssertEqual(CLICommand.browserIsEnabled.usageExample, "cocxy browser is enabled <ref>")
        XCTAssertEqual(CLICommand.browserIsChecked.usageExample, "cocxy browser is checked <ref>")
        XCTAssertEqual(CLICommand.browserFindRole.usageExample, "cocxy browser find role <role> [name]")
        XCTAssertEqual(CLICommand.browserFindText.usageExample, "cocxy browser find text <text>")
        XCTAssertEqual(CLICommand.browserFindLabel.usageExample, "cocxy browser find label <text>")
        XCTAssertEqual(CLICommand.browserFindPlaceholder.usageExample, "cocxy browser find placeholder <text>")
        XCTAssertEqual(CLICommand.browserFindAlt.usageExample, "cocxy browser find alt <text>")
        XCTAssertEqual(CLICommand.browserFindTitle.usageExample, "cocxy browser find title <text>")
        XCTAssertEqual(CLICommand.browserFindTestID.usageExample, "cocxy browser find testid <id>")
        XCTAssertEqual(CLICommand.browserFindFirst.usageExample, "cocxy browser find first <selector>")
        XCTAssertEqual(CLICommand.browserFindLast.usageExample, "cocxy browser find last <selector>")
        XCTAssertEqual(CLICommand.browserFindNth.usageExample, "cocxy browser find nth <index> <selector>")
        XCTAssertEqual(CLICommand.browserScreenshot.usageExample, "cocxy browser screenshot [--output <path>]")
        XCTAssertEqual(CLICommand.browserConsole.usageExample, "cocxy browser console")
        XCTAssertEqual(CLICommand.browserWait.usageExample, "cocxy browser wait <selector> [--timeout <ms>]")
        XCTAssertEqual(CLICommand.browserCookiesList.usageExample, "cocxy browser cookies list")
        XCTAssertEqual(CLICommand.browserCookiesSet.usageExample, "cocxy browser cookies set <name> <value>")
        XCTAssertEqual(CLICommand.browserCookiesDelete.usageExample, "cocxy browser cookies delete <name>")
        XCTAssertEqual(CLICommand.browserNetwork.usageExample, "cocxy browser network [--filter <text>] [--tail <n>]")
        XCTAssertEqual(CLICommand.browserFrames.usageExample, "cocxy browser frames")
        XCTAssertEqual(CLICommand.browserDownloads.usageExample, "cocxy browser downloads")
        XCTAssertEqual(CLICommand.browserStorageList.usageExample, "cocxy browser storage list [--area local|session]")
        XCTAssertEqual(CLICommand.browserStorageGet.usageExample, "cocxy browser storage get <key> [--area local|session]")
        XCTAssertEqual(CLICommand.browserStorageSet.usageExample, "cocxy browser storage set <key> <value> [--area local|session]")
        XCTAssertEqual(CLICommand.browserStorageDelete.usageExample, "cocxy browser storage delete <key> [--area local|session]")
        XCTAssertEqual(CLICommand.browserImportPreview.usageExample, "cocxy browser import preview --source <browser>")
        XCTAssertEqual(CLICommand.browserImportRun.usageExample, "cocxy browser import run --source <browser>")

        guard case .browserNavigate(let url) = try CLIArgumentParser.parse(["browser", "navigate", "https://example.com"]) else {
            return XCTFail("browser navigate should parse through the public CLI shape")
        }
        XCTAssertEqual(url, "https://example.com")

        guard case .browserEval(let script) = try CLIArgumentParser.parse(["browser", "eval", "document.title"]) else {
            return XCTFail("browser eval should parse through the public CLI shape")
        }
        XCTAssertEqual(script, "document.title")

        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "add", "script", "window.ready", "=", "true"]),
            .browserAddScript(script: "window.ready = true")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "add", "style", "body", "{", "color:", "red;", "}"]),
            .browserAddStyle(css: "body { color: red; }")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "init", "scripts", "add", "window.ready", "=", "true"]),
            .browserInitScriptAdd(script: "window.ready = true")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "init", "scripts", "list"]),
            .browserInitScriptsList
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "dialogs"]),
            .browserDialogs
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "dialog", "accept", "dialog-1", "--text", "Cocxy", "Terminal"]),
            .browserDialogAccept(id: "dialog-1", promptText: "Cocxy Terminal")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "dialog", "dismiss"]),
            .browserDialogDismiss(id: nil)
        )

        XCTAssertNoThrow(try CLIArgumentParser.parse(["browser", "state"]))
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "state", "save", "/tmp/cocxy-state.json"]),
            .browserStateSave(path: "/tmp/cocxy-state.json")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "state", "load", "/tmp/cocxy-state.json"]),
            .browserStateLoad(path: "/tmp/cocxy-state.json")
        )
        XCTAssertNoThrow(try CLIArgumentParser.parse(["browser", "tabs"]))
        XCTAssertNoThrow(try CLIArgumentParser.parse(["browser", "text"]))
        XCTAssertNoThrow(try CLIArgumentParser.parse(["browser", "snapshot"]))
        XCTAssertEqual(
            try CLIArgumentParser.parse([
                "browser", "context",
                "--target", "card-1",
                "--around", "2",
                "--console", "5",
                "--network", "8",
            ]),
            .browserContext(targetRef: "card-1", around: 2, consoleTail: 5, networkTail: 8)
        )
        XCTAssertThrowsError(try CLIArgumentParser.parse(["browser", "context", "--around", "21"])) { error in
            XCTAssertEqual(error as? CLIError, .invalidArgument(
                command: "browser context",
                argument: "21",
                reason: "--around must be an integer between 0 and 20."
            ))
        }

        guard case .browserClick(let ref, let clickTimeout) = try CLIArgumentParser.parse(["browser", "click", "b1"]) else {
            return XCTFail("browser click should parse an element ref")
        }
        XCTAssertEqual(ref, "b1")
        XCTAssertNil(clickTimeout)
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "click", "b1", "--timeout", "1250"]),
            .browserClick(ref: "b1", timeoutMilliseconds: 1_250)
        )

        guard case .browserDblClick(let dblClickRef, let dblClickTimeout) = try CLIArgumentParser.parse(["browser", "dblclick", "b1"]) else {
            return XCTFail("browser dblclick should parse an element ref")
        }
        XCTAssertEqual(dblClickRef, "b1")
        XCTAssertNil(dblClickTimeout)

        guard case .browserHover(let hoverRef, let hoverTimeout) = try CLIArgumentParser.parse(["browser", "hover", "b1"]) else {
            return XCTFail("browser hover should parse an element ref")
        }
        XCTAssertEqual(hoverRef, "b1")
        XCTAssertNil(hoverTimeout)

        guard case .browserFocus(let focusRef, let focusTimeout) = try CLIArgumentParser.parse(["browser", "focus", "i1"]) else {
            return XCTFail("browser focus should parse an element ref")
        }
        XCTAssertEqual(focusRef, "i1")
        XCTAssertNil(focusTimeout)

        guard case .browserFill(let ref, let text, let fillTimeout) = try CLIArgumentParser.parse(["browser", "fill", "i1", "hello", "world"]) else {
            return XCTFail("browser fill should parse an element ref and text")
        }
        XCTAssertEqual(ref, "i1")
        XCTAssertEqual(text, "hello world")
        XCTAssertNil(fillTimeout)
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "fill", "i1", "hello", "world", "--timeout", "2500"]),
            .browserFill(ref: "i1", text: "hello world", timeoutMilliseconds: 2_500)
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "fill", "i1", "--timeout", "2500", "--", "hello", "--timeout", "literal"]),
            .browserFill(ref: "i1", text: "hello --timeout literal", timeoutMilliseconds: 2_500)
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "upload", "file-1", "/tmp/cocxy-upload.txt", "--timeout", "3000"]),
            .browserUpload(ref: "file-1", path: "/tmp/cocxy-upload.txt", timeoutMilliseconds: 3_000)
        )

        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "type", "i1", "hello", "world"]),
            .browserType(ref: "i1", text: "hello world")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "type", "--", "hello", "world"]),
            .browserType(ref: nil, text: "hello world")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "type", "--timeout", "1750", "--", "hello", "world"]),
            .browserType(ref: nil, text: "hello world", timeoutMilliseconds: 1_750)
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "type", "--", "hello", "--timeout", "literal"]),
            .browserType(ref: nil, text: "hello --timeout literal")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "press", "Enter", "--timeout", "1200"]),
            .browserPress(key: "Enter", timeoutMilliseconds: 1_200)
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "keydown", "Shift"]),
            .browserKeyDown(key: "Shift")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "keyup", "Shift"]),
            .browserKeyUp(key: "Shift")
        )

        guard case .browserCheck(let checkRef, let checkTimeout) = try CLIArgumentParser.parse(["browser", "check", "agree-1"]) else {
            return XCTFail("browser check should parse an element ref")
        }
        XCTAssertEqual(checkRef, "agree-1")
        XCTAssertNil(checkTimeout)

        guard case .browserUncheck(let uncheckRef, let uncheckTimeout) = try CLIArgumentParser.parse(["browser", "uncheck", "agree-1"]) else {
            return XCTFail("browser uncheck should parse an element ref")
        }
        XCTAssertEqual(uncheckRef, "agree-1")
        XCTAssertNil(uncheckTimeout)

        guard case .browserSelect(let selectRef, let selectValue, let selectTimeout) = try CLIArgumentParser.parse([
            "browser", "select", "country-1", "Honduras"
        ]) else {
            return XCTFail("browser select should parse an element ref and option value")
        }
        XCTAssertEqual(selectRef, "country-1")
        XCTAssertEqual(selectValue, "Honduras")
        XCTAssertNil(selectTimeout)
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "select", "country-1", "Honduras", "--timeout", "2200"]),
            .browserSelect(ref: "country-1", value: "Honduras", timeoutMilliseconds: 2_200)
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse([
                "browser", "select", "country-1", "--timeout", "2200", "--", "Honduras", "--timeout", "literal"
            ]),
            .browserSelect(ref: "country-1", value: "Honduras --timeout literal", timeoutMilliseconds: 2_200)
        )

        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "scroll", "--x", "120", "--y", "-24", "--timeout", "1500"]),
            .browserScroll(x: 120, y: -24, timeoutMilliseconds: 1_500)
        )
        XCTAssertThrowsError(try CLIArgumentParser.parse(["browser", "click", "b1", "--timeout", "99"])) { error in
            XCTAssertEqual(error as? CLIError, .invalidArgument(
                command: "browser click",
                argument: "99",
                reason: "Timeout must be milliseconds between 100 and 60000."
            ))
        }
        XCTAssertThrowsError(try CLIArgumentParser.parse(["browser", "click", "b1", "--timeout"])) { error in
            XCTAssertEqual(error as? CLIError, .missingArgument(command: "browser click", argument: "timeout"))
        }
        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "browser", "scroll", "--x", "120", "--y", "-24", "--timeout", "60001"
        ])) { error in
            XCTAssertEqual(error as? CLIError, .invalidArgument(
                command: "browser scroll",
                argument: "60001",
                reason: "Timeout must be milliseconds between 100 and 60000."
            ))
        }

        guard case .browserScrollIntoView(let scrollRef, let scrollIntoViewTimeout) = try CLIArgumentParser.parse([
            "browser", "scroll-into-view", "footer-1"
        ]) else {
            return XCTFail("browser scroll-into-view should parse an element ref")
        }
        XCTAssertEqual(scrollRef, "footer-1")
        XCTAssertNil(scrollIntoViewTimeout)

        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "get", "html"]),
            .browserGetHTML(ref: nil)
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "get", "html", "card-1"]),
            .browserGetHTML(ref: "card-1")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "get", "value", "i1"]),
            .browserGetValue(ref: "i1")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "get", "attr", "link-1", "href"]),
            .browserGetAttr(ref: "link-1", name: "href")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "get", "title"]),
            .browserGetTitle
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "get", "count", ".item"]),
            .browserGetCount(selector: ".item")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "get", "box", "card-1"]),
            .browserGetBox(ref: "card-1")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "get", "styles", "card-1", "color", "display"]),
            .browserGetStyles(ref: "card-1", names: ["color", "display"])
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "is", "visible", "card-1"]),
            .browserIsVisible(ref: "card-1")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "is", "enabled", "button-1"]),
            .browserIsEnabled(ref: "button-1")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "is", "checked", "agree-1"]),
            .browserIsChecked(ref: "agree-1")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "find", "role", "button", "Save"]),
            .browserFindRole(role: "button", name: "Save")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "find", "text", "Deploy", "now"]),
            .browserFindText(text: "Deploy now")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "find", "label", "Email"]),
            .browserFindLabel(text: "Email")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "find", "placeholder", "Search"]),
            .browserFindPlaceholder(text: "Search")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "find", "alt", "Logo"]),
            .browserFindAlt(text: "Logo")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "find", "title", "Help"]),
            .browserFindTitle(text: "Help")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "find", "testid", "submit-button"]),
            .browserFindTestID(id: "submit-button")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "find", "first", ".row"]),
            .browserFindFirst(selector: ".row")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "find", "last", ".row"]),
            .browserFindLast(selector: ".row")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "find", "nth", "1", ".row"]),
            .browserFindNth(index: 1, selector: ".row")
        )

        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "screenshot", "--output", "/tmp/page.png"]),
            .browserScreenshot(outputPath: "/tmp/page.png")
        )
        XCTAssertNoThrow(try CLIArgumentParser.parse(["browser", "console"]))

        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "wait", "#ready", "--timeout", "1500"]),
            .browserWait(selector: "#ready", timeoutMilliseconds: 1500)
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "cookies", "list", "--domain", "example.com"]),
            .browserCookiesList(domain: "example.com")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse([
                "browser", "cookies", "set", "sid", "abc",
                "--path", "/",
                "--same-site", "Lax",
                "--max-age", "3600",
            ]),
            .browserCookiesSet(BrowserCookieSetCLIOptions(
                name: "sid",
                value: "abc",
                path: "/",
                sameSite: "Lax",
                maxAgeSeconds: 3600
            ))
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "cookies", "delete", "sid", "--path", "/"]),
            .browserCookiesDelete(name: "sid", path: "/", domain: nil)
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "network", "--filter", "api", "--tail", "10"]),
            .browserNetwork(filter: "api", tail: 10)
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "frames"]),
            .browserFrames
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "downloads"]),
            .browserDownloads
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "storage", "list"]),
            .browserStorageList(area: .local)
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "storage", "list", "--area", "session"]),
            .browserStorageList(area: .session)
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "storage", "get", "draft", "--area", "session"]),
            .browserStorageGet(area: .session, key: "draft")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "storage", "set", "theme", "dark", "--area", "local"]),
            .browserStorageSet(area: .local, key: "theme", value: "dark")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["browser", "storage", "delete", "theme"]),
            .browserStorageDelete(area: .local, key: "theme")
        )

        guard case .browserImportPreview(let previewOptions) = try CLIArgumentParser.parse([
            "browser", "import", "preview",
            "--source", "chrome",
            "--history", "/tmp/History",
            "--cookies", "/tmp/Cookies",
            "--domain", "example.com",
            "--no-bookmarks",
        ]) else {
            return XCTFail("browser import preview should parse import options")
        }
        XCTAssertEqual(previewOptions.source, "chrome")
        XCTAssertEqual(previewOptions.historyPath, "/tmp/History")
        XCTAssertEqual(previewOptions.cookiesPath, "/tmp/Cookies")
        XCTAssertEqual(previewOptions.domainWhitelist, ["example.com"])
        XCTAssertFalse(previewOptions.importBookmarks)

        guard case .browserImportRun(let runOptions) = try CLIArgumentParser.parse([
            "browser", "import", "run",
            "--source", "firefox",
            "--profile", "00000000-0000-0000-0000-000000000001",
            "--max-history-days", "7",
            "--exclude-domain", "blocked.example",
        ]) else {
            return XCTFail("browser import run should parse import options")
        }
        XCTAssertEqual(runOptions.source, "firefox")
        XCTAssertEqual(runOptions.profileID, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(runOptions.maxHistoryDays, 7)
        XCTAssertEqual(runOptions.domainBlacklist, ["blocked.example"])
    }

    func testRemoteUsageExamplesMatchPublicParserShape() throws {
        XCTAssertEqual(CLICommand.remoteList.usageExample, "cocxy remote list [--group <group>]")
        XCTAssertEqual(CLICommand.remoteConnect.usageExample, "cocxy remote connect <name-or-uuid>")
        XCTAssertEqual(CLICommand.remoteDisconnect.usageExample, "cocxy remote disconnect <name-or-uuid>")
        XCTAssertEqual(CLICommand.remoteStatus.usageExample, "cocxy remote status [<name-or-uuid>]")
        XCTAssertEqual(CLICommand.remoteTunnels.usageExample, "cocxy remote tunnels [--profile <name>]")

        XCTAssertEqual(try CLIArgumentParser.parse(["remote", "list"]), .remoteList)
        XCTAssertEqual(try CLIArgumentParser.parse(["remote", "connect", "prod-web"]), .remoteConnect(name: "prod-web"))
        XCTAssertEqual(try CLIArgumentParser.parse(["remote", "disconnect", "prod-web"]), .remoteDisconnect(name: "prod-web"))
        XCTAssertEqual(try CLIArgumentParser.parse(["remote", "status"]), .remoteStatus(name: nil))
        XCTAssertEqual(try CLIArgumentParser.parse(["remote", "status", "prod-web"]), .remoteStatus(name: "prod-web"))
        XCTAssertEqual(try CLIArgumentParser.parse(["remote", "tunnels"]), .remoteTunnels(profile: nil))
        XCTAssertEqual(try CLIArgumentParser.parse(["remote", "tunnels", "--profile", "prod-web"]), .remoteTunnels(profile: "prod-web"))

        let help = CLIArgumentParser.helpText()
        XCTAssertTrue(help.contains("cocxy remote list"))
        XCTAssertTrue(help.contains("cocxy remote connect"))
        XCTAssertTrue(help.contains("cocxy remote status"))
        XCTAssertFalse(help.contains("cocxy remote-list"))
        XCTAssertFalse(help.contains("cocxy remote-connect"))
        XCTAssertFalse(help.contains("cocxy remote-status"))
    }

    func testBrowserStorageParserRejectsInvalidArguments() {
        XCTAssertThrowsError(try CLIArgumentParser.parse(["browser", "storage", "get"])) { error in
            XCTAssertEqual(error as? CLIError, .missingArgument(command: "browser storage get", argument: "key"))
        }
        XCTAssertThrowsError(try CLIArgumentParser.parse(["browser", "storage", "get", "draft", "extra"])) { error in
            XCTAssertEqual(error as? CLIError, .invalidArgument(
                command: "browser storage get",
                argument: "extra",
                reason: "Use exactly one key."
            ))
        }
        XCTAssertThrowsError(try CLIArgumentParser.parse(["browser", "storage", "delete", "draft", "extra"])) { error in
            XCTAssertEqual(error as? CLIError, .invalidArgument(
                command: "browser storage delete",
                argument: "extra",
                reason: "Use exactly one key."
            ))
        }
        XCTAssertThrowsError(try CLIArgumentParser.parse(["browser", "storage", "list", "--area", "memory"])) { error in
            XCTAssertEqual(error as? CLIError, .invalidArgument(
                command: "browser storage list",
                argument: "memory",
                reason: "Area must be local or session."
            ))
        }
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
