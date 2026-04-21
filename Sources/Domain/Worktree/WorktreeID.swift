// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeID.swift - Generation and validation of the short unique
// identifier used for cocxy-managed git worktrees.

import Foundation

/// Pure helpers around the short unique identifier that names a cocxy
/// worktree on disk and inside the manifest.
///
/// The identifier appears in three places that must stay consistent:
///   1. The directory path component `<base-path>/<repo-hash>/<id>/`.
///   2. The manifest entry that pairs the id with the origin repo, the
///      branch, and the owning tab.
///   3. The branch name produced by `WorktreeBranch.expand` when the
///      `{id}` placeholder is resolved.
///
/// For all three, we need an identifier that is:
///   - safe as a POSIX path component (no `/`, no whitespace, no shell
///     metacharacters, no leading dot);
///   - safe as a git ref component (no ASCII control, no `~`, `^`, `:`,
///     `?`, `*`, `[`, `\`, no `..`);
///   - short enough to fit in CLI output without wrapping (<= 12
///     characters); and
///   - long enough to make accidental collisions irrelevant for the
///     expected cardinality (~ hundreds of active worktrees per machine).
///
/// The implementation restricts the alphabet to lowercase ASCII letters
/// and digits. With `length = 6`, that is `36^6 ≈ 2.18 × 10⁹`
/// possibilities — a birthday-paradox collision at 100 simultaneous IDs
/// sits below 2.3 × 10⁻⁶. `WorktreeService` is still responsible for
/// catching the rare collision and retrying with `length + 1`.
enum WorktreeID {

    /// Minimum length enforced by both generation and validation.
    ///
    /// Matches `WorktreeConfig.minIDLength` so config clamping and ID
    /// validation agree.
    static let minLength: Int = WorktreeConfig.minIDLength

    /// Maximum length enforced by both generation and validation.
    static let maxLength: Int = WorktreeConfig.maxIDLength

    /// Alphabet used by `generate`. Lowercase ASCII + digits keeps the
    /// output safe on case-insensitive filesystems (APFS default)
    /// without collapsing distinct IDs.
    static let allowedCharacters: String = "abcdefghijklmnopqrstuvwxyz0123456789"

    /// Returns a fresh random identifier of the requested length.
    ///
    /// Values outside `[minLength, maxLength]` are clamped so the caller
    /// cannot accidentally produce an ID the rest of the stack would
    /// reject as too short or too long.
    ///
    /// - Parameter length: Desired length in characters.
    /// - Returns: A string of `length` random characters from
    ///   `allowedCharacters`.
    static func generate(length: Int) -> String {
        let clamped = clamp(length, min: minLength, max: maxLength)
        let alphabet = Array(allowedCharacters)
        var buffer = ""
        buffer.reserveCapacity(clamped)
        for _ in 0..<clamped {
            buffer.append(alphabet.randomElement() ?? "a")
        }
        return buffer
    }

    /// Returns `true` when `id` respects the length and alphabet
    /// invariants.
    ///
    /// Used by the manifest loader to reject tampered entries and by
    /// tests as a regression guard for generator output.
    static func isValid(_ id: String) -> Bool {
        guard (minLength...maxLength).contains(id.count) else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            allowedCharacters.unicodeScalars.contains(scalar)
        }
    }

    // MARK: - Private helpers

    private static func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.min(Swift.max(value, min), max)
    }
}
