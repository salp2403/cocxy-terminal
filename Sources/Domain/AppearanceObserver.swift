// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppearanceObserver.swift - Auto-switch dark/light theme based on macOS appearance.

import Foundation

// MARK: - Appearance Providing Protocol

/// Abstraction over macOS appearance detection.
///
/// Allows injecting test doubles that simulate appearance changes
/// without depending on actual system appearance.
protocol AppearanceProviding: AnyObject {
    /// Whether the system is currently in dark mode.
    var isDarkMode: Bool { get }

    /// Starts observing appearance changes. The callback is invoked
    /// with `true` for dark mode and `false` for light mode.
    func observeAppearanceChanges(_ callback: @escaping @Sendable (Bool) -> Void)

    /// Stops observing appearance changes.
    func stopObserving()
}

// MARK: - System Appearance Provider

/// Production implementation that uses macOS APIs to detect appearance changes.
///
/// Uses `DistributedNotificationCenter` to listen for
/// `AppleInterfaceThemeChangedNotification`.
final class SystemAppearanceProvider: AppearanceProviding {

    var isDarkMode: Bool {
        let appearance = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
        return appearance?.lowercased() == "dark"
    }

    private var notificationObserver: NSObjectProtocol?

    func observeAppearanceChanges(_ callback: @escaping @Sendable (Bool) -> Void) {
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let isDark = self.isDarkMode
            callback(isDark)
        }
    }

    func stopObserving() {
        if let observer = notificationObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            notificationObserver = nil
        }
    }
}

// MARK: - Appearance Observer

/// Observes macOS appearance changes (dark <-> light) and automatically
/// switches themes in the `ThemeEngineImpl`.
///
/// When auto-switch is enabled and the system appearance changes, the
/// observer applies the configured dark or light theme. When disabled,
/// appearance changes are ignored.
///
/// The theme pair (dark theme name, light theme name) can be updated
/// at runtime via `updateThemePair(darkTheme:lightTheme:)`.
///
/// Isolated to `@MainActor` because it interacts with `ThemeEngineImpl`
/// which is also main-actor-isolated.
///
/// - SeeAlso: ADR-007 (Theme system)
@MainActor
final class AppearanceObserver {

    // MARK: - Properties

    /// The appearance provider used to detect dark/light mode.
    private let appearanceProvider: AppearanceProviding

    /// Whether this observer is actively watching for changes.
    private(set) var isObserving: Bool = false

    /// Whether the system is currently in dark mode.
    var isDarkMode: Bool {
        appearanceProvider.isDarkMode
    }

    /// The currently configured dark theme name.
    private var darkThemeName: String = ""

    /// The currently configured light theme name.
    private var lightThemeName: String = ""

    /// Whether auto-switching is enabled.
    private var autoSwitchEnabled: Bool = false

    /// Weak reference to the theme engine to avoid retain cycles.
    private weak var themeEngine: ThemeEngineImpl?

    // MARK: - Initialization

    /// Creates an observer with a custom appearance provider.
    ///
    /// - Parameter appearanceProvider: The source of appearance information.
    ///   Defaults to `SystemAppearanceProvider` for production use.
    init(appearanceProvider: AppearanceProviding = SystemAppearanceProvider()) {
        self.appearanceProvider = appearanceProvider
    }

    // MARK: - Observation

    /// Starts observing appearance changes and auto-switching themes.
    ///
    /// When the system appearance changes:
    /// - If `autoSwitchEnabled` is true, applies the corresponding theme.
    /// - If `autoSwitchEnabled` is false, does nothing.
    ///
    /// - Parameters:
    ///   - themeEngine: The engine to apply theme changes to.
    ///   - darkTheme: Name of the theme to apply in dark mode.
    ///   - lightTheme: Name of the theme to apply in light mode.
    ///   - autoSwitchEnabled: Whether auto-switching is active.
    func startObserving(
        themeEngine: ThemeEngineImpl,
        darkTheme: String,
        lightTheme: String,
        autoSwitchEnabled: Bool
    ) {
        self.themeEngine = themeEngine
        self.darkThemeName = darkTheme
        self.lightThemeName = lightTheme
        self.autoSwitchEnabled = autoSwitchEnabled
        self.isObserving = true

        appearanceProvider.observeAppearanceChanges { [weak self] isDark in
            // Dispatch to MainActor safely — the notification may arrive on any thread
            // depending on the NotificationCenter queue configuration.
            Task { @MainActor in
                self?.handleAppearanceChange(isDark: isDark)
            }
        }
    }

    /// Stops observing appearance changes and releases resources.
    func stopObserving() {
        appearanceProvider.stopObserving()
        isObserving = false
        themeEngine = nil
    }

    /// Updates the dark/light theme pair without restarting observation.
    ///
    /// - Parameters:
    ///   - darkTheme: New dark theme name.
    ///   - lightTheme: New light theme name.
    func updateThemePair(darkTheme: String, lightTheme: String) {
        self.darkThemeName = darkTheme
        self.lightThemeName = lightTheme
    }

    // MARK: - Private

    /// Handles an appearance change by applying the correct theme.
    private func handleAppearanceChange(isDark: Bool) {
        guard autoSwitchEnabled, let engine = themeEngine else { return }

        let targetThemeName = isDark ? darkThemeName : lightThemeName
        try? engine.apply(themeName: targetThemeName)
    }
}
