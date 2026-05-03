// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import AppKit
import Testing
import CocxyCoreKit
@testable import CocxyTerminal

@Suite("CocxyCore Accessibility", .serialized)
@MainActor
struct CocxyCoreAccessibilitySwiftTestingTests {

    @Test("vendored CocxyCore exposes accessibility cells cursor notifications and high contrast")
    func vendoredCocxyCoreExposesAccessibilityAPIs() throws {
        let terminal = try #require(cocxycore_terminal_create(4, 40))
        defer { cocxycore_terminal_destroy(terminal) }

        AccessibilityCallbackCapture.reset()
        cocxycore_terminal_set_a11y_notify_callback(terminal, { kind, _ in
            AccessibilityCallbackCapture.record(kind.rawValue)
        }, nil)

        feed("ab", into: terminal)

        var elements = [cocxycore_a11y_element](
            repeating: cocxycore_a11y_element(),
            count: 4
        )
        let count = cocxycore_terminal_iterate_a11y_elements(terminal, &elements, elements.count, 0, 1)
        #expect(count == 2)
        #expect(elements[0].row == 0)
        #expect(elements[0].column == 0)
        #expect(elements[0].width == 1)
        #expect(String(cString: try #require(elements[0].role_str)) == "text")
        #expect(String(cString: try #require(elements[0].value)) == "a")
        #expect(String(cString: try #require(elements[0].hint)) == "Terminal cell")
        #expect(elements[1].column == 1)
        #expect(String(cString: try #require(elements[1].value)) == "b")

        var cursor = cocxycore_a11y_element()
        #expect(cocxycore_terminal_get_a11y_cursor_element(terminal, &cursor) == true)
        #expect(cursor.row == 0)
        #expect(cursor.column == 2)
        #expect(String(cString: try #require(cursor.role_str)) == "cursor")

        #expect(AccessibilityCallbackCapture.kinds.contains(1))
        #expect(AccessibilityCallbackCapture.kinds.contains(4))

        #expect(cocxycore_terminal_enable_semantic(terminal, 16) == true)
        let cycle = "\u{001B}]133;A\u{0007}\u{001B}]133;B\u{0007}\u{001B}]133;C\u{0007}\u{001B}]133;D;0\u{0007}"
        feed(cycle, into: terminal)
        #expect(AccessibilityCallbackCapture.kinds.contains(2))

        try injectPluginError(into: terminal)
        #expect(AccessibilityCallbackCapture.kinds.contains(3))

        cocxycore_terminal_set_theme(terminal, 120, 120, 120, 112, 112, 112, 255, 255, 255)
        var foreground = cocxycore_rgba()
        cocxycore_terminal_resolve_cell_colors(terminal, 0, 0, &foreground, nil)
        #expect(foreground.r == 120)

        cocxycore_terminal_set_high_contrast_mode(terminal, true)
        #expect(cocxycore_terminal_high_contrast_mode(terminal) == true)
        cocxycore_terminal_resolve_cell_colors(terminal, 0, 0, &foreground, nil)
        #expect(foreground.r == 255)
        #expect(foreground.g == 255)
        #expect(foreground.b == 255)
    }

    @Test("bridge maps accessibility elements and high contrast controls")
    func bridgeMapsAccessibilityElementsAndHighContrastControls() async throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createAccessibilitySurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed("xy", into: state.terminal)

        let elements = try #require(bridge.accessibilityElements(
            for: surfaceID,
            viewportStartRow: 0,
            viewportEndRow: 1
        ))
        #expect(elements.count == 2)
        #expect(elements[0] == TerminalAccessibilityElement(
            row: 0,
            column: 0,
            width: 1,
            height: 1,
            role: "text",
            value: "x",
            hint: "Terminal cell"
        ))
        #expect(elements[1].value == "y")

        let cursor = try #require(bridge.accessibilityCursorElement(for: surfaceID))
        #expect(cursor.role == "cursor")
        #expect(cursor.column == 2)

        bridge.setHighContrastMode(true, for: surfaceID)
        #expect(bridge.highContrastMode(for: surfaceID) == true)
        #expect(bridge.colorDiagnostics(for: surfaceID)?.highContrastEnabled == true)

        AccessibilityBridgeNotificationCapture.reset()
        bridge.setAccessibilityNotificationHandler({ notification in
            AccessibilityBridgeNotificationCapture.record(notification)
        }, for: surfaceID)
        feed("z", into: state.terminal)

        try await waitUntil {
            AccessibilityBridgeNotificationCapture.notifications.contains(.contentChanged)
        }

        #expect(AccessibilityBridgeNotificationCapture.notifications.contains(.contentChanged))
        #expect(AccessibilityBridgeNotificationCapture.notifications.contains(.cursorMoved))
    }
}

private enum AccessibilityCallbackCapture {
    static var kinds: [UInt32] = []

    static func reset() {
        kinds.removeAll()
    }

    static func record(_ kind: UInt32) {
        kinds.append(kind)
    }
}

private enum AccessibilityBridgeNotificationCapture {
    static var notifications: [TerminalAccessibilityNotification] = []

    static func reset() {
        notifications.removeAll()
    }

    static func record(_ notification: TerminalAccessibilityNotification) {
        notifications.append(notification)
    }
}

private func feed(_ text: String, into terminal: OpaquePointer) {
    let bytes = Array(text.utf8)
    cocxycore_terminal_feed(terminal, bytes, bytes.count)
}

@MainActor
private func createAccessibilitySurface(
    using bridge: CocxyCoreBridge
) throws -> (SurfaceID, NSView) {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
    let surfaceID = try bridge.createSurface(
        in: view,
        workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
        command: "/bin/cat"
    )
    return (surfaceID, view)
}

private func injectPluginError(into terminal: OpaquePointer) throws {
    let detail = Array("plugin error".utf8)
    detail.withUnsafeBufferPointer { buffer in
        var event = cocxycore_semantic_event(
            event_type: 6,
            source: 5,
            exit_code: -1,
            row: 0,
            block_id: 0,
            confidence: 1.0,
            timestamp: 0,
            detail_ptr: buffer.baseAddress,
            detail_len: UInt16(detail.count),
            _pad: 0,
            stream_id: 0
        )
        #expect(cocxycore_terminal_inject_semantic_event(terminal, &event) == true)
    }
}
