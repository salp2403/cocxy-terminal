// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GlassRenderModeSwiftTestingTests.swift - Decision-table coverage for
// the Liquid Glass render-mode resolver.
//
// The Aurora `GlassSurface` primitive needs the resolver to be
// completely deterministic: a single helper chooses between real
// Liquid Glass, the NSVisualEffectView fallback, and the opaque
// accessibility surface. These tests pin every cell of the truth
// table so later refactors cannot silently skip the
// Increase Contrast / Reduce Transparency gates.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("GlassSurface render-mode resolver")
struct GlassRenderModeSwiftTestingTests {

    // MARK: - Override wins

    @Test("Developer override bypasses every runtime signal")
    func developerOverrideWins() {
        let inputs = Design.GlassRenderInputs(
            supportsLiquidGlass: true,
            reduceTransparency: true,
            increaseContrast: true,
            developerOverride: .visualEffect
        )
        #expect(Design.resolveGlassRenderMode(inputs) == .visualEffect)
    }

    @Test("Developer override can force opaque even on a capable platform")
    func developerOverrideForcesOpaque() {
        let inputs = Design.GlassRenderInputs(
            supportsLiquidGlass: true,
            reduceTransparency: false,
            increaseContrast: false,
            developerOverride: .opaque
        )
        #expect(Design.resolveGlassRenderMode(inputs) == .opaque)
    }

    // MARK: - Accessibility gates

    @Test("Increase Contrast forces the opaque surface regardless of platform")
    func increaseContrastForcesOpaque() {
        let capable = Design.GlassRenderInputs(
            supportsLiquidGlass: true,
            reduceTransparency: false,
            increaseContrast: true
        )
        let legacy = Design.GlassRenderInputs(
            supportsLiquidGlass: false,
            reduceTransparency: false,
            increaseContrast: true
        )
        #expect(Design.resolveGlassRenderMode(capable) == .opaque)
        #expect(Design.resolveGlassRenderMode(legacy) == .opaque)
    }

    @Test("Increase Contrast dominates Reduce Transparency")
    func increaseContrastDominatesReduceTransparency() {
        let inputs = Design.GlassRenderInputs(
            supportsLiquidGlass: true,
            reduceTransparency: true,
            increaseContrast: true
        )
        #expect(Design.resolveGlassRenderMode(inputs) == .opaque)
    }

    @Test("Reduce Transparency forces the opaque surface on every platform")
    func reduceTransparencyForcesOpaque() {
        let capable = Design.GlassRenderInputs(
            supportsLiquidGlass: true,
            reduceTransparency: true,
            increaseContrast: false
        )
        let legacy = Design.GlassRenderInputs(
            supportsLiquidGlass: false,
            reduceTransparency: true,
            increaseContrast: false
        )
        #expect(Design.resolveGlassRenderMode(capable) == .opaque)
        #expect(Design.resolveGlassRenderMode(legacy) == .opaque)
    }

    // MARK: - Platform capability

    @Test("Liquid Glass is picked only when the platform supports it")
    func liquidGlassRequiresCapablePlatform() {
        let capable = Design.GlassRenderInputs(
            supportsLiquidGlass: true,
            reduceTransparency: false,
            increaseContrast: false
        )
        let legacy = Design.GlassRenderInputs(
            supportsLiquidGlass: false,
            reduceTransparency: false,
            increaseContrast: false
        )
        #expect(Design.resolveGlassRenderMode(capable) == .liquid)
        #expect(Design.resolveGlassRenderMode(legacy) == .visualEffect)
    }
}
