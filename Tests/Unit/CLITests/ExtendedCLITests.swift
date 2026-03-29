// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ExtendedCLITests.swift - Tests for extended CLI commands (T-077/T-078).

import XCTest
@testable import CocxyCLILib

// MARK: - Tab Extended Commands Tests

/// Tests for `tab rename` and `tab move` parsing and request building.
final class TabExtendedCommandTests: XCTestCase {

    private let runner = CommandRunner(
        socketClient: SocketClient(socketPath: "/tmp/test.sock")
    )

    // MARK: - 1. Tab rename parses correctly

    func testTabRenameWithIDAndNameParsesCorrectly() throws {
        let result = try CLIArgumentParser.parse(["tab", "rename", "abc-123", "My Tab"])
        XCTAssertEqual(result, .tabRename(id: "abc-123", name: "My Tab"))
    }

    // MARK: - 2. Tab rename without name throws error

    func testTabRenameWithoutNameThrowsMissingArgument() {
        XCTAssertThrowsError(
            try CLIArgumentParser.parse(["tab", "rename", "abc-123"])
        ) { error in
            guard let cliError = error as? CLIError else {
                XCTFail("Expected CLIError, got \(error)")
                return
            }
            XCTAssertEqual(
                cliError,
                .missingArgument(command: "tab rename", argument: "name")
            )
        }
    }

    // MARK: - 3. Tab rename builds correct request

    func testTabRenameBuildRequest() {
        let request = runner.buildRequest(from: .tabRename(id: "abc-123", name: "My Tab"))
        XCTAssertEqual(request.command, "tab-rename")
        XCTAssertEqual(request.params?["id"], "abc-123")
        XCTAssertEqual(request.params?["name"], "My Tab")
    }

    // MARK: - 4. Tab move parses correctly

    func testTabMoveWithIDAndPositionParsesCorrectly() throws {
        let result = try CLIArgumentParser.parse(["tab", "move", "abc-123", "3"])
        XCTAssertEqual(result, .tabMove(id: "abc-123", position: "3"))
    }

    // MARK: - 5. Tab move builds correct request

    func testTabMoveBuildRequest() {
        let request = runner.buildRequest(from: .tabMove(id: "abc-123", position: "3"))
        XCTAssertEqual(request.command, "tab-move")
        XCTAssertEqual(request.params?["id"], "abc-123")
        XCTAssertEqual(request.params?["position"], "3")
    }
}

// MARK: - Split Extended Commands Tests

/// Tests for extended split commands: list, focus, close, resize.
final class SplitExtendedCommandTests: XCTestCase {

    private let runner = CommandRunner(
        socketClient: SocketClient(socketPath: "/tmp/test.sock")
    )

    // MARK: - 6. Split list parses correctly

    func testSplitListParsesCorrectly() throws {
        let result = try CLIArgumentParser.parse(["split", "list"])
        XCTAssertEqual(result, .splitList)
    }

    // MARK: - 7. Split focus with valid direction

    func testSplitFocusWithValidDirectionParsesCorrectly() throws {
        let result = try CLIArgumentParser.parse(["split", "focus", "left"])
        XCTAssertEqual(result, .splitFocus(direction: "left"))
    }

    // MARK: - 8. Split close parses correctly

    func testSplitCloseParsesCorrectly() throws {
        let result = try CLIArgumentParser.parse(["split", "close"])
        XCTAssertEqual(result, .splitClose)
    }

    // MARK: - 9. Split resize with direction and pixels

    func testSplitResizeParsesCorrectly() throws {
        let result = try CLIArgumentParser.parse(["split", "resize", "right", "50"])
        XCTAssertEqual(result, .splitResize(direction: "right", pixels: "50"))
    }

    // MARK: - 10. Split list builds correct request

    func testSplitListBuildRequest() {
        let request = runner.buildRequest(from: .splitList)
        XCTAssertEqual(request.command, "split-list")
        XCTAssertNil(request.params)
    }

    // MARK: - 11. Split focus builds correct request

    func testSplitFocusBuildRequest() {
        let request = runner.buildRequest(from: .splitFocus(direction: "up"))
        XCTAssertEqual(request.command, "split-focus")
        XCTAssertEqual(request.params?["direction"], "up")
    }
}

// MARK: - Dashboard Commands Tests

/// Tests for dashboard commands: show, hide, toggle, status.
final class DashboardCommandTests: XCTestCase {

    private let runner = CommandRunner(
        socketClient: SocketClient(socketPath: "/tmp/test.sock")
    )

    // MARK: - 12. Dashboard show/hide/toggle all parse correctly

    func testDashboardShowHideToggleParseCorrectly() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse(["dashboard", "show"]),
            .dashboardShow
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["dashboard", "hide"]),
            .dashboardHide
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["dashboard", "toggle"]),
            .dashboardToggle
        )
    }

    // MARK: - 13. Dashboard status parses correctly

    func testDashboardStatusParsesCorrectly() throws {
        let result = try CLIArgumentParser.parse(["dashboard", "status"])
        XCTAssertEqual(result, .dashboardStatus)
    }

    // MARK: - 14. Dashboard show builds valid request

    func testDashboardShowBuildRequest() {
        let request = runner.buildRequest(from: .dashboardShow)
        XCTAssertEqual(request.command, "dashboard-show")
        XCTAssertNil(request.params)
    }

    // MARK: - 15. Dashboard commands produce valid success messages

    func testDashboardCommandsFormatSuccess() {
        let response = CLISocketResponse(
            id: "r-1", success: true, data: nil, error: nil
        )
        XCTAssertEqual(
            OutputFormatter.formatSuccess(command: .dashboardShow, response: response),
            "Dashboard shown."
        )
        XCTAssertEqual(
            OutputFormatter.formatSuccess(command: .dashboardHide, response: response),
            "Dashboard hidden."
        )
        XCTAssertEqual(
            OutputFormatter.formatSuccess(command: .dashboardToggle, response: response),
            "Dashboard toggled."
        )
    }
}

// MARK: - Timeline Commands Tests

/// Tests for timeline commands: show, export.
final class TimelineCommandTests: XCTestCase {

    private let runner = CommandRunner(
        socketClient: SocketClient(socketPath: "/tmp/test.sock")
    )

    // MARK: - 16. Timeline show parses tab ID correctly

    func testTimelineShowParsesTabIDCorrectly() throws {
        let result = try CLIArgumentParser.parse(["timeline", "show", "tab-uuid-1"])
        XCTAssertEqual(result, .timelineShow(tabID: "tab-uuid-1"))
    }

    // MARK: - 17. Timeline export supports json and md formats

    func testTimelineExportSupportsFormats() throws {
        let resultJSON = try CLIArgumentParser.parse(
            ["timeline", "export", "tab-uuid-1", "--format", "json"]
        )
        XCTAssertEqual(
            resultJSON,
            .timelineExport(tabID: "tab-uuid-1", format: "json")
        )

        let resultMD = try CLIArgumentParser.parse(
            ["timeline", "export", "tab-uuid-1", "--format", "md"]
        )
        XCTAssertEqual(
            resultMD,
            .timelineExport(tabID: "tab-uuid-1", format: "md")
        )
    }

    // MARK: - 18. Timeline show builds correct request

    func testTimelineShowBuildRequest() {
        let request = runner.buildRequest(from: .timelineShow(tabID: "tab-uuid-1"))
        XCTAssertEqual(request.command, "timeline-show")
        XCTAssertEqual(request.params?["tabId"], "tab-uuid-1")
    }
}

// MARK: - Search Commands Tests

/// Tests for search commands: query with flags.
final class SearchCommandTests: XCTestCase {

    private let runner = CommandRunner(
        socketClient: SocketClient(socketPath: "/tmp/test.sock")
    )

    // MARK: - 19. Search parses query with flags

    func testSearchParsesQueryWithFlags() throws {
        let result = try CLIArgumentParser.parse(
            ["search", "error", "--regex", "--case-sensitive"]
        )
        XCTAssertEqual(
            result,
            .search(
                query: "error",
                regex: true,
                caseSensitive: true,
                tabID: nil
            )
        )
    }

    // MARK: - 20. Search with --tab flag

    func testSearchWithTabFlag() throws {
        let result = try CLIArgumentParser.parse(
            ["search", "--tab", "tab-1", "pattern"]
        )
        XCTAssertEqual(
            result,
            .search(
                query: "pattern",
                regex: false,
                caseSensitive: false,
                tabID: "tab-1"
            )
        )
    }

    // MARK: - 21. Search builds correct request

    func testSearchBuildRequest() {
        let request = runner.buildRequest(from: .search(
            query: "error",
            regex: true,
            caseSensitive: false,
            tabID: "tab-1"
        ))
        XCTAssertEqual(request.command, "search")
        XCTAssertEqual(request.params?["query"], "error")
        XCTAssertEqual(request.params?["regex"], "true")
        XCTAssertEqual(request.params?["caseSensitive"], "false")
        XCTAssertEqual(request.params?["tabId"], "tab-1")
    }
}

// MARK: - Config Commands Tests

/// Tests for config commands: get, set, path.
final class ConfigCommandTests: XCTestCase {

    private let runner = CommandRunner(
        socketClient: SocketClient(socketPath: "/tmp/test.sock")
    )

    // MARK: - 22. Config get/set/path all parse correctly

    func testConfigGetSetPathParseCorrectly() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse(["config", "get", "font.size"]),
            .configGet(key: "font.size")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["config", "set", "font.size", "14"]),
            .configSet(key: "font.size", value: "14")
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["config", "path"]),
            .configPath
        )
    }

    // MARK: - 23. Config get builds correct request

    func testConfigGetBuildRequest() {
        let request = runner.buildRequest(from: .configGet(key: "font.size"))
        XCTAssertEqual(request.command, "config-get")
        XCTAssertEqual(request.params?["key"], "font.size")
    }

    // MARK: - 24. Config set builds correct request

    func testConfigSetBuildRequest() {
        let request = runner.buildRequest(from: .configSet(key: "font.size", value: "14"))
        XCTAssertEqual(request.command, "config-set")
        XCTAssertEqual(request.params?["key"], "font.size")
        XCTAssertEqual(request.params?["value"], "14")
    }
}

// MARK: - Theme Commands Tests

/// Tests for theme commands: list, set.
final class ThemeCommandTests: XCTestCase {

    private let runner = CommandRunner(
        socketClient: SocketClient(socketPath: "/tmp/test.sock")
    )

    // MARK: - 25. Theme list and set parse correctly

    func testThemeListAndSetParseCorrectly() throws {
        XCTAssertEqual(
            try CLIArgumentParser.parse(["theme", "list"]),
            .themeList
        )
        XCTAssertEqual(
            try CLIArgumentParser.parse(["theme", "set", "dracula"]),
            .themeSet(name: "dracula")
        )
    }

    // MARK: - 26. Theme set builds correct request

    func testThemeSetBuildRequest() {
        let request = runner.buildRequest(from: .themeSet(name: "dracula"))
        XCTAssertEqual(request.command, "theme-set")
        XCTAssertEqual(request.params?["name"], "dracula")
    }

    // MARK: - 27. Theme list builds correct request

    func testThemeListBuildRequest() {
        let request = runner.buildRequest(from: .themeList)
        XCTAssertEqual(request.command, "theme-list")
        XCTAssertNil(request.params)
    }
}

// MARK: - System Commands Tests

/// Tests for system commands: version, send, send-key.
final class SystemCommandTests: XCTestCase {

    private let runner = CommandRunner(
        socketClient: SocketClient(socketPath: "/tmp/test.sock")
    )

    // MARK: - 28. Send parses text correctly

    func testSendParsesTextCorrectly() throws {
        let result = try CLIArgumentParser.parse(["send", "hello world"])
        XCTAssertEqual(result, .send(text: "hello world"))
    }

    // MARK: - 29. Send-key parses key correctly

    func testSendKeyParsesKeyCorrectly() throws {
        let result = try CLIArgumentParser.parse(["send-key", "ctrl+c"])
        XCTAssertEqual(result, .sendKey(key: "ctrl+c"))
    }

    // MARK: - 30. Send builds correct request

    func testSendBuildRequest() {
        let request = runner.buildRequest(from: .send(text: "hello"))
        XCTAssertEqual(request.command, "send")
        XCTAssertEqual(request.params?["text"], "hello")
    }

    // MARK: - 31. Send-key builds correct request

    func testSendKeyBuildRequest() {
        let request = runner.buildRequest(from: .sendKey(key: "ctrl+c"))
        XCTAssertEqual(request.command, "send-key")
        XCTAssertEqual(request.params?["key"], "ctrl+c")
    }
}

// MARK: - Extended CLI Error Tests

/// Tests for error handling on extended commands.
final class ExtendedCLIErrorTests: XCTestCase {

    // MARK: - 32. Unknown subcommand under tab throws error

    func testUnknownTabSubcommandThrowsError() {
        XCTAssertThrowsError(
            try CLIArgumentParser.parse(["tab", "destroy"])
        ) { error in
            guard let cliError = error as? CLIError else {
                XCTFail("Expected CLIError, got \(error)")
                return
            }
            if case .invalidArgument(let command, let argument, _) = cliError {
                XCTAssertEqual(command, "tab")
                XCTAssertEqual(argument, "destroy")
            } else {
                XCTFail("Expected .invalidArgument, got \(cliError)")
            }
        }
    }

    // MARK: - 33. Unknown subcommand under dashboard throws error

    func testUnknownDashboardSubcommandThrowsError() {
        XCTAssertThrowsError(
            try CLIArgumentParser.parse(["dashboard", "explode"])
        ) { error in
            guard let cliError = error as? CLIError else {
                XCTFail("Expected CLIError, got \(error)")
                return
            }
            if case .invalidArgument(let command, let argument, _) = cliError {
                XCTAssertEqual(command, "dashboard")
                XCTAssertEqual(argument, "explode")
            } else {
                XCTFail("Expected .invalidArgument, got \(cliError)")
            }
        }
    }
}

// MARK: - Enum Parity Tests

/// Tests that CLICommand and CLICommandName have matching cases.
final class EnumParityTests: XCTestCase {

    // MARK: - 34. CLICommand has all expected cases (10 original + 20 new + 8 browser + 5 remote = 43)

    func testCLICommandHasExpectedCaseCount() {
        XCTAssertEqual(CLICommand.allCases.count, 44)
    }

    // MARK: - 35. All CLICommand cases have non-empty helpDescription

    func testAllExtendedCommandsHaveHelpDescriptions() {
        for command in CLICommand.allCases {
            XCTAssertFalse(
                command.helpDescription.isEmpty,
                "\(command) should have a help description"
            )
        }
    }

    // MARK: - 36. All CLICommand cases have usage examples starting with cocxy

    func testAllExtendedCommandsHaveUsageExamples() {
        for command in CLICommand.allCases {
            XCTAssertTrue(
                command.usageExample.hasPrefix("cocxy"),
                "\(command) usage example should start with 'cocxy', got: \(command.usageExample)"
            )
        }
    }

    // MARK: - 37. Extended help text contains new commands

    func testHelpTextContainsExtendedCommands() {
        let helpText = CLIArgumentParser.helpText()

        // Spot check a few new commands
        XCTAssertTrue(helpText.contains("tab rename"), "Help should mention tab rename")
        XCTAssertTrue(helpText.contains("dashboard"), "Help should mention dashboard")
        XCTAssertTrue(helpText.contains("timeline"), "Help should mention timeline")
        XCTAssertTrue(helpText.contains("search"), "Help should mention search")
        XCTAssertTrue(helpText.contains("config"), "Help should mention config")
        XCTAssertTrue(helpText.contains("theme"), "Help should mention theme")
        XCTAssertTrue(helpText.contains("send"), "Help should mention send")
    }
}

// MARK: - Output Formatter Extended Tests

/// Tests for output formatting of extended commands.
final class ExtendedOutputFormatterTests: XCTestCase {

    // MARK: - 38. Tab rename success message

    func testFormatTabRenameSuccess() {
        let response = CLISocketResponse(
            id: "r-1", success: true, data: nil, error: nil
        )
        let output = OutputFormatter.formatSuccess(
            command: .tabRename(id: "abc", name: "New"),
            response: response
        )
        XCTAssertEqual(output, "Tab renamed.")
    }

    // MARK: - 39. Split list formats JSON output

    func testFormatSplitListSuccess() {
        let response = CLISocketResponse(
            id: "r-2", success: true,
            data: ["splits": "[{\"id\":\"s1\",\"direction\":\"h\"}]"],
            error: nil
        )
        let output = OutputFormatter.formatSuccess(
            command: .splitList,
            response: response
        )
        // Should contain formatted JSON
        XCTAssertTrue(output.contains("s1"))
    }

    // MARK: - 40. Config path success message

    func testFormatConfigPathSuccess() {
        let response = CLISocketResponse(
            id: "r-3", success: true,
            data: ["path": "~/.config/cocxy/config.toml"],
            error: nil
        )
        let output = OutputFormatter.formatSuccess(
            command: .configPath,
            response: response
        )
        XCTAssertTrue(output.contains("config.toml"))
    }
}
