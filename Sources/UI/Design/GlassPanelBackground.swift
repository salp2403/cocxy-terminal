// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GlassPanelBackground.swift - Shared glass background for full-pane SwiftUI panels.

import SwiftUI

extension View {
    /// Applies the Aurora glass primitive as the full bounds background for
    /// split-pane and overlay panels that should not create an additional card.
    func glassPanelBackground() -> some View {
        background {
            Design.GlassSurface(shape: Rectangle()) {
                Color.clear
            }
        }
    }
}
