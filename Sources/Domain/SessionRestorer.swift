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

    /// Restores tabs and window state from a saved session.
    ///
    /// The restorer processes the first window in the session (multi-window
    /// support will come in a future iteration). Each tab is validated:
    /// directories are checked for existence, and the split tree is converted
    /// from `SplitNodeState` to `SplitNode`.
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
        // Handle empty session.
        guard let windowState = session.windows.first else {
            return RestorationResult(
                restoredTabs: [],
                activeTabIndex: 0,
                windowFrame: defaultWindowSize,
                isFullScreen: false
            )
        }

        // Handle empty tabs.
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

        // Restore each tab.
        let restoredTabs = windowState.tabs.map { tabState in
            restoreTab(from: tabState)
        }

        // Validate active tab index.
        let validActiveIndex: Int
        if windowState.activeTabIndex >= 0
            && windowState.activeTabIndex < restoredTabs.count {
            validActiveIndex = windowState.activeTabIndex
        } else {
            validActiveIndex = 0
        }

        // Validate window frame.
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
        let splitNode = tabState.splitTree.toSplitNode()

        return RestoredTab(
            tabID: tabState.id,
            title: tabState.title ?? "Terminal",
            workingDirectory: validatedDirectory,
            splitNode: splitNode
        )
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

/// A single tab reconstructed from session state.
///
/// Contains the validated working directory, the converted split tree,
/// and the original tab metadata.
struct RestoredTab: Sendable {
    /// The original tab ID from the session.
    let tabID: TabID
    /// The tab's display title.
    let title: String
    /// The validated working directory (falls back to home if the saved path was missing).
    let workingDirectory: URL
    /// The split tree converted from `SplitNodeState` to `SplitNode`.
    let splitNode: SplitNode
}
