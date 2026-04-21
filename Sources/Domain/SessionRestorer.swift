// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionRestorer.swift - Restores application state from a saved session.

import Foundation

// MARK: - Session Restorer

/// Restores application state from a saved `Session`.
///
/// Takes a deserialized session and reconstructs the tab list, split trees,
/// and window frame. Handles graceful degradation:
///
/// - Missing working directories fall back to the user's home directory.
/// - Window frames outside the current screen bounds are reset to a default.
/// - Invalid active tab indices fall back to the first tab.
///
/// This is a stateless utility: it takes input, validates it, and produces
/// a `RestorationResult` that the caller (typically `AppDelegate`) uses to
/// set up the UI.
///
/// - SeeAlso: `SessionManagerImpl` for loading the `Session` from disk.
/// - SeeAlso: `RestorationResult` for the output structure.
enum SessionRestorer {

    // MARK: - Constants

    /// Minimum overlap in pixels for a window to be considered "on screen".
    /// If the window overlaps less than this with the screen, it's repositioned.
    private static let minimumVisibleOverlap: Double = 100

    /// Default window size used when the saved frame is off-screen.
    private static let defaultWindowSize = CodableRect(
        x: 100, y: 100, width: 1200, height: 800
    )

    // MARK: - Public API

    /// Restores tabs and window state from the first window in a session.
    ///
    /// For single-window restore or the primary window of a multi-window
    /// session. Each tab is validated: directories are checked for existence,
    /// and the split tree is converted from `SplitNodeState` to `SplitNode`.
    ///
    /// - Parameters:
    ///   - session: The session to restore from.
    ///   - tabManager: The tab manager to populate (not modified directly;
    ///     the caller uses the result to do so).
    ///   - splitCoordinator: The split coordinator for setting up split managers.
    ///   - screenBounds: The current screen bounds for frame validation.
    /// - Returns: A `RestorationResult` describing the restored state.
    static func restore(
        from session: Session,
        into tabManager: TabManager,
        splitCoordinator: TabSplitCoordinator,
        screenBounds: CodableRect
    ) -> RestorationResult {
        guard let windowState = session.windows.first else {
            return RestorationResult(
                restoredTabs: [],
                activeTabIndex: 0,
                windowFrame: defaultWindowSize,
                isFullScreen: false
            )
        }
        return restoreWindow(from: windowState, screenBounds: screenBounds)
    }

    /// Restores all windows from a session.
    ///
    /// Returns one `RestorationResult` per `WindowState` in the session,
    /// plus the index of the window that should be key (focused).
    ///
    /// - Parameters:
    ///   - session: The session to restore from.
    ///   - screenBounds: The current screen bounds for frame validation.
    /// - Returns: A `MultiWindowRestorationResult` with all windows.
    static func restoreAllWindows(
        from session: Session,
        screenBounds: CodableRect
    ) -> MultiWindowRestorationResult {
        guard !session.windows.isEmpty else {
            return MultiWindowRestorationResult(
                windows: [],
                focusedWindowIndex: 0
            )
        }

        let windows = session.windows.map { windowState in
            restoreWindow(from: windowState, screenBounds: screenBounds)
        }

        let focusedIndex = session.focusedWindowIndex >= 0
            && session.focusedWindowIndex < windows.count
            ? session.focusedWindowIndex
            : 0

        return MultiWindowRestorationResult(
            windows: windows,
            focusedWindowIndex: focusedIndex
        )
    }

    /// Restores a single window from its saved state.
    static func restoreWindow(
        from windowState: WindowState,
        screenBounds: CodableRect
    ) -> RestorationResult {
        guard !windowState.tabs.isEmpty else {
            return RestorationResult(
                restoredTabs: [],
                activeTabIndex: 0,
                windowFrame: validateFrame(
                    windowState.frame,
                    screenBounds: screenBounds
                ),
                isFullScreen: windowState.isFullScreen
            )
        }

        let restoredTabs = windowState.tabs.map { tabState in
            restoreTab(from: tabState)
        }

        let validActiveIndex: Int
        if windowState.activeTabIndex >= 0
            && windowState.activeTabIndex < restoredTabs.count {
            validActiveIndex = windowState.activeTabIndex
        } else {
            validActiveIndex = 0
        }

        let validFrame = validateFrame(
            windowState.frame,
            screenBounds: screenBounds
        )

        return RestorationResult(
            restoredTabs: restoredTabs,
            activeTabIndex: validActiveIndex,
            windowFrame: validFrame,
            isFullScreen: windowState.isFullScreen
        )
    }

    // MARK: - Private Helpers

    /// Restores a single tab from its saved state.
    ///
    /// Validates the working directory and converts the split tree.
    private static func restoreTab(from tabState: TabState) -> RestoredTab {
        let validatedDirectory = validateDirectory(tabState.workingDirectory)
        let validatedSplitTree = validateSplitTree(tabState.splitTree)
        let splitNode = validatedSplitTree.toSplitNode()

        return RestoredTab(
            tabID: tabState.id,
            sessionID: tabState.sessionID,
            title: tabState.title ?? "Terminal",
            workingDirectory: validatedDirectory,
            splitTreeState: validatedSplitTree,
            splitNode: splitNode,
            // Propagate worktree metadata verbatim. The SessionManagement
            // restore code uses these to reconstruct the Tab with its
            // original worktree state, and to feed
            // `loadConfig(for:originRepo:)` with the origin repo fallback.
            worktreeID: tabState.worktreeID,
            worktreeRoot: tabState.worktreeRoot,
            worktreeOriginRepo: tabState.worktreeOriginRepo,
            worktreeBranch: tabState.worktreeBranch
        )
    }

    private static func validateSplitTree(_ state: SplitNodeState) -> SplitNodeState {
        switch state {
        case .leaf(let workingDirectory, let command):
            return .leaf(
                workingDirectory: validateDirectory(workingDirectory),
                command: command
            )

        case .split(let direction, let first, let second, let ratio):
            return .split(
                direction: direction,
                first: validateSplitTree(first),
                second: validateSplitTree(second),
                ratio: ratio
            )
        }
    }

    /// Validates that a directory exists. Falls back to home if it does not.
    private static func validateDirectory(_ directory: URL) -> URL {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return directory
        }

        #if DEBUG
        print("[SessionRestorer] Directory does not exist, falling back to home: \(directory.path)")
        #endif

        return fileManager.homeDirectoryForCurrentUser
    }

    /// Validates that a window frame is reasonably visible on the current screen.
    ///
    /// A frame is considered "visible" if at least `minimumVisibleOverlap` pixels
    /// of the frame overlap with the screen bounds in both X and Y.
    private static func validateFrame(
        _ frame: CodableRect,
        screenBounds: CodableRect
    ) -> CodableRect {
        let overlapX = min(frame.x + frame.width, screenBounds.x + screenBounds.width)
            - max(frame.x, screenBounds.x)
        let overlapY = min(frame.y + frame.height, screenBounds.y + screenBounds.height)
            - max(frame.y, screenBounds.y)

        let isReasonablyVisible = overlapX >= minimumVisibleOverlap
            && overlapY >= minimumVisibleOverlap

        if isReasonablyVisible {
            return frame
        }

        #if DEBUG
        print("[SessionRestorer] Window frame off-screen, using default: \(frame)")
        #endif

        // Center the default frame on the screen.
        let centeredX = screenBounds.x + (screenBounds.width - defaultWindowSize.width) / 2
        let centeredY = screenBounds.y + (screenBounds.height - defaultWindowSize.height) / 2
        return CodableRect(
            x: centeredX,
            y: centeredY,
            width: defaultWindowSize.width,
            height: defaultWindowSize.height
        )
    }
}

// MARK: - Restoration Result

/// The output of a session restoration.
///
/// Contains all the information needed to reconstruct the application's UI state.
/// The caller (typically `AppDelegate`) uses this to create tabs, set up split
/// managers, position the window, etc.
struct RestorationResult: Sendable {
    /// The tabs restored from the session, in their original order.
    let restoredTabs: [RestoredTab]
    /// The index of the tab that should be active after restoration.
    let activeTabIndex: Int
    /// The validated window frame (adjusted if it was off-screen).
    let windowFrame: CodableRect
    /// Whether the window was in full-screen mode.
    let isFullScreen: Bool
}

// MARK: - Restored Tab

/// The output of a multi-window session restoration.
///
/// Contains one `RestorationResult` per window, plus which window should
/// be made key (focused) after all windows are created.
struct MultiWindowRestorationResult: Sendable {
    /// One result per window, in the same order as the session's windows.
    let windows: [RestorationResult]
    /// Index of the window that should be key after restoration.
    let focusedWindowIndex: Int
}

/// A single tab reconstructed from session state.
///
/// Contains the validated working directory, the converted split tree,
/// and the original tab metadata.
struct RestoredTab: Sendable {
    /// The original tab ID from the session.
    let tabID: TabID
    /// Stable session ID restored from disk (or synthesized for v1 sessions).
    let sessionID: SessionID
    /// The tab's display title.
    let title: String
    /// The validated working directory (falls back to home if the saved path was missing).
    let workingDirectory: URL
    /// The serialized split tree used to rebuild surfaces during restore.
    let splitTreeState: SplitNodeState
    /// The split tree converted from `SplitNodeState` to `SplitNode`.
    let splitNode: SplitNode
    /// Cocxy-managed worktree identifier, if the tab was attached to a
    /// worktree when the session was saved. Added in v0.1.81.
    let worktreeID: String?
    /// Immutable on-disk worktree root, if `worktreeID` is set.
    let worktreeRoot: URL?
    /// Origin repository the worktree was created from.
    let worktreeOriginRepo: URL?
    /// Cached branch name of the worktree at save time.
    let worktreeBranch: String?
}
