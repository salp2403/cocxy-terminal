// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Canonical project identity", .serialized)
struct ProjectIdentitySwiftTestingTests {
    private final class CountingRootResolver: AuroraWorkspaceRootResolver, @unchecked Sendable {
        var roots: [String: URL]
        let fallback: (any AuroraWorkspaceRootResolver)?
        private(set) var callCount = 0

        init(
            roots: [String: URL] = [:],
            fallback: (any AuroraWorkspaceRootResolver)? = nil
        ) {
            self.roots = roots
            self.fallback = fallback
        }

        func workspaceRoot(for directory: URL) -> URL? {
            callCount += 1
            return roots[directory.standardizedFileURL.path]
                ?? fallback?.workspaceRoot(for: directory)
        }
    }

    private final class TrackingProjectResolver: ProjectResolving {
        let descriptor: ProjectDescriptor
        private(set) var invalidatedPaths: [String] = []

        init(root: URL) {
            let canonical = ProjectPathCanonicalizer.canonicalURL(root)
            descriptor = ProjectDescriptor(
                id: ProjectID(rootURL: canonical),
                rootURL: canonical,
                automaticName: canonical.lastPathComponent,
                displayName: canonical.lastPathComponent,
                parent: nil
            )
        }

        func resolveProject(for directory: URL) -> ProjectDescriptor { descriptor }

        func invalidate(directory: URL) {
            invalidatedPaths.append(ProjectPathCanonicalizer.canonicalURL(directory).path)
        }

        func invalidateAll() {
            invalidatedPaths.append("*")
        }
    }

    @Test("same project basenames retain distinct canonical IDs and storage keys")
    func sameBasenamesDoNotCollide() {
        let firstRoot = URL(fileURLWithPath: "/Users/user/first/html")
        let secondRoot = URL(fileURLWithPath: "/Users/user/second/html")
        let resolver = CountingRootResolver(roots: [
            "/Users/user/first/html/Sources": firstRoot,
            "/Users/user/second/html/Sources": secondRoot,
        ])
        let cache = CachedProjectResolver(rootResolver: resolver)

        let first = cache.resolveProject(
            for: URL(fileURLWithPath: "/Users/user/first/html/Sources")
        )
        let second = cache.resolveProject(
            for: URL(fileURLWithPath: "/Users/user/second/html/Sources")
        )

        #expect(first.automaticName == "html")
        #expect(second.automaticName == "html")
        #expect(first.id != second.id)
        #expect(first.id.storageKey != second.id.storageKey)
    }

    @Test("non-repository directory is its own project fallback")
    func directoryFallback() {
        let resolver = CachedProjectResolver(rootResolver: CountingRootResolver())
        let directory = URL(fileURLWithPath: "/tmp/cocxy-project-fallback")

        let descriptor = resolver.resolveProject(for: directory)

        #expect(descriptor.id.rawValue == directory.standardizedFileURL.path)
        #expect(descriptor.rootURL == directory.standardizedFileURL)
        #expect(descriptor.automaticName == "cocxy-project-fallback")
        #expect(descriptor.displayName == "cocxy-project-fallback")
        #expect(descriptor.parent == nil)
    }

    @Test("linked worktree folds under its origin while preserving child identity")
    func linkedWorktreeParent() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectIdentityTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let origin = sandbox.appendingPathComponent("origin", isDirectory: true)
        let originGit = origin.appendingPathComponent(".git", isDirectory: true)
        let child = sandbox.appendingPathComponent("child", isDirectory: true)
        let childGitDirectory = originGit
            .appendingPathComponent("worktrees", isDirectory: true)
            .appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: childGitDirectory, withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(
            to: originGit.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )
        try "ref: refs/heads/feature\n".write(
            to: childGitDirectory.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )
        try "../..\n".write(
            to: childGitDirectory.appendingPathComponent("commondir"),
            atomically: true,
            encoding: .utf8
        )
        try "gitdir: \(childGitDirectory.path)\n".write(
            to: child.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )
        let rootResolver = CountingRootResolver(roots: [child.path: child])
        let resolver = CachedProjectResolver(rootResolver: rootResolver)

        let descriptor = resolver.resolveProject(for: child)

        #expect(descriptor.id == ProjectID(rootURL: child))
        #expect(descriptor.parent == ProjectID(rootURL: origin))
        #expect(descriptor.groupingID == ProjectID(rootURL: origin))
        #expect(descriptor.groupingRootURL == origin.standardizedFileURL)
        #expect(descriptor.groupingAutomaticName == "origin")
    }

    @Test("cache is bounded and updates after explicit invalidation")
    func cacheInvalidationAfterRepositoryCreation() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let openDirectory = sandbox.appendingPathComponent("project/Sources", isDirectory: true)
        let projectRoot = sandbox.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: openDirectory, withIntermediateDirectories: true)
        let rootResolver = CountingRootResolver(
            fallback: GitAncestorWorkspaceRootResolver(
                homeDirectory: sandbox.deletingLastPathComponent()
            )
        )
        let resolver = CachedProjectResolver(
            rootResolver: rootResolver,
            cacheTTL: 60,
            maximumEntryCount: 2
        )

        let before = resolver.resolveProject(for: openDirectory)
        _ = resolver.resolveProject(for: openDirectory)
        #expect(before.id == ProjectID(rootURL: openDirectory))
        #expect(rootResolver.callCount == 1)

        let gitInit = Process()
        gitInit.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        gitInit.arguments = ["init", "--quiet", projectRoot.path]
        try gitInit.run()
        gitInit.waitUntilExit()
        #expect(gitInit.terminationStatus == 0)
        resolver.invalidate(directory: projectRoot)
        let after = resolver.resolveProject(for: openDirectory)

        #expect(after.id == ProjectID(rootURL: projectRoot))
        #expect(rootResolver.callCount == 2)

        _ = resolver.resolveProject(for: sandbox.appendingPathComponent("second"))
        _ = resolver.resolveProject(for: sandbox.appendingPathComponent("third"))
        #expect(resolver.cachedEntryCount == 2)
    }

    @Test("symlinked and physical paths share one canonical identity and cache entry")
    func symlinkCanonicalization() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectSymlinkTests-\(UUID().uuidString)", isDirectory: true)
        let physical = sandbox.appendingPathComponent("physical", isDirectory: true)
        let link = sandbox.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createDirectory(at: physical, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: physical)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let rootResolver = CountingRootResolver()
        let resolver = CachedProjectResolver(rootResolver: rootResolver, cacheTTL: 60)

        let linked = resolver.resolveProject(for: link)
        let direct = resolver.resolveProject(for: physical)

        #expect(linked.id == direct.id)
        #expect(linked.rootURL == physical.standardizedFileURL)
        #expect(resolver.cachedEntryCount == 1)
        #expect(rootResolver.callCount == 1)
    }

    @Test("repeated OSC 7 paths preserve the resolver cache")
    func repeatedCurrentDirectoryDoesNotInvalidate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectOSC7Tests-\(UUID().uuidString)", isDirectory: true)
        let child = root.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let resolver = TrackingProjectResolver(root: root)
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            projectResolver: resolver,
            deferContentSetup: true
        )
        let tab = controller.tabManager.addTab(workingDirectory: root)

        controller.handleCurrentDirectoryChange(root, tabID: tab.id, surfaceID: nil)
        controller.handleCurrentDirectoryChange(root, tabID: tab.id, surfaceID: nil)
        #expect(resolver.invalidatedPaths.isEmpty)

        controller.handleCurrentDirectoryChange(child, tabID: tab.id, surfaceID: nil)
        #expect(resolver.invalidatedPaths == [root.path, child.path])
    }
}
