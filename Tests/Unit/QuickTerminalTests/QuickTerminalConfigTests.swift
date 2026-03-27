// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// QuickTerminalConfigTests.swift - Tests for QuickTerminalConfig extensions (T-037).

import XCTest
@testable import CocxyTerminal

// MARK: - Quick Terminal Config Tests

/// Tests for the extended `QuickTerminalConfig` fields added in T-037.
@MainActor
final class QuickTerminalConfigTests: XCTestCase {

    // MARK: - 1. Default enabled is true

    func testDefaultEnabledIsTrue() {
        let config = QuickTerminalConfig.defaults
        XCTAssertTrue(config.enabled,
                      "Quick terminal must be enabled by default")
    }

    // MARK: - 2. Default hideOnDeactivate is true

    func testDefaultHideOnDeactivateIsTrue() {
        let config = QuickTerminalConfig.defaults
        XCTAssertTrue(config.hideOnDeactivate,
                      "Quick terminal must hide on deactivate by default")
    }

    // MARK: - 3. Default working directory is home

    func testDefaultWorkingDirectoryIsHome() {
        let config = QuickTerminalConfig.defaults
        XCTAssertEqual(config.workingDirectory, "~",
                       "Default working directory must be home (~)")
    }

    // MARK: - 4. Custom config preserves all fields

    func testCustomConfigPreservesAllFields() {
        let config = QuickTerminalConfig(
            enabled: false,
            hotkey: "cmd+shift+grave",
            position: .left,
            heightPercentage: 60,
            hideOnDeactivate: false,
            workingDirectory: "/tmp",
            animationDuration: 0.15,
            screen: .mouse
        )

        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.hotkey, "cmd+shift+grave")
        XCTAssertEqual(config.position, .left)
        XCTAssertEqual(config.heightPercentage, 60)
        XCTAssertFalse(config.hideOnDeactivate)
        XCTAssertEqual(config.workingDirectory, "/tmp")
    }

    // MARK: - 5. Config is Equatable

    func testConfigIsEquatable() {
        let config1 = QuickTerminalConfig.defaults
        let config2 = QuickTerminalConfig.defaults
        XCTAssertEqual(config1, config2,
                       "Two default configs must be equal")
    }

    // MARK: - 6. Config is Codable

    func testConfigIsCodable() throws {
        let original = QuickTerminalConfig(
            enabled: true,
            hotkey: "cmd+grave",
            position: .bottom,
            heightPercentage: 50,
            hideOnDeactivate: false,
            workingDirectory: "/Users/test",
            animationDuration: 0.2,
            screen: .main
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(QuickTerminalConfig.self, from: data)

        XCTAssertEqual(original, decoded,
                       "Config must survive encode/decode round trip")
    }
}
