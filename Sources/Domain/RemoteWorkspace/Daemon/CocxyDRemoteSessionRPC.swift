// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyDRemoteSessionRPC.swift - Typed session RPC wrapper for cocxyd-remote.

import Foundation

@MainActor
protocol CocxyDRemoteRPCSending: AnyObject {
    func sendRemoteRPC(method: String, params: [String: String]) async throws -> [String: String]
}

struct CocxyDRemoteTerminalSize: Equatable, Sendable {
    let cols: Int
    let rows: Int
}

struct CocxyDRemoteResizeCoordinator: Sendable {
    private var sizes: [String: CocxyDRemoteTerminalSize] = [:]

    init() {}

    mutating func update(clientID: String, cols: Int, rows: Int) -> CocxyDRemoteTerminalSize {
        sizes[clientID] = CocxyDRemoteTerminalSize(cols: cols, rows: rows)
        return smallestSize()
    }

    mutating func remove(clientID: String) -> CocxyDRemoteTerminalSize? {
        sizes.removeValue(forKey: clientID)
        return sizes.isEmpty ? nil : smallestSize()
    }

    private func smallestSize() -> CocxyDRemoteTerminalSize {
        CocxyDRemoteTerminalSize(
            cols: sizes.values.map(\.cols).min() ?? 80,
            rows: sizes.values.map(\.rows).min() ?? 24
        )
    }
}
@MainActor
final class CocxyDRemoteSessionRPC {
    private let sender: any CocxyDRemoteRPCSending

    init(sender: any CocxyDRemoteRPCSending) {
        self.sender = sender
    }

    func open(command: String, cols: Int, rows: Int) async throws -> String {
        let data = try await sender.sendRemoteRPC(
            method: "session.open",
            params: ["command": command, "cols": "\(cols)", "rows": "\(rows)"]
        )
        guard let sessionID = data["sessionID"] else { throw DaemonProtocolError.invalidResponse }
        return sessionID
    }

    func attach(sessionID: String, clientID: String) async throws {
        _ = try await sender.sendRemoteRPC(
            method: "session.attach",
            params: ["sessionID": sessionID, "clientID": clientID]
        )
    }

    func resize(sessionID: String, clientID: String, cols: Int, rows: Int) async throws {
        _ = try await sender.sendRemoteRPC(
            method: "session.resize",
            params: ["sessionID": sessionID, "clientID": clientID, "cols": "\(cols)", "rows": "\(rows)"]
        )
    }

    func write(sessionID: String, data: Data) async throws {
        _ = try await sender.sendRemoteRPC(
            method: "session.write",
            params: ["sessionID": sessionID, "data": data.base64EncodedString()]
        )
    }

    func detach(sessionID: String, clientID: String) async throws {
        _ = try await sender.sendRemoteRPC(
            method: "session.detach",
            params: ["sessionID": sessionID, "clientID": clientID]
        )
    }

    func close(sessionID: String) async throws {
        _ = try await sender.sendRemoteRPC(
            method: "session.close",
            params: ["sessionID": sessionID]
        )
    }
}
