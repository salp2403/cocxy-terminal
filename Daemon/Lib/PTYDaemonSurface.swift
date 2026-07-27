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
    static let maximumRows = 512
    static let maximumColumns = 2_048
    static let maximumCells = 131_072

    let surfaceID: String
    let shellPID: Int32
    let ptyMasterFD: Int32

    let terminal: OpaquePointer
    let pty: OpaquePointer
    let writer: PTYDaemonLineWriter
    let terminalLock = NSLock()
    let ioQueue: DispatchQueue
    var callbackContext: Unmanaged<PTYDaemonSurfaceCallbackContext>?
    var revision: UInt64 = 0

    private let stateLock = NSLock()
    private let cleanupGroup = DispatchGroup()
    private var readSource: DispatchSourceRead?
    private var exitMonitorSource: DispatchSourceTimer?
    private var frameSubscribed = false
    private var closed = false
    private var cleanupSucceeded = true

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
        self.ioQueue = DispatchQueue(
            label: "dev.cocxy.pty-daemon.surface.\(surfaceID)",
            qos: .userInteractive
        )
        cleanupGroup.enter()
    }

    deinit {
        close(emitEvent: false)
    }

    static func create(
        payload: [String: String],
        writer: PTYDaemonLineWriter
    ) throws -> PTYDaemonSurface {
        let dimensions = try validatedDimensions(payload: payload)
        let rows = dimensions.rows
        let columns = dimensions.columns
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
        return surface
    }

    func activate(onClosed: @escaping @Sendable (String) -> Void) {
        startReadSource(onClosed: onClosed)
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
        guard Self.dimensionsAreValid(rows: rows, columns: columns) else { return false }
        return terminalLock.withLock {
            let didResize = cocxycore_terminal_resize(terminal, rows, columns)
            cocxycore_pty_resize(pty, rows, columns)
            return didResize
        }
    }

    static func validatedDimensions(
        payload: [String: String],
        defaultRows: UInt16 = 24,
        defaultColumns: UInt16 = 80
    ) throws -> (rows: UInt16, columns: UInt16) {
        let rows = try payload.uint16("rows", default: defaultRows)
        let columns = try payload.uint16("columns", default: defaultColumns)
        guard dimensionsAreValid(rows: rows, columns: columns) else {
            throw PTYDaemonSurfaceError.invalidPayload(
                "terminal dimensions exceed the daemon safety limit"
            )
        }
        return (rows, columns)
    }

    private static func dimensionsAreValid(rows: UInt16, columns: UInt16) -> Bool {
        rows > 0
            && columns > 0
            && Int(rows) <= maximumRows
            && Int(columns) <= maximumColumns
            && Int(rows) * Int(columns) <= maximumCells
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

    func scroll(by deltaRows: Int) -> Bool {
        guard deltaRows != 0 else { return true }
        return terminalLock.withLock {
            cocxycore_terminal_history_scroll_viewport(
                terminal,
                Int32(max(Int(Int32.min), min(Int(Int32.max), deltaRows)))
            )
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
        // File descriptor numbers are process-local. The daemon can expose
        // the shell PID, but its PTY master descriptor is meaningless and
        // potentially dangerous in the app process.
        PTYDaemonProcessRegistration(shellPID: shellPID, ptyMasterFD: nil)
    }

    @discardableResult
    func close(
        emitEvent: Bool = true,
        waitForCleanup: Bool = true
    ) -> Bool {
        let closeRequest = stateLock.withLock {
            () -> (Bool, DispatchSourceRead?, DispatchSourceTimer?) in
            guard closed == false else { return (false, nil, nil) }
            closed = true
            let read = readSource
            let monitor = exitMonitorSource
            readSource = nil
            exitMonitorSource = nil
            return (true, read, monitor)
        }

        if closeRequest.0 {
            closeRequest.2?.cancel()
            closeRequest.1?.cancel()
        }
        if closeRequest.0, emitEvent {
            writer.write(PTYDaemonEvent(event: .surfaceClosed, surfaceID: surfaceID))
        }
        guard waitForCleanup else { return true }
        guard cleanupGroup.wait(timeout: .now() + 3) == .success else { return false }
        return stateLock.withLock { cleanupSucceeded }
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

    private func startReadSource(onClosed: @escaping @Sendable (String) -> Void) {
        guard ptyMasterFD >= 0 else { return }
        let source = DispatchSource.makeReadSource(
            fileDescriptor: ptyMasterFD,
            queue: ioQueue
        )
        let exitMonitor = DispatchSource.makeTimerSource(queue: ioQueue)
        source.setEventHandler { [weak self] in
            self?.readAvailablePTYBytes()
        }
        source.setCancelHandler { [weak self, terminal, pty, callbackContext, shellPID, surfaceID, cleanupGroup] in
            cocxycore_terminal_detach_pty(terminal)
            let didReap = TerminalProcessBoundary.terminateAndReapPTYChild(shellPID)
            cocxycore_pty_destroy(pty)
            cocxycore_terminal_destroy(terminal)
            callbackContext?.release()
            self?.stateLock.withLock {
                self?.cleanupSucceeded = didReap
            }
            cleanupGroup.leave()
            onClosed(surfaceID)
        }
        exitMonitor.setEventHandler { [weak self] in
            self?.pollChildExit()
        }
        exitMonitor.schedule(deadline: .now() + 0.05, repeating: 0.05)
        stateLock.withLock {
            readSource = source
            exitMonitorSource = exitMonitor
        }
        source.resume()
        exitMonitor.resume()
    }

    private func pollChildExit() {
        guard isClosed() == false else { return }
        var waitResult = cocxycore_pty_wait_result()
        guard cocxycore_pty_wait_check(pty, &waitResult),
              cocxycore_pty_is_alive(pty) == false else { return }

        // A final readable notification is not guaranteed after the child
        // exits. Drain one pending chunk on each timer tick; the first empty
        // read closes the surface without discarding buffered terminal output.
        readAvailablePTYBytes()
    }

    private func readAvailablePTYBytes() {
        guard isClosed() == false else { return }
        var buffer = [UInt8](repeating: 0, count: Self.readBufferSize)
        let bytesRead = cocxycore_pty_read(pty, &buffer, buffer.count)
        guard bytesRead > 0 else {
            if !cocxycore_pty_is_alive(pty) {
                close(waitForCleanup: false)
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

    private func markFrameSubscribed() {
        stateLock.withLock {
            frameSubscribed = true
        }
    }

    private func shouldEmitFrames() -> Bool {
        stateLock.withLock { frameSubscribed }
    }
}
