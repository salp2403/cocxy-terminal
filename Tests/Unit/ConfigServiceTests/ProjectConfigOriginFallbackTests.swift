// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectConfigOriginFallbackTests.swift - Exercises the worktree
// origin-repo fallback for `ProjectConfigService.loadConfig(for:originRepo:)`
// and `findConfigPath(for:originRepo:)` introduced in v0.1.81.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ProjectConfigService — origin repo fallback")
struct ProjectConfigOriginFallbackTests {

    // MARK: - Fixture helpers

    private func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-project-config-origin", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true
        )
        return base
    }

    private func removeTempDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func writeConfig(
        _ toml: String,
        inside directory: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try toml.write(
            to: directory.appendingPathComponent(".cocxy.toml"),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - Primary walk still wins

    @Test("config in primary directory tree wins over originRepo")
    func primaryWalkWinsOverOrigin() throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }

        let worktree = root.appendingPathComponent("wt", isDirectory: true)
        let originRepo = root.appendingPathComponent("origin", isDirectory: true)
        try writeConfig("font-size = 18", inside: worktree)
        try writeConfig("font-size = 22", inside: originRepo)

        let service = ProjectConfigService()
        let config = service.loadConfig(for: worktree, originRepo: originRepo)

        #expect(config?.fontSize == 18)
    }

    // MARK: - Fallback kicks in when primary is empty

    @Test("missing primary config triggers fallback walk on originRepo")
    func missingPrimaryTriggersOriginFallback() throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }

        let worktreeBase = root.appendingPathComponent("empty-worktree", isDirectory: true)
        try FileManager.default.createDirectory(
            at: worktreeBase,
            withIntermediateDirectories: true
        )
        // No .cocxy.toml anywhere in the worktree tree.

        let originRepo = root.appendingPathComponent("origin", isDirectory: true)
        try writeConfig("font-size = 22", inside: originRepo)

        let service = ProjectConfigService()
        let config = service.loadConfig(for: worktreeBase, originRepo: originRepo)

        #expect(config?.fontSize == 22)
    }

    // MARK: - No fallback when originRepo is omitted

    @Test("nil originRepo preserves the legacy single-walk behaviour")
    func nilOriginRepoIsIdentical() throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }

        let worktreeBase = root.appendingPathComponent("empty-worktree", isDirectory: true)
        try FileManager.default.createDirectory(
            at: worktreeBase,
            withIntermediateDirectories: true
        )

        let originRepo = root.appendingPathComponent("origin", isDirectory: true)
        try writeConfig("font-size = 22", inside: originRepo)

        let service = ProjectConfigService()
        let config = service.loadConfig(for: worktreeBase)

        // Without originRepo, the service cannot reach the origin repo
        // config — callers who do not opt in to the fallback get the
        // legacy behaviour (nil).
        #expect(config == nil)
    }

    // MARK: - originRepo equal to directory is a no-op

    @Test("originRepo equal to primary directory does not walk twice")
    func originRepoEqualToPrimaryNoOp() throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }

        let dir = root.appendingPathComponent("same", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )

        let service = ProjectConfigService()
        let config = service.loadConfig(for: dir, originRepo: dir)
        #expect(config == nil)
    }

    // MARK: - findConfigPath mirrors the fallback

    @Test("findConfigPath falls back to originRepo when primary is empty")
    func findConfigPathFallsBackToOrigin() throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }

        let worktreeBase = root.appendingPathComponent("empty-worktree", isDirectory: true)
        try FileManager.default.createDirectory(
            at: worktreeBase,
            withIntermediateDirectories: true
        )

        let originRepo = root.appendingPathComponent("origin", isDirectory: true)
        try writeConfig("font-size = 22", inside: originRepo)

        let service = ProjectConfigService()
        let path = service.findConfigPath(for: worktreeBase, originRepo: originRepo)

        #expect(path != nil)
        #expect(path?.hasSuffix("origin/.cocxy.toml") == true)
    }

    @Test("findConfigPath still prefers the primary .cocxy.toml when present")
    func findConfigPathPrefersPrimary() throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }

        let worktree = root.appendingPathComponent("wt", isDirectory: true)
        let originRepo = root.appendingPathComponent("origin", isDirectory: true)
        try writeConfig("font-size = 18", inside: worktree)
        try writeConfig("font-size = 22", inside: originRepo)

        let service = ProjectConfigService()
        let path = service.findConfigPath(for: worktree, originRepo: originRepo)

        #expect(path?.hasSuffix("wt/.cocxy.toml") == true)
    }

    @Test("findConfigPath without originRepo returns nil when primary is empty")
    func findConfigPathNilWithoutOrigin() throws {
        let root = try makeTempDir()
        defer { removeTempDir(root) }

        let worktreeBase = root.appendingPathComponent("empty-worktree", isDirectory: true)
        try FileManager.default.createDirectory(
            at: worktreeBase,
            withIntermediateDirectories: true
        )
        let originRepo = root.appendingPathComponent("origin", isDirectory: true)
        try writeConfig("font-size = 22", inside: originRepo)

        let service = ProjectConfigService()
        let path = service.findConfigPath(for: worktreeBase)
        #expect(path == nil)
    }
}
