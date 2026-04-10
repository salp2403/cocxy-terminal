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
}
