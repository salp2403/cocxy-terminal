// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonSessionBridge.swift - Bridges daemon sessions to local terminal.

import Foundation

// MARK: - Daemon Session Bridge

@MainActor
protocol DaemonSessionRPCSending: AnyObject {
    var isConnected: Bool { get }

    func sendSessionRPC(
        cmd: String,
        args: [String: String]?
    ) async throws -> DaemonResponse
}

extension DaemonConnection: DaemonSessionRPCSending {
    func sendSessionRPC(
        cmd: String,
        args: [String: String]?
    ) async throws -> DaemonResponse {
        try await send(cmd: cmd, args: args)
    }
}

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

private struct DaemonSnapshotCursor: Equatable {
    let x: Int
    let y: Int
}

private struct DaemonSnapshotState: Equatable {
    let bytes: Data
    let cursor: DaemonSnapshotCursor?
}

@MainActor
final class DaemonSessionBridge: ObservableObject {

    static let maximumQueuedInputBytes = 256 * 1_024
    static let activePollIntervalNanoseconds: UInt64 = 50_000_000
    static let idlePollIntervalNanoseconds: UInt64 = 150_000_000
    static let maximumConsecutiveReadFailures = 3

    static func isValidSessionIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= 128,
              value.first != "-" else {
            return false
        }
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._@$-"
        )
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    // MARK: - State

    @Published private(set) var attachedSessionID: String?
    @Published private(set) var isAttached = false

    // MARK: - I/O Callbacks

    /// Called when output data is received from the remote session.
    /// The consumer terminal host view registers this to display output.
    var onOutput: SessionOutputHandler?

    /// Called when the session disconnects unexpectedly.
    var onDisconnect: SessionDisconnectHandler?

    /// Task that continuously reads output from the daemon.
    private var readTask: Task<Void, Never>?
    private var inputDrainTask: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?
    private var queuedInputs: [Data] = []
    private var queuedInputReadIndex = 0
    private var queuedInputByteCount = 0
    private var pendingResize: TerminalSize?
    private var lastSnapshotState: DaemonSnapshotState?

    // MARK: - Dependencies

    private let connection: any DaemonSessionRPCSending
    private let activePollIntervalNanoseconds: UInt64
    private let idlePollIntervalNanoseconds: UInt64

    init(
        connection: any DaemonSessionRPCSending,
        activePollIntervalNanoseconds: UInt64 = DaemonSessionBridge.activePollIntervalNanoseconds,
        idlePollIntervalNanoseconds: UInt64 = DaemonSessionBridge.idlePollIntervalNanoseconds
    ) {
        self.connection = connection
        self.activePollIntervalNanoseconds = activePollIntervalNanoseconds
        self.idlePollIntervalNanoseconds = idlePollIntervalNanoseconds
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
        if isAttached {
            await detach()
        }

        let response = try await connection.sendSessionRPC(
            cmd: DaemonCommand.sessionAttach.rawValue,
            args: ["id": sessionID]
        )

        guard response.ok else {
            throw DaemonProtocolError.invalidResponse
        }

        attachedSessionID = sessionID
        isAttached = true
        lastSnapshotState = nil

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
        inputDrainTask?.cancel()
        inputDrainTask = nil
        resizeTask?.cancel()
        resizeTask = nil
        queuedInputs.removeAll(keepingCapacity: false)
        queuedInputReadIndex = 0
        queuedInputByteCount = 0
        pendingResize = nil
        lastSnapshotState = nil

        _ = try? await connection.sendSessionRPC(
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
    func sendInput(_ data: Data) async throws {
        guard !data.isEmpty else { return }
        guard let sessionID = attachedSessionID, isAttached else {
            throw DaemonProtocolError.connectionLost
        }

        let base64Input = data.base64EncodedString()
        let response = try await connection.sendSessionRPC(
            cmd: DaemonCommand.sessionInput.rawValue,
            args: ["id": sessionID, "data": base64Input]
        )
        guard response.ok else { throw DaemonProtocolError.invalidResponse }
    }

    /// Enqueues input without blocking AppKit's key event dispatch. One drain
    /// task preserves byte ordering across rapid keyboard and paste events.
    @discardableResult
    func enqueueInput(_ data: Data) -> Bool {
        guard !data.isEmpty, isAttached, attachedSessionID != nil else { return false }
        guard data.count <= Self.maximumQueuedInputBytes,
              queuedInputByteCount <= Self.maximumQueuedInputBytes - data.count else {
            return false
        }

        queuedInputs.append(data)
        queuedInputByteCount += data.count
        startInputDrainIfNeeded()
        return true
    }

    func enqueueResize(_ size: TerminalSize) {
        guard isAttached, attachedSessionID != nil else { return }
        pendingResize = size
        guard resizeTask == nil else { return }

        resizeTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 75_000_000)
            } catch {
                return
            }
            guard let self,
                  let sessionID = self.attachedSessionID,
                  let size = self.pendingResize,
                  self.isAttached else {
                self?.resizeTask = nil
                return
            }
            self.pendingResize = nil
            self.resizeTask = nil
            do {
                let response = try await self.connection.sendSessionRPC(
                    cmd: DaemonCommand.sessionResize.rawValue,
                    args: [
                        "id": sessionID,
                        "cols": "\(size.columns)",
                        "rows": "\(size.rows)",
                    ]
                )
                guard response.ok else {
                    self.handleDisconnect()
                    return
                }
            } catch {
                self.handleDisconnect()
                return
            }
            if let pendingResize = self.pendingResize {
                self.enqueueResize(pendingResize)
            }
        }
    }

    func beginDetach() {
        Task { @MainActor [self] in
            await detach()
        }
    }

    private func startInputDrainIfNeeded() {
        guard inputDrainTask == nil else { return }
        inputDrainTask = Task { @MainActor [weak self] in
            while let self,
                  !Task.isCancelled,
                  self.queuedInputReadIndex < self.queuedInputs.count {
                let data = self.queuedInputs[self.queuedInputReadIndex]
                self.queuedInputReadIndex += 1
                self.queuedInputByteCount -= data.count
                do {
                    try await self.sendInput(data)
                } catch {
                    self.inputDrainTask = nil
                    self.handleDisconnect()
                    return
                }
            }
            self?.queuedInputs.removeAll(keepingCapacity: true)
            self?.queuedInputReadIndex = 0
            self?.inputDrainTask = nil
        }
    }

    // MARK: - Output Reader (daemon → local terminal)

    /// Continuously polls the daemon for session output.
    ///
    /// The daemon sends output data as base64-encoded chunks in
    /// response to `session.output` requests. Active output polls at 50ms;
    /// unchanged snapshots back off to 150ms to avoid needless remote work.
    private func startOutputReader(sessionID: String) {
        readTask?.cancel()
        readTask = Task { @MainActor [weak self] in
            var consecutiveFailures = 0
            while !Task.isCancelled {
                guard let self, self.isAttached, self.connection.isConnected else {
                    self?.handleDisconnect()
                    return
                }

                var receivedOutput = false
                do {
                    let response = try await self.connection.sendSessionRPC(
                        cmd: DaemonCommand.sessionOutput.rawValue,
                        args: ["id": sessionID]
                    )
                    guard response.ok,
                          let data = response.data,
                          let encoded = data["data"] as? String,
                          let bytes = Data(base64Encoded: encoded) else {
                        throw DaemonProtocolError.invalidResponse
                    }
                    consecutiveFailures = 0
                    let mode = data["mode"] as? String
                    if !bytes.isEmpty || mode == "snapshot",
                       let output = self.normalizedOutput(
                           bytes,
                           mode: mode,
                           cursor: Self.snapshotCursor(from: data)
                       ) {
                        receivedOutput = true
                        self.onOutput?(output)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    consecutiveFailures += 1
                    if consecutiveFailures >= Self.maximumConsecutiveReadFailures {
                        self.handleDisconnect()
                        return
                    }
                }

                let interval = receivedOutput
                    ? self.activePollIntervalNanoseconds
                    : self.idlePollIntervalNanoseconds
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }
            }
        }
    }

    private func normalizedOutput(
        _ bytes: Data,
        mode: String?,
        cursor: DaemonSnapshotCursor?
    ) -> Data? {
        guard mode == "snapshot" else { return bytes }
        let state = DaemonSnapshotState(bytes: bytes, cursor: cursor)
        guard lastSnapshotState != state else { return nil }
        lastSnapshotState = state

        var framed = Data("\u{1B}[2J\u{1B}[H".utf8)
        var snapshot = Self.normalizedSnapshotLineEndings(bytes)
        if snapshot.last == 0x0A {
            snapshot.removeLast()
        }
        framed.append(snapshot)
        if let cursor {
            framed.append(Data("\u{1B}[\(cursor.y + 1);\(cursor.x + 1)H".utf8))
        }
        return framed
    }

    private static func snapshotCursor(from data: [String: Any]) -> DaemonSnapshotCursor? {
        guard let x = nonnegativeCoordinate(data["cursor_x"]),
              let y = nonnegativeCoordinate(data["cursor_y"]),
              x < Int.max,
              y < Int.max else {
            return nil
        }
        return DaemonSnapshotCursor(x: x, y: y)
    }

    private static func nonnegativeCoordinate(_ value: Any?) -> Int? {
        let coordinate: Int?
        if let value = value as? Int {
            coordinate = value
        } else if let value = value as? String {
            coordinate = Int(value)
        } else {
            coordinate = nil
        }
        guard let coordinate, coordinate >= 0 else { return nil }
        return coordinate
    }

    private static func normalizedSnapshotLineEndings(_ bytes: Data) -> Data {
        var previousWasCarriageReturn = false
        var hasBareLineFeed = false
        for byte in bytes {
            if byte == 0x0A, !previousWasCarriageReturn {
                hasBareLineFeed = true
                break
            }
            previousWasCarriageReturn = byte == 0x0D
        }
        guard hasBareLineFeed else { return bytes }

        var normalized = Data()
        normalized.reserveCapacity(bytes.count)
        previousWasCarriageReturn = false
        for byte in bytes {
            if byte == 0x0A, !previousWasCarriageReturn {
                normalized.append(0x0D)
            }
            normalized.append(byte)
            previousWasCarriageReturn = byte == 0x0D
        }
        return normalized
    }

    private func handleDisconnect() {
        guard isAttached || attachedSessionID != nil else { return }
        readTask?.cancel()
        readTask = nil
        inputDrainTask?.cancel()
        inputDrainTask = nil
        resizeTask?.cancel()
        resizeTask = nil
        queuedInputs.removeAll(keepingCapacity: false)
        queuedInputReadIndex = 0
        queuedInputByteCount = 0
        pendingResize = nil
        lastSnapshotState = nil
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
        let response = try await connection.sendSessionRPC(
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
        let response = try await connection.sendSessionRPC(
            cmd: DaemonCommand.sessionList.rawValue,
            args: nil
        )

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
        let response = try await connection.sendSessionRPC(
            cmd: DaemonCommand.sessionKill.rawValue,
            args: ["id": sessionID]
        )

        guard response.ok else {
            throw DaemonProtocolError.invalidResponse
        }

        if attachedSessionID == sessionID {
            handleDisconnect()
        }
    }
}
