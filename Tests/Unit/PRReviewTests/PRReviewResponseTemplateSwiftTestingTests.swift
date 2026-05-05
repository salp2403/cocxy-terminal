// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PRReviewResponseTemplateSwiftTestingTests.swift - Response template catalog tests.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PR review response templates")
struct PRReviewResponseTemplateSwiftTestingTests {

    @Test("default templates expose stable unique identifiers")
    func defaultTemplatesExposeStableUniqueIdentifiers() {
        let ids = PRReviewResponseTemplateCatalog.defaultTemplates.map(\.id.rawValue)

        #expect(ids == [
            "needs-tests",
            "narrow-scope",
            "handle-failure",
            "explain-impact",
            "nit",
        ])
        #expect(Set(ids).count == ids.count)
    }

    @Test("template titles and bodies localize to Spanish")
    func templateTitlesAndBodiesLocalizeToSpanish() throws {
        let bundle = try #require(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let template = try #require(
            PRReviewResponseTemplateCatalog.defaultTemplates.first {
                $0.id == .needsTests
            }
        )

        #expect(template.title(using: localizer) == "Pedir pruebas")
        #expect(template.body(using: localizer).contains("Agrega cobertura enfocada"))
    }

    @Test("template insertion preserves existing draft text with one blank line")
    func templateInsertionPreservesExistingDraftText() {
        #expect(
            PRReviewResponseTemplateCatalog.inserting(
                templateBody: "Please add coverage.",
                into: ""
            ) == "Please add coverage."
        )

        #expect(
            PRReviewResponseTemplateCatalog.inserting(
                templateBody: "Please add coverage.",
                into: "Existing note"
            ) == "Existing note\n\nPlease add coverage."
        )

        #expect(
            PRReviewResponseTemplateCatalog.inserting(
                templateBody: "Please add coverage.\n",
                into: "  Existing note  \n\n"
            ) == "Existing note\n\nPlease add coverage."
        )
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}
