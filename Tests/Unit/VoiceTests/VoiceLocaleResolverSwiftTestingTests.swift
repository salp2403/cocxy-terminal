// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VoiceLocaleResolverSwiftTestingTests.swift - Multi-locale Voice input selection.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("VoiceLocaleResolver")
struct VoiceLocaleResolverSwiftTestingTests {
    @Test("system locale resolves exact supported locale first")
    func systemLocaleResolvesExactSupportedLocaleFirst() {
        let resolver = VoiceLocaleResolver(
            supportedLocales: [
                Locale(identifier: "en_US"),
                Locale(identifier: "es_ES"),
            ],
            systemLocale: Locale(identifier: "en_US")
        )

        let resolution = resolver.resolve(config: .defaults)

        #expect(resolution == VoiceLocaleResolution(
            localeIdentifier: "en-US",
            source: .systemExact
        ))
    }

    @Test("system locale falls back by language when region is unsupported")
    func systemLocaleFallsBackByLanguageWhenRegionIsUnsupported() {
        let resolver = VoiceLocaleResolver(
            supportedLocales: [
                Locale(identifier: "fr_FR"),
                Locale(identifier: "es_ES"),
                Locale(identifier: "en_US"),
            ],
            systemLocale: Locale(identifier: "es_HN")
        )

        let resolution = resolver.resolve(config: .defaults)

        #expect(resolution == VoiceLocaleResolution(
            localeIdentifier: "es-ES",
            source: .systemLanguageFallback
        ))
    }

    @Test("manual override wins over system locale when supported")
    func manualOverrideWinsOverSystemLocaleWhenSupported() {
        let resolver = VoiceLocaleResolver(
            supportedLocales: [
                Locale(identifier: "en_US"),
                Locale(identifier: "fr_FR"),
            ],
            systemLocale: Locale(identifier: "en_US")
        )

        let resolution = resolver.resolve(config: VoiceConfig(enabled: true, localeIdentifier: "fr-FR"))

        #expect(resolution == VoiceLocaleResolution(
            localeIdentifier: "fr-FR",
            source: .manualOverride
        ))
    }

    @Test("unsupported manual override falls back to system locale without cloud fallback")
    func unsupportedManualOverrideFallsBackToSystemLocale() {
        let resolver = VoiceLocaleResolver(
            supportedLocales: [
                Locale(identifier: "en_US"),
            ],
            systemLocale: Locale(identifier: "en_US")
        )

        let resolution = resolver.resolve(config: VoiceConfig(enabled: true, localeIdentifier: "de-DE"))

        #expect(resolution == VoiceLocaleResolution(
            localeIdentifier: "en-US",
            source: .manualUnsupportedSystemFallback(requested: "de-DE")
        ))
    }

    @Test("empty supported locales resolve as unavailable")
    func emptySupportedLocalesResolveAsUnavailable() {
        let resolver = VoiceLocaleResolver(
            supportedLocales: [],
            systemLocale: Locale(identifier: "en_US")
        )

        let resolution = resolver.resolve(config: .defaults)

        #expect(resolution == VoiceLocaleResolution(localeIdentifier: nil, source: .unavailable))
    }

    @Test("supported locale options are sorted by stable normalized identifier")
    func supportedLocaleOptionsAreSortedByNormalizedIdentifier() {
        let resolver = VoiceLocaleResolver(
            supportedLocales: [
                Locale(identifier: "es_ES"),
                Locale(identifier: "en_US"),
                Locale(identifier: "fr_FR"),
            ],
            systemLocale: Locale(identifier: "en_US")
        )

        #expect(resolver.supportedLocaleOptions().map(\.identifier) == [
            "en-US",
            "es-ES",
            "fr-FR",
        ])
    }
}
