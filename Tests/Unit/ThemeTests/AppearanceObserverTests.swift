// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppearanceObserverTests.swift - Tests for auto-switch dark/light mode.

import XCTest
import Combine
@testable import CocxyTerminal

@MainActor
final class AppearanceObserverTests: XCTestCase {

    /// Helper: simulate appearance change and wait for async Task to execute.
    private func simulateAndWait(
        provider: MockAppearanceProvider,
        isDarkMode: Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        provider.simulateAppearanceChange(isDarkMode: isDarkMode)
        // The observer dispatches via Task { @MainActor }, so we need to yield.
        let expectation = expectation(description: "Task yield")
        Task { @MainActor in expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)
    }

    func testDetectDarkModeReturnsDark() {
        let provider = MockAppearanceProvider(isDarkMode: true)
        let observer = AppearanceObserver(appearanceProvider: provider)

        XCTAssertTrue(observer.isDarkMode)
    }

    func testDetectLightModeReturnsLight() {
        let provider = MockAppearanceProvider(isDarkMode: false)
        let observer = AppearanceObserver(appearanceProvider: provider)

        XCTAssertFalse(observer.isDarkMode)
    }

    func testAutoSwitchDisabledDoesNotChangeTheme() throws {
        let engine = ThemeEngineImpl()
        try engine.apply(themeName: "Catppuccin Mocha")

        let provider = MockAppearanceProvider(isDarkMode: false)
        let observer = AppearanceObserver(appearanceProvider: provider)

        observer.startObserving(
            themeEngine: engine,
            darkTheme: "Catppuccin Mocha",
            lightTheme: "Catppuccin Latte",
            autoSwitchEnabled: false
        )

        simulateAndWait(provider: provider, isDarkMode: false)

        XCTAssertEqual(
            engine.activeTheme.metadata.name,
            "Catppuccin Mocha",
            "Theme must not change when auto-switch is disabled"
        )

        observer.stopObserving()
    }

    func testAutoSwitchAppliesDarkThemeWhenSystemIsDark() throws {
        let engine = ThemeEngineImpl()
        try engine.apply(themeName: "Catppuccin Latte")

        let provider = MockAppearanceProvider(isDarkMode: true)
        let observer = AppearanceObserver(appearanceProvider: provider)

        observer.startObserving(
            themeEngine: engine,
            darkTheme: "Catppuccin Mocha",
            lightTheme: "Catppuccin Latte",
            autoSwitchEnabled: true
        )

        simulateAndWait(provider: provider, isDarkMode: true)

        XCTAssertEqual(engine.activeTheme.metadata.name, "Catppuccin Mocha")

        observer.stopObserving()
    }

    func testAutoSwitchAppliesLightThemeWhenSystemIsLight() throws {
        let engine = ThemeEngineImpl()
        try engine.apply(themeName: "Catppuccin Mocha")

        let provider = MockAppearanceProvider(isDarkMode: false)
        let observer = AppearanceObserver(appearanceProvider: provider)

        observer.startObserving(
            themeEngine: engine,
            darkTheme: "Catppuccin Mocha",
            lightTheme: "Catppuccin Latte",
            autoSwitchEnabled: true
        )

        simulateAndWait(provider: provider, isDarkMode: false)

        XCTAssertEqual(engine.activeTheme.metadata.name, "Catppuccin Latte")

        observer.stopObserving()
    }

    func testStopObservingCleansUpResources() {
        let provider = MockAppearanceProvider(isDarkMode: true)
        let observer = AppearanceObserver(appearanceProvider: provider)
        let engine = ThemeEngineImpl()

        observer.startObserving(
            themeEngine: engine,
            darkTheme: "Catppuccin Mocha",
            lightTheme: "Catppuccin Latte",
            autoSwitchEnabled: true
        )

        observer.stopObserving()

        XCTAssertFalse(
            observer.isObserving,
            "Observer must not be observing after stopObserving"
        )
    }

    func testConfigChangeUpdatesThemePair() throws {
        let engine = ThemeEngineImpl()
        let provider = MockAppearanceProvider(isDarkMode: true)
        let observer = AppearanceObserver(appearanceProvider: provider)

        observer.startObserving(
            themeEngine: engine,
            darkTheme: "Catppuccin Mocha",
            lightTheme: "Catppuccin Latte",
            autoSwitchEnabled: true
        )

        observer.updateThemePair(
            darkTheme: "Dracula",
            lightTheme: "Solarized Light"
        )

        simulateAndWait(provider: provider, isDarkMode: true)

        XCTAssertEqual(engine.activeTheme.metadata.name, "Dracula")

        observer.stopObserving()
    }
}

// MARK: - Mock Appearance Provider

final class MockAppearanceProvider: AppearanceProviding, @unchecked Sendable {
    private(set) var isDarkMode: Bool
    private var onChangeCallback: (@Sendable (Bool) -> Void)?

    init(isDarkMode: Bool) {
        self.isDarkMode = isDarkMode
    }

    func observeAppearanceChanges(_ callback: @escaping @Sendable (Bool) -> Void) {
        onChangeCallback = callback
    }

    func stopObserving() {
        onChangeCallback = nil
    }

    func simulateAppearanceChange(isDarkMode: Bool) {
        self.isDarkMode = isDarkMode
        onChangeCallback?(isDarkMode)
    }
}
