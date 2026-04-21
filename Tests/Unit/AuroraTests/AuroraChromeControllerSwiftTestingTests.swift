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
    func tabsPublisherUsesEmittedTabsWhenAddingNewTab() {
        let harness = makeHarness()

        let newTab = harness.tabManager.addTab(
            workingDirectory: URL(fileURLWithPath: "/tmp/aurora-tabs-willset")
        )

        let sessionIDs = Set(
            harness.controller.workspaces
                .flatMap { $0.sessions }
                .map(\.id)
        )
        #expect(
            sessionIDs.contains(newTab.id.rawValue.uuidString),
            "Aurora must consume the tabs array emitted by @Published instead of reading TabManager.tabs during willSet"
        )
    }

    @Test
    func activeTabPublisherUsesEmittedIDWhenSwitchingExistingTabs() {
        let harness = makeHarness()
        let firstTab = harness.tabManager.tabs[0]
        let secondTab = harness.tabManager.addTab(
            workingDirectory: URL(fileURLWithPath: "/tmp/aurora-active-switch")
        )
        harness.controller.refreshSources()
        #expect(harness.controller.activeSessionID == secondTab.id.rawValue.uuidString)

        harness.tabManager.setActive(id: firstTab.id)

        #expect(harness.tabManager.activeTabID == firstTab.id)
        #expect(
            harness.controller.activeSessionID == firstTab.id.rawValue.uuidString,
            "Aurora must use the activeTabID emitted by @Published, not a stale read during willSet"
        )
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

    @Test
    func storePublisherUsesEmittedStatesWhenAgentLaunches() {
        let harness = makeHarness()
        let tab = harness.tabManager.tabs[0]
        let sid = SurfaceID()
        harness.controller.surfaceIDsByTabProvider = { [tab] in [tab.id: [sid]] }
        harness.controller.refreshSources()

        harness.store.set(
            surfaceID: sid,
            state: SurfaceAgentState(
                agentState: .launched,
                detectedAgent: DetectedAgent(
                    name: "Claude Code",
                    launchCommand: "claude",
                    startedAt: Date()
                )
            )
        )

        let firstSession = harness.controller.workspaces.first?.sessions.first
        #expect(
            firstSession?.state == .launched,
            "Aurora must render the just-emitted store state immediately instead of waiting for a later tab switch"
        )
        #expect(firstSession?.agent == .claude)
        #expect(firstSession?.panes.first?.state == .launched)
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
    func closeSessionCallbackResolvesTabID() {
        let harness = makeHarness()
        let tab = harness.tabManager.addTab(
            workingDirectory: URL(fileURLWithPath: "/tmp/aurora-close")
        )
        var closed: TabID?
        harness.controller.onCloseSession = { closed = $0 }

        if let tabID = harness.controller.tabID(forSessionID: tab.id.rawValue.uuidString) {
            harness.controller.onCloseSession?(tabID)
        }

        #expect(closed == tab.id)
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

    @Test
    func showPaletteUnhidesTheHostingView() {
        let harness = makeHarness()
        // Instantiate the palette host so the visibility contract has
        // a real view to flip. Mirrors how the integration layer
        // mounts it on install.
        let host = harness.controller.makePaletteHost()
        host.isHidden = true

        harness.controller.showPalette()

        #expect(harness.controller.isPaletteVisible == true)
        #expect(host.isHidden == false,
                "showPalette must un-hide the hosting view so hit-testing reaches the SwiftUI overlay")
    }

    @Test
    func hidePaletteReHidesTheHostingView() {
        let harness = makeHarness()
        let host = harness.controller.makePaletteHost()
        harness.controller.showPalette()
        #expect(host.isHidden == false)

        harness.controller.hidePalette()

        #expect(harness.controller.isPaletteVisible == false)
        #expect(host.isHidden == true,
                "hidePalette must hide the hosting view so clicks fall through to the terminal underneath")
    }

    @Test
    func togglePaletteAlternatesVisibilityAndHostState() {
        let harness = makeHarness()
        let host = harness.controller.makePaletteHost()

        harness.controller.togglePalette()
        #expect(harness.controller.isPaletteVisible == true)
        #expect(host.isHidden == false)

        harness.controller.togglePalette()
        #expect(harness.controller.isPaletteVisible == false)
        #expect(host.isHidden == true)
    }

    // MARK: - Shortcut label publishing

    @Test
    func shortcutLabelsDefaultToCatalogPrettyLabels() {
        let harness = makeHarness()
        // The catalog emits labels through `KeybindingShortcut.prettyLabel`,
        // which follows the macOS-canonical modifier order
        // (`⌃⌥⇧⌘<key>`), so `cmd+shift+p` becomes `⇧⌘P`, not `⌘⇧P`.
        #expect(
            harness.controller.paletteShortcutLabel ==
                KeybindingActionCatalog.windowCommandPalette.defaultShortcut.prettyLabel,
            "Default palette label must match KeybindingActionCatalog.windowCommandPalette"
        )
        #expect(harness.controller.paletteShortcutLabel == "⇧⌘P")
        #expect(
            harness.controller.newTabShortcutLabel ==
                KeybindingActionCatalog.tabNew.defaultShortcut.prettyLabel,
            "Default new-tab label must match KeybindingActionCatalog.tabNew"
        )
        #expect(harness.controller.newTabShortcutLabel == "⌘T")
    }

    @Test
    func shortcutLabelsArePublishedAndMutable() {
        let harness = makeHarness()
        harness.controller.paletteShortcutLabel = "⌃⇧Space"
        harness.controller.newTabShortcutLabel = "⌘N"
        #expect(harness.controller.paletteShortcutLabel == "⌃⇧Space")
        #expect(harness.controller.newTabShortcutLabel == "⌘N")
    }

    // MARK: - Theme identity publishing

    @Test
    func themeIdentityDefaultsToDarkAuroraAndCanSwitchToPaper() {
        let harness = makeHarness()
        #expect(harness.controller.themeIdentity == .aurora)

        harness.controller.themeIdentity = .paper
        #expect(harness.controller.themeIdentity == .paper)
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
