// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyCoreBridge.swift - Bridge between CocxyCore C API and Swift.

import AppKit
import Darwin
import CocxyCoreKit

struct TerminalLigatureDiagnostics: Equatable, Sendable {
    let enabled: Bool
    let cacheHits: UInt32
    let cacheMisses: UInt32
}

struct TerminalImageDiagnostics: Equatable, Sendable {
    let imageCount: UInt32
    let memoryUsedBytes: UInt64
    let memoryLimitBytes: UInt64
    let fileTransferEnabled: Bool
    let sixelEnabled: Bool
    let kittyEnabled: Bool
    let atlasWidth: UInt32
    let atlasHeight: UInt32
    let atlasGeneration: UInt32
    let atlasDirty: Bool
}

struct TerminalImageSnapshot: Equatable, Sendable {
    let imageID: UInt32
    let width: UInt32
    let height: UInt32
    let byteSize: UInt32
    let source: UInt8
    let placementCount: UInt16
}

struct TerminalSearchDiagnostics: Equatable, Sendable {
    let gpuActive: Bool
    let indexedRows: UInt32
}

struct TerminalProtocolDiagnostics: Equatable, Sendable {
    let observed: Bool
    let capabilitiesRequested: Bool
    let currentStreamID: UInt32
}

struct TerminalModeDiagnostics: Equatable, Sendable {
    let cursorVisible: Bool
    let appCursorMode: Bool
    let altScreen: Bool
    let semanticBlockCount: UInt32
}

struct TerminalStreamSnapshot: Equatable, Sendable {
    let streamID: UInt32
    let pid: pid_t
    let parentPID: pid_t
    let state: UInt8
    let exitCode: Int16
}

struct WebTerminalConfiguration: Equatable, Sendable {
    let bindAddress: String
    let port: UInt16
    let authToken: String
    let maxConnections: UInt16
    let maxFrameRate: UInt32

    static let `default` = WebTerminalConfiguration(
        bindAddress: "127.0.0.1",
        port: 7770,
        authToken: "",
        maxConnections: 4,
        maxFrameRate: 60
    )
}

struct WebTerminalStatus: Equatable, Sendable {
    let running: Bool
    let bindAddress: String
    let port: UInt16
    let connectionCount: UInt16
    let authRequired: Bool
    let maxFrameRate: UInt32
    let lastEventType: String?
    let lastEventConnectionID: UInt16?
}

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
        struct WebServerState {
            let handle: OpaquePointer
            let bindAddress: String
            let authToken: String
            var maxFrameRate: UInt32
            var lastEventType: String?
            var lastEventConnectionID: UInt16?
        }

        let terminal: OpaquePointer      // cocxycore_terminal*
        let pty: OpaquePointer           // cocxycore_pty*
        let masterFD: Int32
        let childPID: pid_t
        let childProcessIdentity: TerminalProcessIdentity?
        let readSource: DispatchSourceRead
        let contextBox: Unmanaged<CallbackContext>
        /// Serializes access to the C terminal state between the PTY read
        /// loop (background queue, calls `cocxycore_terminal_feed`) and the
        /// render path (main thread, calls `cocxycore_terminal_build_frame`
        /// / `build_gpu_frame`). Without this serialization the C core can
        /// observe a half-written screen buffer and `build_frame` returns
        /// false, causing the renderer to drop the frame and leave the view
        /// transparent until another event re-triggers rendering.
        let terminalLock: NSLock
        weak var hostView: NSView?
        var lastKnownWorkingDirectory: URL?
        var lastFallbackWorkingDirectoryProbeAt: TimeInterval = 0
        var pendingFallbackWorkingDirectoryProbe: DispatchWorkItem?
        var lastReportedFocus: Bool?
        var webServer: WebServerState?
        var currentStreamID: UInt32 = 0
        var protocolV2Observed: Bool = false
        var protocolV2CapabilitiesRequested: Bool = false
        var configuredImageMemoryLimitBytes: UInt64 = 256 * 1024 * 1024
        var configuredImageFileTransferEnabled: Bool = false

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
    var clipboardService: any ClipboardServiceProtocol = SystemClipboardService()
    var clipboardReadAuthorizationHandler: ((NSWindow?) -> Bool)?

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

    /// When shell integration is absent, probe the PTY child cwd at a low rate
    /// so sidebar/session routing can still converge without polling every read.
    private static let fallbackWorkingDirectoryProbeInterval: TimeInterval = 0.35

    /// Context extracted around native search matches for UI display.
    private static let searchContextCharacterCount = 20

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

        guard cocxycore_terminal_attach_pty(terminal, pty) else {
            cocxycore_pty_destroy(pty)
            cocxycore_terminal_destroy(terminal)
            throw TerminalEngineError.surfaceCreationFailed(reason: "Failed to attach PTY to terminal")
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

        // Per-surface lock that serializes PTY feed (background) and frame
        // build (main thread) against the same C terminal state. Created
        // before the read source so the closure captures the same instance
        // stored in SurfaceState.
        let terminalLock = NSLock()

        let readSource = createReadSource(
            masterFd: masterFd,
            terminal: terminal,
            pty: pty,
            contextBox: contextBox,
            surfaceID: surfaceID,
            terminalLock: terminalLock
        )

        // 8. Store state
        surfaces[surfaceID] = SurfaceState(
            terminal: terminal,
            pty: pty,
            masterFD: masterFd,
            childPID: childPid,
            childProcessIdentity: processIdentity(for: childPid),
            readSource: readSource,
            contextBox: contextBox,
            terminalLock: terminalLock,
            hostView: view,
            lastKnownWorkingDirectory: (workingDirectory ?? config.workingDirectory).standardizedFileURL,
            lastReportedFocus: nil,
            configuredImageMemoryLimitBytes: config.imageMemoryLimitBytes,
            configuredImageFileTransferEnabled: config.imageFileTransferEnabled
        )

        applyFont(family: config.fontFamily, size: config.fontSize, to: surfaceID)
        readSource.resume()
        return surfaceID
    }

    func destroySurface(_ id: SurfaceID) {
        guard let state = surfaces.removeValue(forKey: id) else { return }

        state.pendingFallbackWorkingDirectoryProbe?.cancel()

        // Clean up semantic adapter state for this surface.
        semanticAdapter.surfaceDestroyed(id)

        if let webState = state.webServer {
            cocxycore_web_detach_terminal(webState.handle)
            cocxycore_web_stop(webState.handle)
            cocxycore_web_destroy(webState.handle)
        }

        // Resource teardown is deferred to the source's cancel handler so
        // any in-flight read callback drains before the raw pointers vanish.
        state.readSource.cancel()
    }

    @discardableResult
    func writeBytes(_ bytes: [UInt8], to surface: SurfaceID) -> Bool {
        guard let state = surfaces[surface], !bytes.isEmpty else { return false }
        return writeBytes(bytes, to: state)
    }

    @discardableResult
    private func writeBytes(_ bytes: [UInt8], to state: SurfaceState) -> Bool {
        writeAttachedPTYBytes(bytes, terminal: state.terminal, pty: state.pty) > 0
    }

    @discardableResult
    private func writeAttachedPTYBytes(
        _ bytes: [UInt8],
        terminal: OpaquePointer,
        pty: OpaquePointer
    ) -> Int {
        guard !bytes.isEmpty else { return 0 }

        let attachedWritten = bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return Int(cocxycore_terminal_write_attached_pty(terminal, baseAddress, buffer.count))
        }

        if attachedWritten > 0 {
            return attachedWritten
        }

        return bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return Int(cocxycore_pty_write(pty, baseAddress, buffer.count))
        }
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
            _ = writeBytes(Array(buf.prefix(bytesWritten)), to: state)
            return true
        }
        return false
    }

    func sendText(_ text: String, to surface: SurfaceID) {
        guard let state = surfaces[surface] else { return }
        let bytes = Array(text.utf8)
        if !bytes.isEmpty {
            _ = writeBytes(bytes, to: state)
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
            let displayWidth = Self.terminalDisplayWidth(of: text)
            cocxycore_terminal_preedit_set(
                state.terminal, row, col, bytes, bytes.count, displayWidth
            )
        }
    }

    func resize(_ surface: SurfaceID, to size: TerminalSize) {
        guard let state = surfaces[surface] else { return }
        cocxycore_terminal_resize(state.terminal, size.rows, size.columns)
        cocxycore_pty_resize(state.pty, size.rows, size.columns)
        if let webState = state.webServer {
            cocxycore_web_force_full_frame(webState.handle)
        }
        if state.protocolV2Observed {
            _ = sendProtocolV2Viewport(for: surface, requestID: nil)
        }
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

        if state.protocolV2Observed {
            _ = sendProtocolV2Viewport(for: surfaceID, requestID: nil)
        }
        (state.hostView as? TerminalHostView)?.requestImmediateRedraw()
    }

    func notifyFocus(_ focused: Bool, for surface: SurfaceID) {
        guard var state = surfaces[surface] else { return }
        guard state.lastReportedFocus != focused else { return }

        cocxycore_terminal_notify_focus(state.terminal, focused)
        state.lastReportedFocus = focused
        surfaces[surface] = state
        (state.hostView as? TerminalHostView)?.requestImmediateRedraw()
    }

    func searchScrollback(surfaceID: SurfaceID, options: SearchOptions) -> [SearchResult]? {
        guard let state = surfaces[surfaceID] else { return nil }
        guard !options.query.isEmpty else { return [] }
        guard let engine = cocxycore_gpu_search_init(state.terminal) else { return nil }
        defer { cocxycore_gpu_search_destroy(engine) }

        cocxycore_gpu_search_sync(engine, state.terminal)

        let cappedResultCount = max(1, min(options.maxResults, Int(UInt32.max)))
        var matches = Array(
            repeating: cocxycore_search_match(row: 0, start_col: 0, end_col: 0),
            count: cappedResultCount
        )
        var elapsedMicros: UInt64 = 0

        let matchCount = options.query.withCString { queryPtr in
            matches.withUnsafeMutableBufferPointer { buffer -> UInt32 in
                guard let baseAddress = buffer.baseAddress else { return 0 }
                return cocxycore_gpu_search_find(
                    engine,
                    state.terminal,
                    queryPtr,
                    UInt32(options.query.utf8.count),
                    options.useRegex,
                    !options.caseSensitive,
                    0,
                    0,
                    0,
                    UInt32(cappedResultCount),
                    baseAddress,
                    &elapsedMicros
                )
            }
        }

        guard matchCount > 0 else { return [] }

        let columnCount = cocxycore_terminal_cols(state.terminal)
        return matches.prefix(Int(matchCount)).map { match in
            let line = historyLineText(
                terminal: state.terminal,
                absoluteRow: match.row,
                columnCount: columnCount
            )
            return Self.makeSearchResult(
                line: line,
                lineNumber: Int(match.row),
                startColumn: Int(match.start_col),
                endColumnInclusive: Int(match.end_col),
                fallbackMatchText: options.query
            )
        }
    }

    // MARK: - Extended API (beyond TerminalEngine protocol)

    /// Access surface state for renderer and view integration (Block 2-3).
    func surfaceState(for id: SurfaceID) -> SurfaceState? {
        surfaces[id]
    }

    func processMonitorRegistration(for id: SurfaceID) -> TerminalProcessMonitorRegistration? {
        guard let state = surfaces[id],
              state.childPID > 0,
              state.masterFD >= 0 else {
            return nil
        }

        return TerminalProcessMonitorRegistration(
            shellPID: state.childPID,
            ptyMasterFD: state.masterFD,
            shellIdentity: state.childProcessIdentity
        )
    }

    func ligatureDiagnostics(for surface: SurfaceID) -> TerminalLigatureDiagnostics? {
        guard let state = surfaces[surface] else { return nil }
        return TerminalLigatureDiagnostics(
            enabled: cocxycore_terminal_get_ligatures(state.terminal),
            cacheHits: cocxycore_ligature_cache_hits(state.terminal),
            cacheMisses: cocxycore_ligature_cache_misses(state.terminal)
        )
    }

    func applyLigaturesEnabled(_ enabled: Bool) {
        updateDefaults(ligaturesEnabled: enabled)
        for surface in surfaces.keys {
            applyLigaturesEnabled(enabled, to: surface)
        }
    }

    func applyLigaturesEnabled(_ enabled: Bool, to surface: SurfaceID) {
        guard let state = surfaces[surface] else { return }
        cocxycore_terminal_set_ligatures(state.terminal, enabled)
        if let webState = state.webServer {
            cocxycore_web_force_full_frame(webState.handle)
        }
        (state.hostView as? TerminalHostView)?.updateInteractionMetrics()
        (state.hostView as? TerminalHostView)?.requestImmediateRedraw()
    }

    func imageDiagnostics(for surface: SurfaceID) -> TerminalImageDiagnostics? {
        guard let state = surfaces[surface] else { return nil }
        var atlasInfo = cocxycore_image_atlas_info()
        let hasAtlasInfo = cocxycore_image_get_atlas_info(state.terminal, &atlasInfo)
        return TerminalImageDiagnostics(
            imageCount: cocxycore_image_count(state.terminal),
            memoryUsedBytes: cocxycore_image_memory_used(state.terminal),
            memoryLimitBytes: state.configuredImageMemoryLimitBytes,
            fileTransferEnabled: state.configuredImageFileTransferEnabled,
            sixelEnabled: cocxycore_image_sixel_enabled(state.terminal),
            kittyEnabled: cocxycore_image_kitty_enabled(state.terminal),
            atlasWidth: hasAtlasInfo ? atlasInfo.width : 0,
            atlasHeight: hasAtlasInfo ? atlasInfo.height : 0,
            atlasGeneration: hasAtlasInfo ? atlasInfo.generation : 0,
            atlasDirty: hasAtlasInfo ? atlasInfo.dirty : false
        )
    }

    func imageSnapshots(for surface: SurfaceID) -> [TerminalImageSnapshot] {
        guard let state = surfaces[surface] else { return [] }
        let count = cocxycore_image_count(state.terminal)
        guard count > 0 else { return [] }

        var snapshots: [TerminalImageSnapshot] = []
        snapshots.reserveCapacity(Int(count))
        for index in 0..<count {
            var info = cocxycore_image_info()
            guard cocxycore_image_get_info_at(state.terminal, index, &info) else { continue }
            snapshots.append(
                TerminalImageSnapshot(
                    imageID: info.image_id,
                    width: info.width,
                    height: info.height,
                    byteSize: info.byte_size,
                    source: info.source,
                    placementCount: info.placement_count
                )
            )
        }
        return snapshots.sorted { $0.imageID < $1.imageID }
    }

    func applyImageSettings(
        memoryLimitBytes: UInt64,
        fileTransferEnabled: Bool,
        sixelEnabled: Bool,
        kittyEnabled: Bool
    ) {
        updateDefaults(
            imageMemoryLimitBytes: memoryLimitBytes,
            imageFileTransferEnabled: fileTransferEnabled,
            sixelImagesEnabled: sixelEnabled,
            kittyImagesEnabled: kittyEnabled
        )
        for surface in surfaces.keys {
            applyImageSettings(
                memoryLimitBytes: memoryLimitBytes,
                fileTransferEnabled: fileTransferEnabled,
                sixelEnabled: sixelEnabled,
                kittyEnabled: kittyEnabled,
                to: surface
            )
        }
    }

    func applyImageSettings(
        memoryLimitBytes: UInt64,
        fileTransferEnabled: Bool,
        sixelEnabled: Bool,
        kittyEnabled: Bool,
        to surface: SurfaceID
    ) {
        guard var state = surfaces[surface] else { return }
        cocxycore_image_set_memory_limit(state.terminal, memoryLimitBytes)
        cocxycore_image_set_file_transfer(state.terminal, fileTransferEnabled)
        cocxycore_image_enable_sixel(state.terminal, sixelEnabled)
        cocxycore_image_enable_kitty(state.terminal, kittyEnabled)
        state.configuredImageMemoryLimitBytes = memoryLimitBytes
        state.configuredImageFileTransferEnabled = fileTransferEnabled
        surfaces[surface] = state
        if let webState = state.webServer {
            cocxycore_web_force_full_frame(webState.handle)
        }
        (state.hostView as? TerminalHostView)?.requestImmediateRedraw()
    }

    func searchDiagnostics(for surface: SurfaceID) -> TerminalSearchDiagnostics? {
        guard let state = surfaces[surface] else { return nil }
        guard let engine = cocxycore_gpu_search_init(state.terminal) else { return nil }
        defer { cocxycore_gpu_search_destroy(engine) }
        cocxycore_gpu_search_sync(engine, state.terminal)
        return TerminalSearchDiagnostics(
            gpuActive: cocxycore_gpu_search_is_gpu_active(engine),
            indexedRows: cocxycore_gpu_search_indexed_rows(engine)
        )
    }

    func streamSnapshots(for surface: SurfaceID) -> [TerminalStreamSnapshot] {
        guard let state = surfaces[surface] else { return [] }
        let count = cocxycore_terminal_stream_count(state.terminal)
        guard count > 0 else { return [] }

        return (1...count).compactMap { streamID in
            var info = cocxycore_process_info()
            guard cocxycore_terminal_stream_info(state.terminal, streamID, &info) else { return nil }
            return TerminalStreamSnapshot(
                streamID: info.stream_id,
                pid: info.pid,
                parentPID: info.parent_pid,
                state: info.state,
                exitCode: info.exit_code
            )
        }.sorted { $0.streamID < $1.streamID }
    }

    func protocolDiagnostics(for surface: SurfaceID) -> TerminalProtocolDiagnostics? {
        guard let state = surfaces[surface] else { return nil }
        return TerminalProtocolDiagnostics(
            observed: state.protocolV2Observed,
            capabilitiesRequested: state.protocolV2CapabilitiesRequested,
            currentStreamID: state.currentStreamID
        )
    }

    func modeDiagnostics(for surface: SurfaceID) -> TerminalModeDiagnostics? {
        guard let state = surfaces[surface] else { return nil }
        return TerminalModeDiagnostics(
            cursorVisible: cocxycore_terminal_cursor_visible(state.terminal),
            appCursorMode: cocxycore_terminal_mode_app_cursor(state.terminal),
            altScreen: cocxycore_terminal_is_alt_screen(state.terminal),
            semanticBlockCount: cocxycore_terminal_semantic_block_count(state.terminal)
        )
    }

    @discardableResult
    func setCurrentStream(_ streamID: UInt32, for surface: SurfaceID) -> Bool {
        guard var state = surfaces[surface] else { return false }
        cocxycore_terminal_set_current_stream(state.terminal, streamID)
        state.currentStreamID = streamID
        surfaces[surface] = state
        return true
    }

    @discardableResult
    func syncCurrentStreamWithForegroundProcess(pid: pid_t, for surface: SurfaceID) -> UInt32? {
        guard pid > 0 else {
            _ = setCurrentStream(0, for: surface)
            return 0
        }

        let snapshots = streamSnapshots(for: surface)
        let matchedStream = snapshots.first { $0.pid == pid }?.streamID ?? 0
        _ = setCurrentStream(matchedStream, for: surface)
        return matchedStream
    }

    @discardableResult
    func requestProtocolV2Capabilities(for surface: SurfaceID) -> Bool {
        guard var state = surfaces[surface] else { return false }
        var buf = [UInt8](repeating: 0, count: 2048)
        let bytesWritten = cocxycore_terminal_request_capabilities(state.terminal, &buf, buf.count)
        guard bytesWritten > 0 else { return false }
        _ = writeBytes(Array(buf.prefix(bytesWritten)), to: state)
        state.protocolV2CapabilitiesRequested = true
        surfaces[surface] = state
        return true
    }

    @discardableResult
    func sendProtocolV2Viewport(for surface: SurfaceID, requestID: String?) -> Bool {
        guard let state = surfaces[surface] else { return false }
        var buf = [UInt8](repeating: 0, count: 2048)
        let bytesWritten = (requestID ?? "").withCString { requestIDPtr in
            cocxycore_terminal_generate_viewport(
                state.terminal,
                &buf,
                buf.count,
                requestIDPtr,
                requestID?.utf8.count ?? 0
            )
        }
        guard bytesWritten > 0 else { return false }
        _ = writeBytes(Array(buf.prefix(bytesWritten)), to: state)
        return true
    }

    @discardableResult
    func sendProtocolV2Message(type: String, json: String, to surface: SurfaceID) -> Bool {
        guard let state = surfaces[surface], !type.isEmpty else { return false }
        var buf = [UInt8](repeating: 0, count: 4096)
        let bytesWritten = type.withCString { typePtr in
            json.withCString { jsonPtr in
                cocxycore_terminal_send_protocol_v2(
                    state.terminal,
                    typePtr,
                    type.utf8.count,
                    jsonPtr,
                    json.utf8.count,
                    &buf,
                    buf.count
                )
            }
        }
        guard bytesWritten > 0 else { return false }
        _ = writeBytes(Array(buf.prefix(bytesWritten)), to: state)
        return true
    }

    @discardableResult
    func clearImages(for surface: SurfaceID) -> UInt32? {
        guard let state = surfaces[surface] else { return nil }
        let removed = cocxycore_image_count(state.terminal)
        cocxycore_image_delete_all(state.terminal)
        if let webState = state.webServer {
            cocxycore_web_force_full_frame(webState.handle)
        }
        (state.hostView as? TerminalHostView)?.requestImmediateRedraw()
        return removed
    }

    @discardableResult
    func deleteImage(_ imageID: UInt32, for surface: SurfaceID) -> Bool {
        guard let state = surfaces[surface] else { return false }
        var info = cocxycore_image_info()
        guard cocxycore_image_get_info(state.terminal, imageID, &info) else { return false }
        cocxycore_image_delete(state.terminal, imageID)
        guard !cocxycore_image_get_info(state.terminal, imageID, &info) else { return false }
        if let webState = state.webServer {
            cocxycore_web_force_full_frame(webState.handle)
        }
        (state.hostView as? TerminalHostView)?.requestImmediateRedraw()
        return true
    }

    func webTerminalStatus(for surface: SurfaceID) -> WebTerminalStatus? {
        guard let state = surfaces[surface], let webState = state.webServer else { return nil }
        return makeWebTerminalStatus(from: webState)
    }

    @discardableResult
    func startWebTerminal(
        for surface: SurfaceID,
        configuration: WebTerminalConfiguration = .default
    ) -> WebTerminalStatus? {
        guard var state = surfaces[surface] else { return nil }

        if let existing = state.webServer {
            if existing.bindAddress != configuration.bindAddress || existing.authToken != configuration.authToken {
                destroyWebServer(existing)
                state.webServer = nil
            } else {
                cocxycore_web_set_max_fps(existing.handle, configuration.maxFrameRate)
                if cocxycore_web_is_running(existing.handle) {
                    var updated = existing
                    updated.maxFrameRate = configuration.maxFrameRate
                    state.webServer = updated
                    surfaces[surface] = state
                    cocxycore_web_force_full_frame(existing.handle)
                    return makeWebTerminalStatus(from: updated)
                }
                destroyWebServer(existing)
                state.webServer = nil
            }
        }

        var webConfig = cocxycore_web_config()
        Self.writeCString(configuration.bindAddress, into: &webConfig.bind_address, maxBytes: 64)
        webConfig.bind_address_len = UInt32(configuration.bindAddress.utf8.count)
        webConfig.port = configuration.port
        Self.writeCString(configuration.authToken, into: &webConfig.auth_token, maxBytes: 128)
        webConfig.auth_token_len = UInt32(configuration.authToken.utf8.count)
        webConfig.max_connections = configuration.maxConnections
        webConfig.max_frame_rate = configuration.maxFrameRate

        guard let server = cocxycore_web_create(&webConfig) else { return nil }
        cocxycore_web_set_event_callback(server, { eventType, connectionID, ctx in
            guard let ctx else { return }
            let box = Unmanaged<CallbackContext>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                box.bridge?.handleWebTerminalEvent(
                    eventType: eventType,
                    connectionID: connectionID,
                    for: box.surfaceID
                )
            }
        }, state.contextBox.toOpaque())

        guard cocxycore_web_attach_terminal(server, state.terminal) else {
            cocxycore_web_destroy(server)
            return nil
        }
        cocxycore_web_set_max_fps(server, configuration.maxFrameRate)
        guard cocxycore_web_start(server) else {
            cocxycore_web_detach_terminal(server)
            cocxycore_web_destroy(server)
            return nil
        }

        state.webServer = SurfaceState.WebServerState(
            handle: server,
            bindAddress: configuration.bindAddress,
            authToken: configuration.authToken,
            maxFrameRate: configuration.maxFrameRate,
            lastEventType: nil,
            lastEventConnectionID: nil
        )
        surfaces[surface] = state
        cocxycore_web_force_full_frame(server)
        return state.webServer.map(makeWebTerminalStatus(from:))
    }

    func stopWebTerminal(for surface: SurfaceID) {
        guard var state = surfaces[surface], let webState = state.webServer else { return }
        destroyWebServer(webState)
        state.webServer = nil
        surfaces[surface] = state
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

        if state.protocolV2Observed {
            _ = sendProtocolV2Viewport(for: surfaceID, requestID: nil)
        }
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
        if let webState = state.webServer {
            cocxycore_web_force_full_frame(webState.handle)
        }
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
        windowPaddingY: Double? = nil,
        clipboardReadAccess: ClipboardReadAccess? = nil,
        ligaturesEnabled: Bool? = nil,
        imageMemoryLimitBytes: UInt64? = nil,
        imageFileTransferEnabled: Bool? = nil,
        sixelImagesEnabled: Bool? = nil,
        kittyImagesEnabled: Bool? = nil
    ) {
        guard let currentConfig = config else { return }
        config = currentConfig.replacing(
            fontFamily: fontFamily,
            fontSize: fontSize,
            themeName: themeName,
            shell: shell,
            themePalette: themePalette,
            windowPaddingX: windowPaddingX,
            windowPaddingY: windowPaddingY,
            clipboardReadAccess: clipboardReadAccess,
            ligaturesEnabled: ligaturesEnabled,
            imageMemoryLimitBytes: imageMemoryLimitBytes,
            imageFileTransferEnabled: imageFileTransferEnabled,
            sixelImagesEnabled: sixelImagesEnabled,
            kittyImagesEnabled: kittyImagesEnabled
        )
    }

    /// Apply a font change to all live surfaces and future surfaces.
    func applyFont(family: String, size: Double) {
        updateDefaults(fontFamily: family, fontSize: size)

        for surfaceID in surfaces.keys {
            applyFont(family: family, size: size, to: surfaceID)
        }
    }

    /// Apply a font change to a specific live surface only.
    func applyFont(family: String, size: Double, to surface: SurfaceID) {
        guard let state = surfaces[surface] else { return }
        let scale = Float(
            state.hostView?.window?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor
                ?? 2.0
        )
        _ = applyResolvedFont(
            family: family,
            size: Float(size),
            scale: scale,
            ligaturesEnabled: config?.ligaturesEnabled ?? true,
            to: state.terminal
        )
        if let webState = state.webServer {
            cocxycore_web_force_full_frame(webState.handle)
        }
        (state.hostView as? TerminalHostView)?.updateInteractionMetrics()
        (state.hostView as? TerminalHostView)?.requestImmediateRedraw()
    }

    /// Reapplies the currently configured default font to a surface using the
    /// surface's live backing scale when available.
    ///
    /// This helps newly attached/restored surfaces and moved windows pick up
    /// the correct raster scale instead of relying on whichever screen was
    /// active when the terminal was first created.
    func reapplyConfiguredFont(to surface: SurfaceID) {
        guard let config else { return }
        applyFont(family: config.fontFamily, size: config.fontSize, to: surface)
    }

    /// Apply the same font change to a batch of surfaces.
    func applyFont(family: String, size: Double, to surfaces: [SurfaceID]) {
        for surface in surfaces {
            applyFont(family: family, size: size, to: surface)
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
        _ = applyResolvedFont(
            family: config.fontFamily,
            size: Float(config.fontSize),
            scale: Float(NSScreen.main?.backingScaleFactor ?? 2.0),
            ligaturesEnabled: config.ligaturesEnabled,
            to: terminal
        )

        cocxycore_image_set_memory_limit(terminal, config.imageMemoryLimitBytes)
        cocxycore_image_set_file_transfer(terminal, config.imageFileTransferEnabled)
        cocxycore_image_enable_sixel(terminal, config.sixelImagesEnabled)
        cocxycore_image_enable_kitty(terminal, config.kittyImagesEnabled)

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
        // INVARIANT: This method mutates global process state (cwd, env vars)
        // and MUST run on the main actor to prevent concurrent access.
        // @MainActor on the class guarantees serialization for now.
        dispatchPrecondition(condition: .onQueue(.main))

        // CocxyCore's current C API inherits cwd/env from the host process at
        // fork time. Scope those mutations carefully and restore them
        // immediately after spawn so other modules/windows do not observe them.
        let previousCwd = FileManager.default.currentDirectoryPath
        let envVars = buildShellIntegrationEnvVars(forShell: shell)
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
    func buildShellIntegrationEnvVars(
        forShell shell: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        resourcesPath: String? = nil
    ) -> [String: String] {
        let resolvedResourcesPath = resourcesPath ?? resolveResourcesPath()
        return Self.makeShellIntegrationEnvVars(
            forShell: shell,
            environment: environment,
            resourcesPath: resolvedResourcesPath
        )
    }

    private func resolveResourcesPath() -> String? {
        let fileManager = FileManager.default

        if let bundleResources = Bundle.main.resourceURL?.path,
           fileManager.fileExists(atPath: bundleResources) {
            return bundleResources
        }

        let sourceResources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Infrastructure
            .deletingLastPathComponent()   // Core
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Resources", isDirectory: true)
            .path

        if fileManager.fileExists(atPath: sourceResources) {
            return sourceResources
        }

        return nil
    }

    private static func makeShellIntegrationEnvVars(
        forShell shell: String,
        environment: [String: String],
        resourcesPath: String?
    ) -> [String: String] {
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

        guard let resourcesPath else {
            return env
        }

        let shellIntegrationRoot = URL(fileURLWithPath: resourcesPath, isDirectory: true)
            .appendingPathComponent("shell-integration", isDirectory: true)
        let shellName = URL(fileURLWithPath: shell).lastPathComponent.lowercased()
        let fileManager = FileManager.default

        env["COCXY_RESOURCES_DIR"] = resourcesPath
        env["COCXY_SHELL_INTEGRATION_DIR"] = shellIntegrationRoot.path
        env["COCXY_SHELL_FEATURES"] = "marks,cwd,title"

        switch shellName {
        case "zsh":
            let zshIntegrationDir = shellIntegrationRoot
                .appendingPathComponent("zsh", isDirectory: true)
            guard fileManager.fileExists(atPath: zshIntegrationDir.path) else {
                return env
            }

            env["ZDOTDIR"] = zshIntegrationDir.path
            if let originalZdotdir = environment["ZDOTDIR"] {
                env["COCXY_ZSH_ORIG_ZDOTDIR"] = originalZdotdir
            }

        case "bash":
            let bashIntegrationDir = shellIntegrationRoot
                .appendingPathComponent("bash", isDirectory: true)
            let bashBootstrap = bashIntegrationDir
                .appendingPathComponent(".bashrc", isDirectory: false)
            guard fileManager.fileExists(atPath: bashIntegrationDir.path),
                  fileManager.fileExists(atPath: bashBootstrap.path) else {
                return env
            }

            if let originalHome = environment["HOME"], !originalHome.isEmpty {
                env["COCXY_BASH_ORIG_HOME"] = originalHome
            }
            env["HOME"] = bashIntegrationDir.path

        case "fish":
            let fishIntegrationDir = shellIntegrationRoot
                .appendingPathComponent("fish", isDirectory: true)
            let fishConfig = fishIntegrationDir
                .appendingPathComponent("config.fish", isDirectory: false)
            let fishScript = fishIntegrationDir
                .appendingPathComponent("cocxy.fish", isDirectory: false)
            guard fileManager.fileExists(atPath: fishIntegrationDir.path),
                  fileManager.fileExists(atPath: fishConfig.path),
                  fileManager.fileExists(atPath: fishScript.path) else {
                return env
            }

            if let originalXDGConfigHome = environment["XDG_CONFIG_HOME"],
               !originalXDGConfigHome.isEmpty {
                env["COCXY_FISH_ORIG_XDG_CONFIG_HOME"] = originalXDGConfigHome
            }
            if let originalHome = environment["HOME"], !originalHome.isEmpty {
                env["COCXY_FISH_ORIG_HOME"] = originalHome
            }
            env["XDG_CONFIG_HOME"] = shellIntegrationRoot.path

        default:
            break
        }

        return env
    }

    // MARK: - Private: PTY Read Loop

    private func createReadSource(
        masterFd: Int32,
        terminal: OpaquePointer,
        pty: OpaquePointer,
        contextBox: Unmanaged<CallbackContext>,
        surfaceID: SurfaceID,
        terminalLock: NSLock
    ) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(
            fileDescriptor: masterFd,
            queue: DispatchQueue.global(qos: .userInteractive)
        )

        source.setEventHandler { [weak self] in
            var buf = [UInt8](repeating: 0, count: Self.readBufferSize)
            let bytesRead = cocxycore_pty_read(pty, &buf, buf.count)

            guard bytesRead > 0 else { return }

            // Serialize all C terminal mutation against the render path.
            // The renderer (main thread) calls cocxycore_terminal_build_frame
            // which reads the same internal state we mutate here with feed,
            // response drain, and process poll. Holding the lock across all
            // three is cheap (per-surface, no contention outside the frame
            // boundary) and keeps the C core consistent from the renderer's
            // point of view.
            terminalLock.lock()

            // Feed bytes through terminal pipeline (parser → executor → screen)
            cocxycore_terminal_feed(terminal, buf, bytesRead)

            // Write back any DSR/DECRQSS responses to the PTY
            var responseBuf = [UInt8](repeating: 0, count: Self.responseBufferSize)
            while cocxycore_terminal_has_response(terminal) {
                let rn = cocxycore_terminal_read_response(
                    terminal, &responseBuf, responseBuf.count
                )
                if rn > 0 {
                    _ = self?.writeAttachedPTYBytes(
                        Array(responseBuf.prefix(rn)),
                        terminal: terminal,
                        pty: pty
                    )
                }
            }

            // Poll process tracker (non-blocking kqueue check)
            cocxycore_terminal_poll_processes(terminal)

            terminalLock.unlock()

            // Notify output handler with raw bytes
            let data = Data(bytes: buf, count: bytesRead)
            DispatchQueue.main.async { [weak self] in
                (self?.surfaces[surfaceID]?.hostView as? TerminalHostView)?.requestImmediateRedraw()
                self?.surfaces[surfaceID]?.outputHandler?(data)
                self?.probeWorkingDirectoryAfterOutputIfNeeded(for: surfaceID)
            }
        }

        source.setCancelHandler {
            cocxycore_terminal_detach_pty(terminal)
            cocxycore_pty_destroy(pty)
            cocxycore_terminal_destroy(terminal)
            contextBox.release()
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
            guard let url = box.bridge?.parseWorkingDirectoryURL(pathStr) else { return }
            DispatchQueue.main.async {
                guard let bridge = box.bridge,
                      bridge.trackWorkingDirectory(url, for: box.surfaceID) else { return }
                bridge.dispatchOSC(.currentDirectory(url), for: box.surfaceID)
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

        // Structured Protocol v2 events (OSC 7770)
        cocxycore_terminal_set_protocol_v2_callback(terminal, { msgType, msgTypeLen, payload, payloadLen, ctx in
            guard let ctx = ctx,
                  let msgType = msgType,
                  let payload = payload else { return }
            let box = Unmanaged<CallbackContext>.fromOpaque(ctx).takeUnretainedValue()
            let type = String(
                bytes: UnsafeBufferPointer(
                    start: UnsafeRawPointer(msgType).assumingMemoryBound(to: UInt8.self),
                    count: msgTypeLen
                ),
                encoding: .utf8
            ) ?? ""
            let json = String(
                bytes: UnsafeBufferPointer(
                    start: UnsafeRawPointer(payload).assumingMemoryBound(to: UInt8.self),
                    count: payloadLen
                ),
                encoding: .utf8
            ) ?? ""
            guard !type.isEmpty, !json.isEmpty else { return }
            DispatchQueue.main.async {
                box.bridge?.handleProtocolV2Message(type: type, payload: json, for: box.surfaceID)
            }
        }, context)
    }

    func parseWorkingDirectoryURL(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let parsed = URL(string: trimmed), parsed.isFileURL {
            return parsed.standardizedFileURL
        }

        return URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL
    }

    @discardableResult
    private func applyResolvedFont(
        family: String,
        size: Float,
        scale: Float,
        ligaturesEnabled: Bool,
        to terminal: OpaquePointer
    ) -> String {
        for candidate in FontFallbackResolver.fallbackChain(for: family) {
            guard FontFallbackResolver.isFontAvailable(candidate) else { continue }

            let applied = candidate.withCString { familyPtr in
                cocxycore_terminal_set_font(
                    terminal,
                    familyPtr,
                    size,
                    scale,
                    ligaturesEnabled
                )
            }

            if applied {
                return candidate
            }
        }

        return family
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
                    clipboardService.write(text)
                }
            }
        } else {
            handleClipboardReadRequest(event, state: state)
        }
    }

    private func handleClipboardReadRequest(
        _ event: cocxycore_clipboard_event,
        state: SurfaceState
    ) {
        let content = resolvedClipboardReadContent(for: state.hostView?.window)
        sendClipboardResponse(selection: event.selection, content: content, to: state)
    }

    func resolvedClipboardReadContent(for window: NSWindow?) -> String {
        switch config?.clipboardReadAccess ?? .prompt {
        case .allow:
            return clipboardService.read() ?? ""
        case .deny:
            return ""
        case .prompt:
            guard requestClipboardReadAuthorization(for: window) else {
                return ""
            }
            return clipboardService.read() ?? ""
        }
    }

    private func requestClipboardReadAuthorization(for window: NSWindow?) -> Bool {
        if let handler = clipboardReadAuthorizationHandler {
            return handler(window)
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Allow clipboard read?"
        alert.informativeText = """
        A terminal program requested access to the system clipboard via OSC 52.
        Allowing this will send your current clipboard contents to the running shell.
        """
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Deny")

        if let window {
            window.makeKeyAndOrderFront(nil)
        }

        return alert.runModal() == .alertFirstButtonReturn
    }

    private func sendClipboardResponse(
        selection: UInt8,
        content: String,
        to state: SurfaceState
    ) {
        let bytes = Array(content.utf8)
        var responseBuf = [UInt8](repeating: 0, count: max(bytes.count * 2 + 64, 64))
        let n = cocxycore_terminal_encode_clipboard_response(
            selection,
            bytes,
            bytes.count,
            &responseBuf,
            responseBuf.count
        )
        guard n > 0 else { return }
        _ = writeBytes(Array(responseBuf.prefix(min(n, responseBuf.count))), to: state)
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
            emitFallbackWorkingDirectoryIfNeeded(for: surfaceID)
            scheduleFallbackWorkingDirectoryProbe(for: surfaceID, delay: 0.12)
            dispatchOSC(.shellPrompt, for: surfaceID)
        case 1: // COMMAND_STARTED
            dispatchOSC(.commandStarted, for: surfaceID)
        case 2: // COMMAND_FINISHED
            emitFallbackWorkingDirectoryIfNeeded(for: surfaceID)
            scheduleFallbackWorkingDirectoryProbe(for: surfaceID, delay: 0.12)
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

    private func handleProtocolV2Message(type: String, payload: String, for surfaceID: SurfaceID) {
        if var state = surfaces[surfaceID] {
            let firstObservation = !state.protocolV2Observed
            state.protocolV2Observed = true
            surfaces[surfaceID] = state
            if firstObservation {
                _ = requestProtocolV2Capabilities(for: surfaceID)
                _ = sendProtocolV2Viewport(for: surfaceID, requestID: nil)
            }
        }

        let cwd = currentWorkingDirectory(for: surfaceID)
        semanticAdapter.processProtocolV2Message(
            type: type,
            payload: payload,
            for: surfaceID,
            cwd: cwd
        )
    }

    private func handleWebTerminalEvent(
        eventType: UInt8,
        connectionID: UInt16,
        for surfaceID: SurfaceID
    ) {
        guard var state = surfaces[surfaceID], var webState = state.webServer else { return }
        switch eventType {
        case 0:
            webState.lastEventType = "connect"
        case 1:
            webState.lastEventType = "disconnect"
        case 2:
            webState.lastEventType = "auth_fail"
        default:
            webState.lastEventType = "unknown"
        }
        webState.lastEventConnectionID = connectionID
        state.webServer = webState
        surfaces[surfaceID] = state
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
        if let cwd = surfaces[surfaceID]?.lastKnownWorkingDirectory?.path {
            return cwd
        }
        return cwdProvider?(surfaceID)
    }

    @discardableResult
    private func trackWorkingDirectory(_ url: URL, for surfaceID: SurfaceID) -> Bool {
        guard var state = surfaces[surfaceID] else { return false }
        let normalized = url.standardizedFileURL
        guard state.lastKnownWorkingDirectory != normalized else { return false }
        state.lastKnownWorkingDirectory = normalized
        surfaces[surfaceID] = state
        return true
    }

    private func emitFallbackWorkingDirectoryIfNeeded(for surfaceID: SurfaceID) {
        guard let url = inferredWorkingDirectory(for: surfaceID),
              trackWorkingDirectory(url, for: surfaceID) else {
            return
        }
        dispatchOSC(.currentDirectory(url), for: surfaceID)
    }

    private func probeWorkingDirectoryAfterOutputIfNeeded(for surfaceID: SurfaceID) {
        guard var state = surfaces[surfaceID] else { return }
        let now = Date.timeIntervalSinceReferenceDate
        guard now - state.lastFallbackWorkingDirectoryProbeAt >= Self.fallbackWorkingDirectoryProbeInterval else {
            return
        }

        state.lastFallbackWorkingDirectoryProbeAt = now
        surfaces[surfaceID] = state
        emitFallbackWorkingDirectoryIfNeeded(for: surfaceID)
        scheduleFallbackWorkingDirectoryProbe(for: surfaceID, delay: 0.12)
    }

    private func scheduleFallbackWorkingDirectoryProbe(
        for surfaceID: SurfaceID,
        delay: TimeInterval
    ) {
        guard var state = surfaces[surfaceID] else { return }
        state.pendingFallbackWorkingDirectoryProbe?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.emitFallbackWorkingDirectoryIfNeeded(for: surfaceID)
            if var refreshed = self.surfaces[surfaceID] {
                refreshed.pendingFallbackWorkingDirectoryProbe = nil
                self.surfaces[surfaceID] = refreshed
            }
        }

        state.pendingFallbackWorkingDirectoryProbe = workItem
        surfaces[surfaceID] = state

        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func inferredWorkingDirectory(for surfaceID: SurfaceID) -> URL? {
        guard let state = surfaces[surfaceID],
              let pid = verifiedChildPID(for: state) else {
            return nil
        }

        var info = proc_vnodepathinfo()
        let result = proc_pidinfo(
            pid,
            PROC_PIDVNODEPATHINFO,
            0,
            &info,
            Int32(MemoryLayout.size(ofValue: info))
        )
        guard result == Int32(MemoryLayout.size(ofValue: info)) else { return nil }

        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { pathPtr in
            let cString = UnsafeRawPointer(pathPtr).assumingMemoryBound(to: CChar.self)
            let path = String(cString: cString).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }
    }

    private func verifiedChildPID(for state: SurfaceState) -> pid_t? {
        guard state.childPID > 0 else { return nil }

        var waitResult = cocxycore_pty_wait_result()
        _ = cocxycore_pty_wait_check(state.pty, &waitResult)
        guard cocxycore_pty_is_alive(state.pty) else { return nil }

        guard let currentIdentity = processIdentity(for: state.childPID) else { return nil }
        if let expectedIdentity = state.childProcessIdentity,
           currentIdentity != expectedIdentity {
            return nil
        }

        return state.childPID
    }

    private func processIdentity(for pid: pid_t) -> TerminalProcessIdentity? {
        guard pid > 0 else { return nil }

        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout.size(ofValue: info))
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expectedSize)
        guard result == expectedSize else { return nil }

        return TerminalProcessIdentity(
            pid: pid,
            startSeconds: UInt64(info.pbi_start_tvsec),
            startMicroseconds: UInt64(info.pbi_start_tvusec)
        )
    }

    private func destroyWebServer(_ webState: SurfaceState.WebServerState) {
        cocxycore_web_detach_terminal(webState.handle)
        cocxycore_web_stop(webState.handle)
        cocxycore_web_destroy(webState.handle)
    }

    private func makeWebTerminalStatus(from webState: SurfaceState.WebServerState) -> WebTerminalStatus {
        WebTerminalStatus(
            running: cocxycore_web_is_running(webState.handle),
            bindAddress: webState.bindAddress,
            port: cocxycore_web_port(webState.handle),
            connectionCount: cocxycore_web_connection_count(webState.handle),
            authRequired: !webState.authToken.isEmpty,
            maxFrameRate: webState.maxFrameRate,
            lastEventType: webState.lastEventType,
            lastEventConnectionID: webState.lastEventConnectionID
        )
    }

    private static func writeCString<T>(
        _ string: String,
        into buffer: inout T,
        maxBytes: Int
    ) {
        withUnsafeMutableBytes(of: &buffer) { rawBuffer in
            guard rawBuffer.count > 0 else { return }
            rawBuffer.initializeMemory(as: UInt8.self, repeating: 0)
            let utf8 = Array(string.utf8.prefix(max(0, maxBytes - 1)))
            rawBuffer.copyBytes(from: utf8)
        }
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

    private static func makeSearchResult(
        line: String,
        lineNumber: Int,
        startColumn: Int,
        endColumnInclusive: Int,
        fallbackMatchText: String
    ) -> SearchResult {
        let characterCount = line.count
        let clampedStart = max(0, min(startColumn, characterCount))
        let clampedEndExclusive = max(
            clampedStart,
            min(endColumnInclusive + 1, characterCount)
        )

        let startIndex = line.index(
            line.startIndex,
            offsetBy: clampedStart,
            limitedBy: line.endIndex
        ) ?? line.endIndex
        let endIndex = line.index(
            line.startIndex,
            offsetBy: clampedEndExclusive,
            limitedBy: line.endIndex
        ) ?? line.endIndex

        let beforeStart = line.index(
            startIndex,
            offsetBy: -searchContextCharacterCount,
            limitedBy: line.startIndex
        ) ?? line.startIndex
        let afterEnd = line.index(
            endIndex,
            offsetBy: searchContextCharacterCount,
            limitedBy: line.endIndex
        ) ?? line.endIndex

        let matchText = startIndex < endIndex
            ? String(line[startIndex..<endIndex])
            : fallbackMatchText
        let contextBefore = beforeStart < startIndex
            ? String(line[beforeStart..<startIndex])
            : nil
        let contextAfter = endIndex < afterEnd
            ? String(line[endIndex..<afterEnd])
            : nil

        return SearchResult(
            id: UUID(),
            lineNumber: lineNumber,
            column: clampedStart,
            matchText: matchText,
            contextBefore: contextBefore,
            contextAfter: contextAfter
        )
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

    /// Calculates the terminal display width (in columns) for a string.
    /// ASCII characters use 1 column; East Asian wide characters use 2.
    static func terminalDisplayWidth(of text: String) -> UInt16 {
        var width: UInt16 = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x1100...0x115F).contains(v) ||   // Hangul Jamo
               (0x2E80...0xA4CF).contains(v) ||   // CJK Radicals through Yi
               (0xAC00...0xD7A3).contains(v) ||   // Hangul Syllables
               (0xF900...0xFAFF).contains(v) ||   // CJK Compatibility Ideographs
               (0xFE10...0xFE19).contains(v) ||   // Vertical forms
               (0xFE30...0xFE6F).contains(v) ||   // CJK Compatibility Forms
               (0xFF01...0xFF60).contains(v) ||   // Fullwidth Forms
               (0xFFE0...0xFFE6).contains(v) ||   // Fullwidth Signs
               (0x20000...0x2FA1F).contains(v) || // CJK Extension B through F
               (0x30000...0x3134F).contains(v) {  // CJK Extension G
                width += 2
            } else if scalar.properties.generalCategory != .control {
                width += 1
            }
        }
        return width
    }
}
