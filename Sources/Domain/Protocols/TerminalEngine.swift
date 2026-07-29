// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalEngine.swift - Contract for the terminal rendering engine bridge.

import Foundation
import CocxyShared

// MARK: - Terminal Engine Protocol

/// Contract for the bridge between the native terminal engine and Swift.
///
/// The concrete implementation (`CocxyCoreBridge`) wraps CocxyCore's C API and
/// exposes a small, testable surface to the rest of the app. The protocol
/// keeps the domain layer decoupled from engine details and allows unit tests
/// to inject lightweight fakes.
///
/// Threading: implementations must dispatch all callbacks to the main thread.
/// The bridge is responsible for keeping terminal I/O and Swift UI state
/// synchronized safely at the boundary.
///
/// - SeeAlso: ADR-001 (Terminal Engine selection)
/// - SeeAlso: ARCHITECTURE.md Section 7.1
@MainActor
protocol TerminalEngine: AnyObject {

    /// Initializes the terminal engine with the given configuration.
    ///
    /// Must be called exactly once before creating any surfaces.
    /// - Parameter config: Engine-level configuration (font, theme, keybindings).
    /// - Throws: `TerminalEngineError.initializationFailed` if the underlying
    ///   engine cannot be created (e.g., missing Metal support).
    func initialize(config: TerminalEngineConfig) throws

    /// Creates a new terminal surface inside the given native view.
    ///
    /// - Parameters:
    ///   - view: The `NSView` that will host the terminal rendering.
    ///   - workingDirectory: Initial working directory for the shell. Defaults
    ///     to the user's home directory when `nil`.
    ///   - command: Shell command to execute. Uses the user's default shell
    ///     when `nil`.
    /// - Returns: A unique identifier for the created surface.
    /// - Throws: `TerminalEngineError.surfaceCreationFailed` on failure.
    func createSurface(
        in view: NativeTerminalView,
        workingDirectory: URL?,
        command: String?
    ) throws -> SurfaceID

    /// Destroys an existing terminal surface and releases its resources.
    ///
    /// After this call the `SurfaceID` is invalid and must not be reused.
    /// - Parameter id: The surface to destroy.
    func destroySurface(_ id: SurfaceID)

    /// Forwards a keyboard event to the specified surface.
    ///
    /// - Parameters:
    ///   - event: The key event to send.
    ///   - surface: Target surface.
    /// - Returns: `true` if the engine handled the key, `false` if the caller
    ///   should fall back to the platform text input system.
    @discardableResult
    func sendKeyEvent(_ event: KeyEvent, to surface: SurfaceID) -> Bool

    /// Sends a plain text string to the terminal surface.
    ///
    /// Used for text insertion from IME composition or programmatic input.
    /// The text is sent directly to the PTY without key event processing.
    ///
    /// - Parameters:
    ///   - text: The UTF-8 text to send.
    ///   - surface: Target surface.
    func sendText(_ text: String, to surface: SurfaceID)

    /// Sends IME preedit (composing) text to the terminal surface.
    ///
    /// During IME composition, this shows underlined preview text at the
    /// cursor position. Send an empty string to clear the preedit.
    ///
    /// - Parameters:
    ///   - text: The composing text to display, or empty to clear.
    ///   - cursorByteOffset: Optional cursor offset in the UTF-8 preedit bytes.
    ///     Engines place the cursor at the end when this is `nil`.
    ///   - surface: Target surface.
    func sendPreeditText(
        _ text: String,
        cursorByteOffset: Int?,
        to surface: SurfaceID
    )

    /// Notifies the engine that a surface has been resized.
    ///
    /// The engine will send `SIGWINCH` to the underlying PTY so that
    /// programs like vim adjust their layout.
    /// - Parameters:
    ///   - surface: The surface that was resized.
    ///   - size: The new size in columns, rows and pixels.
    func resize(_ surface: SurfaceID, to size: TerminalSize)

    /// Applies a font configuration to one live terminal surface.
    ///
    /// Engines use their surface's backing scale and current ligature policy
    /// when rebuilding renderer metrics. Implementations that do not own a
    /// renderer may ignore the request.
    /// - Parameters:
    ///   - family: Font family name.
    ///   - size: Font size in points.
    ///   - surface: Target surface.
    func applyFont(family: String, size: Double, to surface: SurfaceID)

    /// Updates the font defaults used by surfaces created after this call.
    /// Per-surface overrides must continue to use `applyFont` so a project
    /// font does not leak into unrelated future tabs.
    func updateFontDefaults(family: String, size: Double)

    /// Performs one tick of the engine's main loop.
    ///
    /// Must be called synchronously on the main thread, typically tied to the
    /// application's run loop via a `CVDisplayLink` or `CADisplayLink`.
    func tick()

    /// Registers a handler to receive raw output data from a surface.
    ///
    /// The handler is invoked on the main thread whenever the surface produces
    /// output. Only one handler per surface is supported; setting a new handler
    /// replaces the previous one.
    /// - Parameters:
    ///   - surface: The surface to observe.
    ///   - handler: Closure receiving the raw output bytes.
    func setOutputHandler(
        for surface: SurfaceID,
        handler: @escaping @Sendable (Data) -> Void
    )

    /// Registers a handler to receive parsed OSC notifications from a surface.
    ///
    /// OSC sequences (9, 99, 133, 777, etc.) are parsed by the engine and
    /// forwarded as typed `OSCNotification` values.
    /// - Parameters:
    ///   - surface: The surface to observe.
    ///   - handler: Closure receiving the parsed OSC notification.
    func setOSCHandler(
        for surface: SurfaceID,
        handler: @escaping @Sendable (OSCNotification) -> Void
    )

    /// Scrolls the surface to a specific line in the scrollback buffer.
    ///
    /// Used by scrollback search to navigate to matches.
    /// - Parameters:
    ///   - surfaceID: The surface to scroll.
    ///   - lineNumber: The zero-based line number in the scrollback buffer.
    func scrollToSearchResult(surfaceID: SurfaceID, lineNumber: Int)

    /// Scrolls the visible viewport by a signed row delta.
    ///
    /// Positive values move upward into older scrollback; negative values move
    /// back toward the live bottom. Engines that cannot scroll locally may
    /// ignore the request.
    /// - Parameters:
    ///   - surfaceID: The surface to scroll.
    ///   - deltaRows: Signed number of rows to move.
    func scrollViewport(surfaceID: SurfaceID, deltaRows: Int)

    /// Notifies the engine that the host surface gained or lost focus.
    ///
    /// Engines can use this to forward focus changes to the PTY/terminal state,
    /// update cursor behavior, or dispatch focus-related hooks.
    /// - Parameters:
    ///   - focused: `true` when the surface is focused and its window is key.
    ///   - surface: Target surface.
    func notifyFocus(_ focused: Bool, for surface: SurfaceID)

    /// Searches terminal scrollback using the engine's native facilities.
    ///
    /// Engines may return `nil` when they do not offer a native search path.
    /// The host will then fall back to its Swift-side search engine.
    /// - Parameters:
    ///   - surfaceID: The surface whose combined history should be searched.
    ///   - options: Search configuration.
    /// - Returns: Search results, or `nil` if no native search path exists.
    func searchScrollback(surfaceID: SurfaceID, options: SearchOptions) -> [SearchResult]?

    /// Returns actionable terminal content at one absolute history cell.
    ///
    /// Implementations must copy any engine-owned text before returning. The
    /// query is used by pointer hover and click handling, so daemon-backed
    /// engines must answer from their latest frame instead of synchronous IPC.
    func detectedContent(
        atAbsoluteRow row: UInt32,
        column: UInt16,
        for surface: SurfaceID
    ) -> TerminalDetectedContent?

    /// Returns actionable spans intersecting the surface's visible viewport.
    /// The result is ordered from top-left to bottom-right and is used for
    /// keyboard hint presentation.
    func visibleDetectedContents(for surface: SurfaceID) -> [TerminalDetectedContent]

    /// Performs a semantic grid action using shell-integration block metadata.
    ///
    /// Prompt navigation updates the local viewport without emitting PTY input.
    /// Output selection returns an absolute retained-history range and its full
    /// copied text so renderer-backed hosts can preserve off-screen selection.
    func performSemanticNavigation(
        _ action: TerminalSemanticNavigationAction,
        for surface: SurfaceID
    ) -> TerminalSemanticNavigationResult?

    /// Returns process-monitor metadata for a surface when the engine can
    /// expose a real PTY-backed shell process.
    ///
    /// This lets the host monitor foreground processes without guessing shell
    /// PIDs from global process snapshots. Engines that do not support PTYs can
    /// return `nil`.
    func processMonitorRegistration(for surface: SurfaceID) -> TerminalProcessMonitorRegistration?
}

// MARK: - Supporting Types

/// Unique identifier for a terminal surface.
///
/// Wraps a `UUID` to provide type safety — you cannot accidentally pass a
/// `TabID` where a `SurfaceID` is expected.
struct SurfaceID: Hashable, Codable, Sendable {
    let rawValue: UUID

    init() {
        self.rawValue = UUID()
    }

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Terminal dimensions in both character cells and pixels.
///
/// Both representations are needed because the renderer uses pixel dimensions
/// while the PTY uses character cell dimensions.
struct TerminalSize: Equatable, Sendable {
    /// Number of character columns.
    let columns: UInt16
    /// Number of character rows.
    let rows: UInt16
    /// Width in pixels (for GPU rendering).
    let pixelWidth: UInt16
    /// Height in pixels (for GPU rendering).
    let pixelHeight: UInt16
}

/// PTY-backed process metadata that the host can use for foreground-process
/// detection without relying on process-tree heuristics.
struct TerminalProcessMonitorRegistration: Equatable, Sendable {
    let shellPID: pid_t
    let ptyMasterFD: Int32
    let shellIdentity: TerminalProcessIdentity?
}

/// Stable identity for a process PID on macOS.
///
/// The PID alone is not enough because the kernel may recycle it after exit.
/// Pairing it with the process start time lets the host reject stale or
/// recycled shell PIDs when monitoring foreground process changes.
struct TerminalProcessIdentity: Equatable, Sendable {
    let pid: pid_t
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}

/// Keyboard event abstraction decoupled from AppKit's `NSEvent`.
///
/// ViewModels and the domain layer work with this type instead of `NSEvent`
/// so they remain testable without AppKit.
struct KeyEvent: Sendable {
    /// The character(s) produced by the key, if any.
    let characters: String?
    /// The key code (hardware-level, layout-independent).
    let keyCode: UInt16
    /// Active modifier flags at the time of the event.
    let modifiers: KeyModifiers
    /// Whether this is a key-down or key-up event.
    let isKeyDown: Bool
    /// Whether this is a key repeat event (key held down).
    let isRepeat: Bool
    /// Whether this event is part of an IME composition sequence.
    let isComposing: Bool
    /// The Unicode codepoint of the key without Shift applied.
    /// Used by the terminal engine for layout-aware key translation.
    let unshiftedCodepoint: UInt32
    /// The codepoint produced by the shifted form of this key, when known.
    let shiftedCodepoint: UInt32
    /// The unshifted US-layout codepoint for Kitty's base-layout alternate.
    let baseLayoutCodepoint: UInt32
    /// Raw consumed modifiers value used for engine-side modifier tracking.
    /// Set by the view layer after querying the bridge for translation mods.
    let consumedModsRaw: UInt32

    init(
        characters: String?,
        keyCode: UInt16,
        modifiers: KeyModifiers,
        isKeyDown: Bool,
        isRepeat: Bool = false,
        isComposing: Bool = false,
        unshiftedCodepoint: UInt32 = 0,
        shiftedCodepoint: UInt32 = 0,
        baseLayoutCodepoint: UInt32 = 0,
        consumedModsRaw: UInt32 = 0
    ) {
        self.characters = characters
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isKeyDown = isKeyDown
        self.isRepeat = isRepeat
        self.isComposing = isComposing
        self.unshiftedCodepoint = unshiftedCodepoint
        self.shiftedCodepoint = shiftedCodepoint
        self.baseLayoutCodepoint = baseLayoutCodepoint
        self.consumedModsRaw = consumedModsRaw
    }
}

/// Modifier flags abstraction decoupled from AppKit's `NSEvent.ModifierFlags`.
struct KeyModifiers: OptionSet, Sendable {
    let rawValue: UInt

    static let shift   = KeyModifiers(rawValue: 1 << 0)
    static let control = KeyModifiers(rawValue: 1 << 1)
    static let option  = KeyModifiers(rawValue: 1 << 2)
    static let command = KeyModifiers(rawValue: 1 << 3)
    static let hyper   = KeyModifiers(rawValue: 1 << 4)
    static let meta    = KeyModifiers(rawValue: 1 << 5)
    static let capsLock = KeyModifiers(rawValue: 1 << 6)
    static let numLock = KeyModifiers(rawValue: 1 << 7)
}

extension TerminalEngine {
    func sendPreeditText(_ text: String, to surface: SurfaceID) {
        sendPreeditText(text, cursorByteOffset: nil, to: surface)
    }

    func processMonitorRegistration(for surface: SurfaceID) -> TerminalProcessMonitorRegistration? {
        nil
    }

    func notifyFocus(_ focused: Bool, for surface: SurfaceID) {}

    func applyFont(family: String, size: Double, to surface: SurfaceID) {}

    func updateFontDefaults(family: String, size: Double) {}

    func scrollViewport(surfaceID: SurfaceID, deltaRows: Int) {}

    func searchScrollback(surfaceID: SurfaceID, options: SearchOptions) -> [SearchResult]? {
        nil
    }

    func detectedContent(
        atAbsoluteRow row: UInt32,
        column: UInt16,
        for surface: SurfaceID
    ) -> TerminalDetectedContent? {
        nil
    }

    func visibleDetectedContents(for surface: SurfaceID) -> [TerminalDetectedContent] {
        []
    }

    func performSemanticNavigation(
        _ action: TerminalSemanticNavigationAction,
        for surface: SurfaceID
    ) -> TerminalSemanticNavigationResult? {
        nil
    }
}

/// Classification shared by local and daemon-backed actionable content.
enum TerminalDetectedContentKind: UInt8, Codable, Sendable {
    case hyperlink = 0
    case url = 1
    case filePath = 2
    case ipAddress = 3
    case gitHash = 4
    case email = 5
}

/// One actionable span in absolute combined-history coordinates.
struct TerminalDetectedContent: Equatable, Sendable {
    let kind: TerminalDetectedContentKind
    let text: String
    let target: String
    let startRow: UInt32
    let startColumn: UInt16
    let endRow: UInt32
    let endColumn: UInt16
    let line: Int?
    let column: Int?
    let isExplicitHyperlink: Bool

    func contains(absoluteRow row: UInt32, column: UInt16) -> Bool {
        guard row >= startRow, row <= endRow else { return false }
        if startRow == endRow {
            return column >= startColumn && column <= endColumn
        }
        if row == startRow {
            return column >= startColumn
        }
        if row == endRow {
            return column <= endColumn
        }
        return true
    }
}

/// Cursor coordinates captured synchronously while CocxyCore is processing a
/// terminal event. `screenRow` is relative to the active screen, while
/// `absoluteRow` includes the visible history origin at capture time.
struct TerminalGridPosition: Equatable, Sendable {
    let screenRow: UInt16
    let absoluteRow: UInt32
    let column: UInt16
}

/// Parsed OSC (Operating System Command) notification from the terminal.
///
/// These are the standard OSC sequences used by shell integration and
/// agent hooks to communicate state to the terminal emulator.
enum OSCNotification: Sendable {
    /// The terminal title changed (OSC 0/2).
    case titleChange(String)
    /// Explicit notification from a hook or shell (OSC 9/99/777).
    case notification(title: String, body: String)
    /// Shell prompt was displayed (OSC 133 ;A). Indicates the previous command
    /// has finished and the shell is ready for new input.
    case shellPrompt(position: TerminalGridPosition?)
    /// Editable command input began (OSC 133 ;B).
    case commandStarted(inputPosition: TerminalGridPosition?)
    /// A command finished executing (OSC 133 ;D). Contains the exit code
    /// when the shell reports it (nil if not provided).
    case commandFinished(exitCode: Int?)
    /// The current working directory changed (OSC 7).
    case currentDirectory(URL)
    /// Inline image data from an OSC 1337 sequence (iTerm2 protocol).
    /// Contains the raw payload after "1337;" for parsing by the UI layer.
    case inlineImage(String)
    /// The shell process exited.
    /// Used to transition the agent detection engine to idle state.
    case processExited
}

/// Configuration passed to `TerminalEngine.initialize(config:)`.
///
/// This is a snapshot of the engine-relevant subset of `CocxyConfig`.
/// Changes after initialization are applied via engine-specific APIs.
struct TerminalEngineConfig: Sendable {
    /// Font family name (e.g., "JetBrainsMono Nerd Font Mono").
    let fontFamily: String
    /// Font size in points.
    let fontSize: Double
    /// Name of the color theme to apply to the terminal surfaces.
    let themeName: String
    /// Path to the user's default shell.
    let shell: String
    /// Default working directory for new surfaces.
    let workingDirectory: URL
    /// Optional theme palette to apply to the terminal.
    /// When provided, the bridge applies these colors directly through
    /// the native engine API.
    let themePalette: ThemePalette?
    /// Horizontal padding in points (applied to left and right).
    let windowPaddingX: Double
    /// Vertical padding in points (applied to top and bottom).
    let windowPaddingY: Double
    /// Policy for OSC 52 clipboard reads initiated by terminal programs.
    let clipboardReadAccess: ClipboardReadAccess
    /// Policy for OSC 52 clipboard writes initiated by terminal programs.
    let clipboardWriteAccess: ClipboardWriteAccess
    /// App language used for terminal-engine-owned UI prompts.
    let appLanguage: AppLanguage
    /// Hook forwarding environment inherited by new shells.
    let hookIntegration: HookIntegrationConfig
    /// Whether typographic ligatures should be enabled.
    let ligaturesEnabled: Bool
    /// Whether font thickening is enabled (maps to font-thicken / CGContextSetShouldSmoothFonts).
    let fontThickenEnabled: Bool
    /// Maximum inline-image memory budget in bytes.
    let imageMemoryLimitBytes: UInt64
    /// Whether inline image file-transfer mode is enabled.
    let imageFileTransferEnabled: Bool
    /// Whether Sixel inline images are enabled.
    let sixelImagesEnabled: Bool
    /// Whether Kitty inline images are enabled.
    let kittyImagesEnabled: Bool
    /// Whether iTerm2 OSC 1337 inline images are enabled.
    let iterm2ImagesEnabled: Bool
    /// Optional directory for persistent inline-image cache data.
    let imageDiskCacheDirectory: URL?
    /// Maximum inline-image disk cache budget in bytes.
    let imageDiskCacheLimitBytes: UInt64

    init(
        fontFamily: String,
        fontSize: Double,
        themeName: String,
        shell: String,
        workingDirectory: URL,
        themePalette: ThemePalette? = nil,
        windowPaddingX: Double = 8,
        windowPaddingY: Double = 4,
        clipboardReadAccess: ClipboardReadAccess = .prompt,
        clipboardWriteAccess: ClipboardWriteAccess = .prompt,
        appLanguage: AppLanguage = .system,
        hookIntegration: HookIntegrationConfig = .defaults,
        ligaturesEnabled: Bool = true,
        fontThickenEnabled: Bool = false,
        imageMemoryLimitBytes: UInt64 = 256 * 1024 * 1024,
        imageFileTransferEnabled: Bool = false,
        sixelImagesEnabled: Bool = true,
        kittyImagesEnabled: Bool = true,
        iterm2ImagesEnabled: Bool = true,
        imageDiskCacheDirectory: URL? = nil,
        imageDiskCacheLimitBytes: UInt64 = 512 * 1024 * 1024
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.themeName = themeName
        self.shell = shell
        self.workingDirectory = workingDirectory
        self.themePalette = themePalette
        self.windowPaddingX = windowPaddingX
        self.windowPaddingY = windowPaddingY
        self.clipboardReadAccess = clipboardReadAccess
        self.clipboardWriteAccess = clipboardWriteAccess
        self.appLanguage = appLanguage
        self.hookIntegration = hookIntegration
        self.ligaturesEnabled = ligaturesEnabled
        self.fontThickenEnabled = fontThickenEnabled
        self.imageMemoryLimitBytes = imageMemoryLimitBytes
        self.imageFileTransferEnabled = imageFileTransferEnabled
        self.sixelImagesEnabled = sixelImagesEnabled
        self.kittyImagesEnabled = kittyImagesEnabled
        self.iterm2ImagesEnabled = iterm2ImagesEnabled
        self.imageDiskCacheDirectory = imageDiskCacheDirectory
        self.imageDiskCacheLimitBytes = imageDiskCacheLimitBytes
    }

    func replacing(
        fontFamily: String? = nil,
        fontSize: Double? = nil,
        themeName: String? = nil,
        shell: String? = nil,
        workingDirectory: URL? = nil,
        themePalette: ThemePalette? = nil,
        windowPaddingX: Double? = nil,
        windowPaddingY: Double? = nil,
        clipboardReadAccess: ClipboardReadAccess? = nil,
        clipboardWriteAccess: ClipboardWriteAccess? = nil,
        appLanguage: AppLanguage? = nil,
        hookIntegration: HookIntegrationConfig? = nil,
        ligaturesEnabled: Bool? = nil,
        fontThickenEnabled: Bool? = nil,
        imageMemoryLimitBytes: UInt64? = nil,
        imageFileTransferEnabled: Bool? = nil,
        sixelImagesEnabled: Bool? = nil,
        kittyImagesEnabled: Bool? = nil,
        iterm2ImagesEnabled: Bool? = nil,
        imageDiskCacheDirectory: URL? = nil,
        clearsImageDiskCacheDirectory: Bool = false,
        imageDiskCacheLimitBytes: UInt64? = nil
    ) -> TerminalEngineConfig {
        TerminalEngineConfig(
            fontFamily: fontFamily ?? self.fontFamily,
            fontSize: fontSize ?? self.fontSize,
            themeName: themeName ?? self.themeName,
            shell: shell ?? self.shell,
            workingDirectory: workingDirectory ?? self.workingDirectory,
            themePalette: themePalette ?? self.themePalette,
            windowPaddingX: windowPaddingX ?? self.windowPaddingX,
            windowPaddingY: windowPaddingY ?? self.windowPaddingY,
            clipboardReadAccess: clipboardReadAccess ?? self.clipboardReadAccess,
            clipboardWriteAccess: clipboardWriteAccess ?? self.clipboardWriteAccess,
            appLanguage: appLanguage ?? self.appLanguage,
            hookIntegration: hookIntegration ?? self.hookIntegration,
            ligaturesEnabled: ligaturesEnabled ?? self.ligaturesEnabled,
            fontThickenEnabled: fontThickenEnabled ?? self.fontThickenEnabled,
            imageMemoryLimitBytes: imageMemoryLimitBytes ?? self.imageMemoryLimitBytes,
            imageFileTransferEnabled: imageFileTransferEnabled ?? self.imageFileTransferEnabled,
            sixelImagesEnabled: sixelImagesEnabled ?? self.sixelImagesEnabled,
            kittyImagesEnabled: kittyImagesEnabled ?? self.kittyImagesEnabled,
            iterm2ImagesEnabled: iterm2ImagesEnabled ?? self.iterm2ImagesEnabled,
            imageDiskCacheDirectory: clearsImageDiskCacheDirectory
                ? nil
                : (imageDiskCacheDirectory ?? self.imageDiskCacheDirectory),
            imageDiskCacheLimitBytes: imageDiskCacheLimitBytes ?? self.imageDiskCacheLimitBytes
        )
    }
}

/// Errors that can occur during terminal engine operations.
enum TerminalEngineError: Error, Sendable {
    /// The engine could not be initialized (e.g., Metal not available).
    case initializationFailed(reason: String)
    /// A surface could not be created.
    case surfaceCreationFailed(reason: String)
    /// The specified surface was not found.
    case surfaceNotFound(SurfaceID)
}

/// Placeholder typealias for the native view that hosts a terminal surface.
///
/// In production this will be an `NSView` subclass from AppKit.
/// It is defined here as a protocol so the domain layer does not import AppKit.
///
/// - Note: The concrete type is an `NSView` subclass such as `CocxyCoreView`.
#if canImport(AppKit)
import AppKit
typealias NativeTerminalView = NSView
#else
// Fallback for non-macOS platforms (Linux future) — not used today.
final class NativeTerminalView {}
#endif
