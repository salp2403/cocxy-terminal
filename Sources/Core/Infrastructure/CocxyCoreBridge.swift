// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyCoreBridge.swift - Bridge between CocxyCore C API and Swift.

import AppKit
import CocxyCoreKit

// MARK: - CocxyCore Bridge

/// Concrete implementation of `TerminalEngine` using CocxyCore's C API.
///
/// Each surface owns an independent terminal + PTY pair. The bridge manages
/// the I/O loop (DispatchSource on PTY master fd), routes terminal callbacks
/// (title, cwd, bell, clipboard, semantic, process) to the main thread, and
/// encodes keyboard input via the terminal's mode-aware encoder.
///
/// ## Lifecycle
///
/// ```
/// CocxyCoreBridge()          -- Uninitialized
///   .initialize(config:)     -- Config stored, Metal device verified
///   .createSurface(...)      -- Terminal + PTY created, I/O loop running
///   .destroySurface(...)     -- I/O loop cancelled, PTY + terminal freed
///   deinit                   -- All surfaces destroyed
/// ```
///
/// ## Threading model
///
/// - **Background (QoS userInteractive)**: PTY read via `DispatchSource`.
///   Feeds bytes to the terminal, reads responses, dispatches redraw to main.
/// - **Main thread**: All callbacks, UI updates, and public API calls.
///
/// CocxyCore uses a single read source per surface. Terminal state mutation
/// happens on the source's queue; callbacks are dispatched to main before
/// touching Swift-owned state.
@MainActor
final class CocxyCoreBridge: TerminalEngine {

    // MARK: - Per-Surface State

    /// All state associated with a single terminal surface.
    struct SurfaceState {
        let terminal: OpaquePointer      // cocxycore_terminal*
        let pty: OpaquePointer           // cocxycore_pty*
        let readSource: DispatchSourceRead
        let contextBox: Unmanaged<CallbackContext>
        weak var hostView: NSView?

        var outputHandler: (@Sendable (Data) -> Void)?
        var oscHandler: (@Sendable (OSCNotification) -> Void)?
    }

    /// Boxed context passed to C callbacks to recover the bridge + surface ID.
    final class CallbackContext {
        let surfaceID: SurfaceID
        weak var bridge: CocxyCoreBridge?

        init(surfaceID: SurfaceID, bridge: CocxyCoreBridge) {
            self.surfaceID = surfaceID
            self.bridge = bridge
        }
    }

    // MARK: - State

    private var surfaces: [SurfaceID: SurfaceState] = [:]
    private var config: TerminalEngineConfig?

    /// Semantic adapter that converts CocxyCore events to HookEvent/TimelineEvent
    /// format for the existing agent detection and timeline systems.
    let semanticAdapter = CocxyCoreSemanticAdapter()

    /// Whether the bridge has been successfully initialized.
    var isInitialized: Bool { config != nil }

    /// Number of currently active surfaces.
    var activeSurfaceCount: Int { surfaces.count }

    /// All active surface IDs (for bulk operations like theme change).
    var allSurfaceIDs: [SurfaceID] { Array(surfaces.keys) }

    /// Current horizontal content padding in points.
    var configuredPaddingX: CGFloat { CGFloat(config?.windowPaddingX ?? 8.0) }

    /// Current vertical content padding in points.
    var configuredPaddingY: CGFloat { CGFloat(config?.windowPaddingY ?? 4.0) }

    // MARK: - Constants

    /// PTY read buffer size (64 KB — large enough to avoid frequent reads).
    private static let readBufferSize = 65536

    /// DSR/DECRQSS response buffer size.
    private static let responseBufferSize = 256

    /// Scrollback capacity (rows stored in ring buffer).
    private static let scrollbackCapacity: UInt32 = 10000

    /// Semantic block capacity (number of classified blocks stored).
    private static let semanticBlockCapacity: UInt32 = 1024

    /// Process tracker capacity (max concurrent child processes).
    private static let processTrackerCapacity: UInt32 = 64

    // MARK: - Initialization

    init() {}

    deinit {
        assert(Thread.isMainThread, "CocxyCoreBridge.deinit called off main thread")
        MainActor.assumeIsolated {
            let ids = Array(surfaces.keys)
            for id in ids {
                destroySurface(id)
            }
        }
    }

    // MARK: - TerminalEngine Protocol

    func initialize(config: TerminalEngineConfig) throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw TerminalEngineError.initializationFailed(
                reason: "Metal is required for CocxyCore rendering"
            )
        }
        self.config = config
    }

    func createSurface(
        in view: NativeTerminalView,
        workingDirectory: URL?,
        command: String?
    ) throws -> SurfaceID {
        guard let config = self.config else {
            throw TerminalEngineError.initializationFailed(reason: "Bridge not initialized")
        }

        let surfaceID = SurfaceID()

        // 1. Calculate initial grid dimensions
        let initialRows: UInt16 = 24
        let initialCols: UInt16 = 80

        // 2. Create terminal
        guard let terminal = cocxycore_terminal_create(initialRows, initialCols) else {
            throw TerminalEngineError.surfaceCreationFailed(reason: "Terminal allocation failed")
        }

        // 3. Configure terminal (theme, font, scrollback, semantic)
        configureTerminal(terminal, config: config)

        // 4. Spawn PTY with shell
        let shellPath = command ?? config.shell
        guard let pty = spawnPty(
            rows: initialRows,
            cols: initialCols,
            shell: shellPath,
            workingDirectory: workingDirectory ?? config.workingDirectory
        ) else {
            cocxycore_terminal_destroy(terminal)
            throw TerminalEngineError.surfaceCreationFailed(reason: "PTY spawn failed")
        }

        // 5. Enable process tracking
        let childPid = cocxycore_pty_child_pid(pty)
        if childPid > 0 {
            cocxycore_terminal_enable_process_tracking(
                terminal, childPid, Self.processTrackerCapacity
            )
        }

        // 6. Register C callbacks
        let contextBox = Unmanaged.passRetained(
            CallbackContext(surfaceID: surfaceID, bridge: self)
        )
        registerCallbacks(terminal: terminal, context: contextBox.toOpaque())

        // 7. Create PTY read loop
        let masterFd = cocxycore_pty_master_fd(pty)
        guard masterFd >= 0 else {
            cocxycore_pty_destroy(pty)
            cocxycore_terminal_destroy(terminal)
            contextBox.release()
            throw TerminalEngineError.surfaceCreationFailed(reason: "Invalid PTY master fd")
        }

        let readSource = createReadSource(
            masterFd: masterFd,
            terminal: terminal,
            pty: pty,
            surfaceID: surfaceID
        )

        // 8. Store state
        surfaces[surfaceID] = SurfaceState(
            terminal: terminal,
            pty: pty,
            readSource: readSource,
            contextBox: contextBox,
            hostView: view
        )

        readSource.resume()
        return surfaceID
    }

    func destroySurface(_ id: SurfaceID) {
        guard let state = surfaces.removeValue(forKey: id) else { return }

        // Clean up semantic adapter state for this surface.
        semanticAdapter.surfaceDestroyed(id)

        // Order: cancel I/O first, then PTY, then terminal, then context.
        state.readSource.cancel()
        cocxycore_pty_destroy(state.pty)
        cocxycore_terminal_destroy(state.terminal)
        state.contextBox.release()
    }

    @discardableResult
    func sendKeyEvent(_ event: KeyEvent, to surface: SurfaceID) -> Bool {
        guard event.isKeyDown, let state = surfaces[surface] else { return false }

        var buf = [UInt8](repeating: 0, count: 32)
        var bytesWritten = 0

        if let chars = event.characters,
           let scalar = chars.unicodeScalars.first {
            let codepoint = scalar.value
            let mods = mapModifiers(event.modifiers)

            // Try special key mapping first (arrows, function keys, etc.)
            if let key = mapKeyCodeToSpecialKey(event.keyCode) {
                bytesWritten = cocxycore_terminal_encode_key(
                    state.terminal, key, mods, &buf, buf.count
                )
            } else {
                bytesWritten = cocxycore_terminal_encode_char(
                    state.terminal, codepoint, mods, &buf, buf.count
                )
            }
        } else {
            // No characters — try special key mapping
            if let key = mapKeyCodeToSpecialKey(event.keyCode) {
                let mods = mapModifiers(event.modifiers)
                bytesWritten = cocxycore_terminal_encode_key(
                    state.terminal, key, mods, &buf, buf.count
                )
            }
        }

        if bytesWritten > 0 {
            cocxycore_pty_write(state.pty, buf, bytesWritten)
            return true
        }
        return false
    }

    func sendText(_ text: String, to surface: SurfaceID) {
        guard let state = surfaces[surface] else { return }
        let bytes = Array(text.utf8)
        if !bytes.isEmpty {
            cocxycore_pty_write(state.pty, bytes, bytes.count)
        }
    }

    func sendPreeditText(_ text: String, to surface: SurfaceID) {
        guard let state = surfaces[surface] else { return }

        if text.isEmpty {
            cocxycore_terminal_preedit_clear(state.terminal)
        } else {
            let row = cocxycore_terminal_cursor_row(state.terminal)
            let col = cocxycore_terminal_cursor_col(state.terminal)
            let bytes = Array(text.utf8)
            cocxycore_terminal_preedit_set(
                state.terminal, row, col, bytes, bytes.count, UInt16(bytes.count)
            )
        }
    }

    func resize(_ surface: SurfaceID, to size: TerminalSize) {
        guard let state = surfaces[surface] else { return }
        cocxycore_terminal_resize(state.terminal, size.rows, size.columns)
        cocxycore_pty_resize(state.pty, size.rows, size.columns)
    }

    func tick() {
        // CocxyCore does not have a global tick. Each surface's DispatchSource
        // handles I/O independently. This method exists for protocol conformance.
        // Process polling happens in the read source event handler.
    }

    func setOutputHandler(
        for surface: SurfaceID,
        handler: @escaping @Sendable (Data) -> Void
    ) {
        surfaces[surface]?.outputHandler = handler
    }

    func setOSCHandler(
        for surface: SurfaceID,
        handler: @escaping @Sendable (OSCNotification) -> Void
    ) {
        surfaces[surface]?.oscHandler = handler
    }

    func scrollToSearchResult(surfaceID: SurfaceID, lineNumber: Int) {
        guard let state = surfaces[surfaceID] else { return }

        let rows = Int(cocxycore_terminal_rows(state.terminal))
        let maxVisibleStart = Int(cocxycore_terminal_history_max_visible_start(state.terminal))
        guard rows > 0, maxVisibleStart >= 0 else { return }

        let targetRow = max(0, lineNumber)
        let preferredTopRow = max(0, targetRow - max(0, rows / 2))
        let clampedTopRow = min(preferredTopRow, maxVisibleStart)

        guard cocxycore_terminal_history_set_visible_start(
            state.terminal,
            UInt32(clampedTopRow)
        ) else { return }

        (state.hostView as? TerminalHostView)?.requestImmediateRedraw()
    }

    // MARK: - Extended API (beyond TerminalEngine protocol)

    /// Access surface state for renderer and view integration (Block 2-3).
    func surfaceState(for id: SurfaceID) -> SurfaceState? {
        surfaces[id]
    }

    /// Returns the visible-history top row for a surface.
    func historyVisibleStart(for surface: SurfaceID) -> UInt32? {
        guard let state = surfaces[surface] else { return nil }
        return cocxycore_terminal_history_visible_start(state.terminal)
    }

    /// Scroll the surface viewport by a signed number of rows.
    /// Positive values move upward into older scrollback.
    func scrollViewport(surfaceID: SurfaceID, deltaRows: Int) {
        guard deltaRows != 0, let state = surfaces[surfaceID] else { return }
        guard cocxycore_terminal_history_scroll_viewport(
            state.terminal,
            Int32(max(Int(Int32.min), min(Int(Int32.max), deltaRows)))
        ) else { return }

        (state.hostView as? TerminalHostView)?.requestImmediateRedraw()
    }

    /// Snapshot the terminal's combined history as UTF-8 lines.
    func historyLines(for surface: SurfaceID) -> [String] {
        guard let state = surfaces[surface] else { return [] }

        let rowCount = Int(cocxycore_terminal_history_rows(state.terminal))
        let cols = cocxycore_terminal_cols(state.terminal)
        guard rowCount > 0, cols > 0 else { return [] }

        return (0..<rowCount).map { rowIndex in
            historyLineText(
                terminal: state.terminal,
                absoluteRow: UInt32(rowIndex),
                columnCount: cols
            )
        }
    }

    /// Returns the text for a currently visible row in the viewport.
    func visibleLineText(for surface: SurfaceID, visibleRow: UInt16) -> String? {
        guard let state = surfaces[surface] else { return nil }

        let start = cocxycore_terminal_history_visible_start(state.terminal)
        let absoluteRow = start + UInt32(visibleRow)
        return historyLineText(
            terminal: state.terminal,
            absoluteRow: absoluteRow,
            columnCount: cocxycore_terminal_cols(state.terminal)
        )
    }

    /// Apply a theme change without destroying surfaces.
    ///
    /// CocxyCore supports runtime theme updates, so the active surface can
    /// redraw immediately without teardown/recreation.
    func applyTheme(_ palette: ThemePalette, to surface: SurfaceID) {
        guard let state = surfaces[surface] else { return }

        let fg = Self.parseHexColor(palette.foreground)
        let bg = Self.parseHexColor(palette.background)
        let cur = Self.parseHexColor(palette.cursor)

        cocxycore_terminal_set_theme(
            state.terminal,
            fg.r, fg.g, fg.b,
            bg.r, bg.g, bg.b,
            cur.r, cur.g, cur.b
        )

        for i in 0..<min(palette.ansiColors.count, 16) {
            let c = Self.parseHexColor(palette.ansiColors[i])
            cocxycore_terminal_set_theme_base16(state.terminal, UInt8(i), c.r, c.g, c.b)
        }

        let sel = Self.parseHexColor(palette.selectionBackground)
        cocxycore_terminal_set_selection_color(state.terminal, sel.r, sel.g, sel.b, 128)
        (state.hostView as? TerminalHostView)?.requestImmediateRedraw()
    }

    /// Updates the stored defaults used for newly created surfaces.
    ///
    /// Existing surfaces are unaffected unless a dedicated apply method
    /// (for example `applyTheme` or `applyFont`) is also called.
    func updateDefaults(
        fontFamily: String? = nil,
        fontSize: Double? = nil,
        themeName: String? = nil,
        themePalette: ThemePalette? = nil,
        shell: String? = nil,
        windowPaddingX: Double? = nil,
        windowPaddingY: Double? = nil
    ) {
        guard let currentConfig = config else { return }
        config = currentConfig.replacing(
            fontFamily: fontFamily,
            fontSize: fontSize,
            themeName: themeName,
            shell: shell,
            themePalette: themePalette,
            windowPaddingX: windowPaddingX,
            windowPaddingY: windowPaddingY
        )
    }

    /// Apply a font change to all live surfaces and future surfaces.
    func applyFont(family: String, size: Double) {
        updateDefaults(fontFamily: family, fontSize: size)

        for state in surfaces.values {
            let scale = Float(state.hostView?.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0)
            _ = family.withCString { familyPtr in
                cocxycore_terminal_set_font(
                    state.terminal,
                    familyPtr,
                    Float(size),
                    scale,
                    true
                )
            }
            (state.hostView as? TerminalHostView)?.updateInteractionMetrics()
            (state.hostView as? TerminalHostView)?.requestImmediateRedraw()
        }
    }

    /// Check if PTY child process is still alive.
    func isProcessAlive(for surface: SurfaceID) -> Bool {
        guard let state = surfaces[surface] else { return false }
        return cocxycore_pty_is_alive(state.pty)
    }

    /// Check if selection is active for a surface.
    func hasSelection(for surface: SurfaceID) -> Bool {
        guard let state = surfaces[surface] else { return false }
        return cocxycore_terminal_selection_active(state.terminal)
    }

    /// Copy selected text from a surface. Returns nil if no selection.
    func readSelection(for surface: SurfaceID) -> String? {
        guard let state = surfaces[surface],
              cocxycore_terminal_selection_active(state.terminal) else { return nil }

        // First call to get required buffer size
        let needed = cocxycore_terminal_selection_copy_text(state.terminal, nil, 0)
        guard needed > 0 else { return nil }

        var buf = [UInt8](repeating: 0, count: needed)
        let copied = cocxycore_terminal_selection_copy_text(state.terminal, &buf, buf.count)
        guard copied > 0 else { return nil }

        return String(bytes: buf[0..<copied], encoding: .utf8)
    }

    // MARK: - Private: Terminal Configuration

    private func configureTerminal(
        _ terminal: OpaquePointer,
        config: TerminalEngineConfig
    ) {
        // Scrollback
        cocxycore_terminal_enable_scrollback(terminal, Self.scrollbackCapacity)

        // Semantic layer
        cocxycore_terminal_enable_semantic(terminal, Self.semanticBlockCapacity)

        // Font
        _ = config.fontFamily.withCString { family in
            cocxycore_terminal_set_font(
                terminal,
                family,
                Float(config.fontSize),
                Float(NSScreen.main?.backingScaleFactor ?? 2.0),
                true // ligatures
            )
        }

        // Theme (if palette provided)
        if let palette = config.themePalette {
            let fg = Self.parseHexColor(palette.foreground)
            let bg = Self.parseHexColor(palette.background)
            let cur = Self.parseHexColor(palette.cursor)

            cocxycore_terminal_set_theme(
                terminal,
                fg.r, fg.g, fg.b,
                bg.r, bg.g, bg.b,
                cur.r, cur.g, cur.b
            )

            for i in 0..<min(palette.ansiColors.count, 16) {
                let c = Self.parseHexColor(palette.ansiColors[i])
                cocxycore_terminal_set_theme_base16(terminal, UInt8(i), c.r, c.g, c.b)
            }

            let sel = Self.parseHexColor(palette.selectionBackground)
            cocxycore_terminal_set_selection_color(terminal, sel.r, sel.g, sel.b, 128)
        }
    }

    // MARK: - Private: PTY Spawning

    private func spawnPty(
        rows: UInt16,
        cols: UInt16,
        shell: String,
        workingDirectory: URL
    ) -> OpaquePointer? {
        // CocxyCore's current C API inherits cwd/env from the host process at
        // fork time. Scope those mutations carefully and restore them
        // immediately after spawn so other modules/windows do not observe them.
        let previousCwd = FileManager.default.currentDirectoryPath
        let envVars = buildShellIntegrationEnvVars()
        let previousEnv = envVars.reduce(into: [String: String?]()) { result, entry in
            result[entry.key] = Self.environmentValue(for: entry.key)
        }

        let cwd = workingDirectory.path
        _ = FileManager.default.changeCurrentDirectoryPath(cwd)
        for (key, value) in envVars { setenv(key, value, 1) }

        defer {
            for (key, originalValue) in previousEnv {
                if let originalValue {
                    setenv(key, originalValue, 1)
                } else {
                    unsetenv(key)
                }
            }
            _ = FileManager.default.changeCurrentDirectoryPath(previousCwd)
        }

        let pty = shell.withCString { shellPtr in
            cocxycore_pty_spawn(rows, cols, shellPtr)
        }

        return pty
    }

    /// Build shell integration environment variables.
    ///
    /// The PTY inherits the host process environment, so user-defined values
    /// such as `ZDOTDIR`, `HOME`, and `SHELL` flow through naturally. This
    /// method only layers CocxyCore's own integration markers on top.
    private func buildShellIntegrationEnvVars() -> [String: String] {
        var env: [String: String] = [:]

        // CocxyCore base vars
        let count = cocxycore_shell_integration_env_count()
        for i in 0..<count {
            var nameBuf = [UInt8](repeating: 0, count: 256)
            var valBuf = [UInt8](repeating: 0, count: 256)
            let nameLen = cocxycore_shell_integration_env_name(i, &nameBuf, nameBuf.count)
            let valLen = cocxycore_shell_integration_env_value(i, &valBuf, valBuf.count)
            if nameLen > 0, valLen > 0 {
                let name = String(bytes: nameBuf[0..<nameLen], encoding: .utf8) ?? ""
                let val = String(bytes: valBuf[0..<valLen], encoding: .utf8) ?? ""
                if !name.isEmpty {
                    env[name] = val
                }
            }
        }

        env["TERM"] = "xterm-256color"

        return env
    }

    // MARK: - Private: PTY Read Loop

    private func createReadSource(
        masterFd: Int32,
        terminal: OpaquePointer,
        pty: OpaquePointer,
        surfaceID: SurfaceID
    ) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(
            fileDescriptor: masterFd,
            queue: DispatchQueue.global(qos: .userInteractive)
        )

        source.setEventHandler { [weak self] in
            var buf = [UInt8](repeating: 0, count: Self.readBufferSize)
            let bytesRead = cocxycore_pty_read(pty, &buf, buf.count)

            guard bytesRead > 0 else { return }

            // Feed bytes through terminal pipeline (parser → executor → screen)
            cocxycore_terminal_feed(terminal, buf, bytesRead)

            // Write back any DSR/DECRQSS responses to the PTY
            var responseBuf = [UInt8](repeating: 0, count: Self.responseBufferSize)
            while cocxycore_terminal_has_response(terminal) {
                let rn = cocxycore_terminal_read_response(
                    terminal, &responseBuf, responseBuf.count
                )
                if rn > 0 {
                    cocxycore_pty_write(pty, responseBuf, rn)
                }
            }

            // Poll process tracker (non-blocking kqueue check)
            cocxycore_terminal_poll_processes(terminal)

            // Notify output handler with raw bytes
            let data = Data(bytes: buf, count: bytesRead)
            DispatchQueue.main.async { [weak self] in
                (self?.surfaces[surfaceID]?.hostView as? TerminalHostView)?.requestImmediateRedraw()
                self?.surfaces[surfaceID]?.outputHandler?(data)
            }
        }

        return source
    }

    // MARK: - Private: Callback Registration

    private func registerCallbacks(terminal: OpaquePointer, context: UnsafeMutableRawPointer) {
        // Title change (OSC 0/2)
        cocxycore_terminal_set_title_callback(terminal, { title, len, ctx in
            guard let ctx = ctx, let title = title, len > 0 else { return }
            let box = Unmanaged<CallbackContext>.fromOpaque(ctx).takeUnretainedValue()
            let str = String(
                bytes: UnsafeBufferPointer(start: title, count: len),
                encoding: .utf8
            ) ?? ""
            DispatchQueue.main.async {
                box.bridge?.dispatchOSC(.titleChange(str), for: box.surfaceID)
            }
        }, context)

        // Working directory change (OSC 7)
        cocxycore_terminal_set_cwd_callback(terminal, { cwd, len, ctx in
            guard let ctx = ctx, let cwd = cwd, len > 0 else { return }
            let box = Unmanaged<CallbackContext>.fromOpaque(ctx).takeUnretainedValue()
            let pathStr = String(
                bytes: UnsafeBufferPointer(start: cwd, count: len),
                encoding: .utf8
            ) ?? ""
            let url = URL(fileURLWithPath: pathStr, isDirectory: true)
            DispatchQueue.main.async {
                box.bridge?.dispatchOSC(.currentDirectory(url), for: box.surfaceID)
            }
        }, context)

        // Bell (BEL character)
        cocxycore_terminal_set_bell_callback(terminal, { ctx in
            guard let ctx = ctx else { return }
            let box = Unmanaged<CallbackContext>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                box.bridge?.dispatchOSC(
                    .notification(title: "Bell", body: "Terminal bell"),
                    for: box.surfaceID
                )
            }
        }, context)

        // Clipboard (OSC 52)
        cocxycore_terminal_set_clipboard_callback(terminal, { event, ctx in
            guard let ctx = ctx, let event = event else { return }
            let eventCopy = event.pointee
            let box = Unmanaged<CallbackContext>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                box.bridge?.handleClipboardEvent(eventCopy, for: box.surfaceID)
            }
        }, context)

        // Semantic events
        cocxycore_terminal_set_semantic_callback(terminal, { event, ctx in
            guard let ctx = ctx, let event = event else { return }
            let eventCopy = event.pointee
            let box = Unmanaged<CallbackContext>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                box.bridge?.handleSemanticEvent(eventCopy, for: box.surfaceID)
            }
        }, context)

        // Process tracking events
        cocxycore_terminal_set_process_callback(terminal, { event, ctx in
            guard let ctx = ctx, let event = event else { return }
            let eventCopy = event.pointee
            let box = Unmanaged<CallbackContext>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                box.bridge?.handleProcessEvent(eventCopy, for: box.surfaceID)
            }
        }, context)
    }

    // MARK: - Private: Callback Handlers

    private func dispatchOSC(_ notification: OSCNotification, for surfaceID: SurfaceID) {
        surfaces[surfaceID]?.oscHandler?(notification)
    }

    private func handleClipboardEvent(
        _ event: cocxycore_clipboard_event,
        for surfaceID: SurfaceID
    ) {
        guard let state = surfaces[surfaceID] else { return }

        if event.event_type == 0 {
            // Set clipboard (OSC 52 write)
            if let ptr = event.text_ptr, event.text_len > 0 {
                let text = String(
                    bytes: UnsafeBufferPointer(start: ptr, count: event.text_len),
                    encoding: .utf8
                ) ?? ""
                if !text.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
        } else {
            // Query clipboard (OSC 52 read) — respond with current clipboard content
            if let content = NSPasteboard.general.string(forType: .string) {
                let bytes = Array(content.utf8)
                var responseBuf = [UInt8](repeating: 0, count: bytes.count * 2 + 64)
                let n = cocxycore_terminal_encode_clipboard_response(
                    event.selection,
                    bytes,
                    bytes.count,
                    &responseBuf,
                    responseBuf.count
                )
                if n > 0 {
                    cocxycore_pty_write(state.pty, responseBuf, min(n, responseBuf.count))
                }
            }
        }
    }

    /// Handle semantic events from CocxyCore's AI layer.
    ///
    /// Routes shell integration events as OSCNotifications (prompt, command start/finish)
    /// AND feeds ALL event types to the semantic adapter for agent detection + timeline.
    private func handleSemanticEvent(
        _ event: cocxycore_semantic_event,
        for surfaceID: SurfaceID
    ) {
        // Shell integration → OSCNotification for existing tab wiring
        switch Int32(event.event_type) {
        case 0: // PROMPT_SHOWN
            dispatchOSC(.shellPrompt, for: surfaceID)
        case 1: // COMMAND_STARTED
            dispatchOSC(.commandStarted, for: surfaceID)
        case 2: // COMMAND_FINISHED
            let exitCode = event.exit_code >= 0 ? Int(event.exit_code) : nil
            dispatchOSC(.commandFinished(exitCode: exitCode), for: surfaceID)
        default:
            break
        }

        // ALL events → semantic adapter for agent detection + timeline
        let cwd = currentWorkingDirectory(for: surfaceID)
        semanticAdapter.processSemanticEvent(event, for: surfaceID, cwd: cwd)
    }

    /// Handle process tracking events from CocxyCore.
    ///
    /// Routes child exit as OSCNotification and feeds ALL events
    /// to the semantic adapter for subagent visualization.
    private func handleProcessEvent(
        _ event: cocxycore_process_event,
        for surfaceID: SurfaceID
    ) {
        if event.event_type == 1 { // CHILD_EXITED
            dispatchOSC(.processExited, for: surfaceID)
        }

        let cwd = currentWorkingDirectory(for: surfaceID)
        semanticAdapter.processProcessEvent(event, for: surfaceID, cwd: cwd)
    }

    /// Get the last known CWD for a surface (from tab model, if wired).
    /// Returns nil if not yet known.
    private var cwdProvider: ((SurfaceID) -> String?)?

    /// Set a closure that resolves surface ID to current working directory.
    /// Called by AppDelegate during wiring to connect tab CWD tracking.
    func setCwdProvider(_ provider: @escaping (SurfaceID) -> String?) {
        self.cwdProvider = provider
    }

    private func currentWorkingDirectory(for surfaceID: SurfaceID) -> String? {
        cwdProvider?(surfaceID)
    }

    // MARK: - Private: Key Mapping

    /// Map KeyModifiers to CocxyCore modifier bitmask.
    private func mapModifiers(_ mods: KeyModifiers) -> UInt8 {
        var result: UInt8 = 0
        if mods.contains(.shift)   { result |= 1 }  // COCXYCORE_MOD_SHIFT
        if mods.contains(.option)  { result |= 2 }  // COCXYCORE_MOD_ALT
        if mods.contains(.control) { result |= 4 }  // COCXYCORE_MOD_CTRL
        if mods.contains(.command) { result |= 8 }  // COCXYCORE_MOD_META
        return result
    }

    private func historyLineText(
        terminal: OpaquePointer,
        absoluteRow: UInt32,
        columnCount: UInt16
    ) -> String {
        guard columnCount > 0 else { return "" }

        var line = String()
        line.reserveCapacity(Int(columnCount))

        for col in 0..<columnCount {
            let codepoint = cocxycore_terminal_history_cell_char(terminal, absoluteRow, col)
            guard codepoint != 0 else { continue }
            if let scalar = UnicodeScalar(codepoint) {
                line.unicodeScalars.append(scalar)
            }
        }

        while line.last == " " {
            line.removeLast()
        }

        return line
    }

    // MARK: - Private: Color Parsing

    /// Parse a hex color string ("#RRGGBB" or "RRGGBB") to RGB components.
    static func parseHexColor(_ hex: String) -> (r: UInt8, g: UInt8, b: UInt8) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6,
              let value = UInt32(cleaned, radix: 16) else {
            return (0, 0, 0)
        }
        return (
            r: UInt8((value >> 16) & 0xFF),
            g: UInt8((value >> 8) & 0xFF),
            b: UInt8(value & 0xFF)
        )
    }

    /// Map macOS key codes to CocxyCore special key identifiers.
    /// Returns nil for printable keys (handled via encode_char).
    private func mapKeyCodeToSpecialKey(_ keyCode: UInt16) -> UInt8? {
        switch keyCode {
        case 126: return 0   // Up         → COCXYCORE_KEY_UP
        case 125: return 1   // Down       → COCXYCORE_KEY_DOWN
        case 124: return 2   // Right      → COCXYCORE_KEY_RIGHT
        case 123: return 3   // Left       → COCXYCORE_KEY_LEFT
        case 115: return 4   // Home       → COCXYCORE_KEY_HOME
        case 119: return 5   // End        → COCXYCORE_KEY_END
        case 114: return 6   // Insert     → COCXYCORE_KEY_INSERT
        case 117: return 7   // Delete     → COCXYCORE_KEY_DELETE
        case 116: return 8   // Page Up    → COCXYCORE_KEY_PAGE_UP
        case 121: return 9   // Page Down  → COCXYCORE_KEY_PAGE_DOWN
        case 122: return 10  // F1         → COCXYCORE_KEY_F1
        case 120: return 11  // F2         → COCXYCORE_KEY_F2
        case 99:  return 12  // F3         → COCXYCORE_KEY_F3
        case 118: return 13  // F4         → COCXYCORE_KEY_F4
        case 96:  return 14  // F5         → COCXYCORE_KEY_F5
        case 97:  return 15  // F6         → COCXYCORE_KEY_F6
        case 98:  return 16  // F7         → COCXYCORE_KEY_F7
        case 100: return 17  // F8         → COCXYCORE_KEY_F8
        case 101: return 18  // F9         → COCXYCORE_KEY_F9
        case 109: return 19  // F10        → COCXYCORE_KEY_F10
        case 103: return 20  // F11        → COCXYCORE_KEY_F11
        case 111: return 21  // F12        → COCXYCORE_KEY_F12
        case 51:  return 22  // Backspace  → COCXYCORE_KEY_BACKSPACE
        case 48:  return 23  // Tab        → COCXYCORE_KEY_TAB
        case 36:  return 24  // Enter      → COCXYCORE_KEY_ENTER
        case 53:  return 25  // Escape     → COCXYCORE_KEY_ESCAPE
        default:  return nil
        }
    }

    private static func environmentValue(for key: String) -> String? {
        guard let pointer = getenv(key) else { return nil }
        return String(cString: pointer)
    }
}
