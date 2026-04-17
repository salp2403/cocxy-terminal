// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Tests for NotificationRingDecision — the pure decision enum driving the
// per-surface notification ring in Fase 3.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("NotificationRingDecision")
struct NotificationRingDecisionSwiftTestingTests {

    // MARK: - Hide for non-waiting states

    @Test("hides the ring when the surface is idle")
    func hidesWhenIdle() {
        let decision = NotificationRingDecision.decide(
            agentState: .idle,
            isTabVisible: false,
            isSurfaceFocused: false
        )
        #expect(decision == .hide)
    }

    @Test("hides the ring while the agent is working")
    func hidesWhenWorking() {
        let decision = NotificationRingDecision.decide(
            agentState: .working,
            isTabVisible: false,
            isSurfaceFocused: false
        )
        #expect(decision == .hide)
    }

    @Test("hides the ring after the agent finishes")
    func hidesWhenFinished() {
        let decision = NotificationRingDecision.decide(
            agentState: .finished,
            isTabVisible: false,
            isSurfaceFocused: false
        )
        #expect(decision == .hide)
    }

    @Test("hides the ring when the agent errored out")
    func hidesWhenError() {
        let decision = NotificationRingDecision.decide(
            agentState: .error,
            isTabVisible: false,
            isSurfaceFocused: false
        )
        #expect(decision == .hide)
    }

    @Test("hides the ring during launch")
    func hidesWhenLaunched() {
        let decision = NotificationRingDecision.decide(
            agentState: .launched,
            isTabVisible: false,
            isSurfaceFocused: false
        )
        #expect(decision == .hide)
    }

    // MARK: - Show for waitingInput on unattended surfaces

    @Test("shows the ring on a background tab waiting for input")
    func showsOnBackgroundTab() {
        let decision = NotificationRingDecision.decide(
            agentState: .waitingInput,
            isTabVisible: false,
            isSurfaceFocused: false
        )
        #expect(decision == .show)
    }

    @Test("shows the ring on an unfocused split of the displayed tab")
    func showsOnUnfocusedSplitOfVisibleTab() {
        let decision = NotificationRingDecision.decide(
            agentState: .waitingInput,
            isTabVisible: true,
            isSurfaceFocused: false
        )
        #expect(decision == .show)
    }

    // MARK: - Hide when the user is already looking at the surface

    @Test("hides the ring on the focused surface of the displayed tab")
    func hidesOnFocusedSurfaceOfVisibleTab() {
        let decision = NotificationRingDecision.decide(
            agentState: .waitingInput,
            isTabVisible: true,
            isSurfaceFocused: true
        )
        #expect(decision == .hide)
    }

    // MARK: - Edge case: focused flag is ignored on background tabs

    @Test("shows the ring when the tab is hidden even if the surface is flagged focused")
    func ignoresFocusedFlagOnHiddenTab() {
        // A background tab cannot be "focused" from the user's point of
        // view even if first-responder bookkeeping still points at one of
        // its surfaces. The decision must not accidentally swallow the
        // waiting signal.
        let decision = NotificationRingDecision.decide(
            agentState: .waitingInput,
            isTabVisible: false,
            isSurfaceFocused: true
        )
        #expect(decision == .show)
    }
}
