// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorRouteRegistry.swift - Thread-safe terminal stream routing.

import CocxyShared
import Foundation

struct MobileMirrorTerminalRoute: Equatable, Sendable {
    let sessionID: String
    let surfaceID: SurfaceID
    let port: UInt16
    let bearerToken: String
}

final class MobileMirrorRouteRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var routesBySurfaceID: [String: MobileMirrorTerminalRoute] = [:]
    private var defaultSurfaceID: String?

    func replace(
        routes: [MobileMirrorTerminalRoute],
        preferredSurfaceID: String?
    ) {
        lock.lock()
        defer { lock.unlock() }
        routesBySurfaceID = [:]
        for route in routes {
            routesBySurfaceID[route.surfaceID.rawValue.uuidString] = route
        }
        if let preferredSurfaceID, routesBySurfaceID[preferredSurfaceID] != nil {
            defaultSurfaceID = preferredSurfaceID
        } else {
            defaultSurfaceID = routes.first?
                .surfaceID
                .rawValue
                .uuidString
        }
    }

    func route(sessionID: String, surfaceID: String) -> MobileMirrorTerminalRoute? {
        lock.lock()
        defer { lock.unlock() }
        guard let route = routesBySurfaceID[surfaceID], route.sessionID == sessionID else {
            return nil
        }
        return route
    }

    func route(forSurfaceID surfaceID: String) -> MobileMirrorTerminalRoute? {
        lock.lock()
        defer { lock.unlock() }
        return routesBySurfaceID[surfaceID]
    }

    func defaultRoute() -> MobileMirrorTerminalRoute? {
        lock.lock()
        defer { lock.unlock() }
        return defaultSurfaceID.flatMap { routesBySurfaceID[$0] }
    }

    func contains(sessionID: String, surfaceID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return routesBySurfaceID[surfaceID]?.sessionID == sessionID
    }

    var surfaceIDs: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(routesBySurfaceID.keys)
    }
}
