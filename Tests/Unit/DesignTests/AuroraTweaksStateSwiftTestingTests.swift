// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Pure coverage for `AuroraTweaksState` and its derived labels.
///
/// The tweaks panel is a developer inspector and does not ship in the
/// production chrome, but the state type is what any caller persists /
/// wires through `@Binding`. Regressions in the labels or the default
/// value shape would show up in the demo harness without a clear
/// source — pinning them here keeps the contract cheap to verify.
@Suite("Aurora tweaks state")
struct AuroraTweaksStateTests {

    // MARK: - Defaults

    @Test("Default state matches the public documentation")
    func defaultsMatchDocumentation() {
        let state = Design.AuroraTweaksState.defaults
        #expect(state.theme == .aurora)
        #expect(state.renderModeOverride == nil)
        #expect(state.backdropEnabled == true)
    }

    @Test("Init with explicit arguments keeps every field")
    func initKeepsEveryField() {
        let state = Design.AuroraTweaksState(
            theme: .paper,
            renderModeOverride: .opaque,
            backdropEnabled: false
        )
        #expect(state.theme == .paper)
        #expect(state.renderModeOverride == .opaque)
        #expect(state.backdropEnabled == false)
    }

    // MARK: - Mode label

    @Test("renderModeLabel returns the auto copy when no override is set")
    func renderModeLabelReturnsAutoCopy() {
        var state = Design.AuroraTweaksState.defaults
        state.renderModeOverride = nil
        #expect(state.renderModeLabel == "Auto (decision table)")
    }

    @Test("renderModeLabel reflects the liquid override")
    func renderModeLabelForLiquid() {
        let state = Design.AuroraTweaksState(
            theme: .aurora,
            renderModeOverride: .liquid
        )
        #expect(state.renderModeLabel == "Force liquid glass")
    }

    @Test("renderModeLabel reflects the visual-effect override")
    func renderModeLabelForVisualEffect() {
        let state = Design.AuroraTweaksState(
            theme: .aurora,
            renderModeOverride: .visualEffect
        )
        #expect(state.renderModeLabel == "Force visual effect fallback")
    }

    @Test("renderModeLabel reflects the opaque override")
    func renderModeLabelForOpaque() {
        let state = Design.AuroraTweaksState(
            theme: .aurora,
            renderModeOverride: .opaque
        )
        #expect(state.renderModeLabel == "Force opaque accessibility surface")
    }

    // MARK: - Equatable

    @Test("Two states with the same fields are Equatable-equal")
    func equatableEquality() {
        let a = Design.AuroraTweaksState(theme: .nocturne, renderModeOverride: .liquid, backdropEnabled: false)
        let b = Design.AuroraTweaksState(theme: .nocturne, renderModeOverride: .liquid, backdropEnabled: false)
        #expect(a == b)
    }

    @Test("Changing a single field makes two states diverge")
    func equatableInequality() {
        let a = Design.AuroraTweaksState(theme: .aurora)
        let b = Design.AuroraTweaksState(theme: .paper)
        #expect(a != b)
    }
}
