// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonSessionBridge.swift - Bridges daemon sessions to local terminal.

import Foundation

// MARK: - Daemon Session Bridge

/// Connects remote daemon sessions to the local terminal display.
///
/// Sends `session.attach(id)` to the daemon and establishes
/// bidirectional I/O. When SSH disconnects, the remote session
/// persists in the daemon. On reconnect, `attach` is called again
/// for seamless resumption.
/// Callback type for receiving output data from the daemon session.
typealias SessionOutputHandler = @MainActor (Data) -> Void

/// Callback type for receiving session disconnect events.
typealias SessionDisconnectHandler = @MainActor () -> Void

@MainActor
final class DaemonSessionBridge: ObservableObject {

    // MARK: - State

    @Published private(set) var attachedSessionID: String?
    @Published private(set) var isAttached = false

    // MARK: - I/O Callbacks

    /// Called when output data is received from the remote session.
    /// The consumer (e.g., TerminalSurfaceView) registers this to display output.
    var onOutput: SessionOutputHandler?

    /// Called when the session disconnects unexpectedly.
    var onDisconnect: SessionDisconnectHandler?

    /// Task that continuously reads output from the daemon.
    private var readTask: Task<Void, Never>?

    // MARK: - Dependencies

    private let connection: DaemonConnection

    init(connection: DaemonConnection) {
        self.connection = connection
    }

    // MARK: - Attach

    /// Attaches to a remote daemon session.
    ///
    /// Sends the `session.attach` command. After attachment,
    /// I/O flows bidirectionally through the daemon connection.
    ///
    /// - Parameter sessionID: The daemon session ID to attach to.
    func attach(sessionID: String) async throws {
        guard connection.isConnected else {
            throw DaemonProtocolError.connectionLost
        }

        let response = try await connection.send(
            cmd: DaemonCommand.sessionAttach.rawValue,
            args: ["id": sessionID]
        )

        guard response.ok else {
            throw DaemonProtocolError.invalidResponse
        }

        attachedSessionID = sessionID
        isAttached = true

        // Start reading output from the daemon session.
        startOutputReader(sessionID: sessionID)
    }

    // MARK: - Detach

    /// Detaches from the current session without killing it.
    ///
    /// The remote session continues running in the daemon.
    func detach() async {
        guard let sessionID = attachedSessionID else { return }

        readTask?.cancel()
        readTask = nil

        _ = try? await connection.send(
            cmd: DaemonCommand.sessionDetach.rawValue,
            args: ["id": sessionID]
        )

        attachedSessionID = nil
        isAttached = false
    }

    // MARK: - Input (keyboard → daemon → remote PTY)

    /// Sends keyboard input to the attached remote session.
    ///
    /// - Parameter data: Raw bytes from the local keyboard/terminal.
    func sendInput(_ data: Data) async {
        guard let sessionID = attachedSessionID, isAttached else { return }

        let base64Input = data.base64EncodedString()
        _ = try? await connection.send(
            cmd: DaemonCommand.sessionInput.rawValue,
            args: ["id": sessionID, "data": base64Input]
        )
    }

    // MARK: - Output Reader (daemon → local terminal)

    /// Continuously polls the daemon for session output.
    ///
    /// The daemon sends output data as base64-encoded chunks in
    /// response to `session.output` requests. This loop runs every
    /// 50ms while attached, forwarding data to the `onOutput` handler.
    private func startOutputReader(sessionID: String) {
        readTask?.cancel()
        readTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isAttached, self.connection.isConnected else {
                    await self?.handleDisconnect()
                    return
                }

                if let response = try? await self.connection.send(
                    cmd: DaemonCommand.sessionOutput.rawValue,
                    args: ["id": sessionID]
                ) {
                    if response.ok, let data = response.data,
                       let encoded = data["data"] as? String,
                       let bytes = Data(base64Encoded: encoded),
                       !bytes.isEmpty {
                        self.onOutput?(bytes)
                    }
                }

                // Poll interval: 50ms for responsive feel.
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func handleDisconnect() {
        attachedSessionID = nil
        isAttached = false
        onDisconnect?()
    }

    // MARK: - Create and Attach

    /// Creates a new remote session and attaches to it.
    ///
    /// - Parameter title: Human-readable session name.
    /// - Returns: The created session ID.
    @discardableResult
    func createAndAttach(title: String) async throws -> String {
        let response = try await connection.send(
            cmd: DaemonCommand.sessionCreate.rawValue,
            args: ["title": title]
        )

        guard response.ok, let data = response.data,
              let sessionID = data["id"] as? String
        else {
            throw DaemonProtocolError.invalidResponse
        }

        try await attach(sessionID: sessionID)
        return sessionID
    }

    // MARK: - List Sessions

    /// Lists all sessions on the remote daemon.
    func listSessions() async throws -> [DaemonSessionInfo] {
        let response = try await connection.send(cmd: DaemonCommand.sessionList.rawValue)

        guard response.ok, let data = response.data,
              let sessions = data["sessions"] as? [[String: Any]]
        else {
            return []
        }

        return sessions.compactMap { DaemonSessionInfo.from(dict: $0) }
    }

    // MARK: - Kill Session

    /// Kills a remote session.
    func killSession(sessionID: String) async throws {
        let response = try await connection.send(
            cmd: DaemonCommand.sessionKill.rawValue,
            args: ["id": sessionID]
        )

        guard response.ok else {
            throw DaemonProtocolError.invalidResponse
        }

        if attachedSessionID == sessionID {
            attachedSessionID = nil
            isAttached = false
        }
    }
}
