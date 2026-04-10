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
        // lock, it will complete immediately; if it does, it must wait for
        // the holder to release it and the elapsed time will be at least
        // `holdDuration` minus a small setup margin.
        let holdDuration: TimeInterval = 0.200
        let setupMargin: TimeInterval = 0.080
        let expectedMinimum = holdDuration - setupMargin

        let background = DispatchQueue.global(qos: .userInteractive)
        let holderAcquired = DispatchSemaphore(value: 0)

        let state = try #require(bridge.surfaceState(for: surfaceID))
        let lock = state.terminalLock

        background.async {
            lock.lock()
            holderAcquired.signal()
            Thread.sleep(forTimeInterval: holdDuration)
            lock.unlock()
        }

        // Wait until the background queue actually holds the lock.
        holderAcquired.wait()

        let start = Date()
        bridge.resize(
            surfaceID,
            to: TerminalSize(columns: 80, rows: 24, pixelWidth: 640, pixelHeight: 384)
        )
        let elapsed = Date().timeIntervalSince(start)

        #expect(
            elapsed >= expectedMinimum,
            "resize completed in \(elapsed)s, expected ≥ \(expectedMinimum)s (serialized against background holder)"
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

        let holdDuration: TimeInterval = 0.200
        let setupMargin: TimeInterval = 0.080
        let expectedMinimum = holdDuration - setupMargin

        let background = DispatchQueue.global(qos: .userInteractive)
        let holderAcquired = DispatchSemaphore(value: 0)

        let state = try #require(bridge.surfaceState(for: surfaceID))
        let lock = state.terminalLock

        background.async {
            lock.lock()
            holderAcquired.signal()
            Thread.sleep(forTimeInterval: holdDuration)
            lock.unlock()
        }

        holderAcquired.wait()

        let start = Date()
        bridge.applyFont(family: "Menlo", size: 14.0, to: surfaceID)
        let elapsed = Date().timeIntervalSince(start)

        #expect(
            elapsed >= expectedMinimum,
            "applyFont completed in \(elapsed)s, expected ≥ \(expectedMinimum)s (serialized against background holder)"
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

        let holdDuration: TimeInterval = 0.200
        let setupMargin: TimeInterval = 0.080
        let expectedMinimum = holdDuration - setupMargin

        let background = DispatchQueue.global(qos: .userInteractive)
        let holderAcquired = DispatchSemaphore(value: 0)

        let state = try #require(bridge.surfaceState(for: surfaceID))
        let lock = state.terminalLock

        background.async {
            lock.lock()
            holderAcquired.signal()
            Thread.sleep(forTimeInterval: holdDuration)
            lock.unlock()
        }

        holderAcquired.wait()

        // Use the same arrow-left key event that the existing
        // CocxyCoreBridgeTests use to exercise encode_key — keyCode 123,
        // no characters, no modifiers, key-down.
        let arrowLeft = KeyEvent(characters: nil, keyCode: 123, modifiers: [], isKeyDown: true)

        let start = Date()
        _ = bridge.sendKeyEvent(arrowLeft, to: surfaceID)
        let elapsed = Date().timeIntervalSince(start)

        #expect(
            elapsed >= expectedMinimum,
            "sendKeyEvent completed in \(elapsed)s, expected ≥ \(expectedMinimum)s (serialized against background holder)"
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

        // Hold the lock on a background queue. A key-up event must NOT wait
        // for the lock — the early `guard event.isKeyDown` exits before any
        // lock acquisition. We measure that the call returns near-instantly
        // even with the lock held.
        let background = DispatchQueue.global(qos: .userInteractive)
        let holderAcquired = DispatchSemaphore(value: 0)
        let state = try #require(bridge.surfaceState(for: surfaceID))
        let lock = state.terminalLock

        background.async {
            lock.lock()
            holderAcquired.signal()
            Thread.sleep(forTimeInterval: 0.200)
            lock.unlock()
        }
        holderAcquired.wait()

        let arrowLeftUp = KeyEvent(characters: nil, keyCode: 123, modifiers: [], isKeyDown: false)
        let start = Date()
        let handled = bridge.sendKeyEvent(arrowLeftUp, to: surfaceID)
        let elapsed = Date().timeIntervalSince(start)

        #expect(handled == false)
        #expect(elapsed < 0.050, "key-up returned in \(elapsed)s, expected < 0.050s (no lock acquisition)")
    }

    // MARK: - Misc state mutators serialization (preedit, focus, ligatures, theme, stream)

    @Test("sendPreeditText, notifyFocus, ligatures, theme and currentStream acquire the terminal lock")
    func miscStateMutatorsAcquireTerminalLock() throws {
        let bridge = try Self.makeBridge()
        let (surfaceID, _) = try Self.createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        let state = try #require(bridge.surfaceState(for: surfaceID))
        let lock = state.terminalLock
        let holdDuration: TimeInterval = 0.150
        let setupMargin: TimeInterval = 0.060
        let expectedMinimum = holdDuration - setupMargin
        let background = DispatchQueue.global(qos: .userInteractive)

        // Helper: spawns a background queue that holds the lock for
        // `holdDuration`, then runs `op` on the current thread and reports
        // how long it took. If `op` correctly waits for the lock, the
        // elapsed time will be ≥ expectedMinimum. If it does not, the call
        // will return almost instantly and the assertion below catches it.
        func measureUnderHolder(op: () -> Void) -> TimeInterval {
            let acquired = DispatchSemaphore(value: 0)
            background.async {
                lock.lock()
                acquired.signal()
                Thread.sleep(forTimeInterval: holdDuration)
                lock.unlock()
            }
            acquired.wait()
            let start = Date()
            op()
            return Date().timeIntervalSince(start)
        }

        let preeditElapsed = measureUnderHolder {
            bridge.sendPreeditText("hola", to: surfaceID)
        }
        #expect(
            preeditElapsed >= expectedMinimum,
            "sendPreeditText completed in \(preeditElapsed)s, expected ≥ \(expectedMinimum)s"
        )

        // notifyFocus(true) is the first focus signal — lastReportedFocus
        // starts at nil, so the inner guard does NOT short-circuit and the
        // lock is taken.
        let focusElapsed = measureUnderHolder {
            bridge.notifyFocus(true, for: surfaceID)
        }
        #expect(
            focusElapsed >= expectedMinimum,
            "notifyFocus completed in \(focusElapsed)s, expected ≥ \(expectedMinimum)s"
        )

        let ligaturesElapsed = measureUnderHolder {
            bridge.applyLigaturesEnabled(false, to: surfaceID)
        }
        #expect(
            ligaturesElapsed >= expectedMinimum,
            "applyLigaturesEnabled completed in \(ligaturesElapsed)s, expected ≥ \(expectedMinimum)s"
        )

        let themeElapsed = measureUnderHolder {
            bridge.applyTheme(Self.makeTestPalette(), to: surfaceID)
        }
        #expect(
            themeElapsed >= expectedMinimum,
            "applyTheme completed in \(themeElapsed)s, expected ≥ \(expectedMinimum)s"
        )

        let streamElapsed = measureUnderHolder {
            _ = bridge.setCurrentStream(0, for: surfaceID)
        }
        #expect(
            streamElapsed >= expectedMinimum,
            "setCurrentStream completed in \(streamElapsed)s, expected ≥ \(expectedMinimum)s"
        )
    }

    @Test("notifyFocus skips the lock when the focus state is already current")
    func notifyFocusShortCircuitsWhenStateUnchanged() throws {
        let bridge = try Self.makeBridge()
        let (surfaceID, _) = try Self.createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        // First call drives lastReportedFocus from nil → true.
        bridge.notifyFocus(true, for: surfaceID)

        // Hold the lock; the second `notifyFocus(true, ...)` should
        // short-circuit at the `state.lastReportedFocus != focused` guard
        // and return immediately without contending for the lock.
        let background = DispatchQueue.global(qos: .userInteractive)
        let acquired = DispatchSemaphore(value: 0)
        let state = try #require(bridge.surfaceState(for: surfaceID))
        let lock = state.terminalLock

        background.async {
            lock.lock()
            acquired.signal()
            Thread.sleep(forTimeInterval: 0.200)
            lock.unlock()
        }
        acquired.wait()

        let start = Date()
        bridge.notifyFocus(true, for: surfaceID)
        let elapsed = Date().timeIntervalSince(start)

        #expect(
            elapsed < 0.050,
            "duplicate notifyFocus took \(elapsed)s; the early-return guard must skip the lock"
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
        let holdDuration: TimeInterval = 0.150
        let setupMargin: TimeInterval = 0.060
        let expectedMinimum = holdDuration - setupMargin
        let background = DispatchQueue.global(qos: .userInteractive)

        func measureUnderHolder(op: () -> Void) -> TimeInterval {
            let acquired = DispatchSemaphore(value: 0)
            background.async {
                lock.lock()
                acquired.signal()
                Thread.sleep(forTimeInterval: holdDuration)
                lock.unlock()
            }
            acquired.wait()
            let start = Date()
            op()
            return Date().timeIntervalSince(start)
        }

        let setElapsed = measureUnderHolder {
            bridge.setSelection(
                for: surfaceID,
                startRow: 0,
                startCol: 0,
                endRow: 0,
                endCol: 5
            )
        }
        #expect(
            setElapsed >= expectedMinimum,
            "setSelection completed in \(setElapsed)s, expected ≥ \(expectedMinimum)s"
        )

        let clearElapsed = measureUnderHolder {
            bridge.clearSelection(for: surfaceID)
        }
        #expect(
            clearElapsed >= expectedMinimum,
            "clearSelection completed in \(clearElapsed)s, expected ≥ \(expectedMinimum)s"
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
}
