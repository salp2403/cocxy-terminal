// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionRegistry.swift - Central session tracking for multi-window support.

import Foundation
import Combine

// MARK: - Protocol

/// Contract for the central session registry.
///
/// The registry tracks every terminal session across all windows, enabling:
/// - Cross-window tab drag-and-drop.
/// - Synchronized notification badges.
/// - Shared agent detection state.
/// - Window-to-window event broadcasting.
/// - Multi-window session save/restore.
///
/// All mutations happen on `@MainActor`. Publishers emit on the main thread.
/// Inject via protocol for testability — each test gets a fresh instance.
///
/// - SeeAlso: `SessionRegistryImpl` for the production implementation.
/// - SeeAlso: `SessionRegistryTypes.swift` for the data types.
@MainActor
protocol SessionRegistering: AnyObject {

    // MARK: - Session CRUD

    /// Registers a new session in the registry.
    ///
    /// Called when a tab is created. The session ID should be unique.
    /// Duplicate registrations (same session ID) are silently ignored.
    ///
    /// - Parameter entry: The session metadata to register.
    func registerSession(_ entry: SessionEntry)

    /// Removes a session from the registry.
    ///
    /// Called when a tab is closed. Removes the entry and publishes
    /// a removal event. Removing a non-existent session is a no-op.
    ///
    /// - Parameter sessionID: The session to remove.
    func removeSession(_ sessionID: SessionID)

    /// Returns the entry for a specific session.
    ///
    /// - Parameter sessionID: The session to look up.
    /// - Returns: The session entry, or `nil` if not registered.
    func session(for sessionID: SessionID) -> SessionEntry?

    /// Returns all sessions owned by a specific window.
    ///
    /// - Parameter windowID: The window to filter by.
    /// - Returns: Sessions owned by that window, in no particular order.
    func sessions(in windowID: WindowID) -> [SessionEntry]

    /// Returns all registered sessions.
    var allSessions: [SessionEntry] { get }

    /// Total number of registered sessions across all windows.
    var sessionCount: Int { get }

    // MARK: - Session Updates

    /// Updates the title of a session.
    func updateTitle(_ sessionID: SessionID, title: String)

    /// Updates the working directory of a session.
    func updateWorkingDirectory(_ sessionID: SessionID, directory: URL)

    /// Updates the agent state of a session.
    func updateAgentState(_ sessionID: SessionID, state: AgentState, agentName: String?)

    /// Marks a session as having unread notifications.
    func markUnread(_ sessionID: SessionID)

    /// Marks a session as read (clears unread state).
    func markRead(_ sessionID: SessionID)

    // MARK: - Transfer Lifecycle

    /// Prepares a session for transfer between windows.
    ///
    /// Marks the session as `.inTransfer`. Only one transfer per session
    /// is allowed at a time.
    ///
    /// - Parameters:
    ///   - sessionID: The session to transfer.
    ///   - from: The source window.
    ///   - to: The destination window.
    /// - Returns: `true` if the transfer was initiated, `false` if the
    ///   session is already mid-transfer or does not exist.
    @discardableResult
    func prepareTransfer(_ sessionID: SessionID, from: WindowID, to: WindowID) -> Bool

    /// Completes a pending transfer.
    ///
    /// Updates the session's owner to the destination window and resets
    /// the transfer state to `.stable`.
    ///
    /// - Parameters:
    ///   - sessionID: The session being transferred.
    ///   - newTabID: The tab ID in the destination window.
    func completeTransfer(_ sessionID: SessionID, newTabID: TabID)

    /// Cancels a pending transfer.
    ///
    /// Resets the transfer state to `.stable` without changing ownership.
    ///
    /// - Parameter sessionID: The session whose transfer to cancel.
    func cancelTransfer(_ sessionID: SessionID)

    // MARK: - Window Management

    /// Registers a window with the registry.
    ///
    /// Called from `MainWindowController.init`. The registry does not
    /// hold strong references to controllers — only tracks IDs.
    ///
    /// - Parameter windowID: The window to register.
    func registerWindow(_ windowID: WindowID)

    /// Removes a window and all its sessions.
    ///
    /// Called from `MainWindowController.windowWillClose`. Sessions owned
    /// by this window are removed (cascade delete) and removal events
    /// are published for each one.
    ///
    /// - Parameter windowID: The window to remove.
    func removeWindow(_ windowID: WindowID)

    /// Returns all registered window IDs.
    var windowIDs: Set<WindowID> { get }

    /// Number of registered windows.
    var windowCount: Int { get }

    // MARK: - Publishers

    /// Emits when a new session is registered.
    var sessionAdded: AnyPublisher<SessionEntry, Never> { get }

    /// Emits when a session is removed.
    var sessionRemoved: AnyPublisher<SessionRemovalEvent, Never> { get }

    /// Emits when a session's metadata changes.
    var sessionUpdated: AnyPublisher<SessionChangeEvent, Never> { get }
}

// MARK: - Implementation

/// Production implementation of the session registry.
///
/// Stores sessions in a flat dictionary for O(1) lookup by `SessionID`.
/// Window-scoped queries filter the dictionary (O(n), acceptable for
/// the expected session counts of < 100).
///
/// The registry does NOT hold strong references to `MainWindowController`
/// or `TerminalViewModel` — those remain owned by their respective
/// controllers. The registry only stores lightweight `SessionEntry`
/// value types.
///
/// ## Memory Model
///
/// ```
/// SessionRegistryImpl
///   ├── sessions: [SessionID: SessionEntry]    (value types, no retain cycles)
///   ├── windows: Set<WindowID>                 (value types)
///   └── subjects: PassthroughSubject<...>      (owned, cleaned up with registry)
/// ```
@MainActor
final class SessionRegistryImpl: SessionRegistering {

    // MARK: - Storage

    private var sessions: [SessionID: SessionEntry] = [:]
    private var windows: Set<WindowID> = []

    // MARK: - Subjects

    private let sessionAddedSubject = PassthroughSubject<SessionEntry, Never>()
    private let sessionRemovedSubject = PassthroughSubject<SessionRemovalEvent, Never>()
    private let sessionUpdatedSubject = PassthroughSubject<SessionChangeEvent, Never>()

    // MARK: - Publishers

    var sessionAdded: AnyPublisher<SessionEntry, Never> {
        sessionAddedSubject.eraseToAnyPublisher()
    }

    var sessionRemoved: AnyPublisher<SessionRemovalEvent, Never> {
        sessionRemovedSubject.eraseToAnyPublisher()
    }

    var sessionUpdated: AnyPublisher<SessionChangeEvent, Never> {
        sessionUpdatedSubject.eraseToAnyPublisher()
    }

    // MARK: - Session CRUD

    func registerSession(_ entry: SessionEntry) {
        windows.insert(entry.ownerWindowID)
        // Duplicate registration is a no-op.
        guard sessions[entry.sessionID] == nil else { return }
        sessions[entry.sessionID] = entry
        sessionAddedSubject.send(entry)
    }

    func removeSession(_ sessionID: SessionID) {
        guard let removed = sessions.removeValue(forKey: sessionID) else { return }
        sessionRemovedSubject.send(SessionRemovalEvent(
            sessionID: sessionID,
            windowID: removed.ownerWindowID
        ))
    }

    func session(for sessionID: SessionID) -> SessionEntry? {
        sessions[sessionID]
    }

    func sessions(in windowID: WindowID) -> [SessionEntry] {
        sessions.values.filter { $0.ownerWindowID == windowID }
    }

    var allSessions: [SessionEntry] {
        Array(sessions.values)
    }

    var sessionCount: Int {
        sessions.count
    }

    // MARK: - Session Updates

    func updateTitle(_ sessionID: SessionID, title: String) {
        guard var entry = sessions[sessionID] else { return }
        let old = entry.title
        guard old != title else { return }
        entry.title = title
        sessions[sessionID] = entry
        sessionUpdatedSubject.send(SessionChangeEvent(
            sessionID: sessionID,
            windowID: entry.ownerWindowID,
            change: .titleChanged(old: old, new: title)
        ))
    }

    func updateWorkingDirectory(_ sessionID: SessionID, directory: URL) {
        guard var entry = sessions[sessionID] else { return }
        let old = entry.workingDirectory
        guard old != directory else { return }
        entry.workingDirectory = directory
        sessions[sessionID] = entry
        sessionUpdatedSubject.send(SessionChangeEvent(
            sessionID: sessionID,
            windowID: entry.ownerWindowID,
            change: .workingDirectoryChanged(old: old, new: directory)
        ))
    }

    func updateAgentState(_ sessionID: SessionID, state: AgentState, agentName: String?) {
        guard var entry = sessions[sessionID] else { return }
        let old = entry.agentState
        guard old != state || entry.detectedAgentName != agentName else { return }
        entry.agentState = state
        entry.detectedAgentName = agentName
        sessions[sessionID] = entry
        sessionUpdatedSubject.send(SessionChangeEvent(
            sessionID: sessionID,
            windowID: entry.ownerWindowID,
            change: .agentStateChanged(old: old, new: state)
        ))
    }

    func markUnread(_ sessionID: SessionID) {
        guard var entry = sessions[sessionID] else { return }
        guard !entry.hasUnreadNotification else { return }
        entry.hasUnreadNotification = true
        sessions[sessionID] = entry
        sessionUpdatedSubject.send(SessionChangeEvent(
            sessionID: sessionID,
            windowID: entry.ownerWindowID,
            change: .notificationStateChanged(hasUnread: true)
        ))
    }

    func markRead(_ sessionID: SessionID) {
        guard var entry = sessions[sessionID] else { return }
        guard entry.hasUnreadNotification else { return }
        entry.hasUnreadNotification = false
        sessions[sessionID] = entry
        sessionUpdatedSubject.send(SessionChangeEvent(
            sessionID: sessionID,
            windowID: entry.ownerWindowID,
            change: .notificationStateChanged(hasUnread: false)
        ))
    }

    // MARK: - Transfer Lifecycle

    @discardableResult
    func prepareTransfer(_ sessionID: SessionID, from: WindowID, to: WindowID) -> Bool {
        guard var entry = sessions[sessionID] else { return false }

        // Reject if already mid-transfer.
        if case .inTransfer = entry.transferState { return false }

        // Source must match current owner.
        guard entry.ownerWindowID == from else { return false }

        // Source and destination must be different.
        guard from != to else { return false }

        entry.transferState = .inTransfer(from: from, to: to)
        sessions[sessionID] = entry
        sessionUpdatedSubject.send(SessionChangeEvent(
            sessionID: sessionID,
            windowID: entry.ownerWindowID,
            change: .transferStateChanged(old: .stable, new: entry.transferState)
        ))
        return true
    }

    func completeTransfer(_ sessionID: SessionID, newTabID: TabID) {
        guard var entry = sessions[sessionID] else { return }

        guard case .inTransfer(_, let to) = entry.transferState else { return }

        let oldWindow = entry.ownerWindowID
        entry.ownerWindowID = to
        entry.tabID = newTabID
        entry.transferState = .stable
        sessions[sessionID] = entry

        sessionUpdatedSubject.send(SessionChangeEvent(
            sessionID: sessionID,
            windowID: to,
            change: .ownerChanged(oldWindow: oldWindow, newWindow: to)
        ))
    }

    func cancelTransfer(_ sessionID: SessionID) {
        guard var entry = sessions[sessionID] else { return }
        let oldState = entry.transferState
        guard case .inTransfer = oldState else { return }
        entry.transferState = .stable
        sessions[sessionID] = entry
        sessionUpdatedSubject.send(SessionChangeEvent(
            sessionID: sessionID,
            windowID: entry.ownerWindowID,
            change: .transferStateChanged(old: oldState, new: .stable)
        ))
    }

    // MARK: - Window Management

    func registerWindow(_ windowID: WindowID) {
        windows.insert(windowID)
    }

    func removeWindow(_ windowID: WindowID) {
        guard windows.remove(windowID) != nil else { return }

        // Cancel transfers whose destination disappeared. Ownership stays in the
        // source window; only the in-flight transfer state is cleared.
        let redirectedTransfers = sessions.values
            .filter {
                if case .inTransfer(_, let to) = $0.transferState {
                    return to == windowID && $0.ownerWindowID != windowID
                }
                return false
            }
            .map(\.sessionID)

        for sessionID in redirectedTransfers {
            cancelTransfer(sessionID)
        }

        // Cascade: remove all sessions owned by this window.
        let ownedSessionIDs = sessions.values
            .filter { $0.ownerWindowID == windowID }
            .map(\.sessionID)

        for id in ownedSessionIDs {
            removeSession(id)
        }
    }

    var windowIDs: Set<WindowID> {
        windows
    }

    var windowCount: Int {
        windows.count
    }
}
