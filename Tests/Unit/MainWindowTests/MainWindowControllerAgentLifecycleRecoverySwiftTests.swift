// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowControllerAgentLifecycleRecoverySwiftTests.swift
//
// Integration coverage for the shell-prompt agent-state recovery and the
// `.launched` watchdog wired into MainWindowController.

import AppKit
import Testing
@testable import CocxyTerminal

/// Serialized because every test that exercises the launched watchdog
/// awaits a real `DispatchQueue.main.asyncAfter` deadline. Under the full
/// test suite's parallel main-actor contention, those deadlines can slip
/// enough to flake the assertion window. Serializing keeps the sequencing
/// deterministic without resorting to retries (see
/// `feedback_no_retry_for_timeouts`).
@Suite("MainWindowController agent lifecycle recovery", .serialized)
@MainActor
struct MainWindowControllerAgentLifecycleRecoverySwiftTests {

    // MARK: - performAgentStateReset

    @Test("performAgentStateReset clears store entry and engine buckets")
    func performAgentStateResetClearsStoreAndEngine() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let store = AgentStatePerSurfaceStore()
        let engine = AgentDetectionEngineImpl(compiledConfigs: [])
        controller.injectedPerSurfaceStore = store
        controller.injectedAgentDetectionEngine = engine

        let surfaceID = SurfaceID()
        let tabID = controller.tabManager.tabs.first!.id

        // Seed the store with a launched agent so the reset has
        // observable state to clear.
        store.update(surfaceID: surfaceID) { state in
            state.agentState = .launched
            state.detectedAgent = DetectedAgent(
                name: "claude",
                displayName: "Claude Code",
                launchCommand: "claude",
                startedAt: Date()
            )
            state.agentToolCount = 5
            state.agentErrorCount = 1
            state.agentActivity = "Read: main.swift"
        }
        #expect(store.state(for: surfaceID).agentState == .launched)

        controller.performAgentStateReset(
            surfaceID: surfaceID,
            tabID: tabID,
            reason: .shellPromptWithShellForeground
        )

        let cleared = store.state(for: surfaceID)
        #expect(cleared == .idle)
        #expect(store.states[surfaceID] == nil)
    }

    @Test("performAgentStateReset cancels a pending launched watchdog")
    func performAgentStateResetCancelsWatchdog() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let store = AgentStatePerSurfaceStore()
        controller.injectedPerSurfaceStore = store

        let surfaceID = SurfaceID()
        let tabID = controller.tabManager.tabs.first!.id

        controller.scheduleLaunchedWatchdog(
            surfaceID: surfaceID,
            tabID: tabID,
            timeout: 60.0
        )
        #expect(controller.agentLaunchedWatchdog.isScheduled(surfaceID: surfaceID))

        controller.performAgentStateReset(
            surfaceID: surfaceID,
            tabID: tabID,
            reason: .shellPromptWithShellForeground
        )

        #expect(controller.agentLaunchedWatchdog.isScheduled(surfaceID: surfaceID) == false)
    }

    @Test("performAgentStateReset is safe when store is not injected")
    func performAgentStateResetWithoutStoreIsSafe() {
        // Runs without crashing even if agent-detection is disabled.
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let tabID = controller.tabManager.tabs.first!.id
        controller.performAgentStateReset(
            surfaceID: SurfaceID(),
            tabID: tabID,
            reason: .launchedWatchdog
        )
    }

    // MARK: - recoverAgentStateOnShellPromptIfNeeded

    @Test("recoverAgentStateOnShellPromptIfNeeded is a no-op when bridge returns no registration")
    func recoverIsNoOpWhenBridgeHasNoRegistration() {
        // MockTerminalEngine uses the protocol default which returns nil
        // for processMonitorRegistration. The helper must treat this as
        // "do not reset" so tests and environments without a real PTY
        // never lose live state.
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let store = AgentStatePerSurfaceStore()
        controller.injectedPerSurfaceStore = store

        let surfaceID = SurfaceID()
        let tabID = controller.tabManager.tabs.first!.id
        store.update(surfaceID: surfaceID) { $0.agentState = .launched }

        controller.recoverAgentStateOnShellPromptIfNeeded(
            surfaceID: surfaceID,
            tabID: tabID
        )

        #expect(store.state(for: surfaceID).agentState == .launched)
    }

    @Test("recoverAgentStateOnShellPromptIfNeeded is a no-op when store is not injected")
    func recoverIsNoOpWhenStoreIsMissing() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let tabID = controller.tabManager.tabs.first!.id
        // Must not crash. Nothing to assert beyond the absence of a crash
        // because there is no store to observe.
        controller.recoverAgentStateOnShellPromptIfNeeded(
            surfaceID: SurfaceID(),
            tabID: tabID
        )
    }

    // MARK: - Watchdog integration

    @Test("launched watchdog flushes the store entry when it fires")
    func launchedWatchdogResetsStoreOnTimeout() async throws {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let store = AgentStatePerSurfaceStore()
        controller.injectedPerSurfaceStore = store

        let surfaceID = SurfaceID()
        let tabID = controller.tabManager.tabs.first!.id

        store.update(surfaceID: surfaceID) { state in
            state.agentState = .launched
            state.detectedAgent = DetectedAgent(
                name: "claude",
                displayName: "Claude Code",
                launchCommand: "claude",
                startedAt: Date()
            )
        }

        controller.scheduleLaunchedWatchdog(
            surfaceID: surfaceID,
            tabID: tabID,
            timeout: 0.20
        )

        // Poll for the watchdog to fire. Fixed sleeps flake under
        // parallel main-actor contention; polling waits for the actual
        // state transition the test is verifying. See
        // `feedback_no_retry_for_timeouts` for why this is the right
        // pattern (polling observable state) instead of retry wrappers.
        let deadline = Date().addingTimeInterval(5.0)
        while store.state(for: surfaceID).agentState != .idle, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(store.state(for: surfaceID) == .idle)
        #expect(controller.agentLaunchedWatchdog.isScheduled(surfaceID: surfaceID) == false)
    }

    @Test("launched watchdog does not fire when surface has already moved off .launched")
    func launchedWatchdogSkipsResetWhenStateAdvanced() async throws {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let store = AgentStatePerSurfaceStore()
        controller.injectedPerSurfaceStore = store

        let surfaceID = SurfaceID()
        let tabID = controller.tabManager.tabs.first!.id

        store.update(surfaceID: surfaceID) { state in
            state.agentState = .launched
        }

        controller.scheduleLaunchedWatchdog(
            surfaceID: surfaceID,
            tabID: tabID,
            timeout: 0.05
        )

        // Advance the state BEFORE the watchdog fires — the handler
        // re-reads the store and should decline the reset.
        store.update(surfaceID: surfaceID) { state in
            state.agentState = .working
            state.agentToolCount = 3
        }

        try await Task.sleep(nanoseconds: 300_000_000)

        let post = store.state(for: surfaceID)
        #expect(post.agentState == .working)
        #expect(post.agentToolCount == 3)
    }

    @Test("cancelLaunchedWatchdog stops the pending reset")
    func cancelLaunchedWatchdogStopsReset() async throws {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let store = AgentStatePerSurfaceStore()
        controller.injectedPerSurfaceStore = store

        let surfaceID = SurfaceID()
        let tabID = controller.tabManager.tabs.first!.id

        store.update(surfaceID: surfaceID) { state in
            state.agentState = .launched
        }

        controller.scheduleLaunchedWatchdog(
            surfaceID: surfaceID,
            tabID: tabID,
            timeout: 0.05
        )
        controller.cancelLaunchedWatchdog(surfaceID: surfaceID)

        try await Task.sleep(nanoseconds: 300_000_000)

        // State remains untouched because the watchdog was cancelled.
        #expect(store.state(for: surfaceID).agentState == .launched)
    }

    @Test("scheduling the watchdog twice replaces the previous work item")
    func schedulingTwiceReplaces() async throws {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let store = AgentStatePerSurfaceStore()
        controller.injectedPerSurfaceStore = store

        let surfaceID = SurfaceID()
        let tabID = controller.tabManager.tabs.first!.id

        store.update(surfaceID: surfaceID) { $0.agentState = .launched }

        // First schedule with a longer timeout — if it fires, we have a
        // leak because the second schedule should cancel it.
        controller.scheduleLaunchedWatchdog(
            surfaceID: surfaceID,
            tabID: tabID,
            timeout: 1.0
        )
        // Second schedule with short timeout.
        controller.scheduleLaunchedWatchdog(
            surfaceID: surfaceID,
            tabID: tabID,
            timeout: 0.20
        )

        // Poll for the second watchdog to fire. Same rationale as
        // `launchedWatchdogResetsStoreOnTimeout`: polling the outcome
        // is the deterministic replacement for a fixed sleep that
        // flakes under parallel main-queue contention.
        let deadline = Date().addingTimeInterval(5.0)
        while store.state(for: surfaceID).agentState != .idle, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(store.state(for: surfaceID) == .idle)
    }
}
