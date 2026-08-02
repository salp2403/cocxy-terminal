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
        let supportedCodes = Set(AppLocalizationResolver.supportedLanguages.map(\.rawValue))

        #expect(Self.localeCodes.count == 21)
        #expect(Set(Self.localeCodes).count == Self.localeCodes.count)
        #expect(Set(Self.localeCodes) == supportedCodes)
        #expect(expectedKeys.isEmpty == false)

        for locale in Self.localeCodes {
            let localized = try localizationStrings(locale: locale, resources: resources)
            let localizedKeys = Set(localized.keys)
            let duplicateKeys = try duplicateLocalizationKeys(locale: locale, resources: resources)
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
                duplicateKeys.isEmpty,
                Comment(rawValue: "\(locale) has duplicate keys: \(duplicateKeys.prefix(20).joined(separator: ", "))")
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
                let expected = formatContract(in: english[key] ?? "")
                let actual = formatContract(in: value)
                return expected == actual ? nil : "\(key): \(expected) != \(actual)"
            }.sorted()

            #expect(
                mismatches.isEmpty,
                Comment(rawValue: "\(locale) changed format placeholders: \(mismatches.prefix(20).joined(separator: "; "))")
            )
        }
    }

    @Test("supported locales do not fall back to English UI copy")
    func supportedLocalesDoNotFallBackToEnglishUICopy() throws {
        let resources = localizationResourcesURL()
        let english = try localizationStrings(locale: "en", resources: resources)
        let representativeKeys = [
            "preferences.window.title",
            "projectHome.inbox.title",
            "projectHome.inbox.empty",
            "projectHome.context.title",
            "projectHome.action.newSession",
            "mobile.mirror.title",
            "mobile.mirror.start",
            "mobile.mirror.confirm.scope",
            "taskQueue.composer.title",
            "common.cancel",
            "common.refresh",
            "codeReview.panel.empty.title",
        ]
        let maximumTechnicalClones = english.count / 8
        let maximumLongEnglishClones = 25

        for locale in Self.localeCodes where locale != "en" {
            let localized = try localizationStrings(locale: locale, resources: resources)
            let identicalKeys = english.keys.filter { key in
                localized[key] == english[key]
            }.sorted()
            let longEnglishClones = identicalKeys.filter { key in
                english[key]?.range(
                    of: #"[A-Za-z]{2,} [A-Za-z]{2,}"#,
                    options: .regularExpression
                ) != nil
            }
            let representativeClones = representativeKeys.filter { key in
                localized[key] == english[key]
            }

            #expect(
                identicalKeys.count <= maximumTechnicalClones,
                Comment(
                    rawValue: "\(locale) retains \(identicalKeys.count) English values; sample: \(identicalKeys.prefix(20).joined(separator: ", "))"
                )
            )
            #expect(
                longEnglishClones.count <= maximumLongEnglishClones,
                Comment(
                    rawValue: "\(locale) retains English prose: \(longEnglishClones.prefix(20).joined(separator: ", "))"
                )
            )
            #expect(
                representativeClones.isEmpty,
                Comment(
                    rawValue: "\(locale) retains representative English UI copy: \(representativeClones.joined(separator: ", "))"
                )
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

    private func duplicateLocalizationKeys(
        locale: String,
        resources: URL
    ) throws -> [String] {
        let url = resources
            .appendingPathComponent("\(locale).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        let source = try String(contentsOf: url, encoding: .utf8)
        let expression = try NSRegularExpression(
            pattern: #"(?m)^\"((?:\\.|[^\"\\])*)\"\s*="#
        )
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        var counts: [String: Int] = [:]
        for match in expression.matches(in: source, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
            counts[String(source[keyRange]), default: 0] += 1
        }
        return counts.compactMap { key, count in count > 1 ? key : nil }.sorted()
    }

    private func formatContract(in value: String) -> [String] {
        let pattern = #"%(?:(\d+)\$)?([-+#0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|L|q|z|t|j)?(?:@|[diuoxXfFeEgGaAcCsSpn%]))"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        var nextPosition = 1
        var sawPositioned = false
        var sawUnpositioned = false
        var contract = expression.matches(in: value, range: range).compactMap { match -> String? in
            guard let bodyRange = Range(match.range(at: 2), in: value) else { return nil }
            let body = String(value[bodyRange])
            if body == "%" { return "literal:%%" }

            let position: Int
            if let range = Range(match.range(at: 1), in: value),
               let explicitPosition = Int(value[range]) {
                position = explicitPosition
                sawPositioned = true
            } else {
                position = nextPosition
                nextPosition += 1
                sawUnpositioned = true
            }
            return "\(position):%\(body)"
        }
        if sawPositioned && sawUnpositioned { contract.append("invalid:mixed-positioning") }
        return contract.sorted()
    }
}
