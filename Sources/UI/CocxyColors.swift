// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyColors.swift - Centralized color palette for all UI components.

import AppKit
import SwiftUI

// MARK: - Cocxy Color Palette

/// Centralized Catppuccin Mocha color palette.
///
/// All UI components MUST use these constants instead of inline RGB literals.
/// Colors follow the official Catppuccin Mocha specification exactly:
/// https://github.com/catppuccin/catppuccin
///
/// The palette provides a layered depth system:
/// - Crust (deepest) → Mantle → Base (main) → Surface0 → Surface1 → Surface2
/// - Each layer is slightly lighter, creating natural visual hierarchy.
enum CocxyColors {

    // MARK: - Base Colors (official Catppuccin Mocha)

    /// Main background (#1e1e2e). The primary terminal area.
    static let base = NSColor(srgbRed: 0x1E / 255.0, green: 0x1E / 255.0, blue: 0x2E / 255.0, alpha: 1.0)

    /// Sidebar/panel background (#181825). One step deeper than base.
    static let mantle = NSColor(srgbRed: 0x18 / 255.0, green: 0x18 / 255.0, blue: 0x25 / 255.0, alpha: 1.0)

    /// Status bar / deepest layer (#11111b). The lowest visual layer.
    static let crust = NSColor(srgbRed: 0x11 / 255.0, green: 0x11 / 255.0, blue: 0x1B / 255.0, alpha: 1.0)

    // MARK: - Surface Colors

    /// Surface0 (#313244) — elevated elements, tab backgrounds.
    static let surface0 = NSColor(srgbRed: 0x31 / 255.0, green: 0x32 / 255.0, blue: 0x44 / 255.0, alpha: 1.0)

    /// Surface1 (#45475a) — hover states, active borders.
    static let surface1 = NSColor(srgbRed: 0x45 / 255.0, green: 0x47 / 255.0, blue: 0x5A / 255.0, alpha: 1.0)

    /// Surface2 (#585b70) — secondary borders, subtle dividers.
    static let surface2 = NSColor(srgbRed: 0x58 / 255.0, green: 0x5B / 255.0, blue: 0x70 / 255.0, alpha: 1.0)

    // MARK: - Overlay Colors

    /// Overlay0 (#6c7086) — disabled text, subtle indicators.
    static let overlay0 = NSColor(srgbRed: 0x6C / 255.0, green: 0x70 / 255.0, blue: 0x86 / 255.0, alpha: 1.0)

    /// Overlay1 (#7f849c) — placeholder text.
    static let overlay1 = NSColor(srgbRed: 0x7F / 255.0, green: 0x84 / 255.0, blue: 0x9C / 255.0, alpha: 1.0)

    /// Overlay2 (#9399b2) — inactive tab text.
    static let overlay2 = NSColor(srgbRed: 0x93 / 255.0, green: 0x99 / 255.0, blue: 0xB2 / 255.0, alpha: 1.0)

    // MARK: - Text Colors

    /// Subtext0 (#a6adc8) — secondary text, descriptions.
    static let subtext0 = NSColor(srgbRed: 0xA6 / 255.0, green: 0xAD / 255.0, blue: 0xC8 / 255.0, alpha: 1.0)

    /// Subtext1 (#bac2de) — primary text on dark surfaces.
    static let subtext1 = NSColor(srgbRed: 0xBA / 255.0, green: 0xC2 / 255.0, blue: 0xDE / 255.0, alpha: 1.0)

    /// Text (#cdd6f4) — main text color, highest contrast.
    static let text = NSColor(srgbRed: 0xCD / 255.0, green: 0xD6 / 255.0, blue: 0xF4 / 255.0, alpha: 1.0)

    // MARK: - Accent Colors

    /// Blue (#89b4fa) — links, active states, working indicator.
    static let blue = NSColor(srgbRed: 0x89 / 255.0, green: 0xB4 / 255.0, blue: 0xFA / 255.0, alpha: 1.0)

    /// Green (#a6e3a1) — success, finished indicator.
    static let green = NSColor(srgbRed: 0xA6 / 255.0, green: 0xE3 / 255.0, blue: 0xA1 / 255.0, alpha: 1.0)

    /// Red (#f38ba8) — error indicator.
    static let red = NSColor(srgbRed: 0xF3 / 255.0, green: 0x8B / 255.0, blue: 0xA8 / 255.0, alpha: 1.0)

    /// Yellow (#f9e2af) — warning, waiting input indicator.
    static let yellow = NSColor(srgbRed: 0xF9 / 255.0, green: 0xE2 / 255.0, blue: 0xAF / 255.0, alpha: 1.0)

    /// Peach (#fab387) — attention, launched indicator.
    static let peach = NSColor(srgbRed: 0xFA / 255.0, green: 0xB3 / 255.0, blue: 0x87 / 255.0, alpha: 1.0)

    /// Mauve (#cba6f7) — purple accent, special highlights.
    static let mauve = NSColor(srgbRed: 0xCB / 255.0, green: 0xA6 / 255.0, blue: 0xF7 / 255.0, alpha: 1.0)

    /// Teal (#94e2d5) — secondary accent, info states.
    static let teal = NSColor(srgbRed: 0x94 / 255.0, green: 0xE2 / 255.0, blue: 0xD5 / 255.0, alpha: 1.0)

    /// Rosewater (#f5e0dc) — cursor color, warm accent.
    static let rosewater = NSColor(srgbRed: 0xF5 / 255.0, green: 0xE0 / 255.0, blue: 0xDC / 255.0, alpha: 1.0)

    /// Lavender (#b4befe) — selection, highlight.
    static let lavender = NSColor(srgbRed: 0xB4 / 255.0, green: 0xBE / 255.0, blue: 0xFE / 255.0, alpha: 1.0)

    /// Flamingo (#f2cdcd) — soft pink accent.
    static let flamingo = NSColor(srgbRed: 0xF2 / 255.0, green: 0xCD / 255.0, blue: 0xCD / 255.0, alpha: 1.0)

    /// Sky (#89dceb) — cool blue accent.
    static let sky = NSColor(srgbRed: 0x89 / 255.0, green: 0xDC / 255.0, blue: 0xEB / 255.0, alpha: 1.0)

    // MARK: - Semantic Interaction Tokens

    /// Hover background on dark surfaces (mantle/crust).
    static let hoverOnDark = NSColor(srgbRed: 0x31 / 255.0, green: 0x32 / 255.0, blue: 0x44 / 255.0, alpha: 0.5)

    /// Hover background on lighter surfaces (surface0).
    static let hoverOnSurface = NSColor(srgbRed: 0x45 / 255.0, green: 0x47 / 255.0, blue: 0x5A / 255.0, alpha: 0.4)

    /// Selected/active item background.
    static let selectedBackground = NSColor(srgbRed: 0x31 / 255.0, green: 0x32 / 255.0, blue: 0x44 / 255.0, alpha: 0.9)

    /// Subtle divider between panel sections.
    static let panelDivider = NSColor(srgbRed: 0x31 / 255.0, green: 0x32 / 255.0, blue: 0x44 / 255.0, alpha: 0.8)

    /// Text color for keyboard shortcut labels.
    static let shortcutText = NSColor(srgbRed: 0x6C / 255.0, green: 0x70 / 255.0, blue: 0x86 / 255.0, alpha: 1.0)

    /// Primary action button background.
    static let buttonPrimary = blue

    /// Primary button text (high contrast on blue).
    static let buttonPrimaryText = crust

    // MARK: - SwiftUI Convenience

    /// SwiftUI Color from any CocxyColors NSColor.
    static func swiftUI(_ nsColor: NSColor) -> SwiftUI.Color {
        SwiftUI.Color(nsColor: nsColor)
    }
}
