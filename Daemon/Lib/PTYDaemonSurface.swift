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
    static let semanticBlockCapacity: UInt32 = 1_024

    /// Deadline for the asynchronous teardown that `close` waits on.
    ///
    /// Derived from the reap budget on purpose: the cancel handler spends at
    /// most `terminationBudget` signalling and reaping the child, and the
    /// remaining slack covers the hop onto `ioQueue` plus the CocxyCore
    /// teardown. Judging that work against an unrelated constant is what let
    /// a successful close report `ok: false` under load.
    static let cleanupDeadline: TimeInterval = TerminalProcessBoundary.terminationBudget + 1.5

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
    private var processExitReported = false

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

        let fontConfiguration = try validatedFontConfiguration(payload: payload)
        guard applyFontConfiguration(fontConfiguration, to: terminal) else {
            cocxycore_terminal_destroy(terminal)
            throw PTYDaemonSurfaceError.creationFailed("terminal font configuration failed")
        }
        guard cocxycore_terminal_enable_scrollback(terminal, 10_000),
              cocxycore_terminal_enable_semantic(terminal, semanticBlockCapacity) else {
            cocxycore_terminal_destroy(terminal)
            throw PTYDaemonSurfaceError.creationFailed("terminal history configuration failed")
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
            drainTerminalResponses()
            return didResize
        }
    }

    func applyFont(payload: [String: String]) throws -> Bool {
        let configuration = try Self.validatedFontConfiguration(payload: payload)
        return terminalLock.withLock {
            let didApply = Self.applyFontConfiguration(configuration, to: terminal)
            drainTerminalResponses()
            return didApply
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

    private struct FontConfiguration {
        let family: String
        let size: Float
        let dpiScale: Float
        let ligatures: Bool
    }

    private static func validatedFontConfiguration(
        payload: [String: String]
    ) throws -> FontConfiguration {
        let family = payload.nonEmpty("fontFamily") ?? payload.nonEmpty("family") ?? "Menlo"
        guard family.utf8.count <= 256 else {
            throw PTYDaemonSurfaceError.invalidPayload("font family exceeds 256 UTF-8 bytes")
        }

        let size = try finiteFloat(
            payload.nonEmpty("fontSize") ?? payload.nonEmpty("size"),
            default: 14,
            range: 4...256,
            field: "font size"
        )
        let dpiScale = try finiteFloat(
            payload.nonEmpty("dpiScale"),
            default: 1,
            range: 0.5...4,
            field: "font dpiScale"
        )
        return FontConfiguration(
            family: family,
            size: size,
            dpiScale: dpiScale,
            ligatures: payload.bool("ligaturesEnabled") ?? true
        )
    }

    private static func finiteFloat(
        _ rawValue: String?,
        default defaultValue: Float,
        range: ClosedRange<Float>,
        field: String
    ) throws -> Float {
        guard let rawValue else { return defaultValue }
        guard let value = Float(rawValue), value.isFinite, range.contains(value) else {
            throw PTYDaemonSurfaceError.invalidPayload(
                "\(field) must be finite and within \(range.lowerBound)...\(range.upperBound)"
            )
        }
        return value
    }

    private static func applyFontConfiguration(
        _ configuration: FontConfiguration,
        to terminal: OpaquePointer
    ) -> Bool {
        configuration.family.withCString { family in
            cocxycore_terminal_set_font(
                terminal,
                family,
                configuration.size,
                configuration.dpiScale,
                configuration.ligatures
            )
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
        guard payload.bool("isComposing") != true else { return false }
        let isKeyDown = payload.bool("isKeyDown") ?? true
        let eventType: UInt8 = isKeyDown
            ? ((payload.bool("isRepeat") ?? false) ? 2 : 1)
            : 3
        let keyCode = payload.uint16("keyCode") ?? 0
        let modifiers = payload.uint("modifiers") ?? 0
        let characters = payload["characters"] ?? ""
        let characterScalars = characters.unicodeScalars.map(\.value)
        let shiftedCodepoint = payload.uint32("shiftedCodepoint") ?? 0
        let baseLayoutCodepoint = payload.uint32("baseLayoutCodepoint") ?? 0
        if let key = TerminalKeyMapping.specialKey(forMacKeyCode: keyCode) {
            let associatedText = isKeyDown && TerminalKeyMapping.carriesAssociatedText(key)
                ? Array(characterScalars.prefix(8))
                : []
            return writeEncodedKey(
                key,
                modifiers: modifiers,
                eventType: eventType,
                shiftedCodepoint: shiftedCodepoint,
                baseLayoutCodepoint: baseLayoutCodepoint,
                associatedText: associatedText
            )
        }

        let primaryCodepoint = payload.uint32("unshiftedCodepoint")
            .flatMap { $0 > 0 ? $0 : nil }
            ?? characterScalars.first
            ?? 0
        guard primaryCodepoint > 0 else { return false }
        return writeEncodedCharacter(
            primaryCodepoint,
            characters: characters,
            modifiers: modifiers,
            eventType: eventType,
            shiftedCodepoint: shiftedCodepoint,
            baseLayoutCodepoint: baseLayoutCodepoint,
            associatedText: isKeyDown ? Array(characterScalars.prefix(8)) : []
        )
    }

    func setPreedit(_ text: String, cursorByteOffset: Int?) {
        let frame: PTYDaemonSurfaceFrame? = terminalLock.withLock {
            if text.isEmpty {
                cocxycore_terminal_preedit_clear(terminal)
            } else {
                let row = cocxycore_terminal_cursor_row(terminal)
                let column = cocxycore_terminal_cursor_col(terminal)
                let bytes = Array(text.utf8)
                let cursorBytes = UInt16(clamping: min(
                    max(0, cursorByteOffset ?? bytes.count),
                    bytes.count
                ))
                cocxycore_terminal_preedit_set(
                    terminal,
                    row,
                    column,
                    bytes,
                    bytes.count,
                    cursorBytes
                )
            }
            return shouldEmitFrames() ? makeFrameLocked() : nil
        }
        if let frame {
            writer.write(
                PTYDaemonEvent(event: .surfaceFrame, surfaceID: surfaceID, frame: frame)
            )
        }
    }

    func notifyFocus(_ focused: Bool) {
        terminalLock.withLock {
            cocxycore_terminal_notify_focus(terminal, focused)
            drainTerminalResponses()
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

    func performSemanticNavigation(
        _ action: TerminalSemanticNavigationAction
    ) -> (result: TerminalSemanticNavigationResult, frame: PTYDaemonSurfaceFrame?)? {
        terminalLock.withLock {
            guard let result = Self.performSemanticNavigation(action, terminal: terminal) else {
                return nil
            }
            return (result, makeFrameLocked())
        }
    }

    func semanticNavigationUnavailableReason() -> String {
        terminalLock.withLock {
            let blockCount = cocxycore_terminal_semantic_block_count(terminal)
            let promptCount = cocxycore_terminal_semantic_block_count_by_type(
                terminal,
                UInt8(COCXYCORE_BLOCK_PROMPT.rawValue)
            )
            let retainedPrompts = Self.semanticPromptRegions(
                terminal: terminal,
                blockCount: blockCount
            ).count
            return "semantic navigation target unavailable " +
                "(blocks=\(blockCount), prompts=\(promptCount), " +
                "retainedPrompts=\(retainedPrompts), " +
                "visibleStart=\(cocxycore_terminal_history_visible_start(terminal)), " +
                "maximumVisibleStart=\(cocxycore_terminal_history_max_visible_start(terminal)))"
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

    private static func performSemanticNavigation(
        _ action: TerminalSemanticNavigationAction,
        terminal: OpaquePointer
    ) -> TerminalSemanticNavigationResult? {
        let visibleStart = cocxycore_terminal_history_visible_start(terminal)
        let maximumVisibleStart = cocxycore_terminal_history_max_visible_start(terminal)
        let blockCount = cocxycore_terminal_semantic_block_count(terminal)
        let promptRegions = semanticPromptRegions(
            terminal: terminal,
            blockCount: blockCount
        )

        switch action {
        case .previousPrompt, .nextPrompt:
            guard let target = TerminalSemanticNavigationResolver.promptRegion(
                for: action,
                visibleStartRow: visibleStart,
                regions: promptRegions,
                maximumSearchSteps: Int(blockCount),
                findOlder: { offset in
                    cocxycore_terminal_semantic_find_next(
                        terminal,
                        UInt8(COCXYCORE_BLOCK_PROMPT.rawValue),
                        offset
                    )
                },
                findNewer: { offset in
                    cocxycore_terminal_semantic_find_prev(
                        terminal,
                        UInt8(COCXYCORE_BLOCK_PROMPT.rawValue),
                        offset
                    )
                }
            ) else { return nil }
            let viewportStart = min(target.startRow, maximumVisibleStart)
            guard cocxycore_terminal_history_set_visible_start(terminal, viewportStart) else {
                return nil
            }
            cocxycore_terminal_selection_clear(terminal)
            return TerminalSemanticNavigationResult(
                action: action,
                viewportStartRow: viewportStart
            )

        case .selectCommandOutput:
            let outputRegions = commandOutputRegions(terminal: terminal)
            guard let target = TerminalSemanticNavigationResolver.commandOutputRegion(
                visibleStartRow: visibleStart,
                regions: promptRegions + outputRegions
            ), let blockID = target.blockID else { return nil }
            let columns = cocxycore_terminal_cols(terminal)
            guard columns > 0 else { return nil }
            let viewportStart = min(target.startRow, maximumVisibleStart)
            guard cocxycore_terminal_history_set_visible_start(terminal, viewportStart) else {
                return nil
            }
            let endColumn = columns - 1
            cocxycore_terminal_selection_set(
                terminal,
                target.startRow,
                0,
                target.endRow,
                endColumn
            )
            return TerminalSemanticNavigationResult(
                action: action,
                viewportStartRow: viewportStart,
                selection: TerminalSemanticSelection(
                    blockID: blockID,
                    startRow: target.startRow,
                    startColumn: 0,
                    endRow: target.endRow,
                    endColumn: endColumn,
                    text: blockOutput(from: terminal, blockID: blockID)
                )
            )
        }
    }

    private static func semanticPromptRegions(
        terminal: OpaquePointer,
        blockCount: UInt32
    ) -> [TerminalSemanticRegion] {
        guard blockCount > 0 else { return [] }
        var regions: [TerminalSemanticRegion] = []
        regions.reserveCapacity(Int(blockCount))

        for offset in 0..<blockCount {
            var block = cocxycore_semantic_block()
            guard cocxycore_terminal_semantic_get_block(terminal, offset, &block),
                  block.block_type == UInt8(COCXYCORE_BLOCK_PROMPT.rawValue) else {
                continue
            }
            var startRow: UInt32 = 0
            var endRow: UInt32 = 0
            guard cocxycore_block_visible_row(terminal, block.start_row, &startRow),
                  cocxycore_block_visible_row(terminal, block.end_row, &endRow) else {
                continue
            }
            regions.append(TerminalSemanticRegion(
                offset: offset,
                kind: .prompt,
                startRow: startRow,
                endRow: endRow
            ))
        }
        return regions
    }

    private static func commandOutputRegions(
        terminal: OpaquePointer
    ) -> [TerminalSemanticRegion] {
        guard let iterator = cocxycore_block_iterator_create(terminal) else { return [] }
        defer { cocxycore_block_iterator_destroy(iterator) }
        var regions: [TerminalSemanticRegion] = []

        while cocxycore_block_iterator_next(iterator) {
            let blockID = cocxycore_block_iterator_current_id(iterator)
            var metadata = cocxycore_block_metadata()
            guard blockID != 0,
                  cocxycore_block_get_metadata(terminal, blockID, &metadata),
                  let kind = TerminalSemanticBlockKind(rawValue: metadata.block_type),
                  kind == .commandOutput || kind == .errorOutput else {
                continue
            }
            var startRow: UInt32 = 0
            var endRow: UInt32 = 0
            guard cocxycore_block_visible_row(terminal, metadata.start_row, &startRow),
                  cocxycore_block_visible_row(terminal, metadata.end_row, &endRow) else {
                continue
            }
            regions.append(TerminalSemanticRegion(
                blockID: blockID,
                kind: kind,
                startRow: startRow,
                endRow: endRow
            ))
        }
        return regions
    }

    private static func blockOutput(from terminal: OpaquePointer, blockID: UInt64) -> String {
        let required = cocxycore_block_get_output(terminal, blockID, nil, 0, true)
        guard required > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: required)
        let copied = cocxycore_block_get_output(
            terminal,
            blockID,
            &buffer,
            buffer.count,
            true
        )
        guard copied > 0 else { return "" }
        return String(decoding: buffer.prefix(copied).map { UInt8(bitPattern: $0) }, as: UTF8.self)
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
        guard cleanupGroup.wait(timeout: .now() + Self.cleanupDeadline) == .success else {
            return false
        }
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

    func emitProcessExitIfNeeded(exitCode: Int?) {
        let shouldEmit = stateLock.withLock {
            guard processExitReported == false else { return false }
            processExitReported = true
            return true
        }
        guard shouldEmit else { return }
        emitOSC(.init(kind: .processExited, exitCode: exitCode))
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
        source.setCancelHandler { [weak self, terminal, pty, callbackContext, shellPID, ptyMasterFD, surfaceID, cleanupGroup] in
            cocxycore_terminal_detach_pty(terminal)
            // Cancelling this source removes the only reader of the PTY
            // master, so a child that is mid-`write` to its terminal blocks on
            // a full PTY buffer. It still takes SIGHUP and enters the exiting
            // state, but it cannot finish flushing, so it never becomes
            // reapable — `ps` reports it as `E` for as long as the daemon
            // waits. Draining on every poll keeps the child's last writes
            // moving so it can actually exit, instead of deadlocking against
            // the very reader this surface just shut down.
            let didReap = TerminalProcessBoundary.terminateAndReapPTYChild(shellPID) {
                PTYDaemonSurface.drainPendingOutput(pty, masterFD: ptyMasterFD)
            }
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

    /// Discards whatever the child has already written to the PTY master
    /// without ever blocking. Used while a closing surface waits for its
    /// child to exit: the surface's reader is gone by then, and a full PTY
    /// buffer would otherwise wedge the child mid-`write`.
    static func drainPendingOutput(_ pty: OpaquePointer, masterFD: Int32) {
        guard masterFD >= 0 else { return }
        var descriptor = pollfd(fd: masterFD, events: Int16(POLLIN), revents: 0)
        var scratch = [UInt8](repeating: 0, count: readBufferSize)
        while Darwin.poll(&descriptor, 1, 0) > 0, descriptor.revents & Int16(POLLIN) != 0 {
            guard cocxycore_pty_read(pty, &scratch, scratch.count) > 0 else { return }
            descriptor.revents = 0
        }
    }

    private func pollChildExit() {
        guard isClosed() == false, pollPTYExit() else { return }

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
            if pollPTYExit() {
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

    private func pollTrackedProcesses() {
        terminalLock.withLock {
            cocxycore_terminal_poll_processes(terminal)
        }
    }

    private func pollPTYExit() -> Bool {
        var waitResult = cocxycore_pty_wait_result()
        let didExit = cocxycore_pty_wait_check(pty, &waitResult)
            && cocxycore_pty_is_alive(pty) == false
        return Self.completePTYExitPoll(
            didExit: didExit,
            exitCode: waitResult.status == 1 ? Int(waitResult.exit_code) : nil,
            emitProcessExit: { [self] in emitProcessExitIfNeeded(exitCode: $0) },
            pollTrackedProcesses: { [self] in pollTrackedProcesses() }
        )
    }

    static func completePTYExitPoll(
        didExit: Bool,
        exitCode: Int?,
        emitProcessExit: (Int?) -> Void,
        pollTrackedProcesses: () -> Void
    ) -> Bool {
        defer { pollTrackedProcesses() }
        guard didExit else { return false }
        emitProcessExit(exitCode)
        return true
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
