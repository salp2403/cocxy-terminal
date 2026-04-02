// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CLICommandTests.swift - Tests for CLI argument parsing, request building, and output formatting.

import XCTest
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
        XCTAssertEqual(result, .newTab(directory: nil))
    }

    func testNewTabWithDirectory() throws {
        let result = try CLIArgumentParser.parse(["new-tab", "--dir", "/tmp/project"])
        XCTAssertEqual(result, .newTab(directory: "/tmp/project"))
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
    }

    // MARK: - 13. Version text

    func testVersionTextContainsVersionNumber() {
        let versionText = CLIArgumentParser.versionText()
        XCTAssertEqual(versionText, "cocxy 0.1.0-alpha")
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
        let request = runner.buildRequest(from: .newTab(directory: nil))

        XCTAssertEqual(request.command, "new-tab")
        XCTAssertNil(request.params)
    }

    // MARK: - 16. New-tab request with directory

    func testBuildNewTabRequestWithDirectory() {
        let request = runner.buildRequest(from: .newTab(directory: "/tmp"))

        XCTAssertEqual(request.command, "new-tab")
        XCTAssertEqual(request.params?["directory"], "/tmp")
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
        XCTAssertEqual(request.params?["direction"], "h")
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
            command: .newTab(directory: nil),
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
        XCTAssertEqual(result.stdout, "cocxy 0.1.0-alpha")
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

    // MARK: - 43. All commands exist (10 original + 21 v2 + 8 browser + 5 remote + 3 plugin + 18 v3 = 65)

    func testAllCommandsExist() {
        XCTAssertEqual(CLICommand.allCases.count, 65)
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
