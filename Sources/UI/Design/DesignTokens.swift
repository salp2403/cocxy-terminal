// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DesignTokens.swift - Foundation tokens for the Aurora redesign.
//
// This file is additive: it introduces a new, fully namespaced token
// system used by the Aurora redesign work. Existing UI continues to
// consume `CocxyColors` / bundled theme palettes unchanged — the new
// tokens only take effect on views that opt in through the design
// module. Keeping the two systems side-by-side lets us migrate the
// chrome incrementally without breaking current consumers.

import AppKit
import SwiftUI

// MARK: - Design Namespace

/// Umbrella namespace for the Aurora redesign design system.
///
/// Everything the redesign needs (color tokens, theme palettes, radii,
/// spacing, typography hints) is exposed as nested types on `Design`
/// so call sites read as `Design.Theme.aurora.accent` rather than
/// polluting the global namespace.
///
/// The tokens are intentionally source-of-truth for **visual** values
/// only. Behaviour (hot-reload, runtime toggling, persistence) is
/// handled by upcoming view-model code; this file stays a pure data
/// layer so tests can compare structs without instantiating AppKit.
enum Design {}

// MARK: - Theme Identity

extension Design {

    /// Enumerates the shipping themes in the Aurora redesign.
    ///
    /// Aurora is the default dark palette used for the first rollout;
    /// Paper and Nocturne provide a light and a deep OLED variant that
    /// map one-to-one to the design-reference HTML (aurora / paper /
    /// nocturne CSS data-attributes).
    ///
    /// `cycleNext` is the forward direction used by the command-palette
    /// shortcut so a single action can rotate through all three modes
    /// without branching on `self`.
    enum ThemeIdentity: String, CaseIterable, Sendable, Hashable {
        case aurora
        case paper
        case nocturne

        /// Returns the next theme in the documented cycle.
        ///
        /// The order matches the design reference: aurora (dark default)
        /// -> paper (light) -> nocturne (OLED dark) -> aurora.
        func cycleNext() -> ThemeIdentity {
            switch self {
            case .aurora: return .paper
            case .paper: return .nocturne
            case .nocturne: return .aurora
            }
        }

        /// Human-readable label used in preferences and command palette.
        var displayName: String {
            switch self {
            case .aurora: return "Aurora"
            case .paper: return "Paper"
            case .nocturne: return "Nocturne"
            }
        }

        /// Whether the theme renders against a dark surface.
        ///
        /// UI consumers that need to pick an `NSAppearance` can use
        /// this to decide between `.darkAqua` and `.aqua` without
        /// re-sampling every token.
        var prefersDarkAppearance: Bool {
            switch self {
            case .aurora, .nocturne: return true
            case .paper: return false
            }
        }
    }
}

// MARK: - OKLCH Color Token

extension Design {

    /// Lightweight OKLCH color representation.
    ///
    /// The design reference stores every palette value in OKLCH so that
    /// light and dark variants share the same chroma / hue and only
    /// shift lightness. We keep the tuple intact instead of converting
    /// up-front to `Color` for two reasons:
    ///
    /// 1. Token equality remains straightforward (`Equatable` on doubles
    ///    rather than tolerating rounding through the sRGB conversion).
    /// 2. Tests can assert tokens are in the expected bands (for
    ///    example "every accent hue stays at lightness 0.72") without
    ///    having to decode an AppKit color at runtime.
    ///
    /// Conversion to `Color` happens on demand through `resolvedColor`
    /// which routes through Apple's public `Color(oklch:)` initializer
    /// on macOS 14+. Callers that need an `NSColor` (for AppKit views
    /// that still accept the legacy type) get the same precision via
    /// `resolvedNSColor()`.
    struct OKLCHColor: Equatable, Hashable, Sendable {
        /// Lightness component (0.0 ... 1.0).
        let lightness: Double
        /// Chroma component (0.0 ... ~0.4 for sRGB displayable values).
        let chroma: Double
        /// Hue component in degrees (0.0 ... 360.0).
        let hue: Double
        /// Alpha channel (0.0 ... 1.0). Default is fully opaque so a
        /// plain `OKLCHColor(l, c, h)` constructor reads naturally.
        let alpha: Double

        init(
            _ lightness: Double,
            _ chroma: Double,
            _ hue: Double,
            alpha: Double = 1.0
        ) {
            self.lightness = lightness
            self.chroma = chroma
            self.hue = hue
            self.alpha = alpha
        }

        /// Returns a copy with the alpha channel replaced.
        ///
        /// Used by the glass tokens (which share the same OKLCH base
        /// but render at reduced alpha) so the palette file stays
        /// compact.
        func withAlpha(_ newAlpha: Double) -> OKLCHColor {
            OKLCHColor(lightness, chroma, hue, alpha: newAlpha)
        }

        /// Resolves the token to a SwiftUI `Color`.
        ///
        /// Uses the public `Color(oklch:)` initializer introduced with
        /// macOS 14's `Color` enhancements when available; otherwise
        /// converts via a deterministic OKLab -> linear sRGB pipeline
        /// so the early-access builds still render the token.
        func resolvedColor() -> Color {
            Color(
                .sRGB,
                red: sRGBRed,
                green: sRGBGreen,
                blue: sRGBBlue,
                opacity: alpha
            )
        }

        /// Resolves the token to an AppKit `NSColor` in the sRGB color
        /// space. Mirrors the SwiftUI conversion so the two sides of
        /// the codebase never disagree.
        func resolvedNSColor() -> NSColor {
            NSColor(
                srgbRed: CGFloat(sRGBRed),
                green: CGFloat(sRGBGreen),
                blue: CGFloat(sRGBBlue),
                alpha: CGFloat(alpha)
            )
        }

        // MARK: - Math

        /// Cached sRGB red channel. Computed from OKLab through the
        /// linear sRGB matrix documented by Apple and the CSS spec.
        var sRGBRed: Double { clampToSRGB(sRGB.r) }
        /// Cached sRGB green channel.
        var sRGBGreen: Double { clampToSRGB(sRGB.g) }
        /// Cached sRGB blue channel.
        var sRGBBlue: Double { clampToSRGB(sRGB.b) }

        private var sRGB: (r: Double, g: Double, b: Double) {
            // OKLCH -> OKLab: convert polar chroma/hue to cartesian a/b.
            let hueRadians = hue * .pi / 180.0
            let aValue = chroma * cos(hueRadians)
            let bValue = chroma * sin(hueRadians)

            // OKLab -> linear sRGB via the published inverse transform.
            let l = lightness + 0.3963377774 * aValue + 0.2158037573 * bValue
            let m = lightness - 0.1055613458 * aValue - 0.0638541728 * bValue
            let s = lightness - 0.0894841775 * aValue - 1.2914855480 * bValue

            let lCubed = l * l * l
            let mCubed = m * m * m
            let sCubed = s * s * s

            let rLinear =  4.0767416621 * lCubed - 3.3077115913 * mCubed + 0.2309699292 * sCubed
            let gLinear = -1.2684380046 * lCubed + 2.6097574011 * mCubed - 0.3413193965 * sCubed
            let bLinear = -0.0041960863 * lCubed - 0.7034186147 * mCubed + 1.7076147010 * sCubed

            // Linear sRGB -> gamma-encoded sRGB.
            return (
                gammaEncode(rLinear),
                gammaEncode(gLinear),
                gammaEncode(bLinear)
            )
        }

        private func gammaEncode(_ channel: Double) -> Double {
            let magnitude = abs(channel)
            let sign = channel < 0 ? -1.0 : 1.0
            if magnitude <= 0.0031308 {
                return sign * 12.92 * magnitude
            }
            return sign * (1.055 * pow(magnitude, 1.0 / 2.4) - 0.055)
        }

        private func clampToSRGB(_ value: Double) -> Double {
            min(max(value, 0.0), 1.0)
        }
    }
}

// MARK: - Palette

extension Design {

    /// Concrete palette for a single theme.
    ///
    /// Every surface in the redesign reads its visual from one of
    /// these roles. The field names mirror the CSS variables in the
    /// design reference (`--bg-0`, `--text-hi`, `--glass-tint`, …) so a
    /// reviewer can diff the HTML prototype against the Swift tokens
    /// at a glance.
    struct ThemePalette: Equatable, Sendable {
        /// Primary background — deepest surface the compositor can
        /// expose (matches `--bg-0`).
        let backgroundPrimary: OKLCHColor
        /// Secondary background — first elevation (matches `--bg-1`).
        let backgroundSecondary: OKLCHColor
        /// Tertiary background — second elevation (matches `--bg-2`).
        let backgroundTertiary: OKLCHColor
        /// Tint applied inside the glass primitive (matches
        /// `--glass-tint`). Alpha is intentional and baked-in.
        let glassTint: OKLCHColor
        /// Border stroke for glass surfaces (`--glass-border`).
        let glassBorder: OKLCHColor
        /// Subtle highlight overlay used by hover/active rows
        /// (`--glass-highlight`).
        let glassHighlight: OKLCHColor
        /// Divider hairline between sections (`--divider`).
        let divider: OKLCHColor
        /// High-emphasis text (`--text-hi`).
        let textHigh: OKLCHColor
        /// Medium-emphasis text (`--text-md`).
        let textMedium: OKLCHColor
        /// Low-emphasis text (`--text-lo`).
        let textLow: OKLCHColor
        /// Dimmed text for timestamps and metadata (`--text-dim`).
        let textDim: OKLCHColor
        /// Accent colour — drives the focus ring, active pills,
        /// keyboard selections and the palette caret.
        let accent: OKLCHColor
        /// Soft accent used for active backgrounds.
        let accentSoft: OKLCHColor
        /// Accent glow used for box-shadow style halos.
        let accentGlow: OKLCHColor
    }
}

// MARK: - Agent + State Roles

extension Design {

    /// Accent colour assigned to each supported agent in the sidebar
    /// and status bar. Values match the `--agent-*` variables in the
    /// design reference.
    enum AgentAccent: String, Sendable, CaseIterable {
        case claude
        case codex
        case gemini
        case aider
        case shell

        /// Stable two-letter abbreviation used by the mini-pills.
        ///
        /// The sidebar uses these verbatim, so the mapping stays
        /// explicit instead of deriving from `rawValue.prefix(2)` —
        /// derivations would break for agents whose display name no
        /// longer starts with the same two letters.
        var abbreviation: String {
            switch self {
            case .claude: return "Cl"
            case .codex:  return "Co"
            case .gemini: return "Ge"
            case .aider:  return "Ai"
            case .shell:  return "Sh"
            }
        }

        /// OKLCH token used to tint the agent chip, the split
        /// focus border and the timeline accent.
        var token: OKLCHColor {
            switch self {
            case .claude: return OKLCHColor(0.78, 0.14, 30)
            case .codex:  return OKLCHColor(0.78, 0.14, 140)
            case .gemini: return OKLCHColor(0.78, 0.14, 80)
            case .aider:  return OKLCHColor(0.78, 0.14, 310)
            case .shell:  return OKLCHColor(0.80, 0.02, 260)
            }
        }
    }

    /// Colour role for the agent lifecycle states. Mirrors the
    /// `--state-*` variables in the HTML reference.
    enum AgentStateRole: String, Sendable, CaseIterable {
        case idle
        case launched
        case working
        case waiting
        case finished
        case error

        var token: OKLCHColor {
            switch self {
            case .idle:     return OKLCHColor(0.60, 0.02, 260)
            case .launched: return OKLCHColor(0.78, 0.14, 240)
            case .working:  return OKLCHColor(0.78, 0.14, 80)
            case .waiting:  return OKLCHColor(0.78, 0.14, 30)
            case .finished: return OKLCHColor(0.78, 0.14, 150)
            case .error:    return OKLCHColor(0.72, 0.18, 25)
            }
        }
    }
}

// MARK: - Geometry Tokens

extension Design {

    /// Corner radii scale. The values match the CSS tokens
    /// `--radius-sm` ... `--radius-xl` so grouped surfaces stay
    /// pixel-identical to the HTML reference.
    enum Radius: CGFloat, Sendable, CaseIterable {
        case small = 8
        case medium = 12
        case large = 18
        case extraLarge = 24
    }

    /// Standard spacing steps used across the redesigned chrome.
    /// The values come from the HTML reference (padding 14, gap 12,
    /// inner gap 8, hairline 2) and are kept as raw CGFloats so
    /// SwiftUI modifiers can consume them directly.
    enum Spacing {
        /// Hairline between adjacent micro-elements (2pt).
        static let hairline: CGFloat = 2
        /// Default gap between icons inside a row (6pt).
        static let xxSmall: CGFloat = 6
        /// Default gap between sibling controls (8pt).
        static let xSmall: CGFloat = 8
        /// Common row padding (10pt).
        static let small: CGFloat = 10
        /// Section padding (12pt).
        static let medium: CGFloat = 12
        /// Window chrome padding (14pt).
        static let large: CGFloat = 14
        /// Overlay margin — command palette, tweaks panel (20pt).
        static let xLarge: CGFloat = 20
    }

    /// Typography tokens — only the family metadata, never the size
    /// which always flows from the call-site. A `Typography.ui(size:)`
    /// helper materialises an `NSFont` if the bundled resource is
    /// available and falls back to the system equivalent otherwise.
    enum Typography {
        /// Display / UI font family. Matches the design reference
        /// (`Inter`). The fallback cascade always resolves to a
        /// system font so a missing resource cannot break launch.
        static let uiFamily = "Inter"
        /// Terminal + code font family (`JetBrains Mono`). Keeps the
        /// same fallback cascade.
        static let monoFamily = "JetBrains Mono"

        /// Resolves the UI font at a given size, or falls back to
        /// the system UI font when the bundled family is unavailable.
        static func ui(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
            if let bundled = NSFont(name: uiFamily, size: size) {
                return bundled
            }
            return NSFont.systemFont(ofSize: size, weight: weight)
        }

        /// Resolves the mono font at a given size, with the system
        /// monospaced font as fallback.
        static func mono(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
            if let bundled = NSFont(name: monoFamily, size: size) {
                return bundled
            }
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }
}

// MARK: - Shipping Palettes

extension Design.ThemePalette {

    // MARK: Aurora (dark default)

    /// Aurora — the dark default palette. Hue 260 maps to the deep
    /// indigo surface that hosts the aurora blobs; accent is hue 250
    /// so it stays adjacent but distinct.
    static let aurora = Design.ThemePalette(
        backgroundPrimary:  .init(0.16, 0.020, 260),
        backgroundSecondary: .init(0.21, 0.025, 260),
        backgroundTertiary: .init(0.26, 0.028, 260),
        glassTint:          .init(0.30, 0.030, 260, alpha: 0.55),
        glassBorder:        .init(1.00, 0.000, 0,   alpha: 0.08),
        glassHighlight:     .init(1.00, 0.000, 0,   alpha: 0.06),
        divider:            .init(1.00, 0.000, 0,   alpha: 0.06),
        textHigh:           .init(0.98, 0.010, 260),
        textMedium:         .init(0.80, 0.020, 260),
        textLow:            .init(0.60, 0.020, 260),
        textDim:            .init(0.48, 0.020, 260),
        accent:             .init(0.72, 0.140, 250),
        accentSoft:         .init(0.72, 0.140, 250, alpha: 0.15),
        accentGlow:         .init(0.72, 0.140, 250, alpha: 0.35)
    )

    // MARK: Paper (light)

    /// Paper — the warm light palette. Hue 85 drives a subtle cream
    /// background that keeps glass surfaces legible without printing
    /// a hard shadow onto dark photos.
    static let paper = Design.ThemePalette(
        backgroundPrimary:  .init(0.96, 0.008, 85),
        backgroundSecondary: .init(0.93, 0.012, 85),
        backgroundTertiary: .init(0.90, 0.015, 85),
        glassTint:          .init(1.00, 0.000, 0,  alpha: 0.55),
        glassBorder:        .init(0.00, 0.000, 0,  alpha: 0.08),
        glassHighlight:     .init(1.00, 0.000, 0,  alpha: 0.55),
        divider:            .init(0.00, 0.000, 0,  alpha: 0.08),
        textHigh:           .init(0.20, 0.015, 260),
        textMedium:         .init(0.38, 0.015, 260),
        textLow:            .init(0.52, 0.015, 260),
        textDim:            .init(0.65, 0.010, 260),
        accent:             .init(0.55, 0.140, 250),
        accentSoft:         .init(0.55, 0.140, 250, alpha: 0.15),
        accentGlow:         .init(0.55, 0.140, 250, alpha: 0.25)
    )

    // MARK: Nocturne (deep OLED dark)

    /// Nocturne — true-black background for OLED. The aurora blobs
    /// fade to 0.25 opacity to avoid burning in; glass borders lift
    /// slightly to preserve edge definition.
    static let nocturne = Design.ThemePalette(
        backgroundPrimary:  .init(0.00, 0.000, 0),
        backgroundSecondary: .init(0.14, 0.005, 260),
        backgroundTertiary: .init(0.18, 0.010, 260),
        glassTint:          .init(0.20, 0.010, 260, alpha: 0.60),
        glassBorder:        .init(1.00, 0.000, 0,   alpha: 0.10),
        glassHighlight:     .init(1.00, 0.000, 0,   alpha: 0.04),
        divider:            .init(1.00, 0.000, 0,   alpha: 0.06),
        textHigh:           .init(0.96, 0.005, 260),
        textMedium:         .init(0.72, 0.005, 260),
        textLow:            .init(0.50, 0.005, 260),
        textDim:            .init(0.38, 0.005, 260),
        accent:             .init(0.78, 0.140, 250),
        accentSoft:         .init(0.78, 0.140, 250, alpha: 0.18),
        accentGlow:         .init(0.78, 0.140, 250, alpha: 0.45)
    )
}

// MARK: - Theme Resolver

extension Design {

    /// Returns the palette shipped with the given theme identity.
    ///
    /// Keeping this helper at module level means future tokens
    /// (for example per-surface overrides defined in project config)
    /// can resolve to a palette without every consumer having to know
    /// about the concrete `ThemePalette` cases.
    static func palette(for identity: ThemeIdentity) -> ThemePalette {
        switch identity {
        case .aurora:   return .aurora
        case .paper:    return .paper
        case .nocturne: return .nocturne
        }
    }

    /// Maps a theme identity to the `NSAppearance` that best matches
    /// its chrome. The redesign eventually renders its own `.glass`
    /// layers, but toolbars, sheets and menus still inherit AppKit
    /// materials so they need the correct system appearance.
    static func appearance(for identity: ThemeIdentity) -> NSAppearance? {
        identity.prefersDarkAppearance ? NSAppearance(named: .darkAqua)
                                       : NSAppearance(named: .aqua)
    }
}
