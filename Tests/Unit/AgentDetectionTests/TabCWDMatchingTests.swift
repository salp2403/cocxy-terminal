// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabCWDMatchingTests.swift - Tests for CWD-based tab matching in hook events.

import Testing
import Foundation
@testable import CocxyTerminal

// MARK: - Tab CWD Matching Tests

/// Tests for `AppDelegate.findMatchingTab()`, which resolves hook events
/// to the correct Cocxy tab by matching working directories.
///
/// After removing the parent-directory heuristic (which caused cross-terminal
/// contamination), matching is strict exact-only: a hook event's CWD must
/// exactly equal a tab's `workingDirectory` to match.
@Suite("Tab CWD Matching")
@MainActor
struct TabCWDMatchingTests {

    // MARK: - Helpers

    private func makeTab(
        title: String = "Test",
        directory: String
    ) -> Tab {
        var tab = Tab(title: title)
        tab.workingDirectory = URL(fileURLWithPath: directory)
        return tab
    }

    // MARK: - Exact Match

    @Test("Exact CWD match returns the correct tab")
    func exactMatchReturnsCorrectTab() {
        let tab1 = makeTab(title: "project", directory: "/Users/dev/project")
        let tab2 = makeTab(title: "other", directory: "/Users/dev/other")
        let tabs = [tab1, tab2]

        let result = AppDelegate.findMatchingTab(
            cwd: "/Users/dev/project",
            tabs: tabs,
            activeTabID: tab2.id
        )

        #expect(result?.id == tab1.id)
    }

    @Test("Exact match works with trailing slash normalization")
    func exactMatchWithTrailingSlash() {
        let tab = makeTab(directory: "/Users/dev/project")

        let result = AppDelegate.findMatchingTab(
            cwd: "/Users/dev/project/",
            tabs: [tab],
            activeTabID: tab.id
        )

        // URL(fileURLWithPath:) standardizes trailing slashes.
        #expect(result?.id == tab.id)
    }

    // MARK: - No Cross-Contamination

    @Test("Parent directory does NOT match (prevents cross-terminal contamination)")
    func parentDirectoryDoesNotMatch() {
        // Tab is at home directory, hook event is from a project subdirectory.
        // This MUST NOT match, otherwise Claude Code running at ~/project
        // would contaminate a Cocxy tab at ~.
        let homeTab = makeTab(title: "home", directory: "/Users/dev")
        let tabs = [homeTab]

        let result = AppDelegate.findMatchingTab(
            cwd: "/Users/dev/project",
            tabs: tabs,
            activeTabID: homeTab.id
        )

        #expect(result == nil, "Parent directory must NOT match")
    }

    @Test("Root directory does NOT match arbitrary paths")
    func rootDirectoryDoesNotMatch() {
        let rootTab = makeTab(title: "root", directory: "/")
        let tabs = [rootTab]

        let result = AppDelegate.findMatchingTab(
            cwd: "/Users/dev/project",
            tabs: tabs,
            activeTabID: rootTab.id
        )

        #expect(result == nil, "Root tab must NOT match arbitrary paths")
    }

    @Test("Active tab is NOT returned as fallback when CWD doesn't match")
    func noActiveTabFallback() {
        let activeTab = makeTab(title: "active", directory: "/Users/dev/frontend")

        let result = AppDelegate.findMatchingTab(
            cwd: "/Users/dev/backend",
            tabs: [activeTab],
            activeTabID: activeTab.id
        )

        #expect(result == nil, "Active tab must NOT be returned when CWD doesn't match")
    }

    // MARK: - Edge Cases

    @Test("No tabs returns nil")
    func noTabsReturnsNil() {
        let result = AppDelegate.findMatchingTab(
            cwd: "/Users/dev/project",
            tabs: [],
            activeTabID: nil
        )

        #expect(result == nil)
    }

    @Test("Multiple tabs with same CWD returns first match")
    func multipleTabsSameCWD() {
        let tab1 = makeTab(title: "tab1", directory: "/Users/dev/project")
        let tab2 = makeTab(title: "tab2", directory: "/Users/dev/project")

        let result = AppDelegate.findMatchingTab(
            cwd: "/Users/dev/project",
            tabs: [tab1, tab2],
            activeTabID: tab2.id
        )

        #expect(result?.id == tab1.id)
    }

    @Test("Home directory expansion matches correctly")
    func homeDirectoryMatch() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let tab = makeTab(directory: home)

        let result = AppDelegate.findMatchingTab(
            cwd: home,
            tabs: [tab],
            activeTabID: tab.id
        )

        #expect(result?.id == tab.id)
    }

    @Test("Sibling directories do NOT match")
    func siblingDirectoriesDoNotMatch() {
        let tab = makeTab(directory: "/Users/dev/frontend")

        let result = AppDelegate.findMatchingTab(
            cwd: "/Users/dev/backend",
            tabs: [tab],
            activeTabID: tab.id
        )

        #expect(result == nil, "Sibling directories must NOT match")
    }
}
