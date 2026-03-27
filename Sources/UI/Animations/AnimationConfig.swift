// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AnimationConfig.swift - Centralized animation timing configuration.

import AppKit

// MARK: - Animation Config

/// Centralized configuration for all UI animation durations.
///
/// All animation code in the app should use these constants instead of
/// hardcoded values. The `duration(_:)` method respects the system
/// reduce-motion preference, returning 0 when motion should be reduced.
///
/// ## Reduce Motion
///
/// macOS users can enable "Reduce motion" in System Settings > Accessibility
/// > Display. When enabled, all animations become instant (duration = 0).
/// This is checked dynamically -- if the user toggles the setting while
/// the app is running, the next animation call will respect the new value.
///
/// ## Usage
///
/// ```swift
/// let duration = AnimationConfig.duration(AnimationConfig.tabAppearDuration)
/// NSAnimationContext.runAnimationGroup { context in
///     context.duration = duration
///     view.animator().alphaValue = 1.0
/// }
/// ```
enum AnimationConfig {

    // MARK: - Duration Constants

    /// Duration for a new tab appearing in the tab bar.
    static let tabAppearDuration: TimeInterval = 0.25

    /// Duration for a tab disappearing from the tab bar.
    static let tabDisappearDuration: TimeInterval = 0.2

    /// Duration for split pane creation/removal transitions.
    static let splitTransitionDuration: TimeInterval = 0.3

    /// Duration for agent state color transitions.
    static let stateColorTransitionDuration: TimeInterval = 0.3

    /// Duration for quick terminal slide in/out.
    static let quickTerminalSlideDuration: TimeInterval = 0.25

    /// Duration for notification toast display (fade in + hold + fade out).
    static let notificationToastDuration: TimeInterval = 1.5

    /// Duration for overlay panels sliding in from the right edge.
    static let overlaySlideInDuration: TimeInterval = 0.25

    /// Duration for overlay panels sliding out.
    static let overlaySlideOutDuration: TimeInterval = 0.2

    /// Duration for command palette fade in.
    static let commandPaletteFadeDuration: TimeInterval = 0.15

    /// Duration for notification ring pulse cycle.
    static let notificationRingPulseDuration: TimeInterval = 1.2

    // MARK: - Reduce Motion

    /// Whether the system reduce-motion preference is currently enabled.
    ///
    /// Reads from `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`
    /// on each access to respect dynamic changes.
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Returns the effective animation duration, respecting reduce-motion.
    ///
    /// - Parameter base: The desired duration when motion is enabled.
    /// - Returns: `base` if motion is allowed, `0` if reduce-motion is active.
    static func duration(_ base: TimeInterval) -> TimeInterval {
        reduceMotion ? 0 : base
    }

    /// Returns the effective animation duration with an explicit reduce-motion override.
    ///
    /// Useful for testing where the system preference cannot be controlled.
    ///
    /// - Parameters:
    ///   - base: The desired duration when motion is enabled.
    ///   - reduceMotionOverride: Explicit reduce-motion flag.
    /// - Returns: `base` if motion is allowed, `0` if reduce-motion is active.
    static func duration(_ base: TimeInterval, reduceMotionOverride: Bool) -> TimeInterval {
        reduceMotionOverride ? 0 : base
    }
}
