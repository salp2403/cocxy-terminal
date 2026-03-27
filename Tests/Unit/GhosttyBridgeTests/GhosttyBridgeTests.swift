// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GhosttyBridgeTests.swift - Tests for GhosttyBridge lifecycle and protocol conformance.

import XCTest
import GhosttyKit
@testable import CocxyTerminal

// MARK: - GhosttyBridge Protocol Conformance Tests

/// Tests that GhosttyBridge correctly conforms to the TerminalEngine protocol.
///
/// These tests verify the structural contract without requiring a full ghostty
/// runtime. Tests that require the Zig runtime (e.g., actual surface creation)
/// are in the integration test suite.
@MainActor
final class GhosttyBridgeConformanceTests: XCTestCase {

    func testGhosttyBridgeConformsToTerminalEngine() {
        // This is a compile-time check: if GhosttyBridge does not conform
        // to TerminalEngine, this line will not compile.
        let bridge: any TerminalEngine = GhosttyBridge()
        XCTAssertNotNil(bridge, "GhosttyBridge must conform to TerminalEngine")
    }

    func testGhosttyBridgeIsReferenceType() {
        // TerminalEngine requires AnyObject, so GhosttyBridge must be a class.
        let bridge = GhosttyBridge()
        let bridge2 = bridge
        XCTAssertTrue(bridge === bridge2, "GhosttyBridge must be a reference type (class)")
    }
}

// MARK: - GhosttyBridge State Tests

/// Tests for the internal state management of GhosttyBridge.
@MainActor
final class GhosttyBridgeStateTests: XCTestCase {

    func testBridgeStartsUninitialized() {
        let bridge = GhosttyBridge()
        XCTAssertFalse(
            bridge.isInitialized,
            "Bridge must start in uninitialized state"
        )
    }

    func testBridgeHasNoSurfacesInitially() {
        let bridge = GhosttyBridge()
        XCTAssertEqual(
            bridge.activeSurfaceCount,
            0,
            "Bridge must have zero surfaces before any are created"
        )
    }

    func testDestroySurfaceWithInvalidIdDoesNotCrash() {
        let bridge = GhosttyBridge()
        let fakeSurfaceID = SurfaceID()
        // This must not crash -- destroying a non-existent surface is a no-op.
        bridge.destroySurface(fakeSurfaceID)
    }

    func testTickBeforeInitializeDoesNotCrash() {
        let bridge = GhosttyBridge()
        // tick() before initialize() must be a safe no-op.
        bridge.tick()
    }
}

// MARK: - GhosttyBridge Surface Registry Tests

/// Tests for the SurfaceID to ghostty_surface_t mapping.
@MainActor
final class GhosttyBridgeSurfaceRegistryTests: XCTestCase {

    func testRegisterAndLookupSurface() {
        let registry = SurfaceRegistry()
        let surfaceID = SurfaceID()
        // Use a fake non-nil pointer to simulate a ghostty_surface_t.
        let fakePointer: ghostty_surface_t = UnsafeMutableRawPointer(bitPattern: 0x1234)!

        registry.register(surfaceID: surfaceID, ghosttySurface: fakePointer)
        let retrieved = registry.lookup(surfaceID)

        XCTAssertEqual(
            retrieved,
            fakePointer,
            "Registered surface must be retrievable by its SurfaceID"
        )
    }

    func testLookupNonExistentSurfaceReturnsNil() {
        let registry = SurfaceRegistry()
        let result = registry.lookup(SurfaceID())
        XCTAssertNil(result, "Looking up an unregistered SurfaceID must return nil")
    }

    func testUnregisterSurface() {
        let registry = SurfaceRegistry()
        let surfaceID = SurfaceID()
        let fakePointer: ghostty_surface_t = UnsafeMutableRawPointer(bitPattern: 0x5678)!

        registry.register(surfaceID: surfaceID, ghosttySurface: fakePointer)
        registry.unregister(surfaceID)
        let result = registry.lookup(surfaceID)

        XCTAssertNil(result, "Unregistered surface must no longer be retrievable")
    }

    func testRegistryCountReflectsActiveSurfaces() {
        let registry = SurfaceRegistry()
        XCTAssertEqual(registry.count, 0)

        let id1 = SurfaceID()
        let id2 = SurfaceID()
        let ptr1: ghostty_surface_t = UnsafeMutableRawPointer(bitPattern: 0x1111)!
        let ptr2: ghostty_surface_t = UnsafeMutableRawPointer(bitPattern: 0x2222)!

        registry.register(surfaceID: id1, ghosttySurface: ptr1)
        XCTAssertEqual(registry.count, 1)

        registry.register(surfaceID: id2, ghosttySurface: ptr2)
        XCTAssertEqual(registry.count, 2)

        registry.unregister(id1)
        XCTAssertEqual(registry.count, 1)

        registry.unregister(id2)
        XCTAssertEqual(registry.count, 0)
    }
}

// MARK: - GhosttyBridge Callback Context Tests

/// Tests for the C callback context (Unmanaged pointer round-trip).
@MainActor
final class GhosttyBridgeCallbackContextTests: XCTestCase {

    func testOpaquePointerRoundTripPreservesIdentity() {
        let bridge = GhosttyBridge()

        // Simulate what we do in the runtime config: pass self as opaque pointer.
        let opaquePtr = Unmanaged.passUnretained(bridge).toOpaque()

        // Simulate what the C callback does: recover the Swift object.
        let recovered = Unmanaged<GhosttyBridge>.fromOpaque(opaquePtr).takeUnretainedValue()

        XCTAssertTrue(
            bridge === recovered,
            "Opaque pointer round-trip must preserve object identity"
        )
    }
}

// MARK: - Runtime Config Builder Tests

/// Tests for the ghostty_runtime_config_s builder.
@MainActor
final class RuntimeConfigBuilderTests: XCTestCase {

    func testRuntimeConfigHasAllRequiredCallbacks() {
        // We need to verify the runtime config struct has non-nil function pointers.
        // Since the callbacks are static C functions, we build a config and verify.
        let config = GhosttyRuntimeConfigBuilder.build(userdata: nil)

        // wakeup_cb must be set (libghostty requires it to know when to tick).
        XCTAssertTrue(
            config.wakeup_cb != nil,
            "wakeup_cb must be set"
        )

        // action_cb must be set (libghostty dispatches actions through it).
        XCTAssertTrue(
            config.action_cb != nil,
            "action_cb must be set"
        )

        // Clipboard callbacks must be set.
        XCTAssertTrue(
            config.read_clipboard_cb != nil,
            "read_clipboard_cb must be set"
        )
        XCTAssertTrue(
            config.write_clipboard_cb != nil,
            "write_clipboard_cb must be set"
        )
        XCTAssertTrue(
            config.confirm_read_clipboard_cb != nil,
            "confirm_read_clipboard_cb must be set"
        )

        // close_surface_cb must be set.
        XCTAssertTrue(
            config.close_surface_cb != nil,
            "close_surface_cb must be set"
        )
    }

    func testRuntimeConfigStoresUserdata() {
        let testValue = UnsafeMutableRawPointer(bitPattern: 0xDEAD)
        let config = GhosttyRuntimeConfigBuilder.build(userdata: testValue)
        XCTAssertEqual(
            config.userdata,
            testValue,
            "userdata must be stored in the runtime config"
        )
    }

    func testRuntimeConfigSupportsSelectionClipboard() {
        let config = GhosttyRuntimeConfigBuilder.build(userdata: nil)
        XCTAssertTrue(
            config.supports_selection_clipboard,
            "macOS supports selection clipboard"
        )
    }
}
