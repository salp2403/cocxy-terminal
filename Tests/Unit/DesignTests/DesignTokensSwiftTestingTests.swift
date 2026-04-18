// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DesignTokensSwiftTestingTests.swift - Tokens and theme palette contracts.
//
// The Aurora redesign ships its tokens as value types so they can be
// compared directly in tests without booting AppKit. These tests pin
// the shipping palettes, the theme cycle, the agent catalog, and the
// OKLCH math so the design reference stays synchronized with the
// Swift source as the redesign evolves.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Design tokens and palettes")
struct DesignTokensSwiftTestingTests {

    // MARK: - Theme cycle + metadata

    @Test("Theme cycle rotates aurora -> paper -> nocturne -> aurora")
    func themeCycleOrder() {
        #expect(Design.ThemeIdentity.aurora.cycleNext() == .paper)
        #expect(Design.ThemeIdentity.paper.cycleNext() == .nocturne)
        #expect(Design.ThemeIdentity.nocturne.cycleNext() == .aurora)
    }

    @Test("Every theme exposes a human-readable display name")
    func themeDisplayNameIsNonEmpty() {
        for identity in Design.ThemeIdentity.allCases {
            #expect(!identity.displayName.isEmpty)
        }
    }

    @Test("Aurora and Nocturne prefer the dark appearance; Paper prefers light")
    func themeDarkPreferenceMatchesReference() {
        #expect(Design.ThemeIdentity.aurora.prefersDarkAppearance == true)
        #expect(Design.ThemeIdentity.paper.prefersDarkAppearance == false)
        #expect(Design.ThemeIdentity.nocturne.prefersDarkAppearance == true)
    }

    // MARK: - OKLCH helpers

    @Test("OKLCHColor.withAlpha preserves lightness / chroma / hue")
    func oklchWithAlphaPreservesComponents() {
        let base = Design.OKLCHColor(0.72, 0.14, 250, alpha: 1.0)
        let transparent = base.withAlpha(0.35)

        #expect(transparent.lightness == base.lightness)
        #expect(transparent.chroma == base.chroma)
        #expect(transparent.hue == base.hue)
        #expect(transparent.alpha == 0.35)
    }

    @Test("OKLCHColor conversion stays inside the sRGB unit cube")
    func oklchResolvesInsideSRGBGamut() {
        // Every documented palette token must resolve to valid sRGB
        // channels (0 ... 1). Out-of-gamut values would be clamped to
        // nonsense on screen.
        for palette in [Design.ThemePalette.aurora, .paper, .nocturne] {
            for token in allTokens(in: palette) {
                #expect(token.sRGBRed >= 0 && token.sRGBRed <= 1)
                #expect(token.sRGBGreen >= 0 && token.sRGBGreen <= 1)
                #expect(token.sRGBBlue >= 0 && token.sRGBBlue <= 1)
            }
        }
    }

    // MARK: - Shipping palettes

    @Test("Aurora palette matches the design reference hue 260 / accent 250")
    func auroraPaletteMatchesReference() {
        let aurora = Design.ThemePalette.aurora
        #expect(aurora.backgroundPrimary == .init(0.16, 0.020, 260))
        #expect(aurora.backgroundSecondary == .init(0.21, 0.025, 260))
        #expect(aurora.backgroundTertiary == .init(0.26, 0.028, 260))
        #expect(aurora.accent == .init(0.72, 0.140, 250))
        #expect(aurora.accentSoft.alpha == 0.15)
        #expect(aurora.accentGlow.alpha == 0.35)
        #expect(aurora.glassTint.alpha == 0.55)
        #expect(aurora.glassBorder.alpha == 0.08)
    }

    @Test("Paper palette stays bright and keeps the indigo text cascade")
    func paperPaletteMatchesReference() {
        let paper = Design.ThemePalette.paper
        // Text cascade shifts hue to 260 so reading copy contrasts well
        // against the warm-hue background.
        #expect(paper.textHigh.hue == 260)
        #expect(paper.textMedium.hue == 260)
        #expect(paper.textLow.hue == 260)
        // Background stays warm at hue 85.
        #expect(paper.backgroundPrimary.hue == 85)
        #expect(paper.backgroundPrimary.lightness == 0.96)
    }

    @Test("Nocturne palette pins the primary background to pure black")
    func nocturnePaletteMatchesReference() {
        let nocturne = Design.ThemePalette.nocturne
        #expect(nocturne.backgroundPrimary.lightness == 0.0)
        #expect(nocturne.backgroundPrimary.chroma == 0.0)
        #expect(nocturne.glassTint.alpha == 0.60)
    }

    @Test("Design.palette(for:) dispatches to the shipping palette")
    func paletteResolverDispatches() {
        #expect(Design.palette(for: .aurora) == .aurora)
        #expect(Design.palette(for: .paper) == .paper)
        #expect(Design.palette(for: .nocturne) == .nocturne)
    }

    // MARK: - Agent catalog

    @Test("Agent abbreviations mirror the design reference (Cl, Co, Ge, Ai, Sh)")
    func agentAbbreviations() {
        #expect(Design.AgentAccent.claude.abbreviation == "Cl")
        #expect(Design.AgentAccent.codex.abbreviation == "Co")
        #expect(Design.AgentAccent.gemini.abbreviation == "Ge")
        #expect(Design.AgentAccent.aider.abbreviation == "Ai")
        #expect(Design.AgentAccent.shell.abbreviation == "Sh")
    }

    @Test("Every agent token stays at the reference lightness")
    func agentTokenLightnessIsUniform() {
        // The design reference keeps accent colours at lightness 0.78
        // so chips look balanced next to each other. Shell is the only
        // exception (it is grayscale and uses 0.80 chroma 0.02).
        for agent in [Design.AgentAccent.claude, .codex, .gemini, .aider] {
            #expect(agent.token.lightness == 0.78)
            #expect(agent.token.chroma == 0.14)
        }
        #expect(Design.AgentAccent.shell.token.chroma == 0.02)
    }

    // MARK: - Agent state roles

    @Test("Agent state tokens enumerate every lifecycle transition")
    func agentStateRoleTokens() {
        #expect(Design.AgentStateRole.idle.token == .init(0.60, 0.02, 260))
        #expect(Design.AgentStateRole.launched.token == .init(0.78, 0.14, 240))
        #expect(Design.AgentStateRole.working.token == .init(0.78, 0.14, 80))
        #expect(Design.AgentStateRole.waiting.token == .init(0.78, 0.14, 30))
        #expect(Design.AgentStateRole.finished.token == .init(0.78, 0.14, 150))
        #expect(Design.AgentStateRole.error.token == .init(0.72, 0.18, 25))
    }

    // MARK: - Radius + spacing

    @Test("Radius tokens match the 8 / 12 / 18 / 24 reference scale")
    func radiusTokenValues() {
        #expect(Design.Radius.small.rawValue == 8)
        #expect(Design.Radius.medium.rawValue == 12)
        #expect(Design.Radius.large.rawValue == 18)
        #expect(Design.Radius.extraLarge.rawValue == 24)
    }

    @Test("Spacing scale stays monotonically increasing")
    func spacingScaleMonotonic() {
        let ladder: [CGFloat] = [
            Design.Spacing.hairline,
            Design.Spacing.xxSmall,
            Design.Spacing.xSmall,
            Design.Spacing.small,
            Design.Spacing.medium,
            Design.Spacing.large,
            Design.Spacing.xLarge,
        ]
        for index in 1..<ladder.count {
            #expect(ladder[index] > ladder[index - 1])
        }
    }

    // MARK: - Helpers

    private func allTokens(in palette: Design.ThemePalette) -> [Design.OKLCHColor] {
        [
            palette.backgroundPrimary,
            palette.backgroundSecondary,
            palette.backgroundTertiary,
            palette.glassTint,
            palette.glassBorder,
            palette.glassHighlight,
            palette.divider,
            palette.textHigh,
            palette.textMedium,
            palette.textLow,
            palette.textDim,
            palette.accent,
            palette.accentSoft,
            palette.accentGlow,
        ]
    }
}
