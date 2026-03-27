// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// QuickTerminalViewModelTests.swift - Tests for QuickTerminal ViewModel (T-038).

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Quick Terminal View Model Tests

/// Tests for `QuickTerminalViewModel` covering state management, persistence and
/// Combine integration.
///
/// Covers:
/// - Toggle updates isVisible.
/// - Show/hide idempotent.
/// - toState captures current values.
/// - restore applies saved values.
/// - restore with default values.
/// - heightPercent clamped to valid range.
/// - slideEdge/position preserved.
/// - workingDirectory preserved.
/// - Combine publisher emits on toggle.
/// - Multiple toggles produce correct publisher sequence.
/// - Default initialization values.
@MainActor
final class QuickTerminalViewModelTests: XCTestCase {

    private var sut: QuickTerminalViewModel!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = QuickTerminalViewModel()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Test 1: Toggle updates isVisible

    func testToggleUpdatesIsVisible() {
        XCTAssertFalse(sut.isVisible, "Initial state must be hidden")

        sut.toggle()
        XCTAssertTrue(sut.isVisible, "After toggle, must be visible")

        sut.toggle()
        XCTAssertFalse(sut.isVisible, "After second toggle, must be hidden again")
    }

    // MARK: - Test 2: Show is idempotent

    func testShowIsIdempotent() {
        sut.show()
        XCTAssertTrue(sut.isVisible)

        sut.show()
        XCTAssertTrue(sut.isVisible, "Calling show twice must still be visible")
    }

    // MARK: - Test 3: Hide is idempotent

    func testHideIsIdempotent() {
        XCTAssertFalse(sut.isVisible)

        sut.hide()
        XCTAssertFalse(sut.isVisible, "Calling hide when already hidden must be no-op")
    }

    // MARK: - Test 4: toState captures current values

    func testToStateCapturesCurrentValues() {
        sut.show()
        sut.workingDirectory = "/tmp/test"
        sut.heightPercent = 0.6
        sut.position = .bottom

        let state = sut.toState()

        XCTAssertTrue(state.isVisible, "State must capture visible")
        XCTAssertEqual(state.workingDirectory, "/tmp/test")
        XCTAssertEqual(state.heightPercent, 0.6, accuracy: 0.001)
        XCTAssertEqual(state.position, .bottom)
    }

    // MARK: - Test 5: Restore applies saved values

    func testRestoreAppliesSavedValues() {
        let state = QuickTerminalSessionState(
            isVisible: true,
            workingDirectory: "/Users/dev/project",
            heightPercent: 0.7,
            position: .left
        )

        sut.restore(from: state)

        XCTAssertTrue(sut.isVisible)
        XCTAssertEqual(sut.workingDirectory, "/Users/dev/project")
        XCTAssertEqual(sut.heightPercent, 0.7, accuracy: 0.001)
        XCTAssertEqual(sut.position, .left)
    }

    // MARK: - Test 6: Restore with default values

    func testRestoreWithDefaultValues() {
        let state = QuickTerminalSessionState(
            isVisible: false,
            workingDirectory: "~",
            heightPercent: 0.4,
            position: .top
        )

        sut.restore(from: state)

        XCTAssertFalse(sut.isVisible)
        XCTAssertEqual(sut.workingDirectory, "~")
        XCTAssertEqual(sut.heightPercent, 0.4, accuracy: 0.001)
        XCTAssertEqual(sut.position, .top)
    }

    // MARK: - Test 7: Height percent clamped below minimum

    func testHeightPercentClampedBelowMinimum() {
        sut.heightPercent = 0.05  // Below 0.2 minimum.

        let state = sut.toState()
        XCTAssertGreaterThanOrEqual(state.heightPercent, 0.2,
                                    "Height percent must be clamped to >= 0.2")
    }

    // MARK: - Test 8: Height percent clamped above maximum

    func testHeightPercentClampedAboveMaximum() {
        sut.heightPercent = 0.99  // Above 0.9 maximum.

        let state = sut.toState()
        XCTAssertLessThanOrEqual(state.heightPercent, 0.9,
                                 "Height percent must be clamped to <= 0.9")
    }

    // MARK: - Test 9: Position preserved through state

    func testPositionPreservedThroughState() {
        for position in [QuickTerminalPosition.top, .bottom, .left, .right] {
            sut.position = position
            let state = sut.toState()
            XCTAssertEqual(state.position, position,
                           "Position \(position) must be preserved in state")
        }
    }

    // MARK: - Test 10: Working directory preserved through state

    func testWorkingDirectoryPreservedThroughState() {
        sut.workingDirectory = "/Users/arturo/projects/cocxy"
        let state = sut.toState()
        XCTAssertEqual(state.workingDirectory, "/Users/arturo/projects/cocxy")
    }

    // MARK: - Test 11: Combine publisher emits on toggle

    func testCombinePublisherEmitsOnToggle() {
        var emittedValues: [Bool] = []
        let expectation = expectation(description: "Publisher emits")
        expectation.expectedFulfillmentCount = 2

        sut.$isVisible
            .dropFirst()  // Skip initial value.
            .sink { value in
                emittedValues.append(value)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        sut.toggle()  // false -> true
        sut.toggle()  // true -> false

        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(emittedValues, [true, false],
                       "Publisher must emit [true, false] after two toggles")
    }

    // MARK: - Test 12: Default initialization values

    func testDefaultInitializationValues() {
        XCTAssertFalse(sut.isVisible)
        XCTAssertEqual(sut.position, .top)
        XCTAssertEqual(sut.heightPercent, 0.4, accuracy: 0.001)
        XCTAssertEqual(sut.workingDirectory, "~")
    }

    // MARK: - Test 13: Round-trip through state preserves all fields

    func testRoundTripThroughStatePreservesAllFields() {
        sut.show()
        sut.workingDirectory = "/opt/test"
        sut.heightPercent = 0.55
        sut.position = .right

        let state = sut.toState()

        let newVM = QuickTerminalViewModel()
        newVM.restore(from: state)

        XCTAssertEqual(newVM.isVisible, sut.isVisible)
        XCTAssertEqual(newVM.workingDirectory, sut.workingDirectory)
        XCTAssertEqual(newVM.heightPercent, sut.heightPercent, accuracy: 0.001)
        XCTAssertEqual(newVM.position, sut.position)
    }
}
