// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectIdentity.swift - Canonical local project identity and resolution.

import Foundation
import Darwin

struct ProjectID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = ProjectPathCanonicalizer.canonicalURL(
            URL(fileURLWithPath: rawValue, isDirectory: true)
        ).path
    }

    init(rootURL: URL) {
        self.init(rawValue: rootURL.path)
    }

    init(verifiedRootURL: URL) {
        rawValue = ProjectPathCanonicalizer.canonicalURL(verifiedRootURL).path
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var storageKey: String {
        NoteWorkspaceID.computeID(
            from: URL(fileURLWithPath: rawValue, isDirectory: true)
        )
    }
}

enum ProjectPathCanonicalizer {
    static func canonicalURL(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        var existingAncestor = standardized
        var missingComponents: [String] = []

        while !FileManager.default.fileExists(atPath: existingAncestor.path) {
            let parent = existingAncestor.deletingLastPathComponent()
            guard parent.path != existingAncestor.path else { break }
            missingComponents.insert(existingAncestor.lastPathComponent, at: 0)
            existingAncestor = parent
        }

        let resolvedAncestor = fullyResolvedRealPath(for: existingAncestor)
            ?? existingAncestor.resolvingSymlinksInPath().standardizedFileURL
        let resolved = missingComponents.reduce(resolvedAncestor) { partial, component in
            partial.appendingPathComponent(component)
        }
        return URL(
            fileURLWithPath: resolved.path,
            isDirectory: url.hasDirectoryPath
        )
    }

    private static func fullyResolvedRealPath(for url: URL) -> URL? {
        guard var resolved = realPath(for: url) else { return nil }
        var visitedPaths: Set<String> = []

        while visitedPaths.insert(resolved.path).inserted {
            guard let next = realPath(for: resolved),
                  next.path != resolved.path else {
                break
            }
            resolved = next
        }
        return resolved
    }

    private static func realPath(for url: URL) -> URL? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        return url.path.withCString { source in
            buffer.withUnsafeMutableBufferPointer { destination in
                guard let baseAddress = destination.baseAddress,
                      Darwin.realpath(source, baseAddress) != nil else { return nil }
                return URL(fileURLWithPath: String(cString: baseAddress))
            }
        }
    }
}

struct ProjectDescriptor: Equatable, Sendable {
    let id: ProjectID
    let rootURL: URL
    let automaticName: String
    let displayName: String
    let parent: ProjectID?

    var groupingID: ProjectID {
        parent ?? id
    }

    var groupingRootURL: URL {
        guard let parent else { return rootURL }
        return URL(fileURLWithPath: parent.rawValue, isDirectory: true)
    }

    var groupingAutomaticName: String {
        Self.automaticName(for: groupingRootURL)
    }

    static func automaticName(for rootURL: URL) -> String {
        let standardizedRoot = rootURL.standardizedFileURL
        let name = standardizedRoot.lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        if standardizedRoot.path == "/" { return "root" }
        return standardizedRoot.path
    }

    static func verifiedStandalone(
        _ directory: ProjectDirectoryRoot
    ) throws -> ProjectDescriptor {
        let rootURL = ProjectPathCanonicalizer.canonicalURL(
            try directory.descriptorBoundURL()
        )
        let id = ProjectID(verifiedRootURL: rootURL)
        let name = automaticName(for: rootURL)
        return ProjectDescriptor(
            id: id,
            rootURL: rootURL,
            automaticName: name,
            displayName: name,
            parent: nil
        )
    }
}

@MainActor
protocol ProjectResolving: AnyObject {
    func resolveProject(for directory: URL) -> ProjectDescriptor
    func invalidate(directory: URL)
    func invalidateAll()
}

@MainActor
final class CachedProjectResolver: ProjectResolving {
    private struct CacheEntry {
        let descriptor: ProjectDescriptor
        let expiresAt: Date
        let accessSequence: UInt64
    }

    private let rootResolver: any AuroraWorkspaceRootResolver
    private let cacheTTL: TimeInterval
    private let maximumEntryCount: Int
    private let clock: () -> Date
    private var cache: [String: CacheEntry] = [:]
    private var accessSequence: UInt64 = 0

    init(
        rootResolver: any AuroraWorkspaceRootResolver = GitAncestorWorkspaceRootResolver(),
        cacheTTL: TimeInterval = 2,
        maximumEntryCount: Int = 256,
        clock: @escaping () -> Date = Date.init
    ) {
        precondition(cacheTTL >= 0)
        precondition(maximumEntryCount > 0)
        self.rootResolver = rootResolver
        self.cacheTTL = cacheTTL
        self.maximumEntryCount = maximumEntryCount
        self.clock = clock
    }

    func resolveProject(for directory: URL) -> ProjectDescriptor {
        let standardizedDirectory = ProjectPathCanonicalizer.canonicalURL(directory)
        let key = standardizedDirectory.path
        let now = clock()

        if let cached = cache[key], cached.expiresAt >= now {
            accessSequence &+= 1
            cache[key] = CacheEntry(
                descriptor: cached.descriptor,
                expiresAt: cached.expiresAt,
                accessSequence: accessSequence
            )
            return cached.descriptor
        }

        cache.removeValue(forKey: key)
        let descriptor = makeDescriptor(for: standardizedDirectory)
        accessSequence &+= 1
        cache[key] = CacheEntry(
            descriptor: descriptor,
            expiresAt: now.addingTimeInterval(cacheTTL),
            accessSequence: accessSequence
        )
        evictLeastRecentlyUsedEntriesIfNeeded()
        return descriptor
    }

    func invalidate(directory: URL) {
        let invalidatedPath = ProjectPathCanonicalizer.canonicalURL(directory).path
        cache = cache.filter { cachedPath, _ in
            !Self.path(cachedPath, isEqualToOrDescendantOf: invalidatedPath)
                && !Self.path(invalidatedPath, isEqualToOrDescendantOf: cachedPath)
        }
    }

    func invalidateAll() {
        cache.removeAll(keepingCapacity: true)
    }

    var cachedEntryCount: Int {
        cache.count
    }

    private func makeDescriptor(for directory: URL) -> ProjectDescriptor {
        let root = ProjectPathCanonicalizer.canonicalURL(
            rootResolver.workspaceRoot(for: directory) ?? directory
        )
        let id = ProjectID(rootURL: root)
        let automaticName = ProjectDescriptor.automaticName(for: root)
        return ProjectDescriptor(
            id: id,
            rootURL: root,
            automaticName: automaticName,
            displayName: automaticName,
            parent: linkedWorktreeParent(for: root)
        )
    }

    private func linkedWorktreeParent(for root: URL) -> ProjectID? {
        let dotGitURL = root.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: dotGitURL.path,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue,
              let gitDirectory = GitInfoProviderImpl.resolveGitDirectoryURL(at: root) else {
            return nil
        }

        let commonDirectoryPointer = gitDirectory.appendingPathComponent("commondir")
        guard let pointer = try? String(contentsOf: commonDirectoryPointer, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !pointer.isEmpty else {
            return nil
        }

        let commonDirectory: URL
        if pointer.hasPrefix("/") {
            commonDirectory = ProjectPathCanonicalizer.canonicalURL(
                URL(fileURLWithPath: pointer, isDirectory: true)
            )
        } else {
            commonDirectory = ProjectPathCanonicalizer.canonicalURL(
                gitDirectory.appendingPathComponent(pointer, isDirectory: true)
            )
        }

        // Linked worktrees share the origin checkout's `<root>/.git`.
        // Submodules point into `.git/modules/...` and intentionally stay
        // independent projects rather than being folded into their parent.
        guard commonDirectory.lastPathComponent == ".git",
              FileManager.default.fileExists(
                atPath: commonDirectory.appendingPathComponent("HEAD").path
              ) else {
            return nil
        }

        let parentRoot = ProjectPathCanonicalizer.canonicalURL(
            commonDirectory.deletingLastPathComponent()
        )
        guard parentRoot != root else { return nil }
        return ProjectID(rootURL: parentRoot)
    }

    private func evictLeastRecentlyUsedEntriesIfNeeded() {
        guard cache.count > maximumEntryCount else { return }
        let overflow = cache.count - maximumEntryCount
        let keysToRemove = cache
            .sorted { $0.value.accessSequence < $1.value.accessSequence }
            .prefix(overflow)
            .map(\.key)
        for key in keysToRemove {
            cache.removeValue(forKey: key)
        }
    }

    private static func path(_ candidate: String, isEqualToOrDescendantOf ancestor: String) -> Bool {
        if candidate == ancestor { return true }
        let prefix = ancestor == "/" ? "/" : ancestor + "/"
        return candidate.hasPrefix(prefix)
    }
}
