// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionRestorerWorktreeSwiftTestingTests.swift - Verifies that the
// four worktree fields added in v0.1.81 travel cleanly through the
// session save/restore chain: Tab → TabState (Codable) → RestoredTab.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("SessionRestorer — worktree metadata roundtrip")
struct SessionRestorerWorktreeSwiftTestingTests {

    // MARK: - TabState Codable round-trip

    @Test("TabState Codable preserves every worktree field")
    func tabStateCodablePreservesWorktreeFields() throws {
        let worktreeRoot = URL(
            fileURLWithPath: "/Users/dev/.cocxy/worktrees/abc123/wt-1"
        )
        let originRepo = URL(fileURLWithPath: "/Users/dev/projects/app")

        let tabState = TabState(
            id: TabID(),
            title: "Test",
            workingDirectory: worktreeRoot,
            splitTree: .leaf(workingDirectory: worktreeRoot, command: nil),
            worktreeID: "wt-1",
            worktreeRoot: worktreeRoot,
            worktreeOriginRepo: originRepo,
            worktreeBranch: "cocxy/claude/wt-1"
        )

        let data = try JSONEncoder().encode(tabState)
        let decoded = try JSONDecoder().decode(TabState.self, from: data)

        #expect(decoded.worktreeID == "wt-1")
        #expect(decoded.worktreeRoot == worktreeRoot)
        #expect(decoded.worktreeOriginRepo == originRepo)
        #expect(decoded.worktreeBranch == "cocxy/claude/wt-1")
    }

    @Test("legacy TabState JSON without worktree keys decodes with nils")
    func legacyTabStateDecodesWithoutWorktreeKeys() throws {
        // JSON shape corresponds to the v0.1.80 TabState layout: no
        // worktree keys present. `decodeIfPresent` on every field must
        // keep the decoder tolerant so upgrading a saved session never
        // loses data.
        let legacyJson = """
        {
            "id": {"rawValue": "\(UUID().uuidString)"},
            "sessionID": {"rawValue": "\(UUID().uuidString)"},
            "title": "Legacy Tab",
            "workingDirectory": "file:///Users/dev/legacy",
            "splitTree": {
                "leaf": {
                    "workingDirectory": "file:///Users/dev/legacy",
                    "command": null
                }
            }
        }
        """
        let decoded = try JSONDecoder().decode(
            TabState.self,
            from: Data(legacyJson.utf8)
        )

        #expect(decoded.worktreeID == nil)
        #expect(decoded.worktreeRoot == nil)
        #expect(decoded.worktreeOriginRepo == nil)
        #expect(decoded.worktreeBranch == nil)
    }

    @Test("TabState Codable roundtrip is nil-preserving for unset worktrees")
    func nilWorktreeFieldsRoundTrip() throws {
        let tabState = TabState(
            id: TabID(),
            title: "Plain Tab",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            splitTree: .leaf(
                workingDirectory: URL(fileURLWithPath: "/tmp"),
                command: nil
            )
        )

        let data = try JSONEncoder().encode(tabState)
        let decoded = try JSONDecoder().decode(TabState.self, from: data)

        #expect(decoded.worktreeID == nil)
        #expect(decoded.worktreeRoot == nil)
        #expect(decoded.worktreeOriginRepo == nil)
        #expect(decoded.worktreeBranch == nil)
    }

    // MARK: - SessionRestorer walks the worktree fields

    @Test("SessionRestorer propagates worktree metadata into RestoredTab")
    func sessionRestorerPropagatesWorktreeFields() throws {
        // Build a minimal valid session with one tab carrying the four
        // worktree fields, round-trip it through `SessionRestorer`, and
        // verify the produced `RestoredTab` mirrors every field.
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "cocxy-session-worktree-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: tempRoot,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // Use the tempRoot as both worktree root and working directory
        // so the `validateDirectory` step inside SessionRestorer keeps
        // the path without falling back to home.
        let worktreeRoot = tempRoot
        let originRepo = tempRoot  // same dir is enough for metadata plumbing

        let tabID = TabID()
        let tabState = TabState(
            id: tabID,
            title: "Worktree Tab",
            workingDirectory: worktreeRoot,
            splitTree: .leaf(
                workingDirectory: worktreeRoot,
                command: nil
            ),
            worktreeID: "wt-xyz",
            worktreeRoot: worktreeRoot,
            worktreeOriginRepo: originRepo,
            worktreeBranch: "cocxy/claude/wt-xyz"
        )

        let windowState = WindowState(
            frame: CodableRect(x: 100, y: 100, width: 800, height: 600),
            isFullScreen: false,
            tabs: [tabState],
            activeTabIndex: 0,
            windowID: nil,
            displayIndex: nil
        )

        let result = SessionRestorer.restoreWindow(
            from: windowState,
            screenBounds: CodableRect(x: 0, y: 0, width: 2560, height: 1440)
        )
        let restored = try #require(result.restoredTabs.first)

        #expect(restored.worktreeID == "wt-xyz")
        #expect(restored.worktreeRoot == worktreeRoot)
        #expect(restored.worktreeOriginRepo == originRepo)
        #expect(restored.worktreeBranch == "cocxy/claude/wt-xyz")
    }
}
