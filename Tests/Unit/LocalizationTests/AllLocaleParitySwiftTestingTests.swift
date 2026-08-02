// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("All localization resources")
struct AllLocaleParitySwiftTestingTests {
    private static let localeCodes = [
        "en", "es", "ar", "bs", "da", "de", "fr", "it", "ja", "km", "ko",
        "no", "pl", "pt-BR", "ru", "th", "tr", "uk", "vi", "zh-CN", "zh-TW",
    ]

    @Test("all 21 locales have exact nonempty key parity")
    func allLocalesHaveExactNonemptyKeyParity() throws {
        let resources = localizationResourcesURL()
        let english = try localizationStrings(locale: "en", resources: resources)
        let expectedKeys = Set(english.keys)

        #expect(Self.localeCodes.count == 21)
        #expect(Set(Self.localeCodes).count == Self.localeCodes.count)
        #expect(expectedKeys.isEmpty == false)

        for locale in Self.localeCodes {
            let localized = try localizationStrings(locale: locale, resources: resources)
            let localizedKeys = Set(localized.keys)
            let missing = expectedKeys.subtracting(localizedKeys).sorted()
            let orphaned = localizedKeys.subtracting(expectedKeys).sorted()
            let empty = localized.compactMap { key, value in
                value.isEmpty ? key : nil
            }.sorted()

            #expect(
                missing.isEmpty,
                Comment(rawValue: "\(locale) is missing keys: \(missing.prefix(20).joined(separator: ", "))")
            )
            #expect(
                orphaned.isEmpty,
                Comment(rawValue: "\(locale) has orphaned keys: \(orphaned.prefix(20).joined(separator: ", "))")
            )
            #expect(
                empty.isEmpty,
                Comment(rawValue: "\(locale) has empty values: \(empty.prefix(20).joined(separator: ", "))")
            )
        }
    }

    @Test("all translations preserve format placeholders")
    func allTranslationsPreserveFormatPlaceholders() throws {
        let resources = localizationResourcesURL()
        let english = try localizationStrings(locale: "en", resources: resources)

        for locale in Self.localeCodes where locale != "en" {
            let localized = try localizationStrings(locale: locale, resources: resources)
            let mismatches = english.keys.compactMap { key -> String? in
                guard let value = localized[key] else { return nil }
                let expected = formatPlaceholders(in: english[key] ?? "")
                let actual = formatPlaceholders(in: value)
                return expected == actual ? nil : "\(key): \(expected) != \(actual)"
            }.sorted()

            #expect(
                mismatches.isEmpty,
                Comment(rawValue: "\(locale) changed format placeholders: \(mismatches.prefix(20).joined(separator: "; "))")
            )
        }
    }

    @Test("resolved Arabic UI direction is RTL")
    func resolvedArabicUIDirectionIsRTL() {
        let arabic = AppLocalizer(languagePreference: .arabic)
        let english = AppLocalizer(languagePreference: .english)
        let systemArabic = AppLocalizer(
            languagePreference: .system,
            resolver: AppLocalizationResolver(preferredLanguageIdentifiers: ["ar-HN"])
        )

        #expect(arabic.isRightToLeft)
        #expect(systemArabic.isRightToLeft)
        #expect(english.isRightToLeft == false)
    }

    private func localizationResourcesURL() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Localization", isDirectory: true)
    }

    private func localizationStrings(
        locale: String,
        resources: URL
    ) throws -> [String: String] {
        let url = resources
            .appendingPathComponent("\(locale).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        return try #require(propertyList as? [String: String])
    }

    private func formatPlaceholders(in value: String) -> [String] {
        let pattern = #"%(?:\d+\$)?[-+#0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|L|q|z|t|j)?(?:@|[diuoxXfFeEgGaAcCsSpn%])"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            Range(match.range, in: value).map { String(value[$0]) }
        }
    }
}
