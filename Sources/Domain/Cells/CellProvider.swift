// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CellProvider.swift - Provider contract for user-owned Cocxy Cells.

import Foundation

struct CellCreateRequest: Equatable, Sendable {
    var name: String
    var metadata: [String: String]

    init(name: String, metadata: [String: String] = [:]) {
        self.name = name
        self.metadata = metadata
    }
}

struct CellAttachCommand: Equatable, Sendable {
    let executable: String
    let arguments: [String]
    let displayName: String

    init(
        executable: String,
        arguments: [String],
        displayName: String
    ) {
        self.executable = executable
        self.arguments = arguments
        self.displayName = displayName
    }

    var argv: [String] {
        [executable] + arguments
    }

    var shellCommand: String {
        argv.map(Self.shellToken).joined(separator: " ")
    }

    private static func shellToken(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let safe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_+-./:@=~")
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

protocol CellProvider: Sendable {
    var kind: CellProviderKind { get }

    func create(_ request: CellCreateRequest) async throws -> Cell
    func list() async throws -> [Cell]
    func status(cellID: UUID) async throws -> CellStatus
    func exec(cellID: UUID, command: [String]) async throws -> String
    func attachCommand(cellID: UUID) async throws -> CellAttachCommand
    func logs(cellID: UUID) async throws -> String
    func destroy(cellID: UUID, force: Bool) async throws
}
