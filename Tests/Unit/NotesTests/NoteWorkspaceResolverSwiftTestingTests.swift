// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Pin the `NoteWorkspaceResolving` contract: the production resolver
/// reuses the Aurora git-ancestor lookup, falls back to the directory
/// itself when no ancestor is reachable (so non-git directories still
/// get notes), and exposes a stable display name. The protocol stays
/// `Sendable` so callers from any actor can ask for a workspace without
/// trampolining through a queue.
@Suite("NoteWorkspaceResolver")
struct NoteWorkspaceResolverSwiftTestingTests {

    /// Stub implementation that returns a pre-recorded URL regardless
    /// of input, so tests can pin the resolver behaviour against a
    /// known git-ancestor without touching the filesystem.
    private struct StubAuroraResolver: AuroraWorkspaceRootResolver {
        let canned: URL?
        func workspaceRoot(for directory: URL) -> URL? { canned }
    }

    @Test("resolver delegates to the supplied Aurora resolver so Notes inherits Aurora's grouping")
    func delegatesToAuroraResolver() {
        let gitAncestor = URL(fileURLWithPath: "/Users/sample/projects/foo")
        let resolver = DefaultNoteWorkspaceResolver(
            auroraResolver: StubAuroraResolver(canned: gitAncestor)
        )

        let resolved = resolver.resolveWorkspace(
            for: URL(fileURLWithPath: "/Users/sample/projects/foo/src/lib")
        )

        #expect(resolved?.rootURL == gitAncestor.standardizedFileURL)
        #expect(
            resolved?.workspaceID
                == NoteWorkspaceID(workspaceRoot: gitAncestor.standardizedFileURL)
        )
    }

    @Test("resolver falls back to the directory itself when Aurora reports no git ancestor")
    func fallsBackWhenAuroraReturnsNil() {
        let directory = URL(fileURLWithPath: "/tmp/scratch")
        let resolver = DefaultNoteWorkspaceResolver(
            auroraResolver: StubAuroraResolver(canned: nil)
        )

        let resolved = resolver.resolveWorkspace(for: directory)

        #expect(resolved?.rootURL == directory.standardizedFileURL)
        #expect(
            resolved?.workspaceID
                == NoteWorkspaceID(workspaceRoot: directory.standardizedFileURL)
        )
    }

    @Test("display name is the last path component so the sidebar shows a friendly label")
    func displayNameUsesBasename() {
        let resolver = DefaultNoteWorkspaceResolver(
            auroraResolver: StubAuroraResolver(canned: nil)
        )

        let resolved = resolver.resolveWorkspace(
            for: URL(fileURLWithPath: "/Users/sample/projects/cocxy-terminal")
        )

        #expect(resolved?.displayName == "cocxy-terminal")
    }

    @Test("display name renders / when the URL points at the filesystem root so the sidebar never shows an empty label")
    func displayNameRendersFilesystemRoot() {
        #expect(DefaultNoteWorkspaceResolver.displayName(for: URL(fileURLWithPath: "/")) == "/")
    }

    @Test("trailing slashes do not change the resolved workspace ID so the same directory always lands on the same notes folder")
    func trailingSlashesNormalisedThroughResolver() {
        let resolver = DefaultNoteWorkspaceResolver(
            auroraResolver: StubAuroraResolver(canned: nil)
        )

        let withSlash = resolver.resolveWorkspace(
            for: URL(fileURLWithPath: "/Users/sample/projects/foo/")
        )
        let withoutSlash = resolver.resolveWorkspace(
            for: URL(fileURLWithPath: "/Users/sample/projects/foo")
        )

        #expect(withSlash?.workspaceID == withoutSlash?.workspaceID)
    }

    @Test("default initializer wires the production Aurora resolver so callers do not have to pass one explicitly")
    func defaultInitializerUsesProductionAuroraResolver() {
        // Smoke test for the production wiring: instantiating the
        // resolver without arguments must not crash, and a directory
        // with no git ancestor (e.g. /private/tmp on macOS — never a
        // repo) should still resolve to a non-nil workspace.
        let resolver = DefaultNoteWorkspaceResolver()

        let resolved = resolver.resolveWorkspace(for: URL(fileURLWithPath: "/private/tmp"))

        #expect(resolved != nil)
        #expect(resolved?.displayName.isEmpty == false)
    }
}
