// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonSurface+Callbacks.swift - CocxyCore callback registration for OSC events.

import CocxyCoreKit
import CocxyShared
import Foundation

extension PTYDaemonSurface {
    /// Registers CocxyCore callbacks that forward terminal and root-process
    /// events to the daemon's JSONL `surface_osc` stream.
    func registerCallbacks() {
        let context = PTYDaemonSurfaceCallbackContext(surface: self)
        let unmanaged = Unmanaged.passRetained(context)
        callbackContext = unmanaged
        let opaque = unmanaged.toOpaque()

        cocxycore_terminal_set_title_callback(terminal, { title, length, context in
            guard let title, let context else { return }
            let box = Unmanaged<PTYDaemonSurfaceCallbackContext>
                .fromOpaque(context)
                .takeUnretainedValue()
            let text = String(
                bytes: UnsafeBufferPointer(start: title, count: length),
                encoding: .utf8
            ) ?? ""
            box.surface?.emitOSC(.init(kind: .titleChange, text: text))
        }, opaque)

        cocxycore_terminal_set_cwd_callback(terminal, { cwd, length, context in
            guard let cwd, let context else { return }
            let box = Unmanaged<PTYDaemonSurfaceCallbackContext>
                .fromOpaque(context)
                .takeUnretainedValue()
            let text = String(
                bytes: UnsafeBufferPointer(start: cwd, count: length),
                encoding: .utf8
            ) ?? ""
            box.surface?.emitOSC(.init(kind: .currentDirectory, text: text, url: text))
        }, opaque)

        cocxycore_terminal_set_bell_callback(terminal, { context in
            guard let context else { return }
            let box = Unmanaged<PTYDaemonSurfaceCallbackContext>
                .fromOpaque(context)
                .takeUnretainedValue()
            box.surface?.emitOSC(.init(kind: .notification, title: "Bell", body: "Terminal bell"))
        }, opaque)

        cocxycore_terminal_set_process_callback(terminal, { event, context in
            guard let event, let context else { return }
            let box = Unmanaged<PTYDaemonSurfaceCallbackContext>
                .fromOpaque(context)
                .takeUnretainedValue()
            guard let surface = box.surface,
                  event.pointee.event_type == 1,
                  event.pointee.pid == surface.shellPID else {
                return
            }
            surface.emitProcessExitIfNeeded(
                exitCode: event.pointee.exit_code >= 0 ? Int(event.pointee.exit_code) : nil
            )
        }, opaque)
    }
}

/// Box passed to CocxyCore as the opaque `void*` context for each callback.
/// Holds a weak reference to the surface so callbacks become no-ops once the
/// surface is torn down by `close()`.
final class PTYDaemonSurfaceCallbackContext {
    weak var surface: PTYDaemonSurface?

    init(surface: PTYDaemonSurface) {
        self.surface = surface
    }
}
