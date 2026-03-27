// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionManager.swift - Session persistence and restoration.

import Foundation

// MARK: - Session Manager

/// Concrete implementation of `SessionManaging`.
///
/// Persists application state as versioned JSON files in
/// `~/.config/cocxy/sessions/`. Supports:
/// - Auto-save every N seconds (configurable, default 30s).
/// - Named sessions for manual save/restore.
/// - Graceful degradation: if a persisted directory no longer exists,
///   falls back to home directory instead of crashing.
/// - Forward-compatible versioning: rejects files with version > current.
///
/// ## File layout
///
/// ```
/// ~/.config/cocxy/sessions/
///   last.json          <- unnamed (auto-save / default)
///   my-workflow.json   <- named session
/// ```
///
/// ## Thread safety
///
/// Saves are dispatched to a serial background queue to avoid blocking the
/// main thread. Loads are synchronous (called during launch before UI shows).
///
/// - SeeAlso: `SessionManaging` protocol
/// - SeeAlso: `Session`, `WindowState`, `TabState`, `SplitNodeState`
final class SessionManagerImpl: SessionManaging {

    // MARK: - Constants

    /// File name used for the unnamed (auto-save) session.
    private static let lastSessionFileName = "last.json"

    // MARK: - Properties

    /// Directory where session files are stored.
    private let sessionsDirectory: URL

    /// Serial queue for background file I/O.
    private let ioQueue = DispatchQueue(label: "com.cocxy.session-io", qos: .utility)

    /// JSON encoder configured for readable output.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// JSON decoder matching the encoder configuration.
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Active auto-save timer, if running.
    private var autoSaveTimer: DispatchSourceTimer?

    // MARK: - Initialization

    /// Creates a session manager that stores files in the given directory.
    ///
    /// - Parameter sessionsDirectory: Path to the sessions directory.
    ///   Defaults to `~/.config/cocxy/sessions/`.
    init(sessionsDirectory: URL? = nil) {
        if let directory = sessionsDirectory {
            self.sessionsDirectory = directory
        } else {
            let configBase = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/cocxy/sessions")
            self.sessionsDirectory = configBase
        }
    }

    // MARK: - SessionManaging

    /// Serializes concurrent save operations (auto-save on ioQueue vs
    /// termination save on main thread).
    private let saveLock = NSLock()

    func saveSession(_ session: Session, named name: String?) throws {
        saveLock.lock()
        defer { saveLock.unlock() }

        let fileURL = fileURL(for: name)

        try ensureDirectoryExists()

        let data: Data
        do {
            data = try encoder.encode(session)
        } catch {
            throw SessionError.writeFailed(reason: "Failed to encode session: \(error.localizedDescription)")
        }

        do {
            try data.write(to: fileURL, options: .atomic)
            // Set file permissions to 0600 (owner read/write only) for session data security.
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            throw SessionError.writeFailed(reason: "Failed to write to \(fileURL.path): \(error.localizedDescription)")
        }
    }

    func loadLastSession() throws -> Session? {
        return try loadFromFile(fileURL(for: nil))
    }

    func loadSession(named name: String) throws -> Session? {
        return try loadFromFile(fileURL(for: name))
    }

    func listSessions() -> [SessionMetadata] {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: sessionsDirectory.path) else {
            return []
        }

        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        let jsonFiles = fileURLs.filter { $0.pathExtension == "json" }

        let metadataList: [SessionMetadata] = jsonFiles.compactMap { fileURL in
            guard let data = try? Data(contentsOf: fileURL),
                  let session = try? decoder.decode(Session.self, from: data) else {
                return nil
            }

            let name = fileURL.deletingPathExtension().lastPathComponent
            let totalTabs = session.windows.reduce(0) { $0 + $1.tabs.count }

            return SessionMetadata(
                name: name,
                savedAt: session.savedAt,
                windowCount: session.windows.count,
                tabCount: totalTabs
            )
        }

        return metadataList.sorted { $0.savedAt > $1.savedAt }
    }

    func deleteSession(named name: String) throws {
        let fileURL = fileURL(for: name)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SessionError.deleteFailed(reason: "Session '\(name)' does not exist at \(fileURL.path)")
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw SessionError.deleteFailed(reason: "Failed to delete \(fileURL.path): \(error.localizedDescription)")
        }
    }

    // MARK: - Session Existence

    /// Checks whether a session file exists.
    ///
    /// - Parameter name: The session name, or `nil` for the unnamed (last) session.
    /// - Returns: `true` if the session file exists on disk.
    func sessionExists(named name: String?) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: name).path)
    }

    // MARK: - Auto-save

    /// Starts periodic auto-saving on a background queue.
    ///
    /// The `captureSession` closure is called on the timer's queue to obtain
    /// the current session state. The result is saved to the unnamed session file.
    ///
    /// - Parameters:
    ///   - intervalSeconds: Time between saves in seconds.
    ///   - captureSession: Closure that returns the current session state.
    func startAutoSave(intervalSeconds: TimeInterval, captureSession: @escaping () -> Session) {
        stopAutoSave()

        let timer = DispatchSource.makeTimerSource(queue: ioQueue)
        timer.schedule(
            deadline: .now() + intervalSeconds,
            repeating: intervalSeconds
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let session = captureSession()
            do {
                try self.saveSession(session, named: nil)
            } catch {
                // Log warning but do not crash. Session auto-save is best-effort.
                #if DEBUG
                print("[SessionManager] Auto-save failed: \(error)")
                #endif
            }
        }
        timer.resume()

        autoSaveTimer = timer
    }

    /// Stops the auto-save timer.
    func stopAutoSave() {
        autoSaveTimer?.cancel()
        autoSaveTimer = nil
    }

    // MARK: - Async Save

    /// Saves a session asynchronously on a background queue.
    ///
    /// Errors are logged but do not propagate -- this is a fire-and-forget
    /// operation suitable for periodic auto-saves.
    ///
    /// - Parameter session: The session state to persist.
    func saveAsync(_ session: Session) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.saveSession(session, named: nil)
            } catch {
                #if DEBUG
                print("[SessionManager] Async save failed: \(error)")
                #endif
            }
        }
    }

    // MARK: - Private Helpers

    /// Returns the file URL for a session name.
    ///
    /// A `nil` name maps to `last.json` (the auto-save session).
    private func fileURL(for name: String?) -> URL {
        let safeName = (name ?? "last")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "..", with: "_")
        let fileName = safeName + ".json"
        let url = sessionsDirectory.appendingPathComponent(fileName)
        guard url.standardizedFileURL.path.hasPrefix(sessionsDirectory.standardizedFileURL.path) else {
            return sessionsDirectory.appendingPathComponent("last.json")
        }
        return url
    }

    /// Creates the sessions directory if it does not exist.
    private func ensureDirectoryExists() throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: sessionsDirectory.path) {
            do {
                try fileManager.createDirectory(
                    at: sessionsDirectory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw SessionError.writeFailed(
                    reason: "Failed to create directory \(sessionsDirectory.path): \(error.localizedDescription)"
                )
            }
        }
    }

    /// Loads and validates a session from a file URL.
    ///
    /// Returns `nil` if the file does not exist.
    /// Throws `SessionError.parseFailed` if the JSON is invalid.
    /// Throws `SessionError.unsupportedVersion` if the schema version is too new.
    private func loadFromFile(_ fileURL: URL) throws -> Session? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw SessionError.parseFailed(reason: "Failed to read \(fileURL.path): \(error.localizedDescription)")
        }

        let session: Session
        do {
            session = try decoder.decode(Session.self, from: data)
        } catch {
            throw SessionError.parseFailed(reason: "Failed to decode JSON: \(error.localizedDescription)")
        }

        guard session.version <= Session.currentVersion else {
            throw SessionError.unsupportedVersion(
                found: session.version,
                supported: Session.currentVersion
            )
        }

        return session
    }
}
