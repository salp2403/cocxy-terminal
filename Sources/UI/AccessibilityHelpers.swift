// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AccessibilityHelpers.swift - WCAG contrast ratio calculations and accessibility utilities.

import AppKit

// MARK: - Accessibility Helpers

/// Utilities for WCAG 2.1 contrast ratio verification and accessibility support.
///
/// Provides static methods to calculate contrast ratios between colors and
/// verify they meet WCAG thresholds:
/// - **AA normal text:** >= 4.5:1
/// - **AA large text / UI elements:** >= 3:1
///
/// ## Usage
///
/// ```swift
/// let ratio = AccessibilityHelpers.contrastRatio(foreground, background)
/// let passes = AccessibilityHelpers.meetsWCAGAA(foreground: fg, background: bg)
/// ```
///
/// - SeeAlso: https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html
enum AccessibilityHelpers {

    // MARK: - WCAG Thresholds

    /// Minimum contrast ratio for normal text (WCAG AA).
    static let wcagAANormalTextThreshold: Double = 4.5

    /// Minimum contrast ratio for large text and UI elements (WCAG AA).
    static let wcagAALargeTextThreshold: Double = 3.0

    // MARK: - Contrast Ratio

    /// Calculates the WCAG 2.1 contrast ratio between two colors.
    ///
    /// The ratio is always >= 1.0, with 21:1 being the maximum (black/white).
    /// Order of parameters does not matter.
    ///
    /// - Parameters:
    ///   - color1: The first color.
    ///   - color2: The second color.
    /// - Returns: The contrast ratio (1.0 to 21.0).
    static func contrastRatio(_ color1: NSColor, _ color2: NSColor) -> Double {
        let luminance1 = relativeLuminance(color1)
        let luminance2 = relativeLuminance(color2)

        let lighter = max(luminance1, luminance2)
        let darker = min(luminance1, luminance2)

        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Calculates the relative luminance of a color per WCAG 2.1.
    ///
    /// Uses the sRGB linearization formula:
    /// - For each channel, if value <= 0.04045: linear = value / 12.92
    /// - Otherwise: linear = ((value + 0.055) / 1.055) ^ 2.4
    ///
    /// Then: L = 0.2126 * R + 0.7152 * G + 0.0722 * B
    ///
    /// - Parameter color: The color to measure.
    /// - Returns: Relative luminance (0.0 to 1.0).
    static func relativeLuminance(_ color: NSColor) -> Double {
        // Convert to sRGB color space to get consistent component values.
        let srgbColor = color.usingColorSpace(.sRGB) ?? color

        let red = Double(srgbColor.redComponent)
        let green = Double(srgbColor.greenComponent)
        let blue = Double(srgbColor.blueComponent)

        let linearRed = linearize(red)
        let linearGreen = linearize(green)
        let linearBlue = linearize(blue)

        return 0.2126 * linearRed + 0.7152 * linearGreen + 0.0722 * linearBlue
    }

    // MARK: - Threshold Checks

    /// Checks if a foreground/background pair meets WCAG AA for normal text.
    ///
    /// - Parameters:
    ///   - foreground: The text color.
    ///   - background: The background color.
    /// - Returns: `true` if the contrast ratio is >= 4.5:1.
    static func meetsWCAGAA(foreground: NSColor, background: NSColor) -> Bool {
        contrastRatio(foreground, background) >= wcagAANormalTextThreshold
    }

    /// Checks if a foreground/background pair meets WCAG AA for large text
    /// and UI elements.
    ///
    /// - Parameters:
    ///   - foreground: The element color.
    ///   - background: The background color.
    /// - Returns: `true` if the contrast ratio is >= 3:1.
    static func meetsWCAGLargeText(foreground: NSColor, background: NSColor) -> Bool {
        contrastRatio(foreground, background) >= wcagAALargeTextThreshold
    }

    // MARK: - Private

    /// Linearizes an sRGB channel value using the WCAG formula.
    private static func linearize(_ channel: Double) -> Double {
        if channel <= 0.04045 {
            return channel / 12.92
        } else {
            return pow((channel + 0.055) / 1.055, 2.4)
        }
    }
}
