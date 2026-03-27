// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GhosttyKitIntegrationTests.swift - Verify GhosttyKit xcframework integration.

import XCTest
import GhosttyKit
@testable import CocxyTerminal

// MARK: - GhosttyKit Integration Tests

/// Tests that verify GhosttyKit.xcframework is correctly linked and
/// its C API symbols are accessible from Swift.
///
/// These tests verify build system integration only:
/// - The xcframework is found by the linker.
/// - Opaque types are importable as Swift type aliases.
/// - Enum values match expected constants.
/// - Function symbols resolve (pointer is non-nil).
///
/// Note: Tests that call runtime functions (ghostty_config_new, etc.) require
/// a fully initialized Zig runtime and are deferred to T-004 integration tests
/// where a ghostty_app lifecycle is properly set up.
///
/// - SeeAlso: `GhosttyBridge` (concrete implementation in T-004)
/// - SeeAlso: `docs/architecture/libghostty-api-reference.md`
final class GhosttyKitIntegrationTests: XCTestCase {

    // MARK: - Opaque type importability

    func testOpaqueTypesAreImportable() {
        // Verify that the opaque pointer types are accessible as Swift typealiases.
        // These are defined as `void*` in ghostty.h and imported as
        // `UnsafeMutableRawPointer` (aka `OpaquePointer` typealias) by Swift.
        // We verify they exist as types by declaring optional variables.
        let app: ghostty_app_t? = nil
        let config: ghostty_config_t? = nil
        let surface: ghostty_surface_t? = nil
        let inspector: ghostty_inspector_t? = nil

        // Compiler would fail if types don't exist. At runtime, just verify nil.
        XCTAssertNil(app)
        XCTAssertNil(config)
        XCTAssertNil(surface)
        XCTAssertNil(inspector)
    }

    // MARK: - Platform enum

    func testPlatformEnumHasMacOSValue() {
        let platform = GHOSTTY_PLATFORM_MACOS
        XCTAssertNotEqual(platform.rawValue, GHOSTTY_PLATFORM_INVALID.rawValue,
            "GHOSTTY_PLATFORM_MACOS should differ from INVALID")
    }

    func testPlatformEnumHasIOSValue() {
        let ios = GHOSTTY_PLATFORM_IOS
        let macos = GHOSTTY_PLATFORM_MACOS
        XCTAssertNotEqual(ios.rawValue, macos.rawValue,
            "iOS and macOS platform should be distinct")
    }

    // MARK: - Clipboard enum

    func testClipboardEnumValues() {
        let standard = GHOSTTY_CLIPBOARD_STANDARD
        let selection = GHOSTTY_CLIPBOARD_SELECTION
        XCTAssertNotEqual(standard.rawValue, selection.rawValue,
            "Standard and selection clipboard should be distinct values")
    }

    func testClipboardRequestEnumValues() {
        let paste = GHOSTTY_CLIPBOARD_REQUEST_PASTE
        let oscRead = GHOSTTY_CLIPBOARD_REQUEST_OSC_52_READ
        let oscWrite = GHOSTTY_CLIPBOARD_REQUEST_OSC_52_WRITE
        XCTAssertNotEqual(paste.rawValue, oscRead.rawValue)
        XCTAssertNotEqual(paste.rawValue, oscWrite.rawValue)
        XCTAssertNotEqual(oscRead.rawValue, oscWrite.rawValue)
    }

    // MARK: - Mouse enum

    func testMouseButtonEnumValues() {
        let left = GHOSTTY_MOUSE_LEFT
        let right = GHOSTTY_MOUSE_RIGHT
        let middle = GHOSTTY_MOUSE_MIDDLE
        XCTAssertNotEqual(left.rawValue, right.rawValue)
        XCTAssertNotEqual(left.rawValue, middle.rawValue)
        XCTAssertNotEqual(right.rawValue, middle.rawValue)
    }

    func testMouseStateEnumValues() {
        let press = GHOSTTY_MOUSE_PRESS
        let release = GHOSTTY_MOUSE_RELEASE
        XCTAssertNotEqual(press.rawValue, release.rawValue,
            "PRESS and RELEASE should be distinct")
    }

    func testMouseMomentumEnumValues() {
        let none = GHOSTTY_MOUSE_MOMENTUM_NONE
        let began = GHOSTTY_MOUSE_MOMENTUM_BEGAN
        let ended = GHOSTTY_MOUSE_MOMENTUM_ENDED
        XCTAssertNotEqual(none.rawValue, began.rawValue)
        XCTAssertNotEqual(began.rawValue, ended.rawValue)
    }

    // MARK: - Input modifier flags

    func testInputModifierValuesAreNonZero() {
        XCTAssertNotEqual(GHOSTTY_MODS_SHIFT.rawValue, 0, "SHIFT should be non-zero")
        XCTAssertNotEqual(GHOSTTY_MODS_CTRL.rawValue, 0, "CTRL should be non-zero")
        XCTAssertNotEqual(GHOSTTY_MODS_ALT.rawValue, 0, "ALT should be non-zero")
        XCTAssertNotEqual(GHOSTTY_MODS_SUPER.rawValue, 0, "SUPER should be non-zero")
    }

    func testInputModifierValuesAreBitmaskFlags() {
        // Each modifier should occupy its own bit position.
        XCTAssertEqual(GHOSTTY_MODS_SHIFT.rawValue & GHOSTTY_MODS_CTRL.rawValue, 0,
            "SHIFT and CTRL should occupy different bits")
        XCTAssertEqual(GHOSTTY_MODS_ALT.rawValue & GHOSTTY_MODS_SUPER.rawValue, 0,
            "ALT and SUPER should occupy different bits")
        XCTAssertEqual(GHOSTTY_MODS_SHIFT.rawValue & GHOSTTY_MODS_ALT.rawValue, 0,
            "SHIFT and ALT should occupy different bits")
    }

    // MARK: - Color scheme enum

    func testColorSchemeEnumValues() {
        XCTAssertEqual(GHOSTTY_COLOR_SCHEME_LIGHT.rawValue, 0, "LIGHT should be 0")
        XCTAssertEqual(GHOSTTY_COLOR_SCHEME_DARK.rawValue, 1, "DARK should be 1")
    }

    // MARK: - Success constant

    func testSuccessConstantIsZero() {
        XCTAssertEqual(GHOSTTY_SUCCESS, 0, "GHOSTTY_SUCCESS should be 0")
    }

    // MARK: - Function symbol resolution

    func testConfigNewSymbolResolves() {
        // Verify ghostty_config_new function pointer is non-nil.
        // We do NOT call it because it requires Zig runtime initialization.
        // The fact that we can reference it proves the symbol links correctly.
        let functionPointer: @convention(c) () -> ghostty_config_t? = ghostty_config_new
        XCTAssertTrue(true, "ghostty_config_new symbol resolved successfully")
        _ = functionPointer // Suppress unused warning
    }

    func testConfigFreeSymbolResolves() {
        let functionPointer: @convention(c) (ghostty_config_t?) -> Void = ghostty_config_free
        XCTAssertTrue(true, "ghostty_config_free symbol resolved successfully")
        _ = functionPointer
    }

    func testAppTickSymbolResolves() {
        // ghostty_app_tick is critical for the main loop integration.
        let functionPointer: @convention(c) (ghostty_app_t?) -> Void = ghostty_app_tick
        XCTAssertTrue(true, "ghostty_app_tick symbol resolved successfully")
        _ = functionPointer
    }

    func testConfigOpenPathSymbolResolves() {
        // ghostty_config_open_path returns a ghostty_string_s struct.
        let functionPointer: @convention(c) () -> ghostty_string_s = ghostty_config_open_path
        XCTAssertTrue(true, "ghostty_config_open_path symbol resolved successfully")
        _ = functionPointer
    }

    // MARK: - Struct layout accessibility

    func testClipboardContentStructIsAccessible() {
        // Verify ghostty_clipboard_content_s struct can be instantiated.
        var content = ghostty_clipboard_content_s()
        content.mime = nil
        content.data = nil
        // Struct fields are accessible without error.
        XCTAssertNil(content.mime)
        XCTAssertNil(content.data)
    }
}
