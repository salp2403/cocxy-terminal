// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GhosttyRuntimeConfigBuilder.swift - Builds ghostty_runtime_config_s with C callbacks.

import AppKit
import GhosttyKit

// MARK: - Runtime Config Builder

/// Builds the `ghostty_runtime_config_s` struct required by `ghostty_app_new`.
///
/// This struct contains the C function pointers that libghostty calls back into
/// during the application lifecycle. Each callback is a `@convention(c)` static
/// function that recovers the `GhosttyBridge` instance from the opaque userdata
/// pointer.
///
/// The callbacks follow libghostty's threading contract:
/// - `wakeup_cb`: Called from ANY thread. Must dispatch to main thread.
/// - All other callbacks: Called from the main thread during `ghostty_app_tick`.
///
/// - SeeAlso: `ghostty_runtime_config_s` (C struct)
@MainActor
enum GhosttyRuntimeConfigBuilder {

    /// Builds a complete runtime config with all required callbacks.
    static func build(userdata: UnsafeMutableRawPointer?) -> ghostty_runtime_config_s {
        return ghostty_runtime_config_s(
            userdata: userdata,
            supports_selection_clipboard: true,
            wakeup_cb: Self.wakeupCallback,
            action_cb: Self.actionCallback,
            read_clipboard_cb: Self.readClipboardCallback,
            confirm_read_clipboard_cb: Self.confirmReadClipboardCallback,
            write_clipboard_cb: Self.writeClipboardCallback,
            close_surface_cb: Self.closeSurfaceCallback
        )
    }

    // MARK: - C Callbacks

    /// Called from ANY thread when libghostty has work pending.
    /// Retains the bridge for the async block to prevent use-after-free:
    /// without retain, the bridge can be deallocated between dispatch and
    /// execution (e.g., during Sparkle auto-update shutdown), causing
    /// ghostty_app_tick to access a corrupt os_unfair_lock.
    private static let wakeupCallback: ghostty_runtime_wakeup_cb = { userdata in
        guard let ud = userdata else { return }
        let retained = Unmanaged<GhosttyBridge>.fromOpaque(ud).retain()
        DispatchQueue.main.async {
            let bridge = retained.takeRetainedValue()
            bridge.tick()
        }
    }

    /// Called on the main thread to dispatch actions from libghostty.
    private static let actionCallback: ghostty_runtime_action_cb = { app, target, action in
        guard let app = app else { return false }
        guard let userdata = ghostty_app_userdata(app) else { return false }
        let bridge = Unmanaged<GhosttyBridge>.fromOpaque(userdata).takeUnretainedValue()
        return bridge.handleAction(target: target, action: action)
    }

    /// Called on the main thread when libghostty wants to read the clipboard.
    private static let readClipboardCallback: ghostty_runtime_read_clipboard_cb = {
        userdata, clipboardType, state in
        guard let userdata = userdata else { return false }
        let bridge = Unmanaged<GhosttyBridge>.fromOpaque(userdata).takeUnretainedValue()
        return bridge.handleReadClipboard(
            clipboardType: clipboardType,
            state: state
        )
    }

    /// Called on the main thread to confirm clipboard read (security).
    private static let confirmReadClipboardCallback: ghostty_runtime_confirm_read_clipboard_cb = {
        userdata, content, state, request in
        guard let userdata = userdata else { return }
        let bridge = Unmanaged<GhosttyBridge>.fromOpaque(userdata).takeUnretainedValue()
        bridge.handleConfirmReadClipboard(
            content: content,
            state: state,
            request: request
        )
    }

    /// Called on the main thread when libghostty wants to write to the clipboard.
    private static let writeClipboardCallback: ghostty_runtime_write_clipboard_cb = {
        userdata, clipboardType, content, contentLength, shouldConfirm in
        guard let userdata = userdata else { return }
        let bridge = Unmanaged<GhosttyBridge>.fromOpaque(userdata).takeUnretainedValue()
        bridge.handleWriteClipboard(
            clipboardType: clipboardType,
            content: content,
            contentLength: contentLength,
            shouldConfirm: shouldConfirm
        )
    }

    /// Called on the main thread when a surface requests to close.
    private static let closeSurfaceCallback: ghostty_runtime_close_surface_cb = {
        userdata, processAlive in
        guard let userdata = userdata else { return }
        let bridge = Unmanaged<GhosttyBridge>.fromOpaque(userdata).takeUnretainedValue()
        bridge.handleCloseSurface(processAlive: processAlive)
    }
}
