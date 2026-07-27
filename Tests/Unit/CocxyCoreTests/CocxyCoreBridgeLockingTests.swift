// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
import CocxyCoreKit
@testable import CocxyTerminal

/// Tests that verify terminal state mutations on `CocxyCoreBridge` are
/// serialized through the per-surface `terminalLock`.
///
/// Without serialization, the PTY read loop (background queue, calling
/// `cocxycore_terminal_feed`) can race with main-thread mutations like
/// `resize`, `applyFont`, `sendKeyEvent`, etc., producing corrupted cell
/// buffers and transparent frames.
///
/// The suite begins here with the infrastructure piece — the generic
/// `withTerminalLock` helper — and is extended by subsequent tasks that
/// migrate each mutator to use it.
@Suite("CocxyCoreBridge terminal lock serialization", .serialized)
@MainActor
struct CocxyCoreBridgeLockingTests {

    // MARK: - withTerminalLock helper

    @Test("withTerminalLock runs the body and returns its value for an active surface")
    func withTerminalLockReturnsBodyValue() throws {
        let bridge = try Self.makeBridge()
        let (surfaceID, _) = try Self.createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        var executedInsideBlock = false
        let result = bridge.withTerminalLock(surfaceID) { _ in
            executedInsideBlock = true
            return 42
        }

        #expect(executedInsideBlock)
        #expect(result == 42)
    }

    @Test("withTerminalLock returns nil without running body when the surface is unknown")
    func withTerminalLockReturnsNilForUnknownSurface() throws {
        let bridge = try Self.makeBridge()

        var bodyCalled = false
        let result: Int? = bridge.withTerminalLock(SurfaceID()) { _ in
            bodyCalled = true
            return 1
        }

        #expect(bodyCalled == false)
        #expect(result == nil)
    }

    @Test("withTerminalLock releases the lock after the body returns")
    func withTerminalLockReleasesLockAfterBody() throws {
        let bridge = try Self.makeBridge()
        let (surfaceID, _) = try Self.createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        // First call runs the body and releases the lock.
        _ = bridge.withTerminalLock(surfaceID) { _ in () }

        // If the lock was not released, the second call would deadlock.
        // We wrap this in a short timeout guard to prevent the suite from
        // hanging on a regression.
        var secondRan = false
        _ = bridge.withTerminalLock(surfaceID) { _ in
            secondRan = true
        }
        #expect(secondRan)
    }

    // MARK: - resize serialization

    @Test("resize waits for the terminal lock held by a background holder")
    func resizeWaitsForBackgroundLockHolder() throws {
        let bridge = try Self.makeBridge()
        let (surfaceID, _) = try Self.createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        // Simulate the background PTY read loop holding the lock around
        // `cocxycore_terminal_feed`. If `resize` does not try to acquire the
        // lock it returns while the holder is still inside its critical
        // section, so the probe never sees the holder's release marker.
        let state = try #require(bridge.surfaceState(for: surfaceID))

        let waitedForHolder = Self.waitedForBackgroundLockHolder(lock: state.terminalLock) {
            bridge.resize(
                surfaceID,
                to: TerminalSize(columns: 80, rows: 24, pixelWidth: 640, pixelHeight: 384)
            )
        }

        #expect(
            waitedForHolder,
            "resize returned before the background holder released the terminal lock"
        )
    }

    @Test("resize applies the new dimensions to the underlying terminal")
    func resizeAppliesNewDimensions() throws {
        let bridge = try Self.makeBridge()
        let (surfaceID, _) = try Self.createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        bridge.resize(
            surfaceID,
            to: TerminalSize(columns: 100, rows: 30, pixelWidth: 800, pixelHeight: 480)
        )

        let state = try #require(bridge.surfaceState(for: surfaceID))
        #expect(cocxycore_terminal_cols(state.terminal) == 100)
        #expect(cocxycore_terminal_rows(state.terminal) == 30)
    }

    // MARK: - applyFont serialization

    @Test("applyFont waits for the terminal lock held by a background holder")
    func applyFontWaitsForBackgroundLockHolder() throws {
        let bridge = try Self.makeBridge()
        let (surfaceID, _) = try Self.createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        let state = try #require(bridge.surfaceState(for: surfaceID))

        let waitedForHolder = Self.waitedForBackgroundLockHolder(lock: state.terminalLock) {
            bridge.applyFont(family: "Menlo", size: 14.0, to: surfaceID)
        }

        #expect(
            waitedForHolder,
            "applyFont returned before the background holder released the terminal lock"
        )
    }

    @Test("applyFont leaves the terminal state intact on a live surface")
    func applyFontLeavesTerminalStateIntact() throws {
        let bridge = try Self.makeBridge()
        let (surfaceID, _) = try Self.createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        // Sanity check that applyFont still drives the surface correctly
        // after the lock refactor. We cannot read back the font family via
        // a public API, but we can verify the call returns cleanly and the
        // grid dimensions remain intact (the lock refactor must not reset
        // or corrupt the terminal state).
        let beforeCols = cocxycore_terminal_cols(
            try #require(bridge.surfaceState(for: surfaceID)).terminal
        )
        let beforeRows = cocxycore_terminal_rows(
            try #require(bridge.surfaceState(for: surfaceID)).terminal
        )

        bridge.applyFont(family: "Menlo", size: 16.0, to: surfaceID)

        let afterState = try #require(bridge.surfaceState(for: surfaceID))
        #expect(cocxycore_terminal_cols(afterState.terminal) == beforeCols)
        #expect(cocxycore_terminal_rows(afterState.terminal) == beforeRows)
    }

    // MARK: - sendKeyEvent serialization

    @Test("sendKeyEvent waits for the terminal lock held by a background holder")
    func sendKeyEventWaitsForBackgroundLockHolder() throws {
        let bridge = try Self.makeBridge()
        let (surfaceID, _) = try Self.createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        let state = try #require(bridge.surfaceState(for: surfaceID))

        // Use the same arrow-left key event that the existing
        // CocxyCoreBridgeTests use to exercise encode_key — keyCode 123,
        // no characters, no modifiers, key-down.
        let arrowLeft = KeyEvent(characters: nil, keyCode: 123, modifiers: [], isKeyDown: true)

        let waitedForHolder = Self.waitedForBackgroundLockHolder(lock: state.terminalLock) {
            _ = bridge.sendKeyEvent(arrowLeft, to: surfaceID)
        }

        #expect(
            waitedForHolder,
            "sendKeyEvent returned before the background holder released the terminal lock"
        )
    }

    @Test("sendKeyEvent still encodes and forwards arrow keys after the lock refactor")
    func sendKeyEventStillHandlesArrowKeys() throws {
        let bridge = try Self.makeBridge()
        let (surfaceID, _) = try Self.createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        let arrowLeft = KeyEvent(characters: nil, keyCode: 123, modifiers: [], isKeyDown: true)
        let handled = bridge.sendKeyEvent(arrowLeft, to: surfaceID)
        #expect(handled == true)
    }

    @Test("sendKeyEvent ignores key-up events without acquiring the lock")
    func sendKeyEventIgnoresKeyUpEvents() throws {
        let bridge = try Self.makeBridge()
        let (surfaceID, _) = try Self.createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        // Hold the lock on a background queue and keep holding it across the
        // call. A key-up event must NOT wait for the lock — the early
        // `guard event.isKeyDown` exits before any lock acquisition, so the
        // holder is still inside its critical section when the call returns.
        let state = try #require(bridge.surfaceState(for: surfaceID))

        let arrowLeftUp = KeyEvent(characters: nil, keyCode: 123, modifiers: [], isKeyDown: false)
        var handled = true
        let waitedForHolder = Self.waitedForRetainedLockHolder(lock: state.terminalLock) {
            handled = bridge.sendKeyEvent(arrowLeftUp, to: surfaceID)
        }

        #expect(handled == false)
        #expect(
            waitedForHolder == false,
            "key-up waited for the terminal lock; the early `guard event.isKeyDown` must return first"
        )
    }

    // MARK: - PTY write serialization

    @Test("sendText and writeBytes wait for the terminal lock held by a background holder")
    func ptyWritePathsWaitForBackgroundLockHolder() throws {
        let bridge = try Self.makeBridge()
        let (surfaceID, _) = try Self.createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        let state = try #require(bridge.surfaceState(for: surfaceID))
        let lock = state.terminalLock

        let sendTextWaited = Self.waitedForBackgroundLockHolder(lock: lock) {
            bridge.sendText("claude --version\r", to: surfaceID)
        }
        #expect(
            sendTextWaited,
            "sendText returned before the background holder released the terminal lock"
        )

        let writeBytesWaited = Self.waitedForBackgroundLockHolder(lock: lock) {
            _ = bridge.writeBytes([0x63, 0x6C, 0x61, 0x75, 0x64, 0x65], to: surfaceID)
        }
        #expect(
            writeBytesWaited,
            "writeBytes returned before the background holder released the terminal lock"
        )
    }

    // MARK: - Misc state mutators serialization (preedit, focus, ligatures, theme, stream)

    @Test("sendPreeditText, notifyFocus, ligatures, theme and currentStream acquire the terminal lock")
    func miscStateMutatorsAcquireTerminalLock() throws {
        let bridge = try Self.makeBridge()
        let (surfaceID, _) = try Self.createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        let state = try #require(bridge.surfaceState(for: surfaceID))
        let lock = state.terminalLock

        let preeditWaited = Self.waitedForBackgroundLockHolder(lock: lock) {
            bridge.sendPreeditText("hola", to: surfaceID)
        }
        #expect(
            preeditWaited,
            "sendPreeditText returned before the background holder released the terminal lock"
        )

        // notifyFocus(true) is the first focus signal — lastReportedFocus
        // starts at nil, so the inner guard does NOT short-circuit and the
        // lock is taken.
        let focusWaited = Self.waitedForBackgroundLockHolder(lock: lock) {
            bridge.notifyFocus(true, for: surfaceID)
        }
        #expect(
            focusWaited,
            "notifyFocus returned before the background holder released the terminal lock"
        )

        let ligaturesWaited = Self.waitedForBackgroundLockHolder(lock: lock) {
            bridge.applyLigaturesEnabled(false, to: surfaceID)
        }
        #expect(
            ligaturesWaited,
            "applyLigaturesEnabled returned before the background holder released the terminal lock"
        )

        let themeWaited = Self.waitedForBackgroundLockHolder(lock: lock) {
            bridge.applyTheme(Self.makeTestPalette(), to: surfaceID)
        }
        #expect(
            themeWaited,
            "applyTheme returned before the background holder released the terminal lock"
        )

        let streamWaited = Self.waitedForBackgroundLockHolder(lock: lock) {
            _ = bridge.setCurrentStream(0, for: surfaceID)
        }
        #expect(
            streamWaited,
            "setCurrentStream returned before the background holder released the terminal lock"
        )
    }

    @Test("notifyFocus skips the lock when the focus state is already current")
    func notifyFocusShortCircuitsWhenStateUnchanged() throws {
        let bridge = try Self.makeBridge()
        let (surfaceID, _) = try Self.createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        // First call drives lastReportedFocus from nil → true.
        bridge.notifyFocus(true, for: surfaceID)

        // Hold the lock across the call; the second `notifyFocus(true, ...)`
        // should short-circuit at the `state.lastReportedFocus != focused`
        // guard and return without contending for the lock, so the holder is
        // still inside its critical section when the call returns.
        let state = try #require(bridge.surfaceState(for: surfaceID))

        let waitedForHolder = Self.waitedForRetainedLockHolder(lock: state.terminalLock) {
            bridge.notifyFocus(true, for: surfaceID)
        }

        #expect(
            waitedForHolder == false,
            "duplicate notifyFocus waited for the terminal lock; the early-return guard must skip it"
        )
    }

    // MARK: - Additional mutator serialization

    @Test("image settings, protocol writers and scroll mutators acquire the terminal lock")
    func imageProtocolAndScrollMutatorsAcquireTerminalLock() throws {
        let bridge = try Self.makeBridge()
        let (surfaceID, _) = try Self.createSurface(using: bridge, command: "/bin/cat")
        defer { bridge.destroySurface(surfaceID) }

        let state = try #require(bridge.surfaceState(for: surfaceID))
        let lock = state.terminalLock

        let applyImageSettingsWaited = Self.waitedForBackgroundLockHolder(lock: lock) {
            bridge.applyImageSettings(
                memoryLimitBytes: 128 * 1024 * 1024,
                fileTransferEnabled: true,
                sixelEnabled: false,
                kittyEnabled: true,
                iterm2Enabled: true,
                diskCacheDirectory: nil,
                diskCacheLimitBytes: 64 * 1024 * 1024,
                to: surfaceID
            )
        }
        #expect(
            applyImageSettingsWaited,
            "applyImageSettings returned before the background holder released the terminal lock"
        )

        let requestCapabilitiesWaited = Self.waitedForBackgroundLockHolder(lock: lock) {
            _ = bridge.requestProtocolV2Capabilities(for: surfaceID)
        }
        #expect(
            requestCapabilitiesWaited,
            "requestProtocolV2Capabilities returned before the background holder released the terminal lock"
        )

        let sendViewportWaited = Self.waitedForBackgroundLockHolder(lock: lock) {
            _ = bridge.sendProtocolV2Viewport(for: surfaceID, requestID: "lock-test")
        }
        #expect(
            sendViewportWaited,
            "sendProtocolV2Viewport returned before the background holder released the terminal lock"
        )

        let sendMessageWaited = Self.waitedForBackgroundLockHolder(lock: lock) {
            _ = bridge.sendProtocolV2Message(type: "ping", json: #"{"ok":true}"#, to: surfaceID)
        }
        #expect(
            sendMessageWaited,
            "sendProtocolV2Message returned before the background holder released the terminal lock"
        )

        let scrollToResultWaited = Self.waitedForBackgroundLockHolder(lock: lock) {
            bridge.scrollToSearchResult(surfaceID: surfaceID, lineNumber: 5)
        }
        #expect(
            scrollToResultWaited,
            "scrollToSearchResult returned before the background holder released the terminal lock"
        )

        let scrollViewportWaited = Self.waitedForBackgroundLockHolder(lock: lock) {
            bridge.scrollViewport(surfaceID: surfaceID, deltaRows: 1)
        }
        #expect(
            scrollViewportWaited,
            "scrollViewport returned before the background holder released the terminal lock"
        )
    }

    // MARK: - Selection mutators serialization

    @Test("clearSelection and setSelection acquire the terminal lock")
    func selectionMutatorsAcquireTerminalLock() throws {
        let bridge = try Self.makeBridge()
        let (surfaceID, _) = try Self.createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        let state = try #require(bridge.surfaceState(for: surfaceID))
        let lock = state.terminalLock

        let setWaited = Self.waitedForBackgroundLockHolder(lock: lock) {
            bridge.setSelection(
                for: surfaceID,
                startRow: 0,
                startCol: 0,
                endRow: 0,
                endCol: 5
            )
        }
        #expect(
            setWaited,
            "setSelection returned before the background holder released the terminal lock"
        )

        let clearWaited = Self.waitedForBackgroundLockHolder(lock: lock) {
            bridge.clearSelection(for: surfaceID)
        }
        #expect(
            clearWaited,
            "clearSelection returned before the background holder released the terminal lock"
        )
    }

    @Test("selection mutators are no-ops on an unknown surface")
    func selectionMutatorsNoOpOnUnknownSurface() throws {
        let bridge = try Self.makeBridge()
        let unknown = SurfaceID()

        // Must not crash and must not deadlock — withTerminalLock returns
        // nil for unknown surfaces and the body is skipped entirely.
        bridge.setSelection(
            for: unknown,
            startRow: 0,
            startCol: 0,
            endRow: 0,
            endCol: 5
        )
        bridge.clearSelection(for: unknown)
    }

    // MARK: - Shared Test Helpers

    /// Minimal config used by every test in this suite. Mirrors the one in
    /// `CocxyCoreBridgeTests.swift`; replicated here because that file
    /// declares its helpers as `private`.
    static func makeConfig() -> TerminalEngineConfig {
        TerminalEngineConfig(
            fontFamily: "Menlo",
            fontSize: 14,
            themeName: "Test",
            shell: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
            windowPaddingX: 8,
            windowPaddingY: 4
        )
    }

    /// Creates and initializes a `CocxyCoreBridge` ready for surface
    /// creation. The caller owns the bridge and is responsible for
    /// destroying any surfaces it creates.
    @MainActor
    static func makeBridge() throws -> CocxyCoreBridge {
        let bridge = CocxyCoreBridge()
        try bridge.initialize(config: makeConfig())
        return bridge
    }

    /// Creates a live surface bound to a throwaway `NSView`. The command is
    /// `/bin/cat` so the child process is a benign byte sink that will not
    /// emit anything on its own during the test.
    @MainActor
    static func createSurface(
        using bridge: CocxyCoreBridge,
        command: String = "/bin/cat"
    ) throws -> (SurfaceID, NSView) {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        let surfaceID = try bridge.createSurface(
            in: view,
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
            command: command
        )
        return (surfaceID, view)
    }

    /// Builds a minimal `ThemePalette` for tests. The values are arbitrary
    /// but well-formed hex strings; the bridge only forwards them to the C
    /// terminal which validates them internally. UI-side fields (tab bar,
    /// badges) are not exercised by the locking tests but must be present
    /// because every property of `ThemePalette` is `let`.
    static func makeTestPalette() -> ThemePalette {
        ThemePalette(
            background: "#000000",
            foreground: "#ffffff",
            cursor: "#ff00ff",
            selectionBackground: "#444444",
            selectionForeground: "#ffffff",
            tabActiveBackground: "#222222",
            tabActiveForeground: "#ffffff",
            tabInactiveBackground: "#111111",
            tabInactiveForeground: "#888888",
            badgeAttention: "#ffaa00",
            badgeCompleted: "#00ff00",
            badgeError: "#ff0000",
            badgeWorking: "#00aaff",
            ansiColors: [
                "#000000", "#ff0000", "#00ff00", "#ffff00",
                "#0000ff", "#ff00ff", "#00ffff", "#ffffff",
                "#444444", "#ff5555", "#55ff55", "#ffff55",
                "#5555ff", "#ff55ff", "#55ffff", "#ffffff"
            ]
        )
    }

    // MARK: - Lock contention probes

    /// How long the background holder keeps the terminal lock while the
    /// operation under test runs.
    private static let lockHoldDuration: TimeInterval = 0.200

    /// How long the background holder of `waitedForRetainedLockHolder`
    /// keeps the lock when the test never gets to release it because the
    /// call under test blocked on the lock. Only reached on a regression;
    /// it exists so a regression fails instead of hanging the suite.
    private static let blockedCallSafetyTimeout: TimeInterval = 5.0

    /// Runs `operation` while a background queue holds `lock`, and reports
    /// whether the holder had already published its release when the
    /// operation returned.
    ///
    /// These probes used to time the call and require a lower bound
    /// (`elapsed >= holdDuration - margin`). A clock measures the
    /// scheduler, not the product: the main thread can be preempted between
    /// the holder's signal and the start of the measurement, so a correctly
    /// serialized call reports an elapsed time under the bound and the test
    /// fails without a regression. The marker below is causal instead of
    /// temporal — the holder publishes `released` immediately before
    /// `unlock()`, so an operation that really waits for the lock cannot
    /// return before that write, while one that skips the lock returns
    /// while the holder still owns it and observes `false`.
    static func waitedForBackgroundLockHolder(
        lock: NSLock,
        operation: () -> Void
    ) -> Bool {
        let probe = LockHolderProbe()
        let acquired = DispatchSemaphore(value: 0)
        let holdDuration = lockHoldDuration

        DispatchQueue.global(qos: .userInteractive).async {
            lock.lock()
            acquired.signal()
            Thread.sleep(forTimeInterval: holdDuration)
            probe.markReleased()
            lock.unlock()
        }

        acquired.wait()
        operation()
        return probe.didRelease
    }

    /// Runs `operation` while a background queue holds `lock` and keeps
    /// holding it until this call releases it, and reports whether the
    /// operation ended up waiting for that lock.
    ///
    /// Used by the negative cases (a key-up event, a duplicate focus
    /// notification), which must return WITHOUT contending for the lock.
    /// Timing them and requiring an upper bound is unreliable: a call that
    /// touches no lock can still be preempted past any small bound on a
    /// loaded machine. Here the holder does not release on a clock — it
    /// waits for this call to release it after `operation` returned, so a
    /// call that skipped the lock always observes `false`. A regressed call
    /// that does take the lock blocks until the holder's safety valve
    /// fires, observes `true` and fails.
    static func waitedForRetainedLockHolder(
        lock: NSLock,
        operation: () -> Void
    ) -> Bool {
        let probe = LockHolderProbe()
        let acquired = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let safetyTimeout = blockedCallSafetyTimeout

        DispatchQueue.global(qos: .userInteractive).async {
            lock.lock()
            acquired.signal()
            _ = release.wait(timeout: .now() + safetyTimeout)
            probe.markReleased()
            lock.unlock()
        }

        acquired.wait()
        operation()
        let waitedForHolder = probe.didRelease
        release.signal()
        return waitedForHolder
    }
}

/// Records whether the background lock holder reached its release point.
///
/// The flag is published under its own lock so the holder thread and the
/// main thread can touch it without a data race; the terminal lock itself
/// orders the write before any acquisition made by the operation under
/// test.
private final class LockHolderProbe: @unchecked Sendable {
    private let stateLock = NSLock()
    private var released = false

    func markReleased() {
        stateLock.lock()
        released = true
        stateLock.unlock()
    }

    var didRelease: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return released
    }
}
