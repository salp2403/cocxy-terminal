// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NoteWorkspaceID.swift - Stable, deterministic identifier for the
// workspace a note belongs to.

import CryptoKit
import Foundation

/// Deterministic, stable identifier for the workspace a note belongs to.
///
/// The Notes module groups notes by workspace root URL (resolved via
/// `NoteWorkspaceResolver`), but using the raw filesystem path as the
/// identifier has two problems:
///
///   * Paths can be long, contain spaces, slashes, and non-ASCII
///     characters that complicate filenames and TOML keys.
///   * Paths leak personally identifiable information (a user's
///     `/Users/<name>` prefix) into any filenames or indexes that
///     persist them.
///
/// `NoteWorkspaceID` solves both by hashing the standardised path with
/// SHA-256 and keeping the first 12 hexadecimal characters. Collisions
/// at 12 chars require ~2^48 paths to become likely, which is far beyond
/// any single user's workspace count.
///
/// ## Properties
///
/// * **Deterministic**: the same workspace root always produces the
///   same ID, regardless of process or run.
/// * **Stable**: not affected by case differences in URL prefixes
///   (`file://`) or trailing slashes — both normalise away.
/// * **Filesystem-safe**: pure lowercase hexadecimal, safe to use as a
///   directory or file name on every platform Cocxy targets.
/// * **Privacy-preserving**: no part of the original path appears in
///   the rendered identifier.
struct NoteWorkspaceID: Sendable, Equatable, Hashable, Codable {

    /// Lowercase hexadecimal representation of the truncated SHA-256
    /// hash. Always 12 characters; tests pin this width because file
    /// layouts depend on a fixed-length identifier.
    let rawValue: String

    /// Builds an identifier from a workspace root URL. The URL is
    /// standardised (resolves symlinks and removes trailing slashes)
    /// before hashing so equivalent URLs collapse onto the same ID.
    init(workspaceRoot: URL) {
        self.rawValue = Self.computeID(from: workspaceRoot)
    }

    /// Re-hydrates an identifier from a raw value. Used by `Codable`
    /// decoding and by callers that read filenames back into typed
    /// values. The caller is responsible for ensuring the raw value
    /// originated from `computeID(from:)`; this initializer does not
    /// validate the format because tests cover that contract.
    init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Pure helper that returns the 12-character lowercase hexadecimal
    /// SHA-256 prefix of the standardised path of `url`. Exposed
    /// `static` so unit tests can pin the contract without constructing
    /// the value type, and so other callers (the resolver, the store)
    /// can pre-compute the same ID without instantiating `NoteWorkspaceID`.
    static func computeID(from url: URL) -> String {
        let normalisedPath = url.standardizedFileURL.path
        let data = Data(normalisedPath.utf8)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(idLength))
    }

    /// Width of `rawValue`. Pinned to 12 hexadecimal characters
    /// (48 bits) so the file layout stays compact while preserving
    /// collision resistance for any practical number of workspaces.
    static let idLength = 12
}
