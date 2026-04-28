// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NoteWorkspaceResolver.swift - Resolves a tab's working directory
// into a stable workspace identifier the Notes module can group on.

import Foundation

/// Resolved metadata for a workspace the Notes module groups on.
///
/// Produced by `NoteWorkspaceResolving.resolveWorkspace(for:)`. Bundles
/// the durable identifier (used for filenames and the `NoteStore`
/// directory layout), the absolute URL (so callers can show the path
/// in the UI or open it in Finder), and a friendly display name (last
/// path component) that surfaces in the sidebar without exposing the
/// full filesystem path.
struct ResolvedNoteWorkspace: Sendable, Equatable {

    /// Stable, deterministic identifier derived from `rootURL`. Used
    /// directly as the directory name on disk, so the resolver and the
    /// store always agree on where a workspace's notes live.
    let workspaceID: NoteWorkspaceID

    /// Absolute URL of the workspace root. Read by the UI when it
    /// needs to render the path or open the directory in Finder.
    let rootURL: URL

    /// User-facing label — last path component of `rootURL`. Pre-computed
    /// here so the sidebar does not have to redo the basename split on
    /// every render.
    let displayName: String
}

/// Resolves the working directory of a terminal tab into a workspace
/// the Notes module can group on. Inputs are `Sendable` value types so
/// the resolver can be called from any actor without contention.
///
/// The default implementation prefers the nearest git ancestor (matches
/// the Aurora sidebar grouping the user already sees) and falls back to
/// the directory itself when no ancestor is reachable. Callers always
/// receive a non-nil resolution from the default implementation; tests
/// inject mocks that return `nil` to exercise the "no workspace" UI
/// path without simulating a missing tab.
protocol NoteWorkspaceResolving: Sendable {

    /// Returns the workspace metadata for `directory`, or `nil` if the
    /// implementation cannot determine one (test stubs / future
    /// implementations that need to opt out for ephemeral paths).
    func resolveWorkspace(for directory: URL) -> ResolvedNoteWorkspace?
}

/// Production resolver that delegates the git-ancestor lookup to the
/// existing `AuroraWorkspaceRootResolver` (so Notes and Aurora group
/// the same way) and falls back to the supplied directory when no
/// git ancestor is reachable.
///
/// Falling back instead of returning `nil` is a deliberate Notes-only
/// choice: the user has explicitly asked for notes per project, and
/// "this folder is not a git repo" is not a useful reason to hide the
/// notes feature. The `displayName` in the fallback case is the
/// directory's basename, so a `/tmp/scratch` tab still gets a
/// reasonable label in the sidebar.
struct DefaultNoteWorkspaceResolver: NoteWorkspaceResolving {

    private let auroraResolver: any AuroraWorkspaceRootResolver

    /// Builds the resolver. Defaults to `GitAncestorWorkspaceRootResolver`
    /// so Notes inherits Aurora's exact grouping rules without
    /// duplicating the walk-up logic; tests inject a stub that returns
    /// fixed values regardless of the filesystem state.
    init(auroraResolver: any AuroraWorkspaceRootResolver = GitAncestorWorkspaceRootResolver()) {
        self.auroraResolver = auroraResolver
    }

    func resolveWorkspace(for directory: URL) -> ResolvedNoteWorkspace? {
        let standardisedDirectory = directory.standardizedFileURL
        let root = auroraResolver.workspaceRoot(for: standardisedDirectory)
            ?? standardisedDirectory
        let displayName = Self.displayName(for: root)
        return ResolvedNoteWorkspace(
            workspaceID: NoteWorkspaceID(workspaceRoot: root),
            rootURL: root,
            displayName: displayName
        )
    }

    /// Pure helper kept `static` so the test suite can pin the
    /// fallback rendering without instantiating a resolver. Returns
    /// the last path component, or `"/"` when the URL points at the
    /// filesystem root (so the sidebar never shows an empty label).
    static func displayName(for url: URL) -> String {
        let lastComponent = url.lastPathComponent
        if lastComponent.isEmpty {
            return "/"
        }
        return lastComponent
    }
}
