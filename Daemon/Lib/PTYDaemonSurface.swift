// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonSurface.swift - CocxyCore-backed terminal surface for cocxyd.

import CocxyCoreKit
import CocxyShared
#if canImport(Darwin)
import Darwin
#endif
import Foundation

/// One CocxyCore-backed terminal surface owned by the daemon.
///
/// Encapsulates the terminal state machine, the PTY child shell, and the
/// JSONL event stream that ships output, OSC notifications, frames, and
/// close events back to the app. The implementation is split across
/// extension files for readability:
///
/// - `PTYDaemonSurface+Spawn.swift` — `spawnPTY` and env scoping helpers.
/// - `PTYDaemonSurface+Frame.swift` — `makeFrame` and grid-cell packing.
/// - `PTYDaemonSurface+Search.swift` — literal and regex scrollback search.
/// - `PTYDaemonSurface+Keys.swift` — special-key and codepoint encoding.
/// - `PTYDaemonSurface+Callbacks.swift` — title/CWD/bell OSC bridging.
final class PTYDaemonSurface: @unchecked Sendable {
    static let spawnEnvironmentLock = NSLock()
    static let readBufferSize = 16 * 1024
    static let responseBufferSize = 4 * 1024

    let surfaceID: String
    let shellPID: Int32
    let ptyMasterFD: Int32

    let terminal: OpaquePointer
    let pty: OpaquePointer
    let writer: PTYDaemonLineWriter
    let terminalLock = NSLock()
    var callbackContext: Unmanaged<PTYDaemonSurfaceCallbackContext>?
    var revision: UInt64 = 0

    private let stateLock = NSLock()
    private var readSource: DispatchSourceRead?
    private var frameSubscribed = false
    private var closed = false

    private init(
        surfaceID: String,
        terminal: OpaquePointer,
        pty: OpaquePointer,
        writer: PTYDaemonLineWriter
    ) {
        self.surfaceID = surfaceID
        self.terminal = terminal
        self.pty = pty
        self.writer = writer
        self.shellPID = cocxycore_pty_child_pid(pty)
        self.ptyMasterFD = cocxycore_pty_master_fd(pty)
    }

    deinit {
        close(emitEvent: false)
    }

    static func create(
        payload: [String: String],
        writer: PTYDaemonLineWriter
    ) throws -> PTYDaemonSurface {
        let rows = payload.uint16("rows") ?? 24
        let columns = payload.uint16("columns") ?? 80
        let shell = payload.nonEmpty("command")
            ?? ProcessInfo.processInfo.environment["SHELL"]
            ?? "/bin/zsh"
        let workingDirectory = payload.nonEmpty("workingDirectory")
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workingDirectory, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw PTYDaemonSurfaceError.invalidPayload("surface_create requires an existing workingDirectory")
        }

        guard let terminal = cocxycore_terminal_create(rows, columns) else {
            throw PTYDaemonSurfaceError.creationFailed("terminal allocation failed")
        }

        guard let pty = spawnPTY(rows: rows, columns: columns, shell: shell, workingDirectory: workingDirectory) else {
            cocxycore_terminal_destroy(terminal)
            throw PTYDaemonSurfaceError.creationFailed("PTY spawn failed")
        }

        guard cocxycore_terminal_attach_pty(terminal, pty) else {
            cocxycore_pty_destroy(pty)
            cocxycore_terminal_destroy(terminal)
            throw PTYDaemonSurfaceError.creationFailed("PTY attach failed")
        }

        _ = cocxycore_terminal_enable_scrollback(terminal, 10_000)
        _ = cocxycore_terminal_enable_process_tracking(terminal, cocxycore_pty_child_pid(pty), 256)

        let surface = PTYDaemonSurface(
            surfaceID: UUID().uuidString,
            terminal: terminal,
            pty: pty,
            writer: writer
        )
        surface.registerCallbacks()
        surface.startReadSource()
        return surface
    }

    func attach() -> Bool {
        !isClosed()
    }

    func write(bytes: Data) -> Bool {
        guard bytes.isEmpty == false else { return true }
        return terminalLock.withLock {
            bytes.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return false
                }
                return cocxycore_terminal_write_attached_pty(
                    terminal,
                    baseAddress,
                    bytes.count
                ) > 0
            }
        }
    }

    func resize(rows: UInt16, columns: UInt16) -> Bool {
        terminalLock.withLock {
            let didResize = cocxycore_terminal_resize(terminal, rows, columns)
            cocxycore_pty_resize(pty, rows, columns)
            return didResize
        }
    }

    func subscribeFrame() -> PTYDaemonSurfaceFrame? {
        markFrameSubscribed()
        return makeFrame()
    }

    func signal(_ value: Int32) {
        cocxycore_pty_send_signal(pty, value)
    }

    func handleKey(payload: [String: String]) -> Bool {
        guard payload.bool("isKeyDown") ?? true else { return true }

        if let characters = payload.nonEmpty("characters"),
           payload.uint("modifiers").map({ $0 & 8 == 0 }) ?? true {
            return write(bytes: Data(characters.utf8))
        }

        let keyCode = payload.uint16("keyCode") ?? 0
        guard let key = Self.specialKey(forMacKeyCode: keyCode) else {
            if let codepoint = payload.uint32("unshiftedCodepoint"), codepoint > 0 {
                return writeEncodedCharacter(codepoint, modifiers: payload.uint("modifiers") ?? 0)
            }
            return false
        }
        return writeEncodedKey(key, modifiers: payload.uint("modifiers") ?? 0)
    }

    func setPreedit(_ text: String) {
        terminalLock.withLock {
            if text.isEmpty {
                cocxycore_terminal_preedit_clear(terminal)
            } else {
                let row = cocxycore_terminal_cursor_row(terminal)
                let column = cocxycore_terminal_cursor_col(terminal)
                let bytes = Array(text.utf8)
                cocxycore_terminal_preedit_set(
                    terminal,
                    row,
                    column,
                    bytes,
                    bytes.count,
                    UInt16(bytes.count)
                )
            }
        }
    }

    func notifyFocus(_ focused: Bool) {
        terminalLock.withLock {
            cocxycore_terminal_notify_focus(terminal, focused)
        }
    }

    func scroll(to lineNumber: Int) -> Bool {
        terminalLock.withLock {
            let maxVisible = cocxycore_terminal_history_max_visible_start(terminal)
            let clamped = UInt32(max(0, min(lineNumber, Int(maxVisible))))
            return cocxycore_terminal_history_set_visible_start(terminal, clamped)
        }
    }

    func search(query: String, caseSensitive: Bool, useRegex: Bool, maxResults: Int) -> [PTYDaemonSearchResult] {
        guard query.isEmpty == false else { return [] }
        return terminalLock.withLock {
            if useRegex, let regexResults = regexSearch(query: query, caseSensitive: caseSensitive, maxResults: maxResults) {
                return regexResults
            }
            return literalSearch(query: query, caseSensitive: caseSensitive, maxResults: maxResults)
        }
    }

    func processRegistration() -> PTYDaemonProcessRegistration {
        PTYDaemonProcessRegistration(shellPID: shellPID, ptyMasterFD: ptyMasterFD)
    }

    func close(emitEvent: Bool = true) {
        guard markClosedIfNeeded() else { return }
        readSource?.cancel()
        readSource = nil
        if emitEvent {
            writer.write(PTYDaemonEvent(event: .surfaceClosed, surfaceID: surfaceID))
        }
    }

    /// Forwards an OSC notification to the JSONL event stream. Called from
    /// the CocxyCore callbacks installed by `registerCallbacks()`.
    func emitOSC(_ osc: PTYDaemonOSCNotification) {
        writer.write(
            PTYDaemonEvent(
                event: .surfaceOSC,
                surfaceID: surfaceID,
                osc: osc
            )
        )
    }

    private func startReadSource() {
        guard ptyMasterFD >= 0 else { return }
        let source = DispatchSource.makeReadSource(
            fileDescriptor: ptyMasterFD,
            queue: DispatchQueue.global(qos: .userInteractive)
        )
        source.setEventHandler { [weak self] in
            self?.readAvailablePTYBytes()
        }
        source.setCancelHandler { [terminal, pty, callbackContext] in
            cocxycore_terminal_detach_pty(terminal)
            cocxycore_pty_destroy(pty)
            cocxycore_terminal_destroy(terminal)
            callbackContext?.release()
        }
        readSource = source
        source.resume()
    }

    private func readAvailablePTYBytes() {
        guard isClosed() == false else { return }
        var buffer = [UInt8](repeating: 0, count: Self.readBufferSize)
        let bytesRead = cocxycore_pty_read(pty, &buffer, buffer.count)
        guard bytesRead > 0 else {
            if !cocxycore_pty_is_alive(pty) {
                close()
            }
            return
        }

        let frame: PTYDaemonSurfaceFrame? = terminalLock.withLock {
            cocxycore_terminal_feed(terminal, buffer, bytesRead)
            drainTerminalResponses()
            cocxycore_terminal_poll_processes(terminal)
            return shouldEmitFrames() ? makeFrameLocked() : nil
        }

        writer.write(
            PTYDaemonEvent(
                event: .surfaceOutput,
                surfaceID: surfaceID,
                bytesBase64: Data(buffer.prefix(bytesRead)).base64EncodedString()
            )
        )
        if let frame {
            writer.write(PTYDaemonEvent(event: .surfaceFrame, surfaceID: surfaceID, frame: frame))
        }
    }

    private func drainTerminalResponses() {
        var responseBuffer = [UInt8](repeating: 0, count: Self.responseBufferSize)
        while cocxycore_terminal_has_response(terminal) {
            let count = cocxycore_terminal_read_response(terminal, &responseBuffer, responseBuffer.count)
            guard count > 0 else { break }
            _ = responseBuffer.withUnsafeBufferPointer { pointer in
                cocxycore_terminal_write_attached_pty(terminal, pointer.baseAddress, count)
            }
        }
    }

    private func isClosed() -> Bool {
        stateLock.withLock { closed }
    }

    private func markClosedIfNeeded() -> Bool {
        stateLock.withLock {
            guard closed == false else { return false }
            closed = true
            return true
        }
    }

    private func markFrameSubscribed() {
        stateLock.withLock {
            frameSubscribed = true
        }
    }

    private func shouldEmitFrames() -> Bool {
        stateLock.withLock { frameSubscribed }
    }
}
