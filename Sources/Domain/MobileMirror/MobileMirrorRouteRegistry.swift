// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorRouteRegistry.swift - Thread-safe terminal stream routing.

import Foundation

struct MobileMirrorTerminalRoute: Equatable, Sendable {
    let sessionID: String
    let port: UInt16
    let bearerToken: String
}

final class MobileMirrorRouteRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var routesBySessionID: [String: MobileMirrorTerminalRoute] = [:]
    private var defaultSessionID: String?

    func replace(
        routes: [MobileMirrorTerminalRoute],
        preferredSessionID: String?
    ) {
        lock.lock()
        defer { lock.unlock() }
        routesBySessionID = Dictionary(uniqueKeysWithValues: routes.map { ($0.sessionID, $0) })
        if let preferredSessionID, routesBySessionID[preferredSessionID] != nil {
            defaultSessionID = preferredSessionID
        } else {
            defaultSessionID = routes
                .sorted { $0.sessionID.localizedStandardCompare($1.sessionID) == .orderedAscending }
                .first?
                .sessionID
        }
    }

    func route(for sessionID: String) -> MobileMirrorTerminalRoute? {
        lock.lock()
        defer { lock.unlock() }
        return routesBySessionID[sessionID]
    }

    func defaultRoute() -> MobileMirrorTerminalRoute? {
        lock.lock()
        defer { lock.unlock() }
        return defaultSessionID.flatMap { routesBySessionID[$0] }
    }

    func contains(sessionID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return routesBySessionID[sessionID] != nil
    }

    var sessionIDs: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(routesBySessionID.keys)
    }
}
