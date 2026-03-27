// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ContrastRatioTests.swift - Tests for WCAG contrast ratio calculations.

import XCTest
@testable import CocxyTerminal

// MARK: - Contrast Ratio Tests

/// Tests for `AccessibilityHelpers.contrastRatio(_:_:)` and related utilities.
///
/// Verifies WCAG 2.1 contrast ratio calculations:
/// - Black/white produces the maximum ratio (21:1).
/// - Same color produces the minimum ratio (1:1).
/// - Catppuccin Mocha text on background meets AA (>= 4.5:1).
/// - Catppuccin Latte text on background meets AA (>= 4.5:1).
/// - UI element colors meet the 3:1 threshold for non-text elements.
@MainActor
final class ContrastRatioTests: XCTestCase {

    // MARK: - Fundamental Calculations

    func testBlackOnWhiteProducesMaximumContrast() {
        let ratio = AccessibilityHelpers.contrastRatio(.black, .white)

        // WCAG defines max contrast as 21:1 (black on white).
        XCTAssertEqual(ratio, 21.0, accuracy: 0.1,
                       "Black on white should produce a contrast ratio of 21:1")
    }

    func testWhiteOnBlackProducesMaximumContrast() {
        let ratio = AccessibilityHelpers.contrastRatio(.white, .black)

        XCTAssertEqual(ratio, 21.0, accuracy: 0.1,
                       "Order of colors should not affect the ratio")
    }

    func testSameColorProducesMinimumContrast() {
        let ratio = AccessibilityHelpers.contrastRatio(.red, .red)

        XCTAssertEqual(ratio, 1.0, accuracy: 0.01,
                       "Same color should produce a contrast ratio of 1:1")
    }

    func testRelativeLuminanceOfBlackIsZero() {
        let luminance = AccessibilityHelpers.relativeLuminance(.black)

        XCTAssertEqual(luminance, 0.0, accuracy: 0.001,
                       "Black should have a relative luminance of 0")
    }

    func testRelativeLuminanceOfWhiteIsOne() {
        let luminance = AccessibilityHelpers.relativeLuminance(.white)

        XCTAssertEqual(luminance, 1.0, accuracy: 0.001,
                       "White should have a relative luminance of 1")
    }

    // MARK: - Catppuccin Mocha Theme Contrast

    func testMochaTextOnBackgroundMeetsWCAGAA() {
        // Mocha foreground (Text): #cdd6f4 -> RGB(205, 214, 244)
        // Mocha background (Base): #1e1e2e -> RGB(30, 30, 46)
        let foreground = NSColor(
            red: 205.0 / 255.0, green: 214.0 / 255.0,
            blue: 244.0 / 255.0, alpha: 1.0
        )
        let background = NSColor(
            red: 30.0 / 255.0, green: 30.0 / 255.0,
            blue: 46.0 / 255.0, alpha: 1.0
        )

        let ratio = AccessibilityHelpers.contrastRatio(foreground, background)

        XCTAssertGreaterThanOrEqual(ratio, 4.5,
                                    "Catppuccin Mocha text on base must meet WCAG AA (>= 4.5:1), got \(ratio):1")
    }

    // MARK: - Catppuccin Latte Theme Contrast

    func testLatteTextOnBackgroundMeetsWCAGAA() {
        // Latte foreground (Text): #4c4f69 -> RGB(76, 79, 105)
        // Latte background (Base): #eff1f5 -> RGB(239, 241, 245)
        let foreground = NSColor(
            red: 76.0 / 255.0, green: 79.0 / 255.0,
            blue: 105.0 / 255.0, alpha: 1.0
        )
        let background = NSColor(
            red: 239.0 / 255.0, green: 241.0 / 255.0,
            blue: 245.0 / 255.0, alpha: 1.0
        )

        let ratio = AccessibilityHelpers.contrastRatio(foreground, background)

        XCTAssertGreaterThanOrEqual(ratio, 4.5,
                                    "Catppuccin Latte text on base must meet WCAG AA (>= 4.5:1), got \(ratio):1")
    }

    // MARK: - UI Element Contrast (3:1 threshold)

    func testSystemBlueOnMochaBackgroundMeetsUIThreshold() {
        // Agent working indicator: systemBlue on Mocha base.
        // systemBlue is approximately RGB(0, 122, 255).
        let blue = NSColor(
            red: 0.0 / 255.0, green: 122.0 / 255.0,
            blue: 255.0 / 255.0, alpha: 1.0
        )
        let background = NSColor(
            red: 30.0 / 255.0, green: 30.0 / 255.0,
            blue: 46.0 / 255.0, alpha: 1.0
        )

        let ratio = AccessibilityHelpers.contrastRatio(blue, background)

        XCTAssertGreaterThanOrEqual(ratio, 3.0,
                                    "Blue indicator on Mocha base must meet 3:1 for UI elements, got \(ratio):1")
    }

    func testSystemRedOnMochaBackgroundMeetsUIThreshold() {
        // Agent error indicator: systemRed on Mocha base.
        // systemRed is approximately RGB(255, 59, 48).
        let red = NSColor(
            red: 255.0 / 255.0, green: 59.0 / 255.0,
            blue: 48.0 / 255.0, alpha: 1.0
        )
        let background = NSColor(
            red: 30.0 / 255.0, green: 30.0 / 255.0,
            blue: 46.0 / 255.0, alpha: 1.0
        )

        let ratio = AccessibilityHelpers.contrastRatio(red, background)

        XCTAssertGreaterThanOrEqual(ratio, 3.0,
                                    "Red indicator on Mocha base must meet 3:1 for UI elements, got \(ratio):1")
    }

    func testSystemGreenOnMochaBackgroundMeetsUIThreshold() {
        // Agent finished indicator: systemGreen on Mocha base.
        // systemGreen is approximately RGB(52, 199, 89).
        let green = NSColor(
            red: 52.0 / 255.0, green: 199.0 / 255.0,
            blue: 89.0 / 255.0, alpha: 1.0
        )
        let background = NSColor(
            red: 30.0 / 255.0, green: 30.0 / 255.0,
            blue: 46.0 / 255.0, alpha: 1.0
        )

        let ratio = AccessibilityHelpers.contrastRatio(green, background)

        XCTAssertGreaterThanOrEqual(ratio, 3.0,
                                    "Green indicator on Mocha base must meet 3:1 for UI elements, got \(ratio):1")
    }

    func testSystemYellowOnMochaBackgroundMeetsUIThreshold() {
        // Agent waiting indicator: systemYellow on Mocha base.
        // systemYellow is approximately RGB(255, 204, 0).
        let yellow = NSColor(
            red: 255.0 / 255.0, green: 204.0 / 255.0,
            blue: 0.0 / 255.0, alpha: 1.0
        )
        let background = NSColor(
            red: 30.0 / 255.0, green: 30.0 / 255.0,
            blue: 46.0 / 255.0, alpha: 1.0
        )

        let ratio = AccessibilityHelpers.contrastRatio(yellow, background)

        XCTAssertGreaterThanOrEqual(ratio, 3.0,
                                    "Yellow indicator on Mocha base must meet 3:1 for UI elements, got \(ratio):1")
    }

    // MARK: - Meets Threshold Helper

    func testMeetsAAReturnsTrueForSufficientContrast() {
        let passes = AccessibilityHelpers.meetsWCAGAA(
            foreground: .white, background: .black
        )

        XCTAssertTrue(passes,
                      "White on black (21:1) should meet WCAG AA (4.5:1)")
    }

    func testMeetsAAReturnsFalseForInsufficientContrast() {
        // Very similar grays should fail.
        let lightGray = NSColor(white: 0.6, alpha: 1.0)
        let slightlyDarkerGray = NSColor(white: 0.5, alpha: 1.0)

        let passes = AccessibilityHelpers.meetsWCAGAA(
            foreground: lightGray, background: slightlyDarkerGray
        )

        XCTAssertFalse(passes,
                       "Very similar grays should not meet WCAG AA")
    }

    func testMeetsLargeTextThresholdAt3To1() {
        let passes = AccessibilityHelpers.meetsWCAGLargeText(
            foreground: .white, background: .black
        )

        XCTAssertTrue(passes,
                      "White on black should meet the 3:1 large text threshold")
    }
}
