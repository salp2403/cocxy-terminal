// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraChromeControllerSwiftTestingTests.swift - Coverage for the
// integration controller that bridges the domain to the Aurora chrome.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("AuroraChromeController — domain bridge")
struct AuroraChromeControllerSwiftTestingTests {

    // MARK: - Test harness

    /// Named harness that retains every collaborator strongly so the
    /// controller's `weak` references stay valid for the duration of
    /// the test. Tuple destructuring with `_` silently released the
    /// store in practice because the controller only holds a weak
    /// reference; using a named struct removes that foot-gun entirely.
    private struct Harness {
        let controller: AuroraChromeController
        let tabManager: TabManager
        let store: AgentStatePerSurfaceStore
    }

    /// Builds a fresh harness, starts the controller subscriptions and
    /// hands it to the caller. Every property must stay bound to a
    /// local `let` in the test body — the controller weak-refs the
    /// tab manager and the store, so discarding either breaks the
    /// reactive pipeline silently.
    private func makeHarness() -> Harness {
        let tabManager = TabManager()
        let store = AgentStatePerSurfaceStore()
        let controller = AuroraChromeController(
            tabManager: tabManager,
            store: store
        )
        controller.beginObservingDomain()
        return Harness(
            controller: controller,
            tabManager: tabManager,
            store: store
        )
    }

    // MARK: - Initial state

    @Test
    func initialSnapshotContainsBootstrapTab() {
        let harness = makeHarness()
        #expect(harness.controller.workspaces.count >= 1)
        #expect(harness.controller.activeSessionID == harness.tabManager.activeTabID?.rawValue.uuidString)
    }

    @Test
    func clockLabelFollowsHHMMFormat() {
        let harness = makeHarness()
        #expect(harness.controller.clockLabel.count == 5)
        #expect(harness.controller.clockLabel.contains(":"))
    }

    // MARK: - Domain reactivity

    @Test
    func addingTabPropagatesNewSession() {
        let harness = makeHarness()
        let initialIDs = Set(
            harness.controller.workspaces
                .flatMap { $0.sessions }
                .map(\.id)
        )

        let newURL = URL(fileURLWithPath: "/tmp/aurora-test-new-tab")
        let newTab = harness.tabManager.addTab(workingDirectory: newURL)

        // Sanity: the TabManager itself accepted the new tab.
        #expect(harness.tabManager.tabs.count == 2)
        #expect(harness.tabManager.activeTabID == newTab.id)

        harness.controller.refreshSources()

        let afterIDs = Set(
            harness.controller.workspaces
                .flatMap { $0.sessions }
                .map(\.id)
        )
        let newSessionID = newTab.id.rawValue.uuidString
        #expect(afterIDs.contains(newSessionID),
                "Aurora workspace tree must include the newly added tab's session id")
        #expect(initialIDs.isSubset(of: afterIDs),
                "Adding a tab must not drop existing sessions from the tree")
        #expect(harness.controller.activeSessionID == newSessionID)
    }

    @Test
    func storeUpdatePropagatesAgentAccent() {
        let harness = makeHarness()
        let tab = harness.tabManager.tabs[0]

        let sid = SurfaceID()
        harness.controller.surfaceIDsByTabProvider = { [tab] in [tab.id: [sid]] }

        harness.store.set(
            surfaceID: sid,
            state: SurfaceAgentState(
                agentState: .working,
                detectedAgent: DetectedAgent(
                    name: "claude-code",
                    launchCommand: "claude-code",
                    startedAt: Date()
                )
            )
        )
        harness.controller.refreshSources()

        let firstSession = harness.controller.workspaces.first?.sessions.first
        #expect(firstSession?.agent == .claude)
        #expect(firstSession?.state == .working)
    }

    // MARK: - Callbacks

    @Test
    func activateSessionCallbackResolvesTabID() {
        let harness = makeHarness()
        let newTab = harness.tabManager.addTab(
            workingDirectory: URL(fileURLWithPath: "/tmp/aurora-activate")
        )

        var activated: TabID?
        harness.controller.onActivateSession = { activated = $0 }

        if let tabID = harness.controller.tabID(forSessionID: newTab.id.rawValue.uuidString) {
            harness.controller.onActivateSession?(tabID)
        }

        #expect(activated == newTab.id)
    }

    @Test
    func createTabCallbackFiresWhenSidebarRequests() {
        let harness = makeHarness()
        var invoked = 0
        harness.controller.onCreateTab = { invoked += 1 }

        harness.controller.onCreateTab?()
        harness.controller.onCreateTab?()
        #expect(invoked == 2)
    }

    @Test
    func togglePaletteCallbackFiresFromSidebar() {
        let harness = makeHarness()
        var invoked = false
        harness.controller.onTogglePalette = { invoked = true }

        harness.controller.onTogglePalette?()
        #expect(invoked == true)
    }

    // MARK: - Palette lifecycle

    @Test
    func setPaletteActionsTruncatesSelectionIndex() {
        let harness = makeHarness()
        harness.controller.paletteSelectedIndex = 42
        harness.controller.setPaletteActions([
            Design.AuroraPaletteAction(
                id: "tab.new",
                label: "New Tab",
                category: "Tabs"
            ),
        ])
        #expect(harness.controller.paletteSelectedIndex == 0)
    }

    @Test
    func showPaletteResetsQueryAndSelection() {
        let harness = makeHarness()
        harness.controller.paletteQuery = "stale query"
        harness.controller.paletteSelectedIndex = 5
        harness.controller.isPaletteVisible = false

        harness.controller.showPalette()

        #expect(harness.controller.isPaletteVisible == true)
        #expect(harness.controller.paletteQuery == "")
        #expect(harness.controller.paletteSelectedIndex == 0)
    }

    @Test
    func hidePaletteTriggersDismissCallback() {
        let harness = makeHarness()
        harness.controller.showPalette()

        var dismissed = false
        harness.controller.onDismissPalette = { dismissed = true }

        harness.controller.hidePalette()

        #expect(harness.controller.isPaletteVisible == false)
        #expect(dismissed == true)
    }

    // MARK: - Idempotent host factories

    @Test
    func sidebarHostIsCachedAcrossCalls() {
        let harness = makeHarness()
        let first = harness.controller.makeSidebarHost()
        let second = harness.controller.makeSidebarHost()
        #expect(first === second)
    }

    @Test
    func statusBarHostIsCachedAcrossCalls() {
        let harness = makeHarness()
        let first = harness.controller.makeStatusBarHost()
        let second = harness.controller.makeStatusBarHost()
        #expect(first === second)
    }

    @Test
    func paletteHostIsCachedAcrossCalls() {
        let harness = makeHarness()
        let first = harness.controller.makePaletteHost()
        let second = harness.controller.makePaletteHost()
        #expect(first === second)
    }

    // MARK: - Observer teardown

    @Test
    func stopObservingPreventsFurtherRefreshes() {
        let harness = makeHarness()
        harness.controller.stopObserving()

        let beforeIDs = Set(
            harness.controller.workspaces
                .flatMap { $0.sessions }
                .map(\.id)
        )
        harness.tabManager.addTab(
            workingDirectory: URL(fileURLWithPath: "/tmp/aurora-detached")
        )
        let afterIDs = Set(
            harness.controller.workspaces
                .flatMap { $0.sessions }
                .map(\.id)
        )

        #expect(afterIDs == beforeIDs,
                "stopObserving must stop the controller from reacting to domain changes")
    }
}
