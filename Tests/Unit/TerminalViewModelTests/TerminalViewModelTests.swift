// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalViewModelTests.swift - Tests for TerminalViewModel state management.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - TerminalViewModel Initial State Tests

/// Tests that verify the TerminalViewModel starts in the correct default state.
@MainActor
final class TerminalViewModelInitialStateTests: XCTestCase {

    func testDefaultTitleIsTerminal() {
        let viewModel = TerminalViewModel()
        XCTAssertEqual(
            viewModel.title,
            "Terminal",
            "Default title must be 'Terminal'"
        )
    }

    func testDefaultIsRunningIsFalse() {
        let viewModel = TerminalViewModel()
        XCTAssertFalse(
            viewModel.isRunning,
            "isRunning must be false before a surface is created"
        )
    }

    func testDefaultSurfaceIdIsNil() {
        let viewModel = TerminalViewModel()
        XCTAssertNil(
            viewModel.surfaceID,
            "surfaceID must be nil before a surface is created"
        )
    }
}

// MARK: - TerminalViewModel Title Update Tests

/// Tests that title changes propagate correctly via Combine.
@MainActor
final class TerminalViewModelTitleTests: XCTestCase {

    func testUpdateTitleChangesPublishedProperty() {
        let viewModel = TerminalViewModel()
        viewModel.updateTitle("zsh: ~/projects")
        XCTAssertEqual(
            viewModel.title,
            "zsh: ~/projects",
            "Title must update when updateTitle is called"
        )
    }

    func testUpdateTitlePublishesThroughCombine() {
        let viewModel = TerminalViewModel()
        var receivedTitles: [String] = []
        let cancellable = viewModel.$title
            .dropFirst() // Skip initial value
            .sink { receivedTitles.append($0) }

        viewModel.updateTitle("First Title")
        viewModel.updateTitle("Second Title")

        XCTAssertEqual(
            receivedTitles,
            ["First Title", "Second Title"],
            "Title changes must publish through Combine"
        )

        cancellable.cancel()
    }

    func testUpdateTitleWithEmptyStringIsAllowed() {
        let viewModel = TerminalViewModel()
        viewModel.updateTitle("")
        XCTAssertEqual(
            viewModel.title,
            "",
            "Empty title must be accepted"
        )
    }
}

// MARK: - TerminalViewModel Running State Tests

/// Tests for the isRunning lifecycle state.
@MainActor
final class TerminalViewModelRunningStateTests: XCTestCase {

    func testMarkRunningChangesState() {
        let viewModel = TerminalViewModel()
        let surfaceID = SurfaceID()

        viewModel.markRunning(surfaceID: surfaceID)

        XCTAssertTrue(
            viewModel.isRunning,
            "isRunning must be true after markRunning"
        )
        XCTAssertEqual(
            viewModel.surfaceID,
            surfaceID,
            "surfaceID must be set after markRunning"
        )
    }

    func testMarkStoppedResetsState() {
        let viewModel = TerminalViewModel()
        let surfaceID = SurfaceID()

        viewModel.markRunning(surfaceID: surfaceID)
        viewModel.markStopped()

        XCTAssertFalse(
            viewModel.isRunning,
            "isRunning must be false after markStopped"
        )
        XCTAssertNil(
            viewModel.surfaceID,
            "surfaceID must be nil after markStopped"
        )
    }

    func testIsRunningPublishesThroughCombine() {
        let viewModel = TerminalViewModel()
        var receivedValues: [Bool] = []
        let cancellable = viewModel.$isRunning
            .dropFirst()
            .sink { receivedValues.append($0) }

        viewModel.markRunning(surfaceID: SurfaceID())
        viewModel.markStopped()

        XCTAssertEqual(
            receivedValues,
            [true, false],
            "isRunning changes must publish through Combine"
        )

        cancellable.cancel()
    }
}

// MARK: - TerminalViewModel Bridge Reference Tests

/// Tests that the ViewModel correctly holds a reference to the bridge.
@MainActor
final class TerminalViewModelBridgeTests: XCTestCase {

    func testCanBeCreatedWithBridge() {
        let bridge = GhosttyBridge()
        let viewModel = TerminalViewModel(bridge: bridge)
        XCTAssertTrue(
            viewModel.bridge === bridge,
            "ViewModel must hold a reference to the provided bridge"
        )
    }

    func testCanBeCreatedWithoutBridge() {
        let viewModel = TerminalViewModel()
        XCTAssertNil(
            viewModel.bridge,
            "Bridge must be nil when not provided"
        )
    }
}
