// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabTests.swift - Tests for the Tab domain model.

import XCTest
@testable import CocxyTerminal

// MARK: - Tab Model Tests

/// Tests for the `Tab` domain model.
///
/// Covers:
/// - Creation with default values.
/// - Codable round-trip (encode -> decode -> equal).
/// - Equatable conformance.
/// - AgentState raw values consistency.
/// - Display title generation.
@MainActor
final class TabTests: XCTestCase {

    // MARK: - Creation with Defaults

    func testCreationWithDefaultValues() {
        let tab = Tab()

        XCTAssertEqual(tab.title, "Terminal")
        XCTAssertNil(tab.gitBranch)
        XCTAssertNil(tab.processName)
        XCTAssertFalse(tab.hasUnreadNotification)
        XCTAssertFalse(tab.isActive)
        XCTAssertNil(tab.lastCommandStartedAt)
        XCTAssertNil(tab.lastCommandDuration)
        XCTAssertNil(tab.lastCommandExitCode)
        XCTAssertFalse(tab.isCommandRunning)
    }

    func testCreationGeneratesUniqueIDs() {
        let tab1 = Tab()
        let tab2 = Tab()

        XCTAssertNotEqual(tab1.id, tab2.id)
    }

    func testCreationWithCustomValues() {
        let workingDirectory = URL(fileURLWithPath: "/Users/dev/project")
        let now = Date()
        let tab = Tab(
            title: "My Tab",
            workingDirectory: workingDirectory,
            gitBranch: "feature/login",
            isActive: true,
            processName: "claude",
            createdAt: now
        )

        XCTAssertEqual(tab.title, "My Tab")
        XCTAssertEqual(tab.workingDirectory, workingDirectory)
        XCTAssertEqual(tab.gitBranch, "feature/login")
        XCTAssertTrue(tab.isActive)
        XCTAssertEqual(tab.processName, "claude")
        XCTAssertEqual(tab.createdAt, now)
    }

    // MARK: - Codable Round-trip

    func testCodableRoundTrip() throws {
        let original = Tab(
            title: "Encoded Tab",
            workingDirectory: URL(fileURLWithPath: "/tmp/test"),
            gitBranch: "main",
            isActive: true,
            processName: "node"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Tab.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testCodableRoundTripWithNilOptionals() throws {
        let original = Tab(
            title: "Minimal Tab",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            gitBranch: nil,
            processName: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Tab.self, from: data)

        XCTAssertEqual(original, decoded)
        XCTAssertNil(decoded.gitBranch)
        XCTAssertNil(decoded.processName)
    }

    func testCodableIgnoresLegacyAgentKeysInOldJSON() throws {
        // Session JSONs persisted before Fase 4 may still carry the
        // retired `agentState`, `detectedAgent`, `agentActivity`,
        // `agentToolCount`, and `agentErrorCount` keys. Swift's
        // auto-synthesized `Codable` must ignore unknown keys so the
        // restore path keeps working without a migration.
        let legacyJSON = """
        {
            "id": {"rawValue": "\(UUID().uuidString)"},
            "title": "Legacy Tab",
            "workingDirectory": "file:///tmp/legacy",
            "hasUnreadNotification": false,
            "lastActivityAt": 700000000,
            "isActive": false,
            "isPinned": false,
            "createdAt": 700000000,
            "agentState": "working",
            "agentActivity": "Read: main.swift",
            "agentToolCount": 4,
            "agentErrorCount": 1,
            "detectedAgent": {
                "name": "claude",
                "displayName": "Claude Code",
                "launchCommand": "claude",
                "startedAt": 700000000
            }
        }
        """

        let decoder = JSONDecoder()
        let tab = try decoder.decode(Tab.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(tab.title, "Legacy Tab")
        XCTAssertEqual(tab.workingDirectory.path, "/tmp/legacy")
    }

    // MARK: - Equatable

    func testEquatableWhenEqual() {
        let id = TabID()
        let date = Date()
        let workingDirectory = URL(fileURLWithPath: "/tmp")

        let tab1 = Tab(
            id: id,
            title: "Terminal",
            workingDirectory: workingDirectory,
            lastActivityAt: date,
            isActive: false,
            createdAt: date
        )
        let tab2 = Tab(
            id: id,
            title: "Terminal",
            workingDirectory: workingDirectory,
            lastActivityAt: date,
            isActive: false,
            createdAt: date
        )

        XCTAssertEqual(tab1, tab2)
    }

    func testEquatableWhenDifferentTitle() {
        let id = TabID()
        let date = Date()
        let workingDirectory = URL(fileURLWithPath: "/tmp")

        let tab1 = Tab(id: id, title: "Tab A", workingDirectory: workingDirectory, createdAt: date)
        let tab2 = Tab(id: id, title: "Tab B", workingDirectory: workingDirectory, createdAt: date)

        XCTAssertNotEqual(tab1, tab2)
    }

    // MARK: - AgentState Raw Values

    func testAgentStateRawValues() {
        XCTAssertEqual(AgentState.idle.rawValue, "idle")
        XCTAssertEqual(AgentState.launched.rawValue, "launched")
        XCTAssertEqual(AgentState.working.rawValue, "working")
        XCTAssertEqual(AgentState.waitingInput.rawValue, "waitingInput")
        XCTAssertEqual(AgentState.finished.rawValue, "finished")
        XCTAssertEqual(AgentState.error.rawValue, "error")
    }

    func testAgentStateAllCasesCovered() {
        // Ensure we have all 6 states.
        let allCases: [AgentState] = [.idle, .launched, .working, .waitingInput, .finished, .error]
        XCTAssertEqual(allCases.count, 6)
    }

    // MARK: - Command Tracking Fields

    func testCommandTrackingFieldsDefaultToNil() {
        let tab = Tab()

        XCTAssertNil(tab.lastCommandStartedAt)
        XCTAssertNil(tab.lastCommandDuration)
        XCTAssertNil(tab.lastCommandExitCode)
    }

    func testIsCommandRunningWhenStartedAndNotFinished() {
        var tab = Tab()
        tab.lastCommandStartedAt = Date()
        tab.lastCommandDuration = nil

        XCTAssertTrue(tab.isCommandRunning)
    }

    func testIsCommandRunningFalseWhenDurationSet() {
        var tab = Tab()
        tab.lastCommandStartedAt = Date()
        tab.lastCommandDuration = 2.5

        XCTAssertFalse(tab.isCommandRunning)
    }

    func testIsCommandRunningFalseWhenNeverStarted() {
        let tab = Tab()

        XCTAssertFalse(tab.isCommandRunning)
    }

    func testCommandTrackingFieldsSurviveCodableRoundTrip() throws {
        let startTime = Date()
        var original = Tab(
            title: "With Command",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        original.lastCommandStartedAt = startTime
        original.lastCommandDuration = 3.14
        original.lastCommandExitCode = 1

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Tab.self, from: data)

        XCTAssertEqual(decoded.lastCommandDuration, 3.14)
        XCTAssertEqual(decoded.lastCommandExitCode, 1)
    }

    func testCommandTrackingNilFieldsDecodableFromMissingKeys() throws {
        // Simulate JSON without command tracking fields (backward compatibility).
        let original = Tab(
            title: "Old Tab",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Tab.self, from: data)

        XCTAssertNil(decoded.lastCommandStartedAt)
        XCTAssertNil(decoded.lastCommandDuration)
        XCTAssertNil(decoded.lastCommandExitCode)
    }
}
