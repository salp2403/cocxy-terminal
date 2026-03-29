// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GhosttyBridge.swift - Bridge between libghostty C API and Swift.

import AppKit
import GhosttyKit

// MARK: - Ghostty Bridge

/// Concrete implementation of `TerminalEngine` that wraps libghostty's C API.
///
/// This class encapsulates all direct interaction with `ghostty_app`,
/// `ghostty_surface` and their callbacks. It is the only place in the
/// codebase that imports the libghostty C headers directly for runtime calls.
///
/// ## Lifecycle
///
/// ```
/// GhosttyBridge()           -- Uninitialized
///   .initialize(config:)    -- Config created, app running
///   .createSurface(...)     -- Surface active, shell spawned
///   .destroySurface(...)    -- Surface torn down
///   deinit                  -- App freed, all resources released
/// ```
///
/// ## Threading model (inherited from libghostty)
///
/// - **Main thread**: App tick, surface creation/destruction, event dispatch.
/// - **Renderer thread**: GPU rendering via Metal (1 per surface).
/// - **I/O thread**: PTY read/write (1 per surface).
/// - **Read thread**: Parses terminal output (1 per surface).
///
/// All callbacks to the Swift side are dispatched to the main thread via
/// `wakeup_cb` -> `DispatchQueue.main.async` -> `ghostty_app_tick`.
///
/// - SeeAlso: ADR-001 (Terminal engine selection)
/// - SeeAlso: `TerminalEngine` protocol
/// - SeeAlso: `GhosttyRuntimeConfigBuilder` for callback wiring
@MainActor
final class GhosttyBridge: TerminalEngine {

    // MARK: - State

    /// The ghostty application instance. Created in `initialize(config:)`.
    private var ghosttyApp: ghostty_app_t?

    /// The ghostty configuration. Created in `initialize(config:)`.
    private var ghosttyConfig: ghostty_config_t?

    /// Registry mapping `SurfaceID` to `ghostty_surface_t` pointers.
    private let surfaceRegistry = SurfaceRegistry()

    /// Output handlers registered per surface.
    private var outputHandlers: [SurfaceID: @Sendable (Data) -> Void] = [:]

    /// OSC notification handlers registered per surface.
    private var oscHandlers: [SurfaceID: @Sendable (OSCNotification) -> Void] = [:]

    /// The currently focused surface ID, used for clipboard request routing.
    private var focusedSurfaceID: SurfaceID?

    // MARK: - Public State (for testing)

    /// Whether the bridge has been successfully initialized.
    var isInitialized: Bool {
        ghosttyApp != nil
    }

    /// Number of currently active surfaces.
    var activeSurfaceCount: Int {
        surfaceRegistry.count
    }

    // MARK: - Initialization

    init() {
        // Bridge starts uninitialized. Call initialize(config:) to set up.
    }

    deinit {
        // Safety: libghostty functions must be called from the main thread.
        // GhosttyBridge must only be owned by @MainActor objects (AppDelegate,
        // MainWindowController) to guarantee this. If this assertion fires,
        // a non-main-actor owner has been introduced.
        assert(Thread.isMainThread, "GhosttyBridge.deinit called off main thread")

        // Free all surfaces first, then the app, then the config.
        // Order matters: surfaces depend on the app, app depends on config.
        // Safe: deinit runs on main thread (asserted above), same as @MainActor isolation.
        MainActor.assumeIsolated {
            let surfaces = surfaceRegistry.removeAll()
            for surface in surfaces {
                ghostty_surface_free(surface)
            }

            if let app = ghosttyApp {
                ghostty_app_free(app)
            }

            if let config = ghosttyConfig {
                ghostty_config_free(config)
            }
        }
    }

    /// Returns the path to ghostty resources during development builds.
    ///
    /// When running via `swift run` or Xcode, the app has no bundle with
    /// a Resources directory. This method locates the shell integration
    /// scripts relative to the project directory.
    /// Resolves the path to ghostty resources (shell-integration scripts).
    ///
    /// In production (.app bundle): `Bundle.main.resourcePath`
    /// In development: `libs/ghostty-resources` relative to the source tree.
    static func resolveResourcesPath() -> String? {
        // Production: app bundle has shell-integration in Resources/.
        if let bundlePath = Bundle.main.resourcePath {
            let shellIntegration = "\(bundlePath)/shell-integration"
            if FileManager.default.fileExists(atPath: shellIntegration) {
                return bundlePath
            }
        }
        // Development: relative to the source file.
        return developmentResourcesPath()
    }

    private static func developmentResourcesPath() -> String? {
        let projectResources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Infrastructure/
            .deletingLastPathComponent()  // Core/
            .deletingLastPathComponent()  // Sources/
            .appendingPathComponent("libs/ghostty-resources")
        if FileManager.default.fileExists(atPath: projectResources.path) {
            return projectResources.path
        }
        return nil
    }

    // MARK: - TerminalEngine: Initialize

    /// One-time global initialization flag.
    private static var isGhosttyInitialized = false

    /// Initializes the ghostty runtime. Must be called once before any other ghostty API.
    private static func ensureGhosttyInitialized() {
        guard !isGhosttyInitialized else { return }
        // ghostty_init takes argc and argv for CLI argument processing.
        // We pass the process arguments.
        let argc = CommandLine.argc
        let argv = CommandLine.unsafeArgv
        let result = ghostty_init(UInt(argc), argv)
        if result != 0 {
            NSLog("[GhosttyBridge] ghostty_init returned non-zero: %d", result)
        }
        isGhosttyInitialized = true
    }

    func initialize(config: TerminalEngineConfig) throws {
        // Step 0: Initialize ghostty runtime (must happen before any other call).
        Self.ensureGhosttyInitialized()

        // Step 1: Create ghostty config.
        guard let gConfig = ghostty_config_new() else {
            throw TerminalEngineError.initializationFailed(
                reason: "ghostty_config_new() returned nil"
            )
        }

        // Step 2: Load config (term type + theme colors) before finalize.
        loadGhosttyConfig(gConfig, palette: config.themePalette)

        // Step 3: Finalize config (applies defaults). This is mandatory before use.
        ghostty_config_finalize(gConfig)

        // Step 4: Check for config diagnostics.
        let diagnosticCount = ghostty_config_diagnostics_count(gConfig)
        if diagnosticCount > 0 {
            let firstDiag = ghostty_config_get_diagnostic(gConfig, 0)
            let message = firstDiag.message.map { String(cString: $0) } ?? "unknown error"
            // Log diagnostics but do not fail -- they may be non-fatal warnings.
            NSLog("[GhosttyBridge] Config diagnostic: %@", message)
        }

        // Step 5: Build runtime config with C callbacks.
        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()
        var runtimeConfig = GhosttyRuntimeConfigBuilder.build(userdata: opaqueSelf)

        // Step 6: Create the ghostty app.
        guard let gApp = ghostty_app_new(&runtimeConfig, gConfig) else {
            ghostty_config_free(gConfig)
            throw TerminalEngineError.initializationFailed(
                reason: "ghostty_app_new() returned nil"
            )
        }

        self.ghosttyConfig = gConfig
        self.ghosttyApp = gApp
    }

    // MARK: - Theme Config Loading

    /// Writes a temporary ghostty config file with the theme palette colors
    /// and loads it into the ghostty config.
    ///
    /// If no palette is provided, this is a no-op and ghostty uses its defaults.
    /// The temp file is written to the app's caches directory and cleaned up
    /// on the next launch.
    ///
    /// - Parameters:
    ///   - gConfig: The ghostty config instance to load into.
    ///   - palette: The theme palette with hex colors. Nil to skip.
    /// Loads all ghostty config: base settings + theme colors.
    /// The base config sets TERM=xterm-256color so the child shell finds terminfo.
    /// Without this, ghostty defaults to "xterm-ghostty" whose terminfo only
    /// exists inside Ghostty.app, causing Backspace and other keys to break.
    private func loadGhosttyConfig(
        _ gConfig: ghostty_config_t,
        palette: ThemePalette?,
        terminalConfig: TerminalConfig? = nil
    ) {
        var lines: [String] = ["term = xterm-256color"]

        // Enable shell integration so libghostty injects precmd/preexec hooks
        // into the user's shell. This is what makes OSC 7 (directory reporting)
        // and OSC 133 (prompt marks) work. Without this, tab titles, directory
        // tracking, and agent detection are all non-functional.
        lines.append("shell-integration = detect")
        lines.append("shell-integration-features = cursor,sudo,title")

        // Cursor configuration.
        if let tc = terminalConfig {
            let ghosttyCursorStyle: String
            switch tc.cursorStyle {
            case .block: ghosttyCursorStyle = "block"
            case .bar: ghosttyCursorStyle = "bar"
            case .underline: ghosttyCursorStyle = "underline"
            }
            lines.append("cursor-style = \(ghosttyCursorStyle)")
            lines.append("cursor-style-blink = \(tc.cursorBlink)")
        }

        if let palette = palette {
            let themeConfig = GhosttyThemeConfigBuilder.buildConfigString(from: palette)
            lines.append(themeConfig)
        }

        let configContent = lines.joined(separator: "\n") + "\n"
        guard let tempPath = GhosttyThemeConfigBuilder.writeTemporaryConfigFile(configContent) else {
            NSLog("[GhosttyBridge] Failed to write config file, using defaults")
            return
        }

        tempPath.withCString { cPath in
            ghostty_config_load_file(gConfig, cPath)
        }
    }

    // MARK: - TerminalEngine: Create Surface

    func createSurface(
        in view: NativeTerminalView,
        workingDirectory: URL?,
        command: String?
    ) throws -> SurfaceID {
        guard let app = ghosttyApp else {
            throw TerminalEngineError.surfaceCreationFailed(
                reason: "GhosttyBridge not initialized. Call initialize(config:) first."
            )
        }

        // Build the surface config struct.
        var surfaceConfig = ghostty_surface_config_new()
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfaceConfig.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(view).toOpaque())
        )
        surfaceConfig.userdata = Unmanaged.passUnretained(self).toOpaque()

        // Set scale factor from the view's window, defaulting to 2.0 (Retina).
        surfaceConfig.scale_factor = Double(view.window?.backingScaleFactor ?? 2.0)

        // Set working directory if provided.
        let workingDirCString: UnsafeMutablePointer<CChar>? = workingDirectory
            .map { strdup($0.path) }
        surfaceConfig.working_directory = UnsafePointer(workingDirCString)

        // Set command if provided.
        let commandCString: UnsafeMutablePointer<CChar>? = command.map { strdup($0) }
        surfaceConfig.command = UnsafePointer(commandCString)

        // Set GHOSTTY_RESOURCES_DIR so libghostty's shell integration scripts
        // are found by the child shell. Without this env var, the shell does not
        // emit OSC 7 (directory) or OSC 133 (prompt), breaking tab titles,
        // directory tracking, and agent detection in production builds.
        let resourcesPath = Self.resolveResourcesPath()
        let envKeyC = strdup("GHOSTTY_RESOURCES_DIR")
        let envValueC = strdup(resourcesPath ?? "")
        // Heap-allocate the env var array so the pointer stays valid through surface creation.
        let envVarPtr = UnsafeMutablePointer<ghostty_env_var_s>.allocate(capacity: 1)
        envVarPtr.initialize(to: ghostty_env_var_s(key: envKeyC, value: envValueC))
        if resourcesPath != nil {
            surfaceConfig.env_vars = envVarPtr
            surfaceConfig.env_var_count = 1
        }

        // Create the surface.
        guard let gSurface = ghostty_surface_new(app, &surfaceConfig) else {
            free(workingDirCString)
            free(commandCString)
            envVarPtr.deinitialize(count: 1)
            envVarPtr.deallocate()
            free(envKeyC)
            free(envValueC)
            throw TerminalEngineError.surfaceCreationFailed(
                reason: "ghostty_surface_new() returned nil"
            )
        }

        // Clean up C strings and env var allocation.
        free(workingDirCString)
        free(commandCString)
        envVarPtr.deinitialize(count: 1)
        envVarPtr.deallocate()
        free(envKeyC)
        free(envValueC)

        // Register the surface.
        let surfaceID = SurfaceID()
        surfaceRegistry.register(surfaceID: surfaceID, ghosttySurface: gSurface)
        registeredSurfaceIDs.append(surfaceID)

        return surfaceID
    }

    // MARK: - TerminalEngine: Destroy Surface

    func destroySurface(_ id: SurfaceID) {
        guard let surface = surfaceRegistry.unregister(id) else {
            // Surface not found -- already destroyed or never existed. Safe no-op.
            return
        }

        // Remove from ID tracking and handlers.
        registeredSurfaceIDs.removeAll { $0 == id }
        outputHandlers.removeValue(forKey: id)
        oscHandlers.removeValue(forKey: id)

        // Free the ghostty surface.
        ghostty_surface_free(surface)
    }

    // MARK: - Binding Actions

    /// Executes a ghostty binding action on the given surface.
    /// For example, "text:\u{7F}" sends DEL to the PTY.
    @discardableResult
    func performBindingAction(_ action: String, on surface: SurfaceID) -> Bool {
        guard let gSurface = surfaceRegistry.lookup(surface) else { return false }
        return action.withCString { cAction in
            ghostty_surface_binding_action(gSurface, cAction, UInt(action.utf8.count))
        }
    }

    /// Scrolls the terminal to a specific line from the scrollback buffer.
    ///
    /// Uses ghostty's `scroll_to_top` binding followed by a `scroll_page_lines`
    /// to position the viewport at the target line. This is a best-effort approach
    /// since ghostty does not expose a "scroll to absolute line" API directly.
    ///
    /// - Parameters:
    ///   - surfaceID: The surface to scroll.
    ///   - lineNumber: The zero-based line number in the scrollback buffer.
    func scrollToSearchResult(surfaceID: SurfaceID, lineNumber: Int) {
        // First scroll to the top of the scrollback.
        performBindingAction("scroll_to_top", on: surfaceID)
        // Then scroll down to the target line.
        if lineNumber > 0 {
            performBindingAction("scroll_page_lines:\(lineNumber)", on: surfaceID)
        }
    }

    // MARK: - Translation Mods

    /// Returns the translation mods for the given surface and modifier state.
    /// Used by TerminalSurfaceView to determine which characters to send as text.
    func translationMods(
        for surface: SurfaceID,
        mods: KeyModifiers
    ) -> UInt {
        guard let gSurface = surfaceRegistry.lookup(surface) else { return 0 }
        let ghosttyMods = GhosttyKeyConverter.ghosttyMods(from: mods)
        let result = ghostty_surface_key_translation_mods(gSurface, ghosttyMods)
        return UInt(result.rawValue)
    }

    // MARK: - TerminalEngine: Send Key Event

    /// Sends a key event to the specified surface.
    /// Matches the official Ghostty macOS implementation exactly.
    ///
    /// - Returns: `true` if ghostty handled the key, `false` if the caller
    ///   should fall back to `interpretKeyEvents`.
    @discardableResult
    func sendKeyEvent(_ event: KeyEvent, to surface: SurfaceID) -> Bool {
        guard let gSurface = surfaceRegistry.lookup(surface) else { return false }

        var ghosttyEvent = GhosttyKeyConverter.ghosttyInputKey(from: event)

        // Set consumed_mods from the event (caller provides these).
        ghosttyEvent.consumed_mods = ghostty_input_mods_e(rawValue: event.consumedModsRaw)

        // Set text if provided.
        let handled: Bool
        if let characters = event.characters, !characters.isEmpty {
            handled = characters.withCString { cString in
                ghosttyEvent.text = cString
                return ghostty_surface_key(gSurface, ghosttyEvent)
            }
        } else {
            handled = ghostty_surface_key(gSurface, ghosttyEvent)
        }

        return handled
    }

    // MARK: - TerminalEngine: Send Text

    func sendText(_ text: String, to surface: SurfaceID) {
        guard let gSurface = surfaceRegistry.lookup(surface) else { return }

        text.withCString { cString in
            ghostty_surface_text(gSurface, cString, UInt(text.utf8.count))
        }
    }

    // MARK: - TerminalEngine: Send Preedit Text

    func sendPreeditText(_ text: String, to surface: SurfaceID) {
        guard let gSurface = surfaceRegistry.lookup(surface) else { return }

        if text.isEmpty {
            ghostty_surface_preedit(gSurface, nil, 0)
        } else {
            text.withCString { cString in
                ghostty_surface_preedit(gSurface, cString, UInt(text.utf8.count))
            }
        }
    }

    // MARK: - TerminalEngine: Resize

    func resize(_ surface: SurfaceID, to size: TerminalSize) {
        guard let gSurface = surfaceRegistry.lookup(surface) else { return }

        ghostty_surface_set_size(
            gSurface,
            UInt32(size.pixelWidth),
            UInt32(size.pixelHeight)
        )
    }

    // MARK: - Mouse Events

    /// Forwards a mouse button event to the specified surface.
    ///
    /// - Parameters:
    ///   - button: Which mouse button was pressed/released.
    ///   - action: Whether the button was pressed or released.
    ///   - position: The mouse position in the view's coordinate system.
    ///   - modifiers: Active modifier keys.
    ///   - surface: Target surface.
    func sendMouseEvent(
        button: MouseButton,
        action: MouseAction,
        position: CGPoint,
        modifiers: KeyModifiers,
        to surface: SurfaceID
    ) {
        guard let gSurface = surfaceRegistry.lookup(surface) else { return }

        let ghosttyMods = GhosttyKeyConverter.ghosttyMods(from: modifiers)

        // Update position BEFORE sending the button event. libghostty uses
        // the last-known mouse position to determine which cell was clicked.
        // Without this, selection targets the wrong location.
        ghostty_surface_mouse_pos(gSurface, position.x, position.y, ghosttyMods)

        let ghosttyButton = Self.ghosttyMouseButton(from: button)
        let ghosttyAction: ghostty_input_mouse_state_e = action == .press
            ? GHOSTTY_MOUSE_PRESS
            : GHOSTTY_MOUSE_RELEASE

        _ = ghostty_surface_mouse_button(gSurface, ghosttyAction, ghosttyButton, ghosttyMods)
    }

    /// Forwards a mouse position update to the specified surface.
    ///
    /// - Parameters:
    ///   - position: The mouse position in the view's coordinate system.
    ///   - modifiers: Active modifier keys.
    ///   - surface: Target surface.
    func sendMousePosition(
        position: CGPoint,
        modifiers: KeyModifiers,
        to surface: SurfaceID
    ) {
        guard let gSurface = surfaceRegistry.lookup(surface) else { return }

        let ghosttyMods = GhosttyKeyConverter.ghosttyMods(from: modifiers)
        ghostty_surface_mouse_pos(gSurface, position.x, position.y, ghosttyMods)
    }

    /// Forwards a scroll event to the specified surface.
    ///
    /// - Parameters:
    ///   - deltaX: Horizontal scroll delta.
    ///   - deltaY: Vertical scroll delta.
    ///   - modifiers: Active modifier keys.
    ///   - surface: Target surface.
    func sendScrollEvent(
        deltaX: CGFloat,
        deltaY: CGFloat,
        modifiers: KeyModifiers,
        to surface: SurfaceID
    ) {
        guard let gSurface = surfaceRegistry.lookup(surface) else { return }

        let ghosttyMods = GhosttyKeyConverter.ghosttyMods(from: modifiers)
        ghostty_surface_mouse_scroll(
            gSurface,
            deltaX,
            deltaY,
            ghostty_input_scroll_mods_t(ghosttyMods.rawValue)
        )
    }

    // MARK: - Focus and Scale Notifications

    /// Notifies libghostty that a surface's focus state changed.
    ///
    /// - Parameters:
    ///   - surfaceID: The surface whose focus changed.
    ///   - focused: Whether the surface gained or lost focus.
    func notifyFocusChanged(surfaceID: SurfaceID, focused: Bool) {
        guard let gSurface = surfaceRegistry.lookup(surfaceID) else { return }

        if focused {
            focusedSurfaceID = surfaceID
        } else if focusedSurfaceID == surfaceID {
            focusedSurfaceID = nil
        }

        ghostty_surface_set_focus(gSurface, focused)
    }

    /// Notifies libghostty that the display scale factor changed.
    ///
    /// This is called when the view moves to a display with a different
    /// backing scale factor (e.g., from Retina to non-Retina).
    ///
    /// - Parameters:
    ///   - surfaceID: The surface whose scale changed.
    ///   - scaleFactor: The new scale factor (2.0 for Retina).
    func notifyContentScaleChanged(surfaceID: SurfaceID, scaleFactor: Double) {
        guard let gSurface = surfaceRegistry.lookup(surfaceID) else { return }
        ghostty_surface_set_content_scale(gSurface, scaleFactor, scaleFactor)
    }

    // MARK: - Selection Query

    /// Returns whether the given surface currently has an active text selection.
    ///
    /// - Parameter surfaceID: The surface to query.
    /// - Returns: `true` if the surface has a selection, `false` otherwise.
    func hasSelection(for surfaceID: SurfaceID) -> Bool {
        guard let gSurface = surfaceRegistry.lookup(surfaceID) else { return false }
        return ghostty_surface_has_selection(gSurface)
    }

    /// Reads the currently selected text from the given surface.
    ///
    /// Copies the text into a Swift `String` and frees the ghostty-allocated
    /// buffer before returning. The caller does not need to manage memory.
    ///
    /// - Parameter surfaceID: The surface to read from.
    /// - Returns: The selected text, or `nil` if no selection exists.
    func readSelection(for surfaceID: SurfaceID) -> String? {
        guard let gSurface = surfaceRegistry.lookup(surfaceID) else { return nil }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(gSurface, &text) else { return nil }
        defer { ghostty_surface_free_text(gSurface, &text) }
        guard text.text != nil, text.text_len > 0 else { return nil }
        return String(cString: text.text)
    }

    // MARK: - Private Mouse Conversion

    private static func ghosttyMouseButton(
        from button: MouseButton
    ) -> ghostty_input_mouse_button_e {
        switch button {
        case .left:   return GHOSTTY_MOUSE_LEFT
        case .right:  return GHOSTTY_MOUSE_RIGHT
        case .middle: return GHOSTTY_MOUSE_MIDDLE
        }
    }

    // MARK: - TerminalEngine: Tick

    func tick() {
        guard let app = ghosttyApp else { return }
        ghostty_app_tick(app)
    }

    // MARK: - TerminalEngine: Output Handler

    func setOutputHandler(
        for surface: SurfaceID,
        handler: @escaping @Sendable (Data) -> Void
    ) {
        outputHandlers[surface] = handler
    }

    // MARK: - TerminalEngine: OSC Handler

    func setOSCHandler(
        for surface: SurfaceID,
        handler: @escaping @Sendable (OSCNotification) -> Void
    ) {
        oscHandlers[surface] = handler
    }

    // MARK: - Action Handling (called from C callbacks)

    /// Handles an action dispatched by libghostty during `ghostty_app_tick`.
    ///
    /// - Parameters:
    ///   - target: The target of the action (app or specific surface).
    ///   - action: The action to handle.
    /// - Returns: `true` if the action was handled, `false` otherwise.
    func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            return handleSetTitle(target: target, action: action)

        case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
            return handleDesktopNotification(target: target, action: action)

        case GHOSTTY_ACTION_PWD:
            return handlePwdChanged(target: target, action: action)

        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            // Notify the process exit handler so the agent detection engine
            // can transition to idle state.
            if target.tag == GHOSTTY_TARGET_SURFACE,
               let gSurface = target.target.surface {
                notifyOSCHandlerForGhosttySurface(
                    gSurface,
                    notification: .processExited
                )
            }
            return true

        case GHOSTTY_ACTION_CLOSE_TAB,
             GHOSTTY_ACTION_CLOSE_WINDOW:
            return true

        case GHOSTTY_ACTION_NEW_WINDOW,
             GHOSTTY_ACTION_NEW_TAB,
             GHOSTTY_ACTION_NEW_SPLIT:
            // We handle window/tab/split creation ourselves.
            // Return true to prevent libghostty from creating its own windows.
            return true

        case GHOSTTY_ACTION_RENDERER_HEALTH:
            return true

        default:
            // Return true for all unhandled actions to prevent libghostty
            // from creating its own UI elements (windows, dialogs, etc.).
            return true
        }
    }

    // MARK: - Clipboard Handling (called from C callbacks)

    func handleReadClipboard(
        clipboardType: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) -> Bool {
        // Read from the system clipboard.
        guard let text = NSPasteboard.general.string(forType: .string) else {
            return false
        }

        // Find the focused surface to complete the clipboard request.
        // Fall back to the first registered surface if none is focused.
        let targetSurfaceID = focusedSurfaceID ?? registeredSurfaceIDs.first
        guard let surfaceID = targetSurfaceID,
              let gSurface = surfaceRegistry.lookup(surfaceID) else {
            return false
        }

        // Complete the clipboard request by providing the content to libghostty.
        text.withCString { cString in
            ghostty_surface_complete_clipboard_request(gSurface, cString, state, true)
        }

        return true
    }

    func handleConfirmReadClipboard(
        content: UnsafePointer<CChar>?,
        state: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e
    ) {
        // SECURITY NOTE: Currently auto-confirms clipboard reads.
        // This is a known limitation documented in the security audit (audit-v1.md).
        // A future release will show a confirmation dialog for clipboard access
        // from terminal applications, similar to how browsers handle clipboard permissions.
        // Until then, this behavior matches standard terminal emulators (iTerm2, Ghostty, Alacritty).
        #if DEBUG
        NSLog("[Cocxy] Clipboard read requested by terminal application (auto-confirmed)")
        #endif
    }

    func handleWriteClipboard(
        clipboardType: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        contentLength: Int,
        shouldConfirm: Bool
    ) {
        guard let content = content, contentLength > 0 else { return }

        // Read the first content entry's data.
        let firstContent = content.pointee
        guard let data = firstContent.data else { return }
        let text = String(cString: data)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func handleCloseSurface(processAlive: Bool) {
        // A surface is requesting to close. The actual cleanup happens
        // when the UI layer calls destroySurface().
        // If processAlive is true, we might want to show a confirmation dialog.
        // For now, we just acknowledge the request.
    }

    // MARK: - Private Action Handlers

    private func handleSetTitle(
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        let titleData = action.action.set_title
        guard let cTitle = titleData.title else { return false }
        let title = String(cString: cTitle)

        // Find the surface this applies to and notify its OSC handler.
        if target.tag == GHOSTTY_TARGET_SURFACE,
           let gSurface = target.target.surface {
            notifyOSCHandlerForGhosttySurface(
                gSurface,
                notification: .titleChange(title)
            )
        }

        return true
    }

    private func handleDesktopNotification(
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        let notifData = action.action.desktop_notification
        let title = notifData.title.map { String(cString: $0) } ?? ""
        let body = notifData.body.map { String(cString: $0) } ?? ""

        if target.tag == GHOSTTY_TARGET_SURFACE,
           let gSurface = target.target.surface {
            notifyOSCHandlerForGhosttySurface(
                gSurface,
                notification: .notification(title: title, body: body)
            )
        }

        return true
    }

    private func handlePwdChanged(
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        let pwdData = action.action.pwd
        guard let cPwd = pwdData.pwd else { return false }
        let pwd = String(cString: cPwd)
        let url = URL(fileURLWithPath: pwd)

        if target.tag == GHOSTTY_TARGET_SURFACE,
           let gSurface = target.target.surface {
            notifyOSCHandlerForGhosttySurface(
                gSurface,
                notification: .currentDirectory(url)
            )
        }

        return true
    }

    // MARK: - Surface Lookup by Pointer

    /// Finds the SurfaceID for a given ghostty_surface_t pointer.
    ///
    /// This is needed when C callbacks give us a surface pointer and we need
    /// to find the corresponding SurfaceID to dispatch to the right handler.
    private func surfaceIDForGhosttySurface(_ gSurface: ghostty_surface_t) -> SurfaceID? {
        // Linear scan is acceptable for small numbers of surfaces (typically <20).
        // If this becomes a bottleneck, add a reverse mapping.
        for surfaceID in allSurfaceIDs() {
            if surfaceRegistry.lookup(surfaceID) == gSurface {
                return surfaceID
            }
        }
        return nil
    }

    /// Returns all currently registered surface IDs.
    /// Used internally for reverse lookups.
    private func allSurfaceIDs() -> [SurfaceID] {
        return registeredSurfaceIDs
    }

    /// Set of all registered surface IDs, maintained alongside the registry.
    private var registeredSurfaceIDs: [SurfaceID] = []

    /// Notifies the OSC handler for a surface identified by its ghostty pointer.
    private func notifyOSCHandlerForGhosttySurface(
        _ gSurface: ghostty_surface_t,
        notification: OSCNotification
    ) {
        guard let surfaceID = surfaceIDForGhosttySurface(gSurface) else { return }
        oscHandlers[surfaceID]?(notification)
    }
}
