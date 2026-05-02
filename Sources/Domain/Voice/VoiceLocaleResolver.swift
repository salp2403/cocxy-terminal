// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VoiceLocaleResolver.swift - Locale selection for local Voice input.

import Foundation
#if canImport(Speech)
import Speech
#endif

/// A selectable locale surfaced in Preferences for local Voice input.
struct VoiceLocaleOption: Identifiable, Sendable, Equatable {
    let identifier: String
    let localizedName: String

    var id: String { identifier }
}

/// The effective Voice locale after applying system locale and manual override rules.
struct VoiceLocaleResolution: Sendable, Equatable {
    enum Source: Sendable, Equatable {
        case systemExact
        case systemLanguageFallback
        case systemUnsupportedFallback
        case manualOverride
        case manualUnsupportedSystemFallback(requested: String)
        case unavailable
    }

    let localeIdentifier: String?
    let source: Source
}

/// Resolves Voice input locales using only local platform capabilities.
struct VoiceLocaleResolver: Sendable {
    private let supportedLocales: [Locale]
    private let supportedIdentifiers: [String]
    private let systemLocale: Locale

    init(
        supportedLocales: Set<Locale>,
        systemLocale: Locale = .current
    ) {
        self.supportedLocales = supportedLocales.sorted {
            Self.normalizedIdentifier(for: $0) < Self.normalizedIdentifier(for: $1)
        }
        self.supportedIdentifiers = self.supportedLocales.map(Self.normalizedIdentifier(for:))
        self.systemLocale = systemLocale
    }

    static func live(systemLocale: Locale = .current) -> VoiceLocaleResolver {
        VoiceLocaleResolver(
            supportedLocales: SpeechSupportedLocalesProvider.supportedLocales(),
            systemLocale: systemLocale
        )
    }

    func resolve(config: VoiceConfig) -> VoiceLocaleResolution {
        guard !supportedIdentifiers.isEmpty else {
            return VoiceLocaleResolution(localeIdentifier: nil, source: .unavailable)
        }

        let configured = VoiceConfig.normalizedLocaleIdentifier(config.localeIdentifier)
        if configured != VoiceConfig.systemLocaleIdentifier {
            if supportedIdentifiers.contains(configured) {
                return VoiceLocaleResolution(localeIdentifier: configured, source: .manualOverride)
            }
            return resolveSystemLocale(
                unsupportedManualOverride: configured
            )
        }

        return resolveSystemLocale(unsupportedManualOverride: nil)
    }

    func supportedLocaleOptions() -> [VoiceLocaleOption] {
        supportedLocales.map { locale in
            let identifier = Self.normalizedIdentifier(for: locale)
            return VoiceLocaleOption(
                identifier: identifier,
                localizedName: Self.localizedName(for: locale, identifier: identifier)
            )
        }
    }

    private func resolveSystemLocale(unsupportedManualOverride: String?) -> VoiceLocaleResolution {
        let systemIdentifier = Self.normalizedIdentifier(for: systemLocale)

        if supportedIdentifiers.contains(systemIdentifier) {
            return VoiceLocaleResolution(
                localeIdentifier: systemIdentifier,
                source: source(
                    forSystemFallback: .systemExact,
                    unsupportedManualOverride: unsupportedManualOverride
                )
            )
        }

        if let languageCode = Self.languageCode(from: systemIdentifier),
           let fallbackIdentifier = supportedIdentifiers.first(where: {
               Self.languageCode(from: $0) == languageCode
           }) {
            return VoiceLocaleResolution(
                localeIdentifier: fallbackIdentifier,
                source: source(
                    forSystemFallback: .systemLanguageFallback,
                    unsupportedManualOverride: unsupportedManualOverride
                )
            )
        }

        return VoiceLocaleResolution(
            localeIdentifier: supportedIdentifiers[0],
            source: source(
                forSystemFallback: .systemUnsupportedFallback,
                unsupportedManualOverride: unsupportedManualOverride
            )
        )
    }

    private func source(
        forSystemFallback systemSource: VoiceLocaleResolution.Source,
        unsupportedManualOverride: String?
    ) -> VoiceLocaleResolution.Source {
        if let unsupportedManualOverride {
            return .manualUnsupportedSystemFallback(requested: unsupportedManualOverride)
        }
        return systemSource
    }

    private static func normalizedIdentifier(for locale: Locale) -> String {
        VoiceConfig.normalizedLocaleIdentifier(locale.identifier)
    }

    private static func languageCode(from identifier: String) -> String? {
        let language = identifier.split(separator: "-").first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return language?.isEmpty == false ? language : nil
    }

    private static func localizedName(for locale: Locale, identifier: String) -> String {
        locale.localizedString(forIdentifier: identifier) ?? identifier
    }
}

private enum SpeechSupportedLocalesProvider {
    static func supportedLocales() -> Set<Locale> {
        #if canImport(Speech)
        return SFSpeechRecognizer.supportedLocales()
        #else
        return []
        #endif
    }
}
