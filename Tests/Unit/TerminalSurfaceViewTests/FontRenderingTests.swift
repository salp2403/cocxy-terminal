// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// FontRenderingTests.swift - Tests for font config, fallback chain and zoom.

import XCTest
import AppKit
import Combine
@testable import CocxyTerminal

// MARK: - Font Config Tests

/// Tests that font family and size are correctly read from config.
final class FontConfigTests: XCTestCase {

    func testDefaultFontFamilyIsJetBrainsMono() {
        let defaults = AppearanceConfig.defaults
        XCTAssertEqual(
            defaults.fontFamily, "JetBrainsMono Nerd Font",
            "Default font family must be JetBrainsMono Nerd Font"
        )
    }

    func testDefaultFontSizeIsFourteen() {
        let defaults = AppearanceConfig.defaults
        XCTAssertEqual(
            defaults.fontSize, 14.0,
            "Default font size must be 14 points"
        )
    }

    func testFontFamilyCanBeConfigured() throws {
        let toml = """
        [appearance]
        font-family = "Fira Code"
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        XCTAssertEqual(
            service.current.appearance.fontFamily, "Fira Code",
            "Font family must be configurable via TOML"
        )
    }
}

// MARK: - Font Fallback Tests

/// Tests the font fallback chain: JetBrainsMono NF -> JetBrains Mono -> Menlo.
@MainActor
final class FontFallbackTests: XCTestCase {

    func testFontFallbackReturnsUsableFont() {
        let resolved = FontFallbackResolver.resolveFont(
            family: "NonexistentFontThatDoesNotExist_ABC123",
            size: 14.0
        )

        XCTAssertNotNil(
            resolved,
            "Font fallback must always return a usable font"
        )
    }

    func testFontFallbackReturnsRequestedSize() {
        let resolved = FontFallbackResolver.resolveFont(
            family: "Menlo",
            size: 16.0
        )

        XCTAssertNotNil(resolved)
        XCTAssertEqual(
            Double(resolved?.pointSize ?? 0), 16.0, accuracy: 0.1,
            "Resolved font must use the requested point size"
        )
    }

    func testFontFallbackChainForJetBrainsMono() {
        let chain = FontFallbackResolver.fallbackChain(
            for: "JetBrainsMono Nerd Font"
        )

        XCTAssertEqual(chain.count, 3, "Fallback chain must have 3 entries")
        XCTAssertEqual(chain[0], "JetBrainsMono Nerd Font")
        XCTAssertEqual(chain[1], "JetBrains Mono")
        XCTAssertEqual(chain[2], "Menlo")
    }

    func testFontFallbackChainAlwaysEndWithMenlo() {
        let chain = FontFallbackResolver.fallbackChain(for: "CustomFont")
        XCTAssertEqual(chain.last, "Menlo",
            "Fallback chain must always end with Menlo"
        )
    }
}

// MARK: - Font Zoom Tests

/// Tests for Cmd+/Cmd-/Cmd+0 font size zoom.
@MainActor
final class FontZoomTests: XCTestCase {

    func testZoomInIncreasesFontSize() {
        let viewModel = TerminalViewModel()
        viewModel.setDefaultFontSize(14.0)

        viewModel.zoomIn()
        XCTAssertEqual(
            viewModel.currentFontSize, 15.0,
            "Zoom in must increase font size by 1 point"
        )
    }

    func testZoomOutDecreasesFontSize() {
        let viewModel = TerminalViewModel()
        viewModel.setDefaultFontSize(14.0)

        viewModel.zoomOut()
        XCTAssertEqual(
            viewModel.currentFontSize, 13.0,
            "Zoom out must decrease font size by 1 point"
        )
    }

    func testResetZoomRestoresDefaultSize() {
        let viewModel = TerminalViewModel()
        viewModel.setDefaultFontSize(14.0)

        viewModel.zoomIn()
        viewModel.zoomIn()
        viewModel.zoomIn()
        viewModel.resetZoom()

        XCTAssertEqual(
            viewModel.currentFontSize, 14.0,
            "Reset zoom must restore the configured default font size"
        )
    }

    func testZoomInDoesNotExceedMaximum() {
        let viewModel = TerminalViewModel()
        viewModel.setDefaultFontSize(71.0)

        viewModel.zoomIn()
        viewModel.zoomIn()
        viewModel.zoomIn()

        XCTAssertEqual(
            viewModel.currentFontSize, 72.0,
            "Font size must not exceed 72 points"
        )
    }

    func testZoomOutDoesNotGoBelowMinimum() {
        let viewModel = TerminalViewModel()
        viewModel.setDefaultFontSize(7.0)

        viewModel.zoomOut()
        viewModel.zoomOut()
        viewModel.zoomOut()

        XCTAssertEqual(
            viewModel.currentFontSize, 6.0,
            "Font size must not go below 6 points"
        )
    }

    func testFontSizePublishesThroughCombine() {
        let viewModel = TerminalViewModel()
        viewModel.setDefaultFontSize(14.0)

        var receivedSizes: [CGFloat] = []
        let cancellable = viewModel.$currentFontSize
            .dropFirst()
            .sink { receivedSizes.append($0) }

        viewModel.zoomIn()
        viewModel.zoomOut()

        XCTAssertEqual(
            receivedSizes, [15.0, 14.0],
            "Font size changes must publish through Combine"
        )

        cancellable.cancel()
    }

    func testSetDefaultFontSizeClampsToValidRange() {
        let viewModel = TerminalViewModel()

        viewModel.setDefaultFontSize(2.0)
        XCTAssertEqual(viewModel.defaultFontSize, 6.0,
            "Default font size below minimum must be clamped to 6"
        )

        viewModel.setDefaultFontSize(100.0)
        XCTAssertEqual(viewModel.defaultFontSize, 72.0,
            "Default font size above maximum must be clamped to 72"
        )
    }
}
