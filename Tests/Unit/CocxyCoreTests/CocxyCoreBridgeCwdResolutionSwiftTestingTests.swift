// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Foundation
import Testing
import CocxyCoreKit
@testable import CocxyTerminal

@Suite("CocxyCoreBridge cwd resolution", .serialized)
@MainActor
struct CocxyCoreBridgeCwdResolutionSwiftTestingTests {

    // MARK: - Pure matcher helper

    @Test("firstSurface returns nil when no candidates match")
    func firstSurfaceReturnsNilWithoutMatch() {
        let match = CocxyCoreBridge.firstSurface(
            matchingNormalizedCwd: "/Users/test/project",
            in: [
                (SurfaceID(), "/Users/test/other"),
                (SurfaceID(), "/tmp")
            ]
        )

        #expect(match == nil)
    }

    @Test("firstSurface returns nil for an empty candidates array")
    func firstSurfaceEmptyCandidates() {
        let match = CocxyCoreBridge.firstSurface(
            matchingNormalizedCwd: "/Users/test/project",
            in: []
        )

        #expect(match == nil)
    }

    @Test("firstSurface returns nil when the normalized target is empty")
    func firstSurfaceEmptyTarget() {
        let match = CocxyCoreBridge.firstSurface(
            matchingNormalizedCwd: "",
            in: [(SurfaceID(), "/Users/test")]
        )

        #expect(match == nil)
    }

    @Test("firstSurface finds an exact-path match")
    func firstSurfaceExactMatch() {
        let expected = SurfaceID()
        let match = CocxyCoreBridge.firstSurface(
            matchingNormalizedCwd: "/Users/test/project",
            in: [
                (SurfaceID(), "/Users/test/other"),
                (expected, "/Users/test/project"),
                (SurfaceID(), "/tmp")
            ]
        )

        #expect(match == expected)
    }

    @Test("firstSurface normalizes trailing slashes on candidate paths")
    func firstSurfaceNormalizesTrailingSlash() {
        let expected = SurfaceID()
        let match = CocxyCoreBridge.firstSurface(
            matchingNormalizedCwd: "/Users/test/project",
            in: [(expected, "/Users/test/project/")]
        )

        #expect(match == expected)
    }

    @Test("firstSurface normalizes \".\" components on candidate paths")
    func firstSurfaceNormalizesDotComponents() {
        let expected = SurfaceID()
        let match = CocxyCoreBridge.firstSurface(
            matchingNormalizedCwd: "/Users/test/project",
            in: [(expected, "/Users/test/./project")]
        )

        #expect(match == expected)
    }

    @Test("firstSurface skips candidates with nil or empty paths")
    func firstSurfaceSkipsEmptyAndNilPaths() {
        let expected = SurfaceID()
        let match = CocxyCoreBridge.firstSurface(
            matchingNormalizedCwd: "/Users/test/project",
            in: [
                (SurfaceID(), nil),
                (SurfaceID(), ""),
                (expected, "/Users/test/project")
            ]
        )

        #expect(match == expected)
    }

    @Test("firstSurface does not match on path prefix alone")
    func firstSurfaceRejectsPrefixMatch() {
        // /Users/test is a prefix of /Users/test/project but must NOT match,
        // so background terminals at $HOME never absorb hook events fired
        // inside project subdirectories.
        let match = CocxyCoreBridge.firstSurface(
            matchingNormalizedCwd: "/Users/test/project",
            in: [(SurfaceID(), "/Users/test")]
        )

        #expect(match == nil)
    }

    @Test("firstSurface returns the first match in iteration order")
    func firstSurfaceReturnsFirstMatch() {
        let first = SurfaceID()
        let second = SurfaceID()
        let match = CocxyCoreBridge.firstSurface(
            matchingNormalizedCwd: "/tmp",
            in: [
                (first, "/tmp"),
                (second, "/tmp")
            ]
        )

        #expect(match == first)
    }

    // MARK: - Instance resolveSurfaceID integration

    @Test("resolveSurfaceID returns nil on a bridge without surfaces")
    func resolveSurfaceIDNilWithNoSurfaces() throws {
        let bridge = try makeBridge()

        #expect(bridge.resolveSurfaceID(matchingCwd: "/tmp") == nil)
    }

    @Test("resolveSurfaceID returns nil for an empty path even with live surfaces")
    func resolveSurfaceIDNilForEmptyPath() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try makeSurface(bridge: bridge)
        defer { bridge.destroySurface(surfaceID) }

        #expect(bridge.resolveSurfaceID(matchingCwd: "") == nil)
    }

    @Test("resolveSurfaceID finds the surface whose lastKnownWorkingDirectory matches")
    func resolveSurfaceIDMatchesLastKnownWorkingDirectory() throws {
        let bridge = try makeBridge()
        let cwd = try uniqueTempDirectory()
        defer { try? FileManager.default.removeItem(at: cwd) }

        let (surfaceID, _) = try makeSurface(bridge: bridge, workingDirectory: cwd)
        defer { bridge.destroySurface(surfaceID) }

        let resolved = bridge.resolveSurfaceID(matchingCwd: cwd.path)
        #expect(resolved == surfaceID)
    }

    @Test("resolveSurfaceID returns nil when no surface matches the path")
    func resolveSurfaceIDReturnsNilWhenNoMatch() throws {
        let bridge = try makeBridge()
        let cwd = try uniqueTempDirectory()
        defer { try? FileManager.default.removeItem(at: cwd) }

        let (surfaceID, _) = try makeSurface(bridge: bridge, workingDirectory: cwd)
        defer { bridge.destroySurface(surfaceID) }

        let mismatched = "/var/empty/cocxy-nonexistent-\(UUID().uuidString)"
        #expect(bridge.resolveSurfaceID(matchingCwd: mismatched) == nil)
    }

    @Test("resolveSurfaceID distinguishes between sibling surfaces with different CWDs")
    func resolveSurfaceIDDistinguishesSiblingSurfaces() throws {
        let bridge = try makeBridge()
        let cwdA = try uniqueTempDirectory()
        let cwdB = try uniqueTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: cwdA)
            try? FileManager.default.removeItem(at: cwdB)
        }

        let (surfaceA, _) = try makeSurface(bridge: bridge, workingDirectory: cwdA)
        let (surfaceB, _) = try makeSurface(bridge: bridge, workingDirectory: cwdB)
        defer {
            bridge.destroySurface(surfaceA)
            bridge.destroySurface(surfaceB)
        }

        #expect(bridge.resolveSurfaceID(matchingCwd: cwdA.path) == surfaceA)
        #expect(bridge.resolveSurfaceID(matchingCwd: cwdB.path) == surfaceB)
    }

    @Test("resolveSurfaceID tolerates trailing slashes in the requested path")
    func resolveSurfaceIDTolerantOfTrailingSlash() throws {
        let bridge = try makeBridge()
        let cwd = try uniqueTempDirectory()
        defer { try? FileManager.default.removeItem(at: cwd) }

        let (surfaceID, _) = try makeSurface(bridge: bridge, workingDirectory: cwd)
        defer { bridge.destroySurface(surfaceID) }

        #expect(bridge.resolveSurfaceID(matchingCwd: cwd.path + "/") == surfaceID)
    }

    @Test("resolveSurfaceID prefers lastKnownWorkingDirectory over the cwdProvider hint")
    func resolveSurfaceIDPrefersLastKnownOverProvider() throws {
        let bridge = try makeBridge()
        let terminalCwd = try uniqueTempDirectory()
        let providerCwd = try uniqueTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: terminalCwd)
            try? FileManager.default.removeItem(at: providerCwd)
        }

        let (surfaceID, _) = try makeSurface(bridge: bridge, workingDirectory: terminalCwd)
        defer { bridge.destroySurface(surfaceID) }

        // Install a provider that reports a different CWD than the one
        // cached by the bridge. The bridge must prefer its own cached
        // value (refreshed from OSC 7 / fallback probes) over the hint.
        bridge.setCwdProvider { queried in
            queried == surfaceID ? providerCwd.path : nil
        }

        #expect(bridge.resolveSurfaceID(matchingCwd: terminalCwd.path) == surfaceID)
        #expect(bridge.resolveSurfaceID(matchingCwd: providerCwd.path) == nil)
    }

    // MARK: - Helpers

    private func makeSurface(
        bridge: CocxyCoreBridge,
        workingDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory())
    ) throws -> (SurfaceID, NSView) {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        let surfaceID = try bridge.createSurface(
            in: view,
            workingDirectory: workingDirectory,
            command: "/bin/cat"
        )
        return (surfaceID, view)
    }

    private func uniqueTempDirectory() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appendingPathComponent(
            "cocxy-cwd-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir.standardizedFileURL
    }
}
