// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// FontFallbackResolver.swift - Font availability checking and fallback chain.

import AppKit

// MARK: - Font Fallback Resolver

/// Resolves a font family to a usable NSFont, falling back through a chain.
///
/// Terminal applications need reliable font rendering. Cocxy now ships a
/// small bundled font set so clean Macs still get a curated terminal look
/// without requiring manual installs.
///
/// CocxyCore handles terminal font rendering itself, so this resolver
/// is primarily used for:
/// - Validating font availability before passing it into terminal config
/// - UI elements outside the terminal surface (tab labels, overlays)
///
/// - SeeAlso: `AppearanceConfig.fontFamily`
enum FontFallbackResolver {

    // MARK: - Known Font Families

    /// The preferred terminal font family with Nerd Font icons and strict mono spacing.
    static let jetBrainsMonoNerdFontMono = "JetBrainsMono Nerd Font Mono"

    /// A bundled, more editorial-feeling monospace option surfaced in preferences.
    static let monaspaceNeon = "Monaspace Neon"

    /// The preferred terminal font family with Nerd Font icons.
    static let jetBrainsMonoNerdFont = "JetBrainsMono Nerd Font"

    /// The base JetBrains Mono without Nerd Font patches.
    static let jetBrainsMono = "JetBrains Mono"

    /// macOS default monospace font. Always available.
    static let menlo = "Menlo"

    /// Older but still reliable built-in monospace option.
    static let monaco = "Monaco"

    /// Curated terminal-friendly font families to surface prominently in the UI.
    private static let curatedFamilies = [
        jetBrainsMonoNerdFontMono,
        monaspaceNeon,
        jetBrainsMonoNerdFont,
        "JetBrains Mono",
        "SF Mono",
        "Monaspace Krypton",
        "CommitMono",
        "Fira Code",
        "Iosevka Term",
        "Inconsolata",
        "Inconsolata XL",
        "PT Mono",
        menlo,
        monaco,
        "Andale Mono",
        "Consolas",
        "Courier New",
    ]

    @MainActor
    static var bundledFamilies: [String] {
        BundledFontRegistry.bundledFamilies
    }

    @MainActor
    private static var cachedAvailableFixedPitchFamilies: [String]?

    @MainActor
    private static var cachedRecommendedFamilies: [String]?

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
        BundledFontRegistry.ensureRegistered()

        if let resolvedFamily = resolvedFamily(for: family) {
            return instantiateFont(family: resolvedFamily, size: size)
        }

        // Absolute last resort: system monospace font.
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Resolves a family name to the concrete installed family that will be used.
    ///
    /// - Parameter family: The requested font family.
    /// - Returns: The installed family name that wins the fallback chain, if any.
    @MainActor
    static func resolvedFamily(for family: String) -> String? {
        BundledFontRegistry.ensureRegistered()

        for candidate in fallbackChain(for: family) {
            guard let font = instantiateFont(family: candidate, size: 13) else { continue }
            return font.familyName ?? candidate
        }
        return nil
    }

    /// Returns the fallback chain for a given font family.
    ///
    /// For the JetBrains Mono variants, the chain preserves patched/mono variants
    /// before falling back to broadly available monospace fonts.
    /// For all other fonts, the chain ends with Menlo.
    ///
    /// - Parameter family: The primary font family name.
    /// - Returns: An ordered array of font family names to try.
    static func fallbackChain(for family: String) -> [String] {
        if family == jetBrainsMonoNerdFontMono {
            return [jetBrainsMonoNerdFontMono, jetBrainsMonoNerdFont, jetBrainsMono, menlo]
        }

        if family == monaspaceNeon {
            return [monaspaceNeon, jetBrainsMonoNerdFontMono, jetBrainsMonoNerdFont, jetBrainsMono, menlo]
        }

        if family == jetBrainsMonoNerdFont {
            return [jetBrainsMonoNerdFont, jetBrainsMonoNerdFontMono, jetBrainsMono, menlo]
        }

        if family == jetBrainsMono {
            return [jetBrainsMono, menlo]
        }

        // Unknown font: try it, then fall back to Cocxy's bundled safe defaults.
        return [family, jetBrainsMonoNerdFontMono, jetBrainsMonoNerdFont, jetBrainsMono, menlo]
    }

    // MARK: - Availability Check

    /// Checks if a font family is available on the system.
    ///
    /// - Parameter family: The font family name to check.
    /// - Returns: Whether the font family can be instantiated.
    @MainActor
    static func isFontAvailable(_ family: String) -> Bool {
        BundledFontRegistry.ensureRegistered()

        if instantiateFont(family: family, size: 13) != nil {
            return true
        }

        if NSFontManager.shared.availableFontFamilies.contains(family) {
            return true
        }

        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
        ])
        return NSFont(descriptor: descriptor, size: 13) != nil
    }

    /// Returns installed fixed-pitch font families available on this Mac.
    @MainActor
    static func availableFixedPitchFamilies() -> [String] {
        BundledFontRegistry.ensureRegistered()

        if let cachedAvailableFixedPitchFamilies {
            return cachedAvailableFixedPitchFamilies
        }

        var families = Set<String>()

        for family in curatedFamilies {
            if let font = instantiateFont(family: family, size: 13), font.isFixedPitch {
                families.insert(font.familyName ?? family)
            }
        }

        for family in NSFontManager.shared.availableFontFamilies {
            guard let font = instantiateFont(family: family, size: 13), font.isFixedPitch else { continue }
            families.insert(font.familyName ?? family)
        }

        let resolvedFamilies = families.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        cachedAvailableFixedPitchFamilies = resolvedFamilies
        return resolvedFamilies
    }

    /// Returns a curated list of installed monospaced fonts worth surfacing first.
    @MainActor
    static func recommendedFamilies() -> [String] {
        BundledFontRegistry.ensureRegistered()

        if let cachedRecommendedFamilies {
            return cachedRecommendedFamilies
        }

        let available = Set(availableFixedPitchFamilies())
        var ordered: [String] = []

        for family in curatedFamilies where available.contains(family) {
            ordered.append(family)
        }

        // Ensure the list is never empty even on unusual systems.
        if ordered.isEmpty, available.contains(menlo) {
            ordered.append(menlo)
        }

        cachedRecommendedFamilies = ordered
        return ordered
    }

    @MainActor
    static func invalidateCaches() {
        cachedAvailableFixedPitchFamilies = nil
        cachedRecommendedFamilies = nil
    }

    @MainActor
    private static func instantiateFont(family: String, size: CGFloat) -> NSFont? {
        if let direct = NSFont(name: family, size: size) {
            return direct
        }

        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
        ])
        return NSFont(descriptor: descriptor, size: size)
    }
}
