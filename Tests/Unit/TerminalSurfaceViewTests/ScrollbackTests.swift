// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ScrollbackTests.swift - Tests for scrollback buffer config and scroll state.

import XCTest
import Combine
import GhosttyKit
@testable import CocxyTerminal

// MARK: - Scrollback Configuration Tests

/// Tests that scrollback buffer size is correctly configured.
final class ScrollbackConfigTests: XCTestCase {

    func testDefaultScrollbackLinesInConfig() {
        let defaults = CocxyConfig.defaults
        XCTAssertEqual(
            defaults.terminal.scrollbackLines, 10_000,
            "Default scrollback must be 10,000 lines"
        )
    }

    func testScrollbackLinesCanBeConfigured() throws {
        let toml = """
        [terminal]
        scrollback-lines = 50000
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        XCTAssertEqual(
            service.current.terminal.scrollbackLines, 50_000,
            "Scrollback lines must be configurable via TOML"
        )
    }

    func testScrollbackLinesMinimumClamp() throws {
        let toml = """
        [terminal]
        scrollback-lines = -1
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        XCTAssertEqual(
            service.current.terminal.scrollbackLines, 0,
            "Scrollback lines below 0 must be clamped to 0"
        )
    }

    func testScrollbackLinesZeroDisablesScrollback() throws {
        let toml = """
        [terminal]
        scrollback-lines = 0
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        XCTAssertEqual(
            service.current.terminal.scrollbackLines, 0,
            "Scrollback lines of 0 must be allowed (disables scrollback)"
        )
    }
}

// MARK: - Scroll State Tracking Tests

/// Tests that the ViewModel correctly tracks scroll position.
@MainActor
final class ScrollStateTrackingTests: XCTestCase {

    func testDefaultIsScrolledBackIsFalse() {
        let viewModel = TerminalViewModel()
        XCTAssertFalse(
            viewModel.isScrolledBack,
            "isScrolledBack must be false by default"
        )
    }

    func testIsScrolledBackCanBeSetToTrue() {
        let viewModel = TerminalViewModel()
        viewModel.isScrolledBack = true
        XCTAssertTrue(
            viewModel.isScrolledBack,
            "isScrolledBack must be settable to true when user scrolls up"
        )
    }

    func testIsScrolledBackPublishesThroughCombine() {
        let viewModel = TerminalViewModel()
        var receivedValues: [Bool] = []
        let cancellable = viewModel.$isScrolledBack
            .dropFirst()
            .sink { receivedValues.append($0) }

        viewModel.isScrolledBack = true
        viewModel.isScrolledBack = false

        XCTAssertEqual(
            receivedValues, [true, false],
            "isScrolledBack changes must publish through Combine"
        )

        cancellable.cancel()
    }
}

// MARK: - Scroll Navigation Key Tests

/// Tests that scroll navigation keys are correctly mapped in GhosttyKeyConverter.
final class ScrollNavigationKeyTests: XCTestCase {

    func testPageUpKeyCode() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x74)
        XCTAssertEqual(key, GHOSTTY_KEY_PAGE_UP,
            "macOS keyCode 0x74 must map to GHOSTTY_KEY_PAGE_UP"
        )
    }

    func testPageDownKeyCode() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x79)
        XCTAssertEqual(key, GHOSTTY_KEY_PAGE_DOWN,
            "macOS keyCode 0x79 must map to GHOSTTY_KEY_PAGE_DOWN"
        )
    }

    func testHomeKeyCode() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x73)
        XCTAssertEqual(key, GHOSTTY_KEY_HOME,
            "macOS keyCode 0x73 must map to GHOSTTY_KEY_HOME"
        )
    }

    func testEndKeyCode() {
        let key = GhosttyKeyConverter.ghosttyKey(fromMacOSKeyCode: 0x77)
        XCTAssertEqual(key, GHOSTTY_KEY_END,
            "macOS keyCode 0x77 must map to GHOSTTY_KEY_END"
        )
    }
}
