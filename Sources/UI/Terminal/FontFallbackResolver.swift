// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// FontFallbackResolver.swift - Font availability checking and fallback chain.

import AppKit

// MARK: - Font Fallback Resolver

/// Resolves a font family to a usable NSFont, falling back through a chain.
///
/// Terminal applications need reliable font rendering. If the user-configured
/// font (e.g., "JetBrainsMono Nerd Font") is not installed, we fall back to:
/// 1. "JetBrains Mono" (the base font without Nerd Font patches)
/// 2. "Menlo" (always available on macOS)
///
/// For arbitrary font families, the chain is:
/// 1. The requested family
/// 2. "Menlo" (system default monospace)
///
/// CocxyCore handles terminal font rendering itself, so this resolver
/// is primarily used for:
/// - Validating font availability before passing it into terminal config
/// - UI elements outside the terminal surface (tab labels, overlays)
///
/// - SeeAlso: `AppearanceConfig.fontFamily`
enum FontFallbackResolver {

    // MARK: - Known Font Families

    /// The preferred terminal font family with Nerd Font icons.
    static let jetBrainsMonoNerdFont = "JetBrainsMono Nerd Font"

    /// The base JetBrains Mono without Nerd Font patches.
    static let jetBrainsMono = "JetBrains Mono"

    /// macOS default monospace font. Always available.
    static let menlo = "Menlo"

    // MARK: - Resolution

    /// Resolves a font family and size to a usable NSFont.
    ///
    /// Tries the requested family first. If not available, walks the
    /// fallback chain until a usable font is found. Menlo is always
    /// the last resort (guaranteed available on macOS).
    ///
    /// - Parameters:
    ///   - family: The desired font family name.
    ///   - size: The desired font size in points.
    /// - Returns: An NSFont, or nil if no font could be resolved (should not happen).
    @MainActor
    static func resolveFont(family: String, size: CGFloat) -> NSFont? {
        let chain = fallbackChain(for: family)

        for candidate in chain {
            if let font = NSFont(name: candidate, size: size) {
                return font
            }
        }

        // Absolute last resort: system monospace font.
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Returns the fallback chain for a given font family.
    ///
    /// For JetBrainsMono Nerd Font, the chain includes the base variant.
    /// For all other fonts, the chain ends with Menlo.
    ///
    /// - Parameter family: The primary font family name.
    /// - Returns: An ordered array of font family names to try.
    static func fallbackChain(for family: String) -> [String] {
        if family == jetBrainsMonoNerdFont {
            return [jetBrainsMonoNerdFont, jetBrainsMono, menlo]
        }

        if family == jetBrainsMono {
            return [jetBrainsMono, menlo]
        }

        // Unknown font: try it, then fall back to Menlo.
        return [family, menlo]
    }

    // MARK: - Availability Check

    /// Checks if a font family is available on the system.
    ///
    /// - Parameter family: The font family name to check.
    /// - Returns: Whether the font family can be instantiated.
    @MainActor
    static func isFontAvailable(_ family: String) -> Bool {
        NSFontManager.shared.availableFontFamilies.contains(family)
    }
}
