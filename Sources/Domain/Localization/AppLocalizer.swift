// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppLocalizer.swift - Local app language resolution and string lookup.

import Foundation

enum AppLocalizationKey: String, CaseIterable, Sendable {
    case preferencesAppearanceLanguageTitle = "preferences.appearance.language.title"
    case preferencesAppearanceLanguagePicker = "preferences.appearance.language.picker"
    case preferencesAppearanceLanguageHelp = "preferences.appearance.language.help"
}

struct AppLocalizationResolver: Sendable {
    static let supportedLanguages: [AppLanguage] = [.english, .spanish]

    var preferredLanguageIdentifiers: [String]

    init(preferredLanguageIdentifiers: [String] = Locale.preferredLanguages) {
        self.preferredLanguageIdentifiers = preferredLanguageIdentifiers
    }

    func resolve(_ preference: AppLanguage) -> AppLanguage {
        switch preference {
        case .english, .spanish:
            return preference
        case .system:
            for identifier in preferredLanguageIdentifiers {
                if let language = AppLanguage.normalized(identifier),
                   Self.supportedLanguages.contains(language) {
                    return language
                }
            }
            return .english
        }
    }
}

struct AppLocalizer {
    private let language: AppLanguage
    private let bundle: Bundle
    private let fallbackStrings: [AppLocalizationKey: String]

    init(
        languagePreference: AppLanguage,
        resolver: AppLocalizationResolver = AppLocalizationResolver(),
        bundle: Bundle = .main,
        fallbackStrings: [AppLocalizationKey: String] = AppLocalizer.defaultFallbackStrings
    ) {
        self.language = resolver.resolve(languagePreference)
        self.bundle = bundle
        self.fallbackStrings = fallbackStrings
    }

    var resolvedLanguage: AppLanguage {
        language
    }

    func string(_ key: AppLocalizationKey) -> String {
        let fallback = fallbackStrings[key] ?? key.rawValue
        return string(key.rawValue, fallback: fallback)
    }

    func string(_ key: String, fallback: String) -> String {
        guard let localizedBundle = localizedBundle(for: language) else {
            return fallback
        }
        return localizedBundle.localizedString(forKey: key, value: fallback, table: nil)
    }

    private func localizedBundle(for language: AppLanguage) -> Bundle? {
        guard let url = bundle.url(forResource: language.rawValue, withExtension: "lproj") else {
            return nil
        }
        return Bundle(url: url)
    }

    static let defaultFallbackStrings: [AppLocalizationKey: String] = [
        .preferencesAppearanceLanguageTitle: "Language",
        .preferencesAppearanceLanguagePicker: "App language",
        .preferencesAppearanceLanguageHelp:
            "System follows the first supported macOS preferred language. English and Spanish are available now.",
    ]
}
