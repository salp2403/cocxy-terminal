// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Phase11CLIEdgeCaseTests.swift - CLI edge cases for Phase 11 (T-079).
//
// Edge cases covered (6 tests in CocxyCLITests target):
// EC-07  Unknown subcommand for `tab` -> CLIError.invalidArgument.
// EC-08  `dashboard status` parse -> .dashboardStatus (valid empty-data scenario).
// EC-09  `theme set` with missing name argument -> CLIError.missingArgument.
// EC-10  `config get` without key argument -> CLIError.missingArgument.
// EC-11  `version` text is non-empty and starts with "cocxy".
// EC-12  All 30 CLICommand cases have non-empty helpDescription.

import XCTest
@testable import CocxyCLILib

final class Phase11CLIEdgeCaseTests: XCTestCase {

    // MARK: - EC-07: Unknown subcommand for `tab` -> CLIError.invalidArgument

    func testEC07_UnknownTabSubcommandThrowsInvalidArgument() {
        // "Funciona con subcommands validos, pero que pasa si le meto uno que no existe?"
        XCTAssertThrowsError(
            try CLIArgumentParser.parse(["tab", "unknown-subcommand"])
        ) { error in
            guard let cliError = error as? CLIError else {
                XCTFail("EC-07: Expected CLIError, got \(type(of: error)): \(error)")
                return
            }
            if case .invalidArgument(let command, let argument, _) = cliError {
                XCTAssertEqual(command, "tab",
                               "EC-07: error command must be 'tab'")
                XCTAssertEqual(argument, "unknown-subcommand",
                               "EC-07: error argument must be the invalid subcommand text")
            } else {
                XCTFail("EC-07: Expected .invalidArgument, got \(cliError)")
            }
        }
    }

    // MARK: - EC-08: `dashboard status` with no agents -> valid .dashboardStatus parse

    func testEC08_DashboardStatusParsesToDashboardStatus() throws {
        // This is the command sent by CLI when querying agent status with 0 agents.
        // Must parse without error and produce .dashboardStatus.
        let result = try CLIArgumentParser.parse(["dashboard", "status"])
        XCTAssertEqual(result, .dashboardStatus,
                       "EC-08: 'dashboard status' must parse to .dashboardStatus regardless of agent count")
    }

    // MARK: - EC-09: `theme set` with missing name -> CLIError.missingArgument

    func testEC09_ThemeSetWithoutNameThrowsMissingArgument() {
        // "Ese edge case que no contemplaste? Lo encontre."
        // theme set requires a name argument; without it must fail gracefully.
        XCTAssertThrowsError(
            try CLIArgumentParser.parse(["theme", "set"])
        ) { error in
            guard let cliError = error as? CLIError else {
                XCTFail("EC-09: Expected CLIError, got \(type(of: error)): \(error)")
                return
            }
            if case .missingArgument(let command, let argument) = cliError {
                XCTAssertEqual(command, "theme set",
                               "EC-09: error command must be 'theme set'")
                XCTAssertEqual(argument, "name",
                               "EC-09: error argument must identify 'name' as missing")
            } else {
                XCTFail("EC-09: Expected .missingArgument, got \(cliError)")
            }
        }
    }

    // MARK: - EC-10: `config get` without key -> CLIError.missingArgument

    func testEC10_ConfigGetWithoutKeyThrowsMissingArgument() {
        XCTAssertThrowsError(
            try CLIArgumentParser.parse(["config", "get"])
        ) { error in
            guard let cliError = error as? CLIError else {
                XCTFail("EC-10: Expected CLIError, got \(type(of: error)): \(error)")
                return
            }
            if case .missingArgument(let command, let argument) = cliError {
                XCTAssertEqual(command, "config get",
                               "EC-10: error command must be 'config get'")
                XCTAssertEqual(argument, "key",
                               "EC-10: error argument must identify 'key' as missing")
            } else {
                XCTFail("EC-10: Expected .missingArgument, got \(cliError)")
            }
        }
    }

    // MARK: - EC-11: `version` text is non-empty and starts with "cocxy"

    func testEC11_VersionTextIsNonEmptyAndStartsWithCocxy() {
        let versionText = CLIArgumentParser.versionText()

        XCTAssertFalse(versionText.isEmpty,
                       "EC-11: version text must not be empty")
        XCTAssertTrue(versionText.hasPrefix("cocxy"),
                      "EC-11: version text must start with 'cocxy', got: '\(versionText)'")

        // Bonus: must contain a numeric version component
        let hasVersion = versionText.range(
            of: #"\d+\.\d+"#,
            options: .regularExpression
        ) != nil
        XCTAssertTrue(hasVersion,
                      "EC-11: version text must contain a semantic version number, got: '\(versionText)'")
    }

    // MARK: - EC-12: All CLICommand cases have non-empty helpDescription

    func testEC12_AllThirtyCommandsHaveNonEmptyHelpDescription() {
        // "80% de cobertura no es suficiente si el 20% restante es el login."
        // Every command must be self-documenting.
        let allCases = CLICommand.allCases

        XCTAssertEqual(allCases.count, 89,
                       "EC-12: CLICommand must have exactly 89 cases including setup-hooks and the expanded core contract commands")

        for command in allCases {
            XCTAssertFalse(
                command.helpDescription.isEmpty,
                "EC-12: CLICommand.\(command.rawValue) must have a non-empty helpDescription"
            )
            XCTAssertFalse(
                command.usageExample.isEmpty,
                "EC-12: CLICommand.\(command.rawValue) must have a non-empty usageExample"
            )
            XCTAssertTrue(
                command.usageExample.hasPrefix("cocxy"),
                "EC-12: usageExample for \(command.rawValue) must start with 'cocxy', got: '\(command.usageExample)'"
            )
        }
    }
}
