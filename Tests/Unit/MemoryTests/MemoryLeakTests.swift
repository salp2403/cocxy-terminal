// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MemoryLeakTests.swift - Memory lifecycle tests for all major components.
//
// Verifies create-use-destroy cycles using weak references.
// Pattern: create object -> use it -> set strong ref to nil -> assert weak ref is nil.
//
// NOTE: GhosttyBridge tests are structural (compile-only) because the bridge
// requires a real libghostty native library (GhosttyKit.xcframework) which is
// not available in the test host process. The lifecycle pattern is tested for
// all other components that do not require the native library.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Memory Leak Tests

final class MemoryLeakTests: XCTestCase {

    // MARK: - Test 1: TabManager Lifecycle

    /// Creates a TabManager, adds 10 tabs, removes all removable tabs, sets to nil.
    /// Verifies the weak reference becomes nil (no retain cycle).
    @MainActor
    func test_tabManager_lifecycle_doesNotLeak() {
        var tabManager: TabManager? = TabManager()
        weak let weakRef = tabManager

        // Use the object: add 10 tabs.
        for _ in 0..<10 {
            tabManager?.addTab()
        }
        XCTAssertEqual(tabManager?.tabs.count, 11) // 1 initial + 10 added.

        // Remove all but the last (invariant: cannot close last tab).
        let tabIDs = tabManager?.tabs.map(\.id) ?? []
        for id in tabIDs.dropLast() {
            tabManager?.removeTab(id: id)
        }
        XCTAssertEqual(tabManager?.tabs.count, 1)

        // Deallocate.
        tabManager = nil

        XCTAssertNil(weakRef, "TabManager was not deallocated: retain cycle suspected.")
    }

    // MARK: - Test 2: SplitManager Lifecycle

    /// Creates a SplitManager, performs 4 splits, closes all splits, sets to nil.
    @MainActor
    func test_splitManager_lifecycle_doesNotLeak() {
        var splitManager: SplitManager? = SplitManager()
        weak let weakRef = splitManager

        // Use the object: 4 splits.
        for direction in [SplitDirection.horizontal, .vertical, .horizontal, .vertical] {
            splitManager?.splitFocused(direction: direction)
        }
        XCTAssertGreaterThan(splitManager?.rootNode.leafCount ?? 0, 1)

        // Close all splits back to 1.
        while (splitManager?.rootNode.leafCount ?? 1) > 1 {
            splitManager?.closeFocused()
        }
        XCTAssertEqual(splitManager?.rootNode.leafCount, 1)

        // Deallocate.
        splitManager = nil

        XCTAssertNil(weakRef, "SplitManager was not deallocated: retain cycle suspected.")
    }

    // MARK: - Test 3: TabSplitCoordinator Lifecycle

    /// Creates a coordinator with 5 tabs, removes all SplitManagers, sets to nil.
    @MainActor
    func test_tabSplitCoordinator_lifecycle_doesNotLeak() {
        var coordinator: TabSplitCoordinator? = TabSplitCoordinator()
        weak let weakRef = coordinator

        // Create 5 SplitManagers via the coordinator.
        let tabIDs = (0..<5).map { _ in TabID() }
        for tabID in tabIDs {
            _ = coordinator?.splitManager(for: tabID)
        }
        XCTAssertEqual(coordinator?.count, 5)

        // Remove all SplitManagers.
        for tabID in tabIDs {
            coordinator?.removeSplitManager(for: tabID)
        }
        XCTAssertEqual(coordinator?.count, 0)

        // Deallocate.
        coordinator = nil

        XCTAssertNil(weakRef, "TabSplitCoordinator was not deallocated: retain cycle suspected.")
    }

    // MARK: - Test 4: TabSplitCoordinator SplitManager Cleanup

    /// Verifies that removing a SplitManager from the coordinator actually
    /// releases the SplitManager (no extra strong references held).
    @MainActor
    func test_tabSplitCoordinator_removedSplitManager_isReleased() {
        let coordinator = TabSplitCoordinator()
        let tabID = TabID()

        var splitManager: SplitManager? = coordinator.splitManager(for: tabID)
        weak let weakSplitRef = splitManager

        // Perform some operations.
        splitManager?.splitFocused(direction: .horizontal)

        // Release our local reference and remove from coordinator.
        splitManager = nil
        coordinator.removeSplitManager(for: tabID)

        XCTAssertNil(weakSplitRef,
            "SplitManager was not released after removal from TabSplitCoordinator.")
    }

    // MARK: - Test 5: NotificationManager Lifecycle

    /// Creates a NotificationManagerImpl, adds attention items, marks all read, sets to nil.
    @MainActor
    func test_notificationManager_lifecycle_doesNotLeak() {
        let mockEmitter = MemoryTestMockEmitter()
        var manager: NotificationManagerImpl? = NotificationManagerImpl(
            config: CocxyConfig.defaults,
            systemEmitter: mockEmitter,
            coalescenceWindow: 0.0,
            rateLimitPerTab: 0.0
        )
        weak let weakRef = manager

        // Use the object: send 5 notifications for different tabs.
        for _ in 0..<5 {
            let tabID = TabID()
            let notification = CocxyNotification(
                type: .agentNeedsAttention,
                tabId: tabID,
                title: "Test",
                body: "Body"
            )
            manager?.notify(notification)
        }
        XCTAssertGreaterThan(manager?.attentionQueue.count ?? 0, 0)

        // Mark all as read.
        manager?.markAllAsRead()
        XCTAssertEqual(manager?.unreadCount, 0)

        // Deallocate.
        manager = nil

        XCTAssertNil(weakRef, "NotificationManagerImpl was not deallocated: retain cycle suspected.")
    }

    // MARK: - Test 6: AgentDetectionEngine Lifecycle

    /// Creates an AgentDetectionEngineImpl, processes data, resets, sets to nil.
    @MainActor
    func test_agentDetectionEngine_lifecycle_doesNotLeak() {
        var engine: AgentDetectionEngineImpl? = AgentDetectionEngineImpl(
            compiledConfigs: [],
            debounceInterval: 0.0
        )
        weak let weakRef = engine

        // Use the object: inject signals and reset.
        engine?.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .osc(code: 133)
        ))
        engine?.reset()
        XCTAssertEqual(engine?.currentState, .idle)

        // Deallocate.
        engine = nil

        XCTAssertNil(weakRef, "AgentDetectionEngineImpl was not deallocated: retain cycle suspected.")
    }

    // MARK: - Test 7: AgentDetectionEngine Combine Subscription Cleanup

    /// Verifies that subscriptions to stateChanged do not create retain cycles.
    @MainActor
    func test_agentDetectionEngine_combineSubscription_doesNotLeak() {
        var engine: AgentDetectionEngineImpl? = AgentDetectionEngineImpl(
            compiledConfigs: [],
            debounceInterval: 0.0
        )
        weak let weakRef = engine

        var cancellables = Set<AnyCancellable>()
        var receivedTransitions = 0

        // Subscribe without capturing engine strongly.
        engine?.stateChanged
            .sink { _ in
                receivedTransitions += 1
            }
            .store(in: &cancellables)

        // Trigger a transition.
        engine?.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .osc(code: 133)
        ))

        // Cancel all subscriptions before dealloc.
        cancellables.removeAll()

        // Deallocate.
        engine = nil

        XCTAssertNil(weakRef, "AgentDetectionEngineImpl leaked after subscription cancellation.")
    }

    // MARK: - Test 8: ConfigWatcher Lifecycle

    /// Creates a ConfigWatcher, starts it, stops it, sets to nil.
    func test_configWatcher_lifecycle_doesNotLeak() {
        let fileProvider = InMemoryConfigFileProvider(
            content: ConfigService.generateDefaultToml()
        )
        let configService = ConfigService(fileProvider: fileProvider)
        var watcher: ConfigWatcher? = ConfigWatcher(
            configService: configService,
            fileProvider: fileProvider
        )
        weak let weakRef = watcher

        // Use the object.
        watcher?.startWatching()
        XCTAssertEqual(watcher?.isWatching, true)

        watcher?.scheduleReload()

        watcher?.stopWatching()
        XCTAssertEqual(watcher?.isWatching, false)

        // Deallocate.
        watcher = nil

        XCTAssertNil(weakRef, "ConfigWatcher was not deallocated: retain cycle suspected.")
    }

    // MARK: - Test 9: ConfigWatcher Debounce WorkItem Does Not Retain Self

    /// Verifies that a pending debounce work item does not prevent deallocation.
    /// scheduleReload creates a DispatchWorkItem with [weak self], so even if
    /// the work item is still scheduled, the watcher should deallocate.
    func test_configWatcher_pendingDebounceWorkItem_doesNotPreventDealloc() {
        let fileProvider = InMemoryConfigFileProvider(
            content: ConfigService.generateDefaultToml()
        )
        let configService = ConfigService(fileProvider: fileProvider)
        var watcher: ConfigWatcher? = ConfigWatcher(
            configService: configService,
            fileProvider: fileProvider
        )
        watcher?.debounceInterval = 60.0 // Long interval -- work item stays pending.
        weak let weakRef = watcher

        // Schedule a reload (creates a pending DispatchWorkItem).
        watcher?.scheduleReload()

        // Deallocate without calling stopWatching (simulates abrupt teardown).
        watcher = nil

        // The work item captures [weak self], so the watcher should be released.
        XCTAssertNil(weakRef,
            "ConfigWatcher leaked: pending debounce work item holds strong reference to self.")
    }

    // MARK: - Test 10: TimingHeuristicsDetector Lifecycle

    /// Creates a TimingHeuristicsDetector, starts timers, stops, sets to nil.
    func test_timingHeuristicsDetector_lifecycle_doesNotLeak() {
        var detector: TimingHeuristicsDetector? = TimingHeuristicsDetector(
            defaultIdleTimeout: 60.0,
            sustainedOutputThreshold: 2.0
        )
        weak let weakRef = detector

        // Simulate timer activity: put the detector in a state where timers would fire.
        detector?.notifyStateChanged(to: .working)
        _ = detector?.processBytes(Data("output".utf8))

        // Explicitly stop to cancel timers.
        detector?.stop()

        // Deallocate.
        detector = nil

        XCTAssertNil(weakRef, "TimingHeuristicsDetector was not deallocated: retain cycle suspected.")
    }

    // MARK: - Test 11: TimingHeuristicsDetector Dealloc Without Stop Does Not Crash

    /// Verifies that deallocating without calling stop() does not crash.
    /// deinit calls cancelIdleTimer() which must be safe even if a timer is active.
    func test_timingHeuristicsDetector_dealloc_withoutStop_doesNotCrash() {
        var detector: TimingHeuristicsDetector? = TimingHeuristicsDetector(
            defaultIdleTimeout: 60.0,
            sustainedOutputThreshold: 2.0
        )
        weak let weakRef = detector

        // Put in working state so a timer is scheduled.
        detector?.notifyStateChanged(to: .working)
        _ = detector?.processBytes(Data("output".utf8))

        // Deallocate WITHOUT calling stop() -- relies on deinit to clean up.
        detector = nil

        // Brief wait to allow async queue to process.
        let expectation = expectation(description: "deinit completes cleanly")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertNil(weakRef,
            "TimingHeuristicsDetector was not deallocated via deinit path.")
    }

    // MARK: - Test 12: TimingHeuristicsDetector onSignalEmitted Weak Self in Engine

    /// Verifies that deallocating the engine releases it even though it holds
    /// the timing detector's onSignalEmitted callback.
    /// The engine uses [weak self] in the callback -- this test confirms that pattern.
    @MainActor
    func test_timingHeuristicsDetector_onSignalEmitted_weakSelfPattern() {
        var engine: AgentDetectionEngineImpl? = AgentDetectionEngineImpl(
            compiledConfigs: [],
            debounceInterval: 0.0
        )
        weak let weakEngine = engine

        // Engine internally sets onSignalEmitted on the timing detector with [weak self].
        // Trigger activity to ensure the callback is wired up.
        engine?.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .osc(code: 133)
        ))

        engine = nil

        XCTAssertNil(weakEngine,
            "AgentDetectionEngineImpl leaked: onSignalEmitted callback holds strong reference.")
    }

    // MARK: - Test 13: SessionManager Lifecycle

    /// Creates a SessionManagerImpl, saves a session, loads it, stops auto-save, sets to nil.
    func test_sessionManager_lifecycle_doesNotLeak() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-memleak-test-\(UUID().uuidString)")

        var manager: SessionManagerImpl? = SessionManagerImpl(sessionsDirectory: tempDir)
        weak let weakRef = manager

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Use the object: save and load.
        let session = Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: []
        )
        try? manager?.saveSession(session, named: nil)
        _ = try? manager?.loadLastSession()

        // Start and stop auto-save.
        manager?.startAutoSave(intervalSeconds: 60.0) { session }
        manager?.stopAutoSave()

        // Deallocate.
        manager = nil

        XCTAssertNil(weakRef, "SessionManagerImpl was not deallocated: retain cycle suspected.")
    }

    // MARK: - Test 14: SessionManager Auto-Save Timer Does Not Retain Self

    /// Verifies that deallocating SessionManagerImpl without stopAutoSave does not leak.
    /// The DispatchSourceTimer uses [weak self] in its event handler.
    func test_sessionManager_autoSaveTimer_doesNotRetainSelf() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-memleak-test-\(UUID().uuidString)")

        var manager: SessionManagerImpl? = SessionManagerImpl(sessionsDirectory: tempDir)
        weak let weakRef = manager

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let session = Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: []
        )

        // Start auto-save with a long interval (timer stays alive).
        manager?.startAutoSave(intervalSeconds: 60.0) { session }

        // Deallocate WITHOUT calling stopAutoSave.
        manager = nil

        // Wait briefly for async queue settling.
        let expectation = expectation(description: "async settling")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertNil(weakRef,
            "SessionManagerImpl leaked: DispatchSourceTimer event handler holds strong reference.")
    }

    // MARK: - Test 15: QuickTerminalController Lifecycle

    /// Creates a QuickTerminalController, sets up, calls tearDown, sets to nil.
    @MainActor
    func test_quickTerminalController_lifecycle_doesNotLeak() {
        var controller: QuickTerminalController? = QuickTerminalController()
        weak let weakRef = controller

        // Use without a bridge (bridge is weak and optional).
        controller?.setup(bridge: nil, config: CocxyConfig.defaults)
        XCTAssertFalse(controller?.isPanelNil ?? true)

        // tearDown releases monitors and panel.
        controller?.tearDown()
        XCTAssertTrue(controller?.isPanelNil ?? false)

        // Deallocate.
        controller = nil

        XCTAssertNil(weakRef, "QuickTerminalController was not deallocated: retain cycle suspected.")
    }

    // MARK: - Test 16: QuickTerminalController TearDown Is Idempotent

    /// Verifies that registerHotkey + tearDown leaves no active monitors.
    /// After tearDown, calling tearDown again must not crash (idempotent).
    @MainActor
    func test_quickTerminalController_tearDown_isIdempotent() {
        let controller = QuickTerminalController()
        controller.setup(bridge: nil, config: CocxyConfig.defaults)
        controller.registerHotkey()

        // First tearDown -- removes monitors.
        controller.tearDown()
        XCTAssertTrue(controller.isPanelNil)

        // Second tearDown -- must not crash (idempotent).
        controller.tearDown()
        XCTAssertTrue(controller.isPanelNil)
    }

    // MARK: - Test 17: SocketServer Lifecycle

    /// Creates a SocketServerImpl, starts it, stops it, sets to nil.
    @MainActor
    func test_socketServer_lifecycle_doesNotLeak() {
        let tempSocketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-test-\(UUID().uuidString).sock")
            .path

        let mockHandler = MemoryTestMockSocketHandler()
        var server: SocketServerImpl? = SocketServerImpl(
            socketPath: tempSocketPath,
            commandHandler: mockHandler
        )
        weak let weakRef = server

        defer {
            try? FileManager.default.removeItem(atPath: tempSocketPath)
        }

        // Start and stop the server.
        try? server?.start()
        XCTAssertTrue(server?.isRunning ?? false)

        server?.stop()
        XCTAssertFalse(server?.isRunning ?? true)

        // Deallocate.
        server = nil

        XCTAssertNil(weakRef, "SocketServerImpl was not deallocated: retain cycle suspected.")
    }

    // MARK: - Test 18: SocketServer File Descriptor Closed on Stop

    /// Verifies that stopping the server removes the socket file.
    /// If the socket file persists, it represents a resource leak.
    @MainActor
    func test_socketServer_stop_removesSocketFile() {
        let tempSocketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-test-\(UUID().uuidString).sock")
            .path

        let mockHandler = MemoryTestMockSocketHandler()
        let server = SocketServerImpl(
            socketPath: tempSocketPath,
            commandHandler: mockHandler
        )

        defer {
            try? FileManager.default.removeItem(atPath: tempSocketPath)
        }

        try? server.start()
        XCTAssertTrue(server.isRunning)

        server.stop()

        // After stop, socket file should be removed.
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tempSocketPath),
            "Socket file was not removed after stop(): potential resource leak."
        )
    }

    // MARK: - Test 19: Combine Publisher Chain Released on Cancellation

    /// Creates a Combine pipeline subscribing to NotificationManagerImpl publishers.
    /// Cancelling the subscription should release all retained objects.
    @MainActor
    func test_combine_publisherChain_releasedOnCancellation() {
        let mockEmitter = MemoryTestMockEmitter()
        var manager: NotificationManagerImpl? = NotificationManagerImpl(
            config: CocxyConfig.defaults,
            systemEmitter: mockEmitter,
            coalescenceWindow: 0.0,
            rateLimitPerTab: 0.0
        )
        weak let weakRef = manager

        var cancellables = Set<AnyCancellable>()

        // Build a Combine chain.
        manager?.unreadCountPublisher
            .filter { $0 > 0 }
            .map { "Unread: \($0)" }
            .sink { _ in }
            .store(in: &cancellables)

        manager?.notificationsPublisher
            .sink { _ in }
            .store(in: &cancellables)

        // Cancel all subscriptions.
        cancellables.removeAll()

        // Deallocate manager.
        manager = nil

        XCTAssertNil(weakRef, "NotificationManagerImpl leaked after Combine subscription cancellation.")
    }

    // MARK: - Test 20: AppearanceObserver stopObserving Releases Provider Reference

    /// Verifies that stopObserving() properly notifies the provider to stop.
    /// This prevents dangling notification observers in the provider.
    @MainActor
    func test_appearanceObserver_stopObserving_callsProviderStopObserving() {
        let mockProvider = MemoryTestMockAppearanceProvider(isDarkMode: false)
        let observer = AppearanceObserver(appearanceProvider: mockProvider)

        let emptyThemeProvider = MemoryTestEmptyThemeProvider()
        let themeEngine = ThemeEngineImpl(themeFileProvider: emptyThemeProvider)

        observer.startObserving(
            themeEngine: themeEngine,
            darkTheme: "dark",
            lightTheme: "light",
            autoSwitchEnabled: true
        )
        XCTAssertTrue(observer.isObserving)

        observer.stopObserving()

        XCTAssertFalse(observer.isObserving)
        XCTAssertTrue(mockProvider.didCallStopObserving,
            "AppearanceObserver.stopObserving did not call provider.stopObserving().")
    }

    // MARK: - Test 21: AgentDetectionEngine processTerminalOutput Weak Self

    /// Verifies that the DispatchQueue.main.async in processTerminalOutput
    /// uses [weak self] and does not prevent deallocation.
    @MainActor
    func test_agentDetectionEngine_processTerminalOutput_weakSelf_doesNotLeak() {
        var engine: AgentDetectionEngineImpl? = AgentDetectionEngineImpl(
            compiledConfigs: [],
            debounceInterval: 0.0
        )
        weak let weakRef = engine

        // Enqueue async work by injecting a batch signal.
        engine?.injectSignalBatch([
            DetectionSignal(
                event: .agentDetected(name: "claude"),
                confidence: 0.9,
                source: .pattern(name: "launch-claude")
            )
        ])

        // Deallocate while async work may still be pending.
        engine = nil

        // Wait for main queue to drain.
        let expectation = expectation(description: "main queue drain")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertNil(weakRef,
            "AgentDetectionEngineImpl leaked: processTerminalOutput closure holds strong reference.")
    }
}

// MARK: - Test Support: Mock System Notification Emitter

@MainActor
private final class MemoryTestMockEmitter: SystemNotificationEmitting {
    var emittedCount: Int = 0

    func emit(_ notification: CocxyNotification) {
        emittedCount += 1
    }
}

// MARK: - Test Support: Mock Socket Command Handler

private final class MemoryTestMockSocketHandler: SocketCommandHandling, @unchecked Sendable {
    func handleCommand(_ request: SocketRequest) -> SocketResponse {
        return SocketResponse.ok(id: request.id)
    }
}

// MARK: - Test Support: Mock Appearance Provider

private final class MemoryTestMockAppearanceProvider: AppearanceProviding {
    var isDarkMode: Bool
    var didCallStopObserving: Bool = false
    private var registeredCallback: (@Sendable (Bool) -> Void)?

    init(isDarkMode: Bool) {
        self.isDarkMode = isDarkMode
    }

    func observeAppearanceChanges(_ callback: @escaping @Sendable (Bool) -> Void) {
        registeredCallback = callback
    }

    func stopObserving() {
        didCallStopObserving = true
        registeredCallback = nil
    }
}

// MARK: - Test Support: Empty Theme File Provider

private final class MemoryTestEmptyThemeProvider: ThemeFileProviding {
    func listCustomThemeFiles() -> [(name: String, content: String)] {
        return []
    }
}
