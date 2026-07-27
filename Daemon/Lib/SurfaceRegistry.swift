// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SurfaceRegistry.swift - Live cocxyd surface ownership.

import Foundation
import CocxyShared

final class SurfaceRegistry: @unchecked Sendable {
    private var surfaces: [String: PTYDaemonSurface] = [:]
    private let lock = NSLock()
    private let writer: PTYDaemonLineWriter

    init(writer: PTYDaemonLineWriter) {
        self.writer = writer
    }

    deinit {
        closeAll()
    }

    func create(payload: [String: String]) throws -> PTYDaemonSurface {
        let surface = try PTYDaemonSurface.create(payload: payload, writer: writer)
        lock.withLock {
            surfaces[surface.surfaceID] = surface
        }
        surface.activate { [weak self] surfaceID in
            self?.removeClosedSurface(id: surfaceID)
        }
        return surface
    }

    func surface(id: String?) -> PTYDaemonSurface? {
        guard let id else { return nil }
        return lock.withLock { surfaces[id] }
    }

    @discardableResult
    func close(id: String?) -> Bool {
        guard let id else { return false }
        let surface = lock.withLock { surfaces.removeValue(forKey: id) }
        guard let surface else { return false }
        return surface.close()
    }

    @discardableResult
    func closeAll() -> Bool {
        let all = lock.withLock { () -> [PTYDaemonSurface] in
            let values = Array(surfaces.values)
            surfaces.removeAll()
            return values
        }
        all.forEach { $0.close(waitForCleanup: false) }
        var succeeded = true
        for surface in all {
            if surface.close(emitEvent: false) == false {
                succeeded = false
            }
        }
        return succeeded
    }

    private func removeClosedSurface(id: String) {
        _ = lock.withLock {
            surfaces.removeValue(forKey: id)
        }
    }
}
