// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonSurface.swift - CocxyCore-backed terminal surface for cocxyd.

import CocxyCoreKit
import CocxyShared
#if canImport(Darwin)
import Darwin
#endif
import Foundation

final class PTYDaemonSurface: @unchecked Sendable {
    private static let spawnEnvironmentLock = NSLock()
    private static let readBufferSize = 16 * 1024
    private static let responseBufferSize = 4 * 1024

    let surfaceID: String
    let shellPID: Int32
    let ptyMasterFD: Int32

    private let terminal: OpaquePointer
    private let pty: OpaquePointer
    private let writer: PTYDaemonLineWriter
    private let terminalLock = NSLock()
    private let stateLock = NSLock()
    private var readSource: DispatchSourceRead?
    private var callbackContext: Unmanaged<PTYDaemonSurfaceCallbackContext>?
    private var revision: UInt64 = 0
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

    private static func spawnPTY(
        rows: UInt16,
        columns: UInt16,
        shell: String,
        workingDirectory: String
    ) -> OpaquePointer? {
        spawnEnvironmentLock.lock()
        defer { spawnEnvironmentLock.unlock() }

        let previousCwd = FileManager.default.currentDirectoryPath
        let previousTERM = getenvString("TERM")
        let previousCOLORTERM = getenvString("COLORTERM")
        let previousTermProgram = getenvString("TERM_PROGRAM")
        let previousCLICOLOR = getenvString("CLICOLOR")

        _ = FileManager.default.changeCurrentDirectoryPath(workingDirectory)
        setenv("TERM", "xterm-256color", 1)
        setenv("COLORTERM", "truecolor", 1)
        setenv("TERM_PROGRAM", "CocxyTerminal", 1)
        setenv("CLICOLOR", "1", 1)

        defer {
            restoreEnv("TERM", previousTERM)
            restoreEnv("COLORTERM", previousCOLORTERM)
            restoreEnv("TERM_PROGRAM", previousTermProgram)
            restoreEnv("CLICOLOR", previousCLICOLOR)
            _ = FileManager.default.changeCurrentDirectoryPath(previousCwd)
        }

        return shell.withCString { cocxycore_pty_spawn(rows, columns, $0) }
    }

    private static func getenvString(_ key: String) -> String? {
        getenv(key).map { String(cString: $0) }
    }

    private static func restoreEnv(_ key: String, _ value: String?) {
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
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

    private func makeFrame() -> PTYDaemonSurfaceFrame? {
        terminalLock.withLock {
            makeFrameLocked()
        }
    }

    private func makeFrameLocked() -> PTYDaemonSurfaceFrame? {
        guard cocxycore_terminal_build_frame(terminal) else { return nil }
        revision &+= 1
        let rows = cocxycore_terminal_rows(terminal)
        let columns = cocxycore_terminal_cols(terminal)
        var cells: [PTYDaemonGridCell] = []
        cells.reserveCapacity(Int(rows) * Int(columns))

        for row in 0..<rows {
            for column in 0..<columns {
                var renderCell = cocxycore_render_cell()
                cocxycore_terminal_frame_cell(terminal, row, column, &renderCell)
                cells.append(
                    PTYDaemonGridCell(
                        row: row,
                        column: column,
                        glyph: renderCell.codepoint,
                        foregroundRGBA: Self.pack(renderCell.fg),
                        backgroundRGBA: Self.pack(renderCell.bg),
                        attributes: UInt16(renderCell.flags)
                    )
                )
            }
        }

        var renderCursor = cocxycore_render_cursor()
        cocxycore_terminal_frame_cursor(terminal, &renderCursor)

        return PTYDaemonSurfaceFrame(
            surfaceID: surfaceID,
            revision: revision,
            timestamp: Date().timeIntervalSince1970,
            columns: columns,
            rows: rows,
            cells: cells,
            cursor: PTYDaemonCursor(
                row: renderCursor.row,
                column: renderCursor.col,
                visible: renderCursor.visible,
                style: Self.cursorStyle(renderCursor.shape)
            ),
            scrollbackTop: Int(cocxycore_terminal_history_visible_start(terminal)),
            images: []
        )
    }

    private static func pack(_ rgba: cocxycore_rgba) -> UInt32 {
        (UInt32(rgba.r) << 24) |
            (UInt32(rgba.g) << 16) |
            (UInt32(rgba.b) << 8) |
            UInt32(rgba.a)
    }

    private static func cursorStyle(_ shape: UInt8) -> String {
        switch shape {
        case 2, 3: return "underline"
        case 4, 5: return "bar"
        default: return "block"
        }
    }

    private func literalSearch(query: String, caseSensitive: Bool, maxResults: Int) -> [PTYDaemonSearchResult] {
        let capped = max(1, min(maxResults, 200))
        var results: [PTYDaemonSearchResult] = []
        var fromRow: UInt32 = 0
        var fromColumn: UInt16 = 0
        let queryBytes = Array(query.utf8)
        let maxRows = cocxycore_terminal_history_rows(terminal)

        while results.count < capped {
            var range = cocxycore_buffer_range()
            let found = queryBytes.withUnsafeBufferPointer { pointer in
                cocxycore_terminal_search_next(
                    terminal,
                    pointer.baseAddress,
                    queryBytes.count,
                    fromRow,
                    fromColumn,
                    caseSensitive,
                    &range
                )
            }
            guard found else { break }
            results.append(
                PTYDaemonSearchResult(
                    id: UUID().uuidString,
                    lineNumber: Int(range.start_row),
                    column: Int(range.start_col),
                    matchText: query,
                    contextBefore: nil,
                    contextAfter: lineText(row: range.start_row)
                )
            )

            fromRow = range.end_row
            fromColumn = range.end_col &+ 1
            if fromColumn >= cocxycore_terminal_cols(terminal) {
                fromRow &+= 1
                fromColumn = 0
            }
            if fromRow >= maxRows { break }
        }
        return results
    }

    private func regexSearch(query: String, caseSensitive: Bool, maxResults: Int) -> [PTYDaemonSearchResult]? {
        guard let engine = cocxycore_gpu_search_init(terminal) else { return nil }
        defer { cocxycore_gpu_search_destroy(engine) }
        cocxycore_gpu_search_sync(engine, terminal)

        let capped = max(1, min(maxResults, 200))
        var matches = Array(
            repeating: cocxycore_search_match(row: 0, start_col: 0, end_col: 0),
            count: capped
        )
        var elapsed: UInt64 = 0
        let found = query.withCString { queryPtr in
            matches.withUnsafeMutableBufferPointer { buffer -> UInt32 in
                guard let baseAddress = buffer.baseAddress else { return 0 }
                return cocxycore_gpu_search_find(
                    engine,
                    terminal,
                    queryPtr,
                    UInt32(query.utf8.count),
                    true,
                    !caseSensitive,
                    0,
                    0,
                    0,
                    UInt32(capped),
                    baseAddress,
                    &elapsed
                )
            }
        }

        guard found > 0 else { return [] }
        return matches.prefix(Int(found)).map { match in
            PTYDaemonSearchResult(
                id: UUID().uuidString,
                lineNumber: Int(match.row),
                column: Int(match.start_col),
                matchText: query,
                contextBefore: nil,
                contextAfter: lineText(row: match.row)
            )
        }
    }

    private func lineText(row: UInt32) -> String {
        let columns = cocxycore_terminal_cols(terminal)
        var scalars = String.UnicodeScalarView()
        for column in 0..<columns {
            let codepoint = cocxycore_terminal_history_cell_char(terminal, row, column)
            guard codepoint != 0, let scalar = UnicodeScalar(codepoint) else { continue }
            scalars.append(scalar)
        }
        return String(scalars).trimmingCharacters(in: .whitespaces)
    }

    private func writeEncodedKey(_ key: UInt8, modifiers: UInt) -> Bool {
        terminalLock.withLock {
            var buffer = [UInt8](repeating: 0, count: 64)
            let count = cocxycore_terminal_encode_key(
                terminal,
                key,
                Self.cocxyModifiers(from: modifiers),
                &buffer,
                buffer.count
            )
            guard count > 0 else { return false }
            return buffer.withUnsafeBufferPointer { pointer in
                cocxycore_terminal_write_attached_pty(terminal, pointer.baseAddress, count) > 0
            }
        }
    }

    private func writeEncodedCharacter(_ codepoint: UInt32, modifiers: UInt) -> Bool {
        terminalLock.withLock {
            var buffer = [UInt8](repeating: 0, count: 64)
            let count = cocxycore_terminal_encode_char(
                terminal,
                codepoint,
                Self.cocxyModifiers(from: modifiers),
                &buffer,
                buffer.count
            )
            guard count > 0 else { return false }
            return buffer.withUnsafeBufferPointer { pointer in
                cocxycore_terminal_write_attached_pty(terminal, pointer.baseAddress, count) > 0
            }
        }
    }

    private static func cocxyModifiers(from raw: UInt) -> UInt8 {
        var result: UInt8 = 0
        if raw & (1 << 0) != 0 { result |= 1 }
        if raw & (1 << 2) != 0 { result |= 2 }
        if raw & (1 << 1) != 0 { result |= 4 }
        if raw & (1 << 3) != 0 { result |= 8 }
        return result
    }

    private static func specialKey(forMacKeyCode code: UInt16) -> UInt8? {
        switch code {
        case 126: return 0
        case 125: return 1
        case 124: return 2
        case 123: return 3
        case 115: return 4
        case 119: return 5
        case 114: return 6
        case 117: return 7
        case 116: return 8
        case 121: return 9
        case 122: return 10
        case 120: return 11
        case 99: return 12
        case 118: return 13
        case 96: return 14
        case 97: return 15
        case 98: return 16
        case 100: return 17
        case 101: return 18
        case 109: return 19
        case 103: return 20
        case 111: return 21
        case 51: return 22
        case 48: return 23
        case 36: return 24
        case 53: return 25
        default: return nil
        }
    }

    private func registerCallbacks() {
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
    }

    private func emitOSC(_ osc: PTYDaemonOSCNotification) {
        writer.write(
            PTYDaemonEvent(
                event: .surfaceOSC,
                surfaceID: surfaceID,
                osc: osc
            )
        )
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

private final class PTYDaemonSurfaceCallbackContext {
    weak var surface: PTYDaemonSurface?

    init(surface: PTYDaemonSurface) {
        self.surface = surface
    }
}

enum PTYDaemonSurfaceError: Error, CustomStringConvertible {
    case creationFailed(String)
    case missingSurface
    case invalidPayload(String)

    var description: String {
        switch self {
        case .creationFailed(let reason), .invalidPayload(let reason):
            return reason
        case .missingSurface:
            return "surface not found"
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

extension Dictionary where Key == String, Value == String {
    func nonEmpty(_ key: String) -> String? {
        guard let value = self[key], value.isEmpty == false else { return nil }
        return value
    }

    func uint16(_ key: String) -> UInt16? {
        nonEmpty(key).flatMap(UInt16.init)
    }

    func uint32(_ key: String) -> UInt32? {
        nonEmpty(key).flatMap(UInt32.init)
    }

    func uint(_ key: String) -> UInt? {
        nonEmpty(key).flatMap(UInt.init)
    }

    func int(_ key: String) -> Int? {
        nonEmpty(key).flatMap(Int.init)
    }

    func int32(_ key: String) -> Int32? {
        nonEmpty(key).flatMap(Int32.init)
    }

    func bool(_ key: String) -> Bool? {
        guard let raw = nonEmpty(key)?.lowercased() else { return nil }
        switch raw {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }
}
