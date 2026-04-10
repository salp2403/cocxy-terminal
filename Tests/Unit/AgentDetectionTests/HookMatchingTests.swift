// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Tests for the hook cwd → tab matching helper used by
/// `AppDelegate.resolvedControllerAndTab` and friends.
///
/// The hook event format reports the working directory exactly as the
/// agent (Claude Code) sees it via `process.cwd()`. macOS resolves
/// `/tmp` to `/private/tmp` for some processes and not others, and the
/// shell-side CWD reported via OSC 7 may or may not pre-resolve the
/// symlink. Without a canonical normalization step, the strict
/// path-equality comparison in `resolvedWorkingDirectoryCandidate` can
/// drop perfectly legitimate hook events because `/tmp` does not equal
/// `/private/tmp` lexically.
///
/// This suite exercises the normalization helper directly. It uses the
/// `normalizedWorkingDirectoryPathForTesting` static seam exposed by
/// `AppDelegate` so the tests do not need to construct an entire
/// `AppDelegate` instance just to verify pure path normalization.
@Suite("AppDelegate hook cwd path normalization")
struct HookMatchingTests {
    @Test("/tmp and /private/tmp resolve to the same canonical path")
    func tmpAndPrivateTmpResolveEqually() {
        let a = AppDelegate.normalizedWorkingDirectoryPathForTesting("/tmp")
        let b = AppDelegate.normalizedWorkingDirectoryPathForTesting("/private/tmp")
        #expect(
            a == b,
            "Expected canonical equality, got \(a) vs \(b)"
        )
    }

    @Test("Trailing slash normalizes to the same canonical path")
    func trailingSlashNormalizes() {
        let withSlash = AppDelegate.normalizedWorkingDirectoryPathForTesting("/tmp/")
        let withoutSlash = AppDelegate.normalizedWorkingDirectoryPathForTesting("/tmp")
        #expect(withSlash == withoutSlash)
    }

    @Test("file:// URL form resolves to the same canonical path as a plain path")
    func fileUrlMatchesPlainPath() {
        let fileURL = AppDelegate.normalizedWorkingDirectoryPathForTesting("file:///tmp")
        let plain = AppDelegate.normalizedWorkingDirectoryPathForTesting("/tmp")
        #expect(fileURL == plain)
    }

    @Test("Whitespace around the path is trimmed")
    func whitespaceIsTrimmed() {
        let trimmed = AppDelegate.normalizedWorkingDirectoryPathForTesting("/tmp")
        let surrounded = AppDelegate.normalizedWorkingDirectoryPathForTesting("  /tmp  \n")
        #expect(trimmed == surrounded)
    }

    @Test("Non-existent paths still normalize without crashing")
    func nonExistentPathsNormalize() {
        // resolvingSymlinksInPath is documented to return the path
        // unchanged when the target does not exist. Both sides should
        // therefore agree on the same lexical canonical form, even if
        // there is no underlying inode.
        let path = "/Users/no_such_user/cocxy-fake-1234567890"
        let normalized = AppDelegate.normalizedWorkingDirectoryPathForTesting(path)
        let normalizedAgain = AppDelegate.normalizedWorkingDirectoryPathForTesting(path)
        #expect(normalized == normalizedAgain)
        #expect(normalized.hasSuffix("/cocxy-fake-1234567890"))
    }
}
