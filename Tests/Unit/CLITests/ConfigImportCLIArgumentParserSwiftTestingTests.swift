// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ConfigImportCLIArgumentParserSwiftTestingTests.swift - Import config CLI contract coverage.

import XCTest
@testable import CocxyCLILib

final class ConfigImportCLIArgumentParserSwiftTestingTests: XCTestCase {
    private let runner = CommandRunner(socketClient: SocketClient(socketPath: "/tmp/test.sock"))

    func testImportConfigParsesDryRunAndBuildsSocketRequest() throws {
        let parsed = try CLIArgumentParser.parse([
            "import-config",
            "--from", "ghostty",
            "--path", "/tmp/ghostty/config",
            "--dry-run",
        ])

        XCTAssertEqual(
            parsed,
            .importConfig(ConfigImportCLIOptions(
                source: "ghostty",
                path: "/tmp/ghostty/config",
                dryRun: true,
                backup: false
            ))
        )

        let request = runner.buildRequest(from: parsed)
        XCTAssertEqual(request.command, "import-config")
        XCTAssertEqual(request.params?["source"], "ghostty")
        XCTAssertEqual(request.params?["path"], "/tmp/ghostty/config")
        XCTAssertEqual(request.params?["dry-run"], "true")
        XCTAssertEqual(request.params?["backup"], "false")
    }

    func testImportConfigParsesApplyWithBackup() throws {
        let parsed = try CLIArgumentParser.parse([
            "import-config",
            "--source", "kitty",
            "--path", "/tmp/kitty.conf",
            "--apply",
            "--backup",
        ])

        XCTAssertEqual(
            parsed,
            .importConfig(ConfigImportCLIOptions(
                source: "kitty",
                path: "/tmp/kitty.conf",
                dryRun: false,
                backup: true
            ))
        )

        let request = runner.buildRequest(from: parsed)
        XCTAssertEqual(request.params?["dry-run"], "false")
        XCTAssertEqual(request.params?["backup"], "true")
    }

    func testImportConfigRequiresSourceAndPath() {
        XCTAssertThrowsError(try CLIArgumentParser.parse(["import-config", "--path", "/tmp/config"])) { error in
            XCTAssertEqual(error as? CLIError, .missingArgument(command: "import-config", argument: "--from <source>"))
        }

        XCTAssertThrowsError(try CLIArgumentParser.parse(["import-config", "--from", "ghostty"])) { error in
            XCTAssertEqual(error as? CLIError, .missingArgument(command: "import-config", argument: "--path <path>"))
        }
    }
}
