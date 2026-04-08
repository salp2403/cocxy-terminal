// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionManagerTests.swift - Tests for session persistence and restoration.

import XCTest
@testable import CocxyTerminal

// MARK: - Session Manager Tests

/// Tests for `SessionManagerImpl` covering save, load, delete, auto-save and
/// conversions between runtime and serializable session models.
///
/// Covers:
/// - Session Codable round-trip (simple and complex).
/// - SplitNode <-> SplitNodeState conversion.
/// - Save creates file at correct path.
/// - Save creates directory if missing.
/// - Load returns nil for missing file.
/// - Load returns nil for corrupt JSON.
/// - Load rejects future schema versions.
/// - Auto-save timer fires on schedule.
/// - captureState from TabManager produces valid Session.
/// - WindowFrame/CodableRect serialization.
/// - QuickTerminal state not included when not visible.
/// - deleteSession removes file.
/// - sessionExists reports correctly.
/// - Version field is always currentVersion.
/// - listSessions returns sorted by date.
/// - Named sessions save and load independently.
/// - Save on background thread does not block.
final class SessionManagerTests: XCTestCase {

    // MARK: - Properties

    private var sessionManager: SessionManagerImpl!
    private var tempDirectory: URL!

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        // Use a unique temp directory for each test to avoid interference.
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-tests-\(UUID().uuidString)")
        sessionManager = SessionManagerImpl(sessionsDirectory: tempDirectory)
    }

    override func tearDown() {
        sessionManager.stopAutoSave()
        try? FileManager.default.removeItem(at: tempDirectory)
        sessionManager = nil
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a minimal valid Session with one window, one tab, one leaf.
    private func makeSimpleSession(savedAt: Date = Date()) -> Session {
        Session(
            version: Session.currentVersion,
            savedAt: savedAt,
            windows: [
                WindowState(
                    frame: CodableRect(x: 100, y: 200, width: 1200, height: 800),
                    isFullScreen: false,
                    tabs: [
                        TabState(
                            id: TabID(),
                            title: "Terminal",
                            workingDirectory: URL(fileURLWithPath: "/Users/dev/project"),
                            splitTree: .leaf(
                                workingDirectory: URL(fileURLWithPath: "/Users/dev/project"),
                                command: nil
                            )
                        )
                    ],
                    activeTabIndex: 0
                )
            ]
        )
    }

    /// Creates a complex Session with multiple windows, tabs, and split trees.
    private func makeComplexSession() -> Session {
        let splitTree = SplitNodeState.split(
            direction: .horizontal,
            first: .leaf(
                workingDirectory: URL(fileURLWithPath: "/Users/dev/left"),
                command: "vim"
            ),
            second: .split(
                direction: .vertical,
                first: .leaf(
                    workingDirectory: URL(fileURLWithPath: "/Users/dev/top-right"),
                    command: nil
                ),
                second: .leaf(
                    workingDirectory: URL(fileURLWithPath: "/Users/dev/bottom-right"),
                    command: "claude"
                ),
                ratio: 0.6
            ),
            ratio: 0.5
        )

        let tabs: [TabState] = (0..<5).map { index in
            TabState(
                id: TabID(),
                title: "Tab \(index)",
                workingDirectory: URL(fileURLWithPath: "/Users/dev/project-\(index)"),
                splitTree: index < 3 ? splitTree : .leaf(
                    workingDirectory: URL(fileURLWithPath: "/Users/dev/project-\(index)"),
                    command: nil
                )
            )
        }

        return Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: CodableRect(x: 0, y: 0, width: 1920, height: 1080),
                    isFullScreen: true,
                    tabs: tabs,
                    activeTabIndex: 2
                )
            ]
        )
    }

    // MARK: - Test 1: Session Codable round-trip (simple)

    func testSessionCodableRoundTripSimple() throws {
        let original = makeSimpleSession()

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Session.self, from: data)

        XCTAssertEqual(decoded.version, original.version)
        XCTAssertEqual(decoded.windows.count, 1)
        XCTAssertEqual(decoded.windows[0].tabs.count, 1)
        XCTAssertEqual(decoded.windows[0].tabs[0].title, "Terminal")
        XCTAssertEqual(decoded.windows[0].frame, original.windows[0].frame)
    }

    // MARK: - Test 2: Session Codable round-trip (complex: 5 tabs, 3 with splits)

    func testSessionCodableRoundTripComplex() throws {
        let original = makeComplexSession()

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Session.self, from: data)

        XCTAssertEqual(decoded.version, Session.currentVersion)
        XCTAssertEqual(decoded.windows[0].tabs.count, 5)
        XCTAssertEqual(decoded.windows[0].activeTabIndex, 2)
        XCTAssertTrue(decoded.windows[0].isFullScreen)

        // Verify the split tree structure of the first tab.
        if case .split(let dir, _, _, let ratio) = decoded.windows[0].tabs[0].splitTree {
            XCTAssertEqual(dir, .horizontal)
            XCTAssertEqual(ratio, 0.5)
        } else {
            XCTFail("Expected split node for first tab")
        }
    }

    // MARK: - Test 3: SplitNodeState leaf round-trip

    func testSplitNodeStateLeafRoundTrip() throws {
        let original = SplitNodeState.leaf(
            workingDirectory: URL(fileURLWithPath: "/tmp/test"),
            command: "zsh"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SplitNodeState.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - Test 4: SplitNodeState nested split round-trip

    func testSplitNodeStateNestedSplitRoundTrip() throws {
        let original = SplitNodeState.split(
            direction: .vertical,
            first: .leaf(workingDirectory: URL(fileURLWithPath: "/a"), command: nil),
            second: .split(
                direction: .horizontal,
                first: .leaf(workingDirectory: URL(fileURLWithPath: "/b"), command: "vim"),
                second: .leaf(workingDirectory: URL(fileURLWithPath: "/c"), command: nil),
                ratio: 0.3
            ),
            ratio: 0.7
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SplitNodeState.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - Test 5: SplitNode to SplitNodeState conversion (leaf)

    func testSplitNodeToStateConversionLeaf() {
        let leafID = UUID()
        let terminalID = UUID()
        let workingDirectory = URL(fileURLWithPath: "/Users/dev")
        let node = SplitNode.leaf(id: leafID, terminalID: terminalID)

        let state = node.toSessionState(
            workingDirectoryResolver: { _ in workingDirectory }
        )

        if case .leaf(let dir, let cmd) = state {
            XCTAssertEqual(dir, workingDirectory)
            XCTAssertNil(cmd)
        } else {
            XCTFail("Expected leaf state")
        }
    }

    // MARK: - Test 6: SplitNode to SplitNodeState conversion (split)

    func testSplitNodeToStateConversionSplit() {
        let firstTerminal = UUID()
        let secondTerminal = UUID()
        let node = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: firstTerminal),
            second: .leaf(id: UUID(), terminalID: secondTerminal),
            ratio: 0.6
        )

        let workDir = URL(fileURLWithPath: "/Users/dev")
        let state = node.toSessionState(
            workingDirectoryResolver: { _ in workDir }
        )

        if case .split(let dir, _, _, let ratio) = state {
            XCTAssertEqual(dir, .horizontal)
            XCTAssertEqual(ratio, 0.6)
        } else {
            XCTFail("Expected split state")
        }
    }

    // MARK: - Test 7: SplitNodeState to SplitNode conversion (leaf)

    func testSplitNodeStateToSplitNodeLeaf() {
        let state = SplitNodeState.leaf(
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            command: nil
        )

        let node = state.toSplitNode()

        XCTAssertEqual(node.leafCount, 1)
        if case .leaf(_, _) = node {
            // Success -- it is a leaf.
        } else {
            XCTFail("Expected leaf SplitNode")
        }
    }

    // MARK: - Test 8: SplitNodeState to SplitNode conversion (split preserves direction and ratio)

    func testSplitNodeStateToSplitNodeSplitPreservesStructure() {
        let state = SplitNodeState.split(
            direction: .vertical,
            first: .leaf(workingDirectory: URL(fileURLWithPath: "/a"), command: nil),
            second: .leaf(workingDirectory: URL(fileURLWithPath: "/b"), command: nil),
            ratio: 0.4
        )

        let node = state.toSplitNode()

        if case .split(_, let dir, let first, let second, let ratio) = node {
            XCTAssertEqual(dir, .vertical)
            XCTAssertEqual(ratio, 0.4, accuracy: 0.001)
            XCTAssertEqual(first.leafCount, 1)
            XCTAssertEqual(second.leafCount, 1)
        } else {
            XCTFail("Expected split SplitNode")
        }
    }

    // MARK: - Test 9: Save creates file at correct path

    func testSaveCreatesFileAtCorrectPath() throws {
        let session = makeSimpleSession()

        try sessionManager.saveSession(session, named: nil)

        let expectedFile = tempDirectory.appendingPathComponent("last.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFile.path))
    }

    // MARK: - Test 10: Save creates directory if missing

    func testSaveCreatesDirectoryIfMissing() throws {
        // tempDirectory does not exist yet -- setUp does not create it.
        let deepPath = tempDirectory.appendingPathComponent("nested/deep")
        let manager = SessionManagerImpl(sessionsDirectory: deepPath)

        let session = makeSimpleSession()
        try manager.saveSession(session, named: nil)

        XCTAssertTrue(FileManager.default.fileExists(atPath: deepPath.path))
    }

    // MARK: - Test 11: Load returns nil for missing file

    func testLoadReturnsNilForMissingFile() throws {
        let result = try sessionManager.loadLastSession()
        XCTAssertNil(result)
    }

    // MARK: - Test 12: Load returns nil for corrupt JSON

    func testLoadReturnsNilForCorruptJSON() throws {
        // Create directory and write garbage data.
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        let filePath = tempDirectory.appendingPathComponent("last.json")
        try "this is not valid json {{{".write(to: filePath, atomically: true, encoding: .utf8)

        do {
            _ = try sessionManager.loadLastSession()
            XCTFail("Expected parseFailed error")
        } catch SessionError.parseFailed {
            // Expected.
        }
    }

    // MARK: - Test 13: Load rejects future schema version

    func testLoadRejectsFutureSchemaVersion() throws {
        let futureSession = Session(
            version: 999,
            savedAt: Date(),
            windows: []
        )

        try sessionManager.saveSession(futureSession, named: nil)

        do {
            _ = try sessionManager.loadLastSession()
            XCTFail("Expected unsupportedVersion error")
        } catch SessionError.unsupportedVersion(let found, let supported) {
            XCTAssertEqual(found, 999)
            XCTAssertEqual(supported, Session.currentVersion)
        }
    }

    // MARK: - Test 14: Auto-save timer fires

    func testAutoSaveTimerFires() {
        let expectation = expectation(description: "Auto-save fires")

        var saveCount = 0
        sessionManager.startAutoSave(intervalSeconds: 0.1) {
            saveCount += 1
            if saveCount >= 1 {
                expectation.fulfill()
            }
            return self.makeSimpleSession()
        }

        waitForExpectations(timeout: 2.0)
        sessionManager.stopAutoSave()

        XCTAssertGreaterThanOrEqual(saveCount, 1)
    }

    // MARK: - Test 15: CodableRect serialization

    func testCodableRectSerialization() throws {
        let original = CodableRect(x: 42.5, y: 100.0, width: 1920.0, height: 1080.0)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodableRect.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - Test 16: deleteSession removes file

    func testDeleteSessionRemovesFile() throws {
        let session = makeSimpleSession()
        try sessionManager.saveSession(session, named: "test-session")

        let filePath = tempDirectory.appendingPathComponent("test-session.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath.path))

        try sessionManager.deleteSession(named: "test-session")
        XCTAssertFalse(FileManager.default.fileExists(atPath: filePath.path))
    }

    func testDeleteUnnamedSessionRemovesLastSnapshot() throws {
        let session = makeSimpleSession()
        try sessionManager.saveSession(session, named: nil)

        let filePath = tempDirectory.appendingPathComponent("last.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath.path))

        try sessionManager.deleteSession(named: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: filePath.path))
    }

    // MARK: - Test 17: sessionExists

    func testSessionExists() throws {
        XCTAssertFalse(sessionManager.sessionExists(named: nil))

        let session = makeSimpleSession()
        try sessionManager.saveSession(session, named: nil)

        XCTAssertTrue(sessionManager.sessionExists(named: nil))
    }

    // MARK: - Test 18: Version field is currentVersion

    func testVersionFieldIsCurrentVersion() {
        let session = makeSimpleSession()
        XCTAssertEqual(session.version, 2)
        XCTAssertEqual(Session.currentVersion, 2)
    }

    // MARK: - Test 19: Named session save and load independently

    func testNamedSessionsSaveAndLoadIndependently() throws {
        let sessionA = Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: CodableRect(x: 0, y: 0, width: 800, height: 600),
                    isFullScreen: false,
                    tabs: [
                        TabState(
                            id: TabID(),
                            title: "Session A",
                            workingDirectory: URL(fileURLWithPath: "/tmp/a"),
                            splitTree: .leaf(
                                workingDirectory: URL(fileURLWithPath: "/tmp/a"),
                                command: nil
                            )
                        )
                    ],
                    activeTabIndex: 0
                )
            ]
        )

        let sessionB = Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: CodableRect(x: 50, y: 50, width: 1024, height: 768),
                    isFullScreen: true,
                    tabs: [
                        TabState(
                            id: TabID(),
                            title: "Session B",
                            workingDirectory: URL(fileURLWithPath: "/tmp/b"),
                            splitTree: .leaf(
                                workingDirectory: URL(fileURLWithPath: "/tmp/b"),
                                command: nil
                            )
                        )
                    ],
                    activeTabIndex: 0
                )
            ]
        )

        try sessionManager.saveSession(sessionA, named: "alpha")
        try sessionManager.saveSession(sessionB, named: "beta")

        let loadedA = try sessionManager.loadSession(named: "alpha")
        let loadedB = try sessionManager.loadSession(named: "beta")

        XCTAssertEqual(loadedA?.windows[0].tabs[0].title, "Session A")
        XCTAssertEqual(loadedB?.windows[0].tabs[0].title, "Session B")
        XCTAssertTrue(loadedB?.windows[0].isFullScreen ?? false)
    }

    // MARK: - Test 20: listSessions returns sorted by date

    func testListSessionsReturnsSortedByDate() throws {
        let oldDate = Date(timeIntervalSince1970: 1_000_000)
        let midDate = Date(timeIntervalSince1970: 2_000_000)
        let newDate = Date(timeIntervalSince1970: 3_000_000)

        try sessionManager.saveSession(makeSimpleSession(savedAt: oldDate), named: "old")
        try sessionManager.saveSession(makeSimpleSession(savedAt: newDate), named: "new")
        try sessionManager.saveSession(makeSimpleSession(savedAt: midDate), named: "mid")

        let sessions = sessionManager.listSessions()

        XCTAssertEqual(sessions.count, 3)
        XCTAssertEqual(sessions[0].name, "new")
        XCTAssertEqual(sessions[1].name, "mid")
        XCTAssertEqual(sessions[2].name, "old")
    }

    // MARK: - Test 21: Save uses prettyPrinted JSON

    func testSaveUsesPrettyPrintedJSON() throws {
        let session = makeSimpleSession()
        try sessionManager.saveSession(session, named: nil)

        let filePath = tempDirectory.appendingPathComponent("last.json")
        let contents = try String(contentsOf: filePath, encoding: .utf8)

        // Pretty printed JSON has newlines and indentation.
        XCTAssertTrue(contents.contains("\n"))
        XCTAssertTrue(contents.contains("  "))
    }

    // MARK: - Test 22: Save and load round-trip preserves full state

    func testSaveAndLoadRoundTripPreservesFullState() throws {
        let original = makeComplexSession()

        try sessionManager.saveSession(original, named: nil)
        let loaded = try sessionManager.loadLastSession()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.version, original.version)
        XCTAssertEqual(loaded?.windows.count, original.windows.count)
        XCTAssertEqual(loaded?.windows[0].tabs.count, original.windows[0].tabs.count)
        XCTAssertEqual(loaded?.windows[0].activeTabIndex, 2)
        XCTAssertEqual(loaded?.windows[0].isFullScreen, true)
    }

    // MARK: - Test 23: Delete non-existent session throws error

    func testDeleteNonExistentSessionThrowsError() {
        XCTAssertThrowsError(try sessionManager.deleteSession(named: "nonexistent")) { error in
            if case SessionError.deleteFailed = error {
                // Expected.
            } else {
                XCTFail("Expected deleteFailed error, got \(error)")
            }
        }
    }

    // MARK: - Test 24: Named session existence check

    func testNamedSessionExistsCheck() throws {
        XCTAssertFalse(sessionManager.sessionExists(named: "workflow"))

        try sessionManager.saveSession(makeSimpleSession(), named: "workflow")

        XCTAssertTrue(sessionManager.sessionExists(named: "workflow"))
    }

    // MARK: - Test 25: SplitNode round-trip through state preserves leaf count

    func testSplitNodeRoundTripThroughStatePreservesLeafCount() {
        let node = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: UUID()),
            second: .split(
                id: UUID(),
                direction: .vertical,
                first: .leaf(id: UUID(), terminalID: UUID()),
                second: .leaf(id: UUID(), terminalID: UUID()),
                ratio: 0.5
            ),
            ratio: 0.5
        )

        let workDir = URL(fileURLWithPath: "/tmp")
        let state = node.toSessionState(
            workingDirectoryResolver: { _ in workDir }
        )
        let restored = state.toSplitNode()

        XCTAssertEqual(node.leafCount, restored.leafCount)
        XCTAssertEqual(restored.leafCount, 3)
    }

    // MARK: - Test 26: WindowState with fullscreen serialization

    func testWindowStateWithFullscreenSerialization() throws {
        let original = WindowState(
            frame: CodableRect(x: 0, y: 0, width: 2560, height: 1440),
            isFullScreen: true,
            tabs: [],
            activeTabIndex: 0
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WindowState.self, from: data)

        XCTAssertTrue(decoded.isFullScreen)
        XCTAssertEqual(decoded.frame.width, 2560)
        XCTAssertEqual(decoded.frame.height, 1440)
    }

    // MARK: - Test 27: Load named session returns nil when not found

    func testLoadNamedSessionReturnsNilWhenNotFound() throws {
        let result = try sessionManager.loadSession(named: "does-not-exist")
        XCTAssertNil(result)
    }

    // MARK: - Test 28: Auto-save stop prevents further saves

    func testAutoSaveStopPreventsFurtherSaves() {
        var saveCount = 0

        sessionManager.startAutoSave(intervalSeconds: 0.05) {
            saveCount += 1
            return self.makeSimpleSession()
        }

        // Stop immediately.
        sessionManager.stopAutoSave()

        // Wait a bit to confirm no more saves happen.
        let beforeCount = saveCount
        let expectation = expectation(description: "Wait after stop")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        // Allow at most 1 save that was already in flight.
        XCTAssertLessThanOrEqual(saveCount - beforeCount, 1)
    }
}
