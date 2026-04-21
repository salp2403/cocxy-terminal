// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Verifies that the worktree fields added to `Tab` in v0.1.81 behave as
/// required by session persistence:
///
/// - New tabs with worktree fields set round-trip through `JSONEncoder`/
///   `JSONDecoder` without losing any field.
/// - New tabs with all worktree fields nil round-trip as nil.
/// - Legacy session JSONs persisted before v0.1.81 (no `worktreeID`,
///   `worktreeRoot`, `worktreeOriginRepo`, `worktreeBranch` keys) decode
///   cleanly with all four fields nil — Swift's auto-synthesised
///   `Codable` uses `decodeIfPresent` for every `Optional` property, so
///   missing keys map to `nil` without throwing.
/// - The default `Tab()` initialiser assigns `nil` to each of the four
///   worktree fields so existing call sites keep their current behaviour.
///
/// The legacy-tolerance guarantee is critical: without it, any user
/// upgrading from v0.1.80 to v0.1.81 would lose their saved session on
/// first launch because the persisted JSON would fail to decode.
@Suite("Tab worktree codable")
struct TabWorktreeCodableSwiftTestingTests {

    @Test("tab with every worktree field set round-trips through JSON")
    func fullWorktreeRoundTrip() throws {
        let originRepo = URL(fileURLWithPath: "/Users/dev/projects/myapp")
        let worktreeRoot = URL(
            fileURLWithPath: "/Users/dev/.cocxy/worktrees/a3f7de/claude-01"
        )
        let original = Tab(
            workingDirectory: worktreeRoot,
            worktreeID: "claude-01",
            worktreeRoot: worktreeRoot,
            worktreeOriginRepo: originRepo,
            worktreeBranch: "cocxy/claude/claude-01"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Tab.self, from: data)

        #expect(decoded.worktreeID == "claude-01")
        #expect(decoded.worktreeRoot == worktreeRoot)
        #expect(decoded.worktreeOriginRepo == originRepo)
        #expect(decoded.worktreeBranch == "cocxy/claude/claude-01")
    }

    @Test("tab with all worktree fields nil round-trips as nil")
    func nilWorktreeRoundTrip() throws {
        let original = Tab(
            title: "Plain Tab",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Tab.self, from: data)

        #expect(decoded.worktreeID == nil)
        #expect(decoded.worktreeRoot == nil)
        #expect(decoded.worktreeOriginRepo == nil)
        #expect(decoded.worktreeBranch == nil)
    }

    @Test("legacy JSON without worktree keys decodes with nil fields")
    func legacyJSONDecodesWithoutWorktreeKeys() throws {
        // JSON shape matches the v0.1.80 `Tab` layout: no worktree keys
        // present. Swift's auto-synthesised `init(from:)` must treat the
        // absent keys as `nil` without throwing. This mirrors how
        // `testCodableIgnoresLegacyAgentKeysInOldJSON` guards the retired
        // agent keys in the XCTest suite.
        let legacyJSON = """
        {
            "id": {"rawValue": "\(UUID().uuidString)"},
            "title": "v0.1.80 Tab",
            "workingDirectory": "file:///Users/dev/projects/legacy",
            "hasUnreadNotification": false,
            "lastActivityAt": 700000000,
            "isActive": true,
            "isPinned": false,
            "createdAt": 700000000
        }
        """

        let decoder = JSONDecoder()
        let tab = try decoder.decode(Tab.self, from: Data(legacyJSON.utf8))

        #expect(tab.title == "v0.1.80 Tab")
        #expect(tab.worktreeID == nil)
        #expect(tab.worktreeRoot == nil)
        #expect(tab.worktreeOriginRepo == nil)
        #expect(tab.worktreeBranch == nil)
    }

    @Test("default Tab() initialiser leaves every worktree field nil")
    func defaultInitProducesNilWorktreeFields() {
        let tab = Tab()

        #expect(tab.worktreeID == nil)
        #expect(tab.worktreeRoot == nil)
        #expect(tab.worktreeOriginRepo == nil)
        #expect(tab.worktreeBranch == nil)
    }

    @Test("partial worktree state (ID + root only) survives round-trip")
    func partialWorktreeStateRoundTrip() throws {
        // Realistic transient state: a worktree has just been created so
        // `worktreeID` and `worktreeRoot` are set, but the origin repo
        // lookup has not completed yet. The persisted session must not
        // drop the populated fields while keeping the unpopulated ones
        // nil.
        let worktreeRoot = URL(
            fileURLWithPath: "/Users/dev/.cocxy/worktrees/repo/wt-1"
        )
        let original = Tab(
            workingDirectory: worktreeRoot,
            worktreeID: "wt-1",
            worktreeRoot: worktreeRoot,
            worktreeOriginRepo: nil,
            worktreeBranch: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Tab.self, from: data)

        #expect(decoded.worktreeID == "wt-1")
        #expect(decoded.worktreeRoot == worktreeRoot)
        #expect(decoded.worktreeOriginRepo == nil)
        #expect(decoded.worktreeBranch == nil)
    }

    @Test("tabs with different worktree IDs are not Equatable")
    func equatableWhenWorktreeIDDiffers() {
        let id = TabID()
        let date = Date()
        let wd = URL(fileURLWithPath: "/tmp")

        let a = Tab(
            id: id,
            workingDirectory: wd,
            lastActivityAt: date,
            createdAt: date,
            worktreeID: "a-1"
        )
        let b = Tab(
            id: id,
            workingDirectory: wd,
            lastActivityAt: date,
            createdAt: date,
            worktreeID: "b-2"
        )

        #expect(a != b)
    }
}
