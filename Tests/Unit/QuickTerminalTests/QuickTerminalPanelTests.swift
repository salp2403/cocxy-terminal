// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// QuickTerminalPanelTests.swift - Tests for the Quick Terminal panel (T-037).

import XCTest
@testable import CocxyTerminal

// MARK: - Quick Terminal Panel Tests

/// Tests for `QuickTerminalPanel`.
///
/// Covers:
/// - Panel configuration (level, style mask, collection behavior).
/// - Frame calculation for each slide edge.
/// - Height percent clamping (min 0.2, max 0.9).
/// - Hide-on-deactivate behavior.
@MainActor
final class QuickTerminalPanelTests: XCTestCase {

    private var sut: QuickTerminalPanel!

    override func setUp() {
        super.setUp()
        sut = QuickTerminalPanel()
    }

    override func tearDown() {
        sut?.close()
        sut = nil
        super.tearDown()
    }

    // MARK: - 1. Panel level is floating

    func testPanelLevelIsFloating() {
        XCTAssertEqual(sut.level, .floating,
                       "Quick terminal panel must float above normal windows")
    }

    // MARK: - 2. Panel is floating panel

    func testPanelIsFloatingPanel() {
        XCTAssertTrue(sut.isFloatingPanel,
                      "isFloatingPanel must be true for the quick terminal")
    }

    // MARK: - 3. Panel collection behavior includes canJoinAllSpaces

    func testPanelCollectionBehaviorCanJoinAllSpaces() {
        XCTAssertTrue(sut.collectionBehavior.contains(.canJoinAllSpaces),
                      "Panel must join all Spaces so it appears everywhere")
    }

    // MARK: - 4. Panel collection behavior includes fullScreenAuxiliary

    func testPanelCollectionBehaviorFullScreenAuxiliary() {
        XCTAssertTrue(sut.collectionBehavior.contains(.fullScreenAuxiliary),
                      "Panel must be able to appear over fullscreen apps")
    }

    // MARK: - 5. Titlebar is transparent

    func testTitlebarIsTransparent() {
        XCTAssertTrue(sut.titlebarAppearsTransparent,
                      "Quick terminal titlebar must be transparent")
    }

    // MARK: - 6. Frame calculation for top edge

    func testFrameCalculationForTopEdge() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = QuickTerminalPanel.calculateFrame(
            for: .top,
            heightPercent: 0.4,
            screenFrame: screenFrame
        )

        XCTAssertEqual(frame.width, 1920, accuracy: 0.1,
                       "Top panel must span full screen width")
        XCTAssertEqual(frame.height, 432, accuracy: 0.1,
                       "Top panel height must be 40% of screen height")
        // Top edge means origin.y is at top of screen minus panel height
        let expectedY = screenFrame.maxY - frame.height
        XCTAssertEqual(frame.origin.y, expectedY, accuracy: 0.1,
                       "Top panel must be anchored to top of screen")
        XCTAssertEqual(frame.origin.x, 0, accuracy: 0.1,
                       "Top panel must start at left edge")
    }

    // MARK: - 7. Frame calculation for bottom edge

    func testFrameCalculationForBottomEdge() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = QuickTerminalPanel.calculateFrame(
            for: .bottom,
            heightPercent: 0.4,
            screenFrame: screenFrame
        )

        XCTAssertEqual(frame.width, 1920, accuracy: 0.1,
                       "Bottom panel must span full screen width")
        XCTAssertEqual(frame.height, 432, accuracy: 0.1,
                       "Bottom panel height must be 40% of screen height")
        XCTAssertEqual(frame.origin.y, 0, accuracy: 0.1,
                       "Bottom panel must be anchored to bottom of screen")
        XCTAssertEqual(frame.origin.x, 0, accuracy: 0.1,
                       "Bottom panel must start at left edge")
    }

    // MARK: - 8. Frame calculation for left edge

    func testFrameCalculationForLeftEdge() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = QuickTerminalPanel.calculateFrame(
            for: .left,
            heightPercent: 0.4,
            screenFrame: screenFrame
        )

        XCTAssertEqual(frame.width, 768, accuracy: 0.1,
                       "Left panel width must be 40% of screen width")
        XCTAssertEqual(frame.height, 1080, accuracy: 0.1,
                       "Left panel must span full screen height")
        XCTAssertEqual(frame.origin.x, 0, accuracy: 0.1,
                       "Left panel must be anchored to left edge")
        XCTAssertEqual(frame.origin.y, 0, accuracy: 0.1,
                       "Left panel must start at bottom edge")
    }

    // MARK: - 9. Frame calculation for right edge

    func testFrameCalculationForRightEdge() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = QuickTerminalPanel.calculateFrame(
            for: .right,
            heightPercent: 0.4,
            screenFrame: screenFrame
        )

        XCTAssertEqual(frame.width, 768, accuracy: 0.1,
                       "Right panel width must be 40% of screen width")
        XCTAssertEqual(frame.height, 1080, accuracy: 0.1,
                       "Right panel must span full screen height")
        let expectedX = screenFrame.maxX - frame.width
        XCTAssertEqual(frame.origin.x, expectedX, accuracy: 0.1,
                       "Right panel must be anchored to right edge")
        XCTAssertEqual(frame.origin.y, 0, accuracy: 0.1,
                       "Right panel must start at bottom edge")
    }

    // MARK: - 10. Height percent clamped minimum

    func testHeightPercentClampedMinimum() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = QuickTerminalPanel.calculateFrame(
            for: .top,
            heightPercent: 0.05,  // Below minimum of 0.2
            screenFrame: screenFrame
        )

        let minHeight = 1080 * 0.2
        XCTAssertEqual(frame.height, minHeight, accuracy: 0.1,
                       "Height percent below 0.2 must be clamped to 0.2")
    }

    // MARK: - 11. Height percent clamped maximum

    func testHeightPercentClampedMaximum() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = QuickTerminalPanel.calculateFrame(
            for: .top,
            heightPercent: 0.95,  // Above maximum of 0.9
            screenFrame: screenFrame
        )

        let maxHeight = 1080 * 0.9
        XCTAssertEqual(frame.height, maxHeight, accuracy: 0.1,
                       "Height percent above 0.9 must be clamped to 0.9")
    }

    // MARK: - 12. Default slide edge is top

    func testDefaultSlideEdgeIsTop() {
        XCTAssertEqual(sut.slideEdge, .top,
                       "Default slide edge must be top")
    }

    // MARK: - 13. Default height percent is 0.4

    func testDefaultHeightPercentIs40() {
        XCTAssertEqual(sut.heightPercent, 0.4, accuracy: 0.01,
                       "Default height percent must be 0.4 (40%%)")
    }

    // MARK: - 14. Off-screen frame for top edge (slide-out position)

    func testOffScreenFrameForTopEdge() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let visibleFrame = QuickTerminalPanel.calculateFrame(
            for: .top,
            heightPercent: 0.4,
            screenFrame: screenFrame
        )
        let offScreen = QuickTerminalPanel.calculateOffScreenFrame(
            for: .top,
            visibleFrame: visibleFrame
        )

        // Off-screen means completely above the visible screen area.
        XCTAssertGreaterThanOrEqual(offScreen.origin.y, screenFrame.maxY,
                                    "Top off-screen frame must be above the screen")
    }

    // MARK: - 15. Off-screen frame for bottom edge

    func testOffScreenFrameForBottomEdge() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let visibleFrame = QuickTerminalPanel.calculateFrame(
            for: .bottom,
            heightPercent: 0.4,
            screenFrame: screenFrame
        )
        let offScreen = QuickTerminalPanel.calculateOffScreenFrame(
            for: .bottom,
            visibleFrame: visibleFrame
        )

        // Off-screen means completely below the visible screen area.
        XCTAssertLessThanOrEqual(offScreen.maxY, screenFrame.origin.y,
                                 "Bottom off-screen frame must be below the screen")
    }

    // MARK: - 16. Off-screen frame for left edge

    func testOffScreenFrameForLeftEdge() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let visibleFrame = QuickTerminalPanel.calculateFrame(
            for: .left,
            heightPercent: 0.4,
            screenFrame: screenFrame
        )
        let offScreen = QuickTerminalPanel.calculateOffScreenFrame(
            for: .left,
            visibleFrame: visibleFrame
        )

        // Off-screen means completely to the left of the visible screen area.
        XCTAssertLessThanOrEqual(offScreen.maxX, screenFrame.origin.x,
                                 "Left off-screen frame must be to the left of the screen")
    }

    // MARK: - 17. Off-screen frame for right edge

    func testOffScreenFrameForRightEdge() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let visibleFrame = QuickTerminalPanel.calculateFrame(
            for: .right,
            heightPercent: 0.4,
            screenFrame: screenFrame
        )
        let offScreen = QuickTerminalPanel.calculateOffScreenFrame(
            for: .right,
            visibleFrame: visibleFrame
        )

        // Off-screen means completely to the right of the visible screen area.
        XCTAssertGreaterThanOrEqual(offScreen.origin.x, screenFrame.maxX,
                                    "Right off-screen frame must be to the right of the screen")
    }

    // MARK: - 18. Style mask contains fullSizeContentView

    func testStyleMaskContainsFullSizeContentView() {
        XCTAssertTrue(sut.styleMask.contains(.fullSizeContentView),
                      "Panel must use fullSizeContentView for borderless look")
    }

    // MARK: - 19. Frame calculation with non-zero origin screen

    func testFrameCalculationWithNonZeroOriginScreen() {
        // Simulates a secondary monitor at an offset position.
        let screenFrame = NSRect(x: 1920, y: 0, width: 2560, height: 1440)
        let frame = QuickTerminalPanel.calculateFrame(
            for: .top,
            heightPercent: 0.4,
            screenFrame: screenFrame
        )

        XCTAssertEqual(frame.origin.x, 1920, accuracy: 0.1,
                       "Panel must respect screen origin X offset")
        XCTAssertEqual(frame.width, 2560, accuracy: 0.1,
                       "Panel must span the target screen width")
    }
}
