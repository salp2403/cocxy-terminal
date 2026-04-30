// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonSurfaceHelpers.swift - Shared helpers for PTYDaemonSurface and friends.

import Foundation

enum PTYDaemonSurfaceError: Error, CustomStringConvertible {
    case creationFailed(String)
    case missingSurface
    case invalidPayload(String)

    var description: String {
        switch self {
        case .creationFailed(let reason), .invalidPayload(let reason):
            return reason
        case .missingSurface:
            return "surface not found"
        }
    }
}

extension NSLock {
    /// Locks, runs `body`, and always unlocks even when `body` throws.
    ///
    /// Defined at module scope so the surface implementation files
    /// (`PTYDaemonSurface`, `SurfaceRegistry`, frame/search/keys extensions)
    /// share a single locking helper instead of redefining it.
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

extension Dictionary where Key == String, Value == String {
    /// Returns the value when present and non-empty, otherwise `nil`.
    func nonEmpty(_ key: String) -> String? {
        guard let value = self[key], value.isEmpty == false else { return nil }
        return value
    }

    func uint16(_ key: String) -> UInt16? {
        nonEmpty(key).flatMap(UInt16.init)
    }

    func uint32(_ key: String) -> UInt32? {
        nonEmpty(key).flatMap(UInt32.init)
    }

    func uint(_ key: String) -> UInt? {
        nonEmpty(key).flatMap(UInt.init)
    }

    func int(_ key: String) -> Int? {
        nonEmpty(key).flatMap(Int.init)
    }

    func int32(_ key: String) -> Int32? {
        nonEmpty(key).flatMap(Int32.init)
    }

    func bool(_ key: String) -> Bool? {
        guard let raw = nonEmpty(key)?.lowercased() else { return nil }
        switch raw {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }
}
