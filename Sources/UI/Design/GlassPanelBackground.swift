// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GlassPanelBackground.swift - Shared glass background for full-pane SwiftUI panels.

import AppKit
import SwiftUI

extension Design {
    static func panelPalette(
        for colorScheme: ColorScheme,
        current palette: ThemePalette,
        appearanceOverride: NSAppearance? = nil
    ) -> ThemePalette {
        if appearanceOverride?.name == .aqua {
            return .paper
        }
        if appearanceOverride?.name == .darkAqua {
            return .aurora
        }
        if colorScheme == .light, palette == .aurora {
            return .paper
        }
        return palette
    }
}

extension View {
    /// Applies the Aurora glass primitive as the full bounds background for
    /// split-pane and overlay panels that should not create an additional card.
    func glassPanelBackground(vibrancyAppearanceOverride: NSAppearance? = nil) -> some View {
        background {
            Design.PanelGlassBackground(vibrancyAppearanceOverride: vibrancyAppearanceOverride)
        }
    }
}

extension Design {
    struct PanelGlassBackground: View {
        var vibrancyAppearanceOverride: NSAppearance?

        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.designThemePalette) private var palette

        var body: some View {
            GlassSurface(shape: Rectangle()) {
                Color.clear
            }
            .designThemePalette(
                Design.panelPalette(
                    for: colorScheme,
                    current: palette,
                    appearanceOverride: vibrancyAppearanceOverride
                )
            )
        }
    }
}
