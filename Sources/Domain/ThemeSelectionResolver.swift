// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ThemeSelectionResolver.swift - Resolves user-facing theme names to concrete themes.

import Foundation

@MainActor
enum ThemeSelectionResolver {
    static let systemThemeAliases: Set<String> = [
        "system",
        "auto",
        "default",
        "follow-system",
        "followsystem",
    ]

    static func isSystemAlias(_ name: String) -> Bool {
        systemThemeAliases.contains(normalizedAlias(name))
    }

    static func resolvedVariantThemeName(
        preferredName: String,
        fallbackName: String,
        requiredVariant: ThemeVariant,
        themeEngine: ThemeEngineImpl?
    ) -> String {
        let candidates = [preferredName, fallbackName]
        for candidate in candidates {
            if let resolved = resolvedThemeName(
                candidate,
                requiredVariant: requiredVariant,
                themeEngine: themeEngine
            ) {
                return resolved
            }
        }

        if let firstMatchingTheme = themeEngine?.availableThemes.first(where: {
            $0.variant == requiredVariant
        }) {
            return firstMatchingTheme.name
        }

        return fallbackName
    }

    static func resolvedThemeName(
        _ name: String,
        requiredVariant: ThemeVariant?,
        themeEngine: ThemeEngineImpl?
    ) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSystemAlias(trimmed) else { return nil }

        guard let themeEngine else { return trimmed }
        guard let theme = try? themeEngine.themeByName(trimmed) else { return nil }
        if let requiredVariant, theme.metadata.variant != requiredVariant {
            return nil
        }
        return theme.metadata.name
    }

    static func resolvedConfiguredThemeName(
        _ configuredName: String,
        isSystemDarkMode: Bool,
        themeEngine: ThemeEngineImpl?
    ) -> String {
        if isSystemAlias(configuredName) {
            return resolvedVariantThemeName(
                preferredName: isSystemDarkMode
                    ? AppearanceConfig.defaults.theme
                    : AppearanceConfig.defaults.lightTheme,
                fallbackName: AppearanceConfig.defaults.theme,
                requiredVariant: isSystemDarkMode ? .dark : .light,
                themeEngine: themeEngine
            )
        }

        return resolvedThemeName(
            configuredName,
            requiredVariant: nil,
            themeEngine: themeEngine
        ) ?? configuredName
    }

    private static func normalizedAlias(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
