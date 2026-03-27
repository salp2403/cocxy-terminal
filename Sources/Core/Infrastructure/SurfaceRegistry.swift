// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SurfaceRegistry.swift - Thread-safe mapping from SurfaceID to ghostty_surface_t.

import GhosttyKit

// MARK: - Surface Registry

/// Maps `SurfaceID` values to their underlying `ghostty_surface_t` pointers.
///
/// This registry is the single source of truth for which surfaces are alive.
/// It decouples the domain layer (which works with `SurfaceID`) from the
/// infrastructure layer (which needs raw `ghostty_surface_t` pointers).
///
/// Threading: All access must happen from the main thread (enforced by
/// `GhosttyBridge`'s `@MainActor` isolation).
///
/// - SeeAlso: `GhosttyBridge.createSurface`, `GhosttyBridge.destroySurface`
final class SurfaceRegistry {

    // MARK: - Storage

    private var surfacesByID: [SurfaceID: ghostty_surface_t] = [:]

    // MARK: - Public API

    /// Number of currently registered surfaces.
    var count: Int {
        surfacesByID.count
    }

    /// Registers a surface with the given ID.
    ///
    /// - Parameters:
    ///   - surfaceID: The domain-level identifier for the surface.
    ///   - ghosttySurface: The opaque pointer returned by `ghostty_surface_new`.
    func register(surfaceID: SurfaceID, ghosttySurface: ghostty_surface_t) {
        surfacesByID[surfaceID] = ghosttySurface
    }

    /// Looks up the ghostty surface pointer for the given ID.
    ///
    /// - Parameter surfaceID: The surface to look up.
    /// - Returns: The opaque pointer, or `nil` if the ID is not registered.
    func lookup(_ surfaceID: SurfaceID) -> ghostty_surface_t? {
        surfacesByID[surfaceID]
    }

    /// Removes a surface from the registry.
    ///
    /// - Parameter surfaceID: The surface to unregister.
    /// - Returns: The opaque pointer that was removed, or `nil` if not found.
    @discardableResult
    func unregister(_ surfaceID: SurfaceID) -> ghostty_surface_t? {
        surfacesByID.removeValue(forKey: surfaceID)
    }

    /// Removes all registered surfaces. Used during teardown.
    func removeAll() -> [ghostty_surface_t] {
        let surfaces = Array(surfacesByID.values)
        surfacesByID.removeAll()
        return surfaces
    }
}
