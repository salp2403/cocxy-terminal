// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CLIArgumentParserVersionSwiftTestingTests.swift
//
// Regression coverage for `CLIArgumentParser.resolveVersion`.
//
// The resolver walks up two directories from the executable path to
// find `Contents/Info.plist`. `Bundle.main.executablePath` does not
// resolve symlinks on its own, so a CLI invocation through Homebrew's
// `/opt/homebrew/bin/cocxy` (a symlink to the bundled binary) would
// otherwise walk up from `/opt/homebrew/bin` and miss the enclosing
// `.app`. The resolver now runs the path through
// `URL.resolvingSymlinksInPath()` before walking upward.

import Foundation
import Testing
@testable import CocxyCLILib

@Suite("CLIArgumentParser version resolver")
struct CLIArgumentParserVersionSwiftTestingTests {

    // MARK: - Helpers

    /// Creates a fake `.app`-style directory with a bundled executable
    /// stub and an `Info.plist` carrying the requested version. The
    /// directory is deleted when the returned cleanup closure runs.
    private func makeFakeBundle(
        version: String
    ) throws -> (exePath: String, cleanup: () -> Void) {
        let uniqueID = UUID().uuidString.prefix(8)
        let bundleRoot = NSTemporaryDirectory()
            .appending("cocxy-version-test-\(uniqueID).app")
        let contentsDir = bundleRoot.appending("/Contents")
        let resourcesDir = contentsDir.appending("/Resources")
        try FileManager.default.createDirectory(
            atPath: resourcesDir,
            withIntermediateDirectories: true
        )

        let exePath = resourcesDir.appending("/cocxy")
        // A zero-byte file is enough — the resolver only reads path
        // metadata, not the executable itself.
        FileManager.default.createFile(atPath: exePath, contents: Data())

        let plistPath = contentsDir.appending("/Info.plist")
        let plist: [String: Any] = ["CFBundleShortVersionString": version]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: URL(fileURLWithPath: plistPath))

        let cleanup: () -> Void = {
            try? FileManager.default.removeItem(atPath: bundleRoot)
        }
        return (exePath, cleanup)
    }

    // MARK: - Tests

    /// Direct invocation through the canonical bundled path must read
    /// the enclosing `Info.plist`.
    @Test("resolver reads Info.plist when executable is a direct bundled path")
    func resolvesVersionFromDirectBundledPath() throws {
        let (exePath, cleanup) = try makeFakeBundle(version: "9.8.7")
        defer { cleanup() }

        let resolved = CLIArgumentParser.resolveVersion(executablePath: exePath)
        #expect(resolved == "9.8.7")
    }

    /// Regression for the Homebrew-style invocation. A symlink pointing
    /// at the bundled executable must still resolve to the enclosing
    /// `.app`'s `Info.plist`.
    @Test("resolver follows symlinks to enclosing bundle (symlink regression)")
    func resolvesVersionFromSymlinkToBundledPath() throws {
        let (exePath, cleanup) = try makeFakeBundle(version: "7.6.5")
        defer { cleanup() }

        let symlinkPath = NSTemporaryDirectory()
            .appending("cocxy-version-symlink-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createSymbolicLink(
            atPath: symlinkPath,
            withDestinationPath: exePath
        )
        defer { try? FileManager.default.removeItem(atPath: symlinkPath) }

        let resolved = CLIArgumentParser.resolveVersion(executablePath: symlinkPath)
        #expect(
            resolved == "7.6.5",
            "Symlinked executable must resolve through to the bundle's Info.plist, not fall back."
        )
    }

    /// A standalone executable (no enclosing `Contents/Info.plist`)
    /// must fall back to the pinned string so dev builds and tests
    /// keep a predictable version. Uses a path under a non-existent
    /// directory so the walk-up cannot accidentally hit an unrelated
    /// plist on the real filesystem.
    @Test("resolver falls back when no Info.plist is reachable")
    func resolvesVersionFallbackForStandaloneExecutable() {
        let standalonePath = NSTemporaryDirectory()
            .appending("cocxy-nobundle-\(UUID().uuidString.prefix(8))/cocxy")
        let resolved = CLIArgumentParser.resolveVersion(executablePath: standalonePath)
        #expect(resolved == CLIArgumentParser.fallbackVersion)
    }

    /// The fallback constant must be a valid semver string so downstream
    /// parsers (Homebrew cask, release pipeline) never see malformed
    /// values if the bundle resolution fails at release time.
    @Test("fallback version is non-empty and semver-shaped")
    func fallbackVersionIsValidSemver() {
        let fallback = CLIArgumentParser.fallbackVersion
        #expect(!fallback.isEmpty)
        let parts = fallback.split(separator: ".")
        #expect(parts.count == 3, "fallback should be major.minor.patch, got: \(fallback)")
        for part in parts {
            #expect(Int(part) != nil, "each segment should parse as int, got: \(part)")
        }
    }
}
