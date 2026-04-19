// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GlassSurface.swift - The single glass primitive for the Aurora redesign.
//
// Every translucent surface in the redesigned chrome (sidebar, status
// bar, tab strip, command palette, overlays) composes itself through
// this primitive so a single file owns the material stack:
//
//   macOS 26+  -> Apple Liquid Glass (`.glassEffect` / `NSGlassEffectView`).
//   macOS 14/15 -> `NSVisualEffectView` with the design-reference blur
//                  radius (~28pt) and an OKLCH tint overlay.
//   Reduce Transparency -> opaque fallback using the theme's
//                          `backgroundTertiary` surface so contrast
//                          still meets WCAG AA when the user opts out
//                          of vibrancy.
//
// The primitive stays agnostic of the surrounding UI: it renders its
// tint and border **inside** the shape supplied by the caller, and the
// caller decides corner radius and elevation. That keeps every adopter
// consistent without forcing a specific capsule/rectangle everywhere.
//
// This file is additive — no existing view consumes it yet. It ships
// with tests that pin the resolved-mode decision table so later
// integration work cannot silently regress the accessibility fallback.

import AppKit
import SwiftUI

// MARK: - Render Mode

extension Design {

    /// Resolved render mode for a glass surface. The primitive picks
    /// one of these based on OS availability, the user's accessibility
    /// preferences, and an optional developer override.
    ///
    /// The enum is public (via `Design.GlassRenderMode`) so tests can
    /// drive the primitive deterministically without flipping system
    /// settings.
    enum GlassRenderMode: Sendable, Hashable {
        /// Real Liquid Glass — available starting macOS 26.
        case liquid
        /// Traditional `NSVisualEffectView` fallback with an overlay
        /// tint. Used on macOS 14 / 15 when Liquid Glass is not yet
        /// available. Reduce Transparency explicitly short-circuits to
        /// `.opaque` instead; see `resolveGlassRenderMode` for the
        /// decision table.
        case visualEffect
        /// Opaque surface used when Increase Contrast is on or the user
        /// opted into Reduce Transparency. The background is the theme's
        /// `backgroundTertiary` role so a sidebar or status bar stays
        /// legible against high-contrast content and honours the
        /// accessibility opt-out from translucent material.
        case opaque
    }

    /// Inputs used to compute the `GlassRenderMode`. Representing the
    /// inputs as a struct (rather than free parameters) lets tests
    /// hit every branch without touching NSWorkspace or `#available`
    /// runtime checks.
    struct GlassRenderInputs: Sendable, Hashable {
        /// Whether the binary is running on macOS 26 or newer, where
        /// real Liquid Glass is available.
        let supportsLiquidGlass: Bool
        /// Whether the user enabled Reduce Transparency in System
        /// Settings.
        let reduceTransparency: Bool
        /// Whether the user enabled Increase Contrast in System
        /// Settings.
        let increaseContrast: Bool
        /// Developer override. When set, this value wins over every
        /// runtime signal. Used by the inspector panel in the demo
        /// prototype and by tests; production chrome leaves it `nil`.
        let developerOverride: GlassRenderMode?

        init(
            supportsLiquidGlass: Bool,
            reduceTransparency: Bool,
            increaseContrast: Bool,
            developerOverride: GlassRenderMode? = nil
        ) {
            self.supportsLiquidGlass = supportsLiquidGlass
            self.reduceTransparency = reduceTransparency
            self.increaseContrast = increaseContrast
            self.developerOverride = developerOverride
        }
    }

    /// Pure resolver that picks the final render mode for a glass
    /// surface. Exposed as a static function so tests can exercise
    /// every branch in the decision table without allocating views.
    ///
    /// Decision table (evaluated in order):
    ///
    /// 1. If the developer override is set, return it verbatim — tests
    ///    and the demo panel need this ability.
    /// 2. If Increase Contrast is on, force `.opaque`. This is
    ///    non-negotiable: the material cannot render with enough
    ///    contrast to satisfy the accessibility setting.
    /// 3. If Reduce Transparency is on, force `.opaque` (matching the
    ///    file-level contract and Apple's accessibility guidance).
    ///    `NSVisualEffectView` still draws a translucent blur, so
    ///    returning it here would silently violate the user request.
    /// 4. If the platform supports real Liquid Glass, return
    ///    `.liquid`. Otherwise fall back to `.visualEffect`.
    static func resolveGlassRenderMode(
        _ inputs: GlassRenderInputs
    ) -> GlassRenderMode {
        if let override = inputs.developerOverride {
            return override
        }
        if inputs.increaseContrast {
            return .opaque
        }
        if inputs.reduceTransparency {
            return .opaque
        }
        if inputs.supportsLiquidGlass {
            return .liquid
        }
        return .visualEffect
    }
}

// MARK: - Environment Keys

private struct GlassRenderModeOverrideKey: EnvironmentKey {
    static let defaultValue: Design.GlassRenderMode? = nil
}

private struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue: Design.ThemePalette = .aurora
}

extension EnvironmentValues {

    /// Injected theme palette used by design views. The default value
    /// is Aurora so previews render correctly without explicit setup.
    var designThemePalette: Design.ThemePalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }

    /// Optional developer override to force a specific render mode.
    /// Used by the demo inspector and by unit tests; production
    /// chrome leaves the environment value unset.
    var glassRenderModeOverride: Design.GlassRenderMode? {
        get { self[GlassRenderModeOverrideKey.self] }
        set { self[GlassRenderModeOverrideKey.self] = newValue }
    }
}

extension View {

    /// Injects the theme palette used by descendant design views.
    func designThemePalette(_ palette: Design.ThemePalette) -> some View {
        environment(\.designThemePalette, palette)
    }

    /// Forces a specific render mode for descendant glass surfaces.
    /// When `nil`, the standard decision table applies.
    func glassRenderModeOverride(_ mode: Design.GlassRenderMode?) -> some View {
        environment(\.glassRenderModeOverride, mode)
    }
}

// MARK: - Glass Surface View

extension Design {

    /// Translucent surface primitive for the Aurora redesign.
    ///
    /// Wraps `content` in a layered stack:
    /// - Background material (`.liquid` / `.visualEffect` / `.opaque`).
    /// - Glass tint sourced from the active theme palette.
    /// - Optional gradient highlight matching the CSS `.glass::before`
    ///   pseudo-element.
    /// - Hairline border sampled from the theme's `glassBorder`.
    /// - The caller's content, clipped to the supplied shape.
    ///
    /// `shape` defaults to a rounded rectangle with `Design.Radius.large`
    /// so call sites that do not care about geometry still match the
    /// design reference. Supply any `Shape` (Capsule, Circle, custom)
    /// when a component needs a different silhouette.
    struct GlassSurface<Content: View, SurfaceShape: InsettableShape>: View {
        @Environment(\.designThemePalette) private var palette
        @Environment(\.glassRenderModeOverride) private var override
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

        private let shape: SurfaceShape
        private let tintOverride: OKLCHColor?
        private let content: Content

        init(
            shape: SurfaceShape,
            tint: OKLCHColor? = nil,
            @ViewBuilder content: () -> Content
        ) {
            self.shape = shape
            self.tintOverride = tint
            self.content = content()
        }

        var body: some View {
            let mode = Design.resolveGlassRenderMode(
                GlassRenderInputs(
                    supportsLiquidGlass: Self.platformSupportsLiquidGlass,
                    reduceTransparency: reduceTransparency,
                    increaseContrast: Self.increaseContrastEnabled,
                    developerOverride: override
                )
            )

            let tint = (tintOverride ?? palette.glassTint).resolvedColor()
            let border = palette.glassBorder.resolvedColor()

            return content
                .background(
                    GlassBackground(
                        mode: mode,
                        shape: AnyShape(shape),
                        tint: tint,
                        palette: palette
                    )
                )
                .overlay(
                    shape.strokeBorder(border, lineWidth: 1)
                )
                .clipShape(shape)
        }

        // MARK: - Capability Gates

        /// Whether the current process runs on macOS 26 or later. The
        /// check folds down to a constant at compile time so every
        /// call site stays cheap. Tests override the value via the
        /// render-mode override environment key.
        private static var platformSupportsLiquidGlass: Bool {
            if #available(macOS 26.0, *) {
                return true
            }
            return false
        }

        /// Whether the user enabled Increase Contrast. SwiftUI only
        /// exposes Reduce Transparency directly; Increase Contrast
        /// comes from `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`.
        private static var increaseContrastEnabled: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        }
    }
}

// MARK: - Convenience Initializer

extension Design.GlassSurface where SurfaceShape == RoundedRectangle {

    /// Default-shape initializer for the common case: a rounded
    /// rectangle with the `Radius.large` corner radius that matches
    /// every panel in the design reference.
    init(
        cornerRadius: Design.Radius = .large,
        tint: Design.OKLCHColor? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            shape: RoundedRectangle(cornerRadius: cornerRadius.rawValue, style: .continuous),
            tint: tint,
            content: content
        )
    }
}

// MARK: - Backgrounds

private struct GlassBackground: View {
    let mode: Design.GlassRenderMode
    let shape: AnyShape
    let tint: Color
    let palette: Design.ThemePalette

    var body: some View {
        // Keep the material layer strictly behind any tint or border
        // work so the clipping surface in `GlassSurface` stays correct
        // across render modes.
        ZStack {
            switch mode {
            case .liquid:
                LiquidGlassBackground()
            case .visualEffect:
                VisualEffectFallback()
            case .opaque:
                palette.backgroundTertiary.resolvedColor()
            }

            // Uniform tint overlay — softens the blurred material so
            // accent chroma comes through consistently across modes.
            tint
        }
        .clipShape(shape)
    }
}

private struct LiquidGlassBackground: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Rectangle()
                .glassEffect(in: Rectangle())
        } else {
            VisualEffectFallback()
        }
    }
}

private struct VisualEffectFallback: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // No runtime mutation: the material is intentionally pinned so
        // the glass look stays consistent regardless of the host
        // window's focus state (a key requirement from the design
        // reference — chrome must not dim when the window loses focus).
    }
}
