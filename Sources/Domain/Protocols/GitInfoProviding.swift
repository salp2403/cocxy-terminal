// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitInfoProviding.swift - Contract for the git information provider.

import Foundation
import Combine

// MARK: - Git Info Providing Protocol

/// Provides git repository information for directories.
///
/// Used by the tab bar to display the current branch name next to each tab.
/// The provider watches for branch changes (e.g., after `git checkout`) and
/// notifies subscribers.
///
/// Implementation note: Uses `git rev-parse --abbrev-ref HEAD` (or reads
/// `.git/HEAD` directly for performance). Must respond within 50ms for
/// a good UX (ADR gate: < 50ms per branch query).
///
/// - SeeAlso: ARCHITECTURE.md Section 7.7
protocol GitInfoProviding: Sendable {

    /// Returns the current branch name for a directory.
    ///
    /// - Parameter directory: Path to a directory (may or may not be a git repo).
    /// - Returns: The branch name (e.g., "main", "feature/T-003"), or `nil`
    ///   if the directory is not inside a git repository.
    func currentBranch(at directory: URL) -> String?

    /// Returns whether the directory is inside a git repository.
    ///
    /// - Parameter directory: Path to check.
    /// - Returns: `true` if the directory is inside a git working tree.
    func isGitRepository(at directory: URL) -> Bool

    /// Observes branch changes for a directory.
    ///
    /// The handler is called whenever the branch changes (e.g., after
    /// `git checkout`, `git switch`, or a rebase). Uses filesystem watching
    /// on `.git/HEAD` for efficiency.
    ///
    /// - Parameters:
    ///   - directory: Path to the directory to observe.
    ///   - handler: Closure called with the new branch name, or `nil` if
    ///     the directory is no longer a git repo.
    /// - Returns: A cancellable that stops the observation when released.
    func observeBranch(
        at directory: URL,
        handler: @escaping @Sendable (String?) -> Void
    ) -> AnyCancellable
}
