// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BundledFontRegistryTests.swift - Regression tests for bundled font discovery.

import Testing
@testable import CocxyTerminal

@Suite("BundledFontRegistry")
@MainActor
struct BundledFontRegistryTests {

    @Test("ensureRegistered is idempotent and never crashes")
    func ensureRegisteredIsIdempotent() {
        BundledFontRegistry.ensureRegistered()
        BundledFontRegistry.ensureRegistered()
        BundledFontRegistry.ensureRegistered()
    }

    @Test("fontResourceURLs returns only valid font extensions")
    func fontResourceURLsReturnsValidExtensions() {
        let urls = BundledFontRegistry.fontResourceURLs()
        // In SwiftPM tests, Bundle.main does not ship fonts — the
        // production .app copies them via build-app.sh. This test
        // verifies the mechanism does not crash and returns only valid
        // font files when any are found.
        for url in urls {
            let ext = url.pathExtension.lowercased()
            #expect(ext == "otf" || ext == "ttf", "Unexpected extension: \(ext)")
        }
    }

    @Test("isBundledFamily matches shipped families case-insensitively")
    func isBundledFamilyMatchesCaseInsensitive() {
        #expect(BundledFontRegistry.isBundledFamily("JetBrainsMono Nerd Font Mono"))
        #expect(BundledFontRegistry.isBundledFamily("jetbrainsmono nerd font mono"))
        #expect(BundledFontRegistry.isBundledFamily("Monaspace Neon"))
        #expect(!BundledFontRegistry.isBundledFamily("Arial"))
    }

    @Test("bundledFamilies lists expected font names")
    func bundledFamiliesContainsExpectedEntries() {
        let families = BundledFontRegistry.bundledFamilies
        #expect(families.contains("JetBrainsMono Nerd Font Mono"))
        #expect(families.contains("Monaspace Neon"))
    }
}
