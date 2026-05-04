// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeDependencyTrackerSwiftTestingTests.swift - Conservative worktree dependency inference.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("WorktreeDependencyTracker")
struct WorktreeDependencyTrackerSwiftTestingTests {

    @Test("branch path children are treated as dependents")
    func branchPathChildrenAreDependents() {
        let parent = Self.entry(
            id: "parent",
            branch: "feature/payment",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let child = Self.entry(
            id: "child",
            branch: "feature/payment/refactor",
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let sibling = Self.entry(
            id: "sibling",
            branch: "feature/payments-v2",
            createdAt: Date(timeIntervalSince1970: 300)
        )

        let graph = WorktreeDependencyTracker().graph(for: [parent, child, sibling])

        #expect(graph.dependents(of: parent.id) == [child.id])
        #expect(graph.dependents(of: child.id).isEmpty)
        #expect(graph.dependents(of: sibling.id).isEmpty)
    }

    @Test("dash suffix children are treated as dependents for valid git refs")
    func dashSuffixChildrenAreDependents() {
        let parent = Self.entry(
            id: "parent",
            branch: "feature/payment/abc123",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let child = Self.entry(
            id: "child",
            branch: "feature/payment/abc123-followup/def456",
            createdAt: Date(timeIntervalSince1970: 200)
        )

        let graph = WorktreeDependencyTracker().graph(for: [parent, child])

        #expect(graph.dependents(of: parent.id) == [child.id])
    }

    @Test("older branch path children are ignored to avoid reverse dependency warnings")
    func olderBranchPathChildrenAreIgnored() {
        let newerParentName = Self.entry(
            id: "newer",
            branch: "feature/payment",
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let olderPathChild = Self.entry(
            id: "older",
            branch: "feature/payment/old",
            createdAt: Date(timeIntervalSince1970: 200)
        )

        let graph = WorktreeDependencyTracker().graph(for: [newerParentName, olderPathChild])

        #expect(graph.dependents(of: newerParentName.id).isEmpty)
    }

    private static func entry(
        id: String,
        branch: String,
        createdAt: Date
    ) -> WorktreeManifest.WorktreeEntry {
        WorktreeManifest.WorktreeEntry(
            id: id,
            branch: branch,
            path: URL(fileURLWithPath: "/tmp/\(id)"),
            createdAt: createdAt,
            agent: nil,
            tabID: nil
        )
    }
}
