// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SplitManagerPanelTitleTests.swift - Tests for custom panel titles in SplitManager.

import XCTest
@testable import CocxyTerminal

// MARK: - SplitManager Panel Title Tests

/// Tests for custom panel title management in `SplitManager`.
///
/// Covers:
/// - Default panel title is nil.
/// - Setting a panel title stores it.
/// - Retrieving a stored panel title.
/// - Clearing a panel title with nil.
/// - Clearing a panel title with empty string.
/// - Panel titles are independent per content ID.
/// - Closing a pane cleans up its panel title.
@MainActor
final class SplitManagerPanelTitleTests: XCTestCase {

    func testDefaultPanelTitleIsNil() {
        let manager = SplitManager()
        let contentID = UUID()

        XCTAssertNil(manager.panelTitle(for: contentID))
    }

    func testSetPanelTitleStoresValue() {
        let manager = SplitManager()
        let contentID = UUID()

        manager.setPanelTitle(for: contentID, title: "My Terminal")

        XCTAssertEqual(manager.panelTitle(for: contentID), "My Terminal")
    }

    func testSetPanelTitleWithNilRemovesValue() {
        let manager = SplitManager()
        let contentID = UUID()

        manager.setPanelTitle(for: contentID, title: "Temporary")
        manager.setPanelTitle(for: contentID, title: nil)

        XCTAssertNil(manager.panelTitle(for: contentID))
    }

    func testSetPanelTitleWithEmptyStringRemovesValue() {
        let manager = SplitManager()
        let contentID = UUID()

        manager.setPanelTitle(for: contentID, title: "Temporary")
        manager.setPanelTitle(for: contentID, title: "")

        XCTAssertNil(manager.panelTitle(for: contentID))
    }

    func testPanelTitlesAreIndependentPerContentID() {
        let manager = SplitManager()
        let contentA = UUID()
        let contentB = UUID()

        manager.setPanelTitle(for: contentA, title: "Panel A")
        manager.setPanelTitle(for: contentB, title: "Panel B")

        XCTAssertEqual(manager.panelTitle(for: contentA), "Panel A")
        XCTAssertEqual(manager.panelTitle(for: contentB), "Panel B")
    }

    func testPanelTitleOverwritesPreviousValue() {
        let manager = SplitManager()
        let contentID = UUID()

        manager.setPanelTitle(for: contentID, title: "First")
        manager.setPanelTitle(for: contentID, title: "Second")

        XCTAssertEqual(manager.panelTitle(for: contentID), "Second")
    }

    func testPanelTitlesDictionaryReflectsStoredTitles() {
        let manager = SplitManager()
        let contentA = UUID()
        let contentB = UUID()

        manager.setPanelTitle(for: contentA, title: "A")
        manager.setPanelTitle(for: contentB, title: "B")

        XCTAssertEqual(manager.panelTitles.count, 2)
        XCTAssertEqual(manager.panelTitles[contentA], "A")
        XCTAssertEqual(manager.panelTitles[contentB], "B")
    }

    func testCloseFocusedCleansUpPanelTitle() {
        let manager = SplitManager()
        guard let newContentID = manager.splitFocused(direction: .horizontal) else {
            XCTFail("Split should succeed")
            return
        }

        manager.setPanelTitle(for: newContentID, title: "Named Panel")
        XCTAssertNotNil(manager.panelTitle(for: newContentID))

        // Close the focused pane (which is the new one after split).
        manager.closeFocused()

        XCTAssertNil(manager.panelTitle(for: newContentID),
                     "Closing a pane should clean up its panel title")
    }
}
