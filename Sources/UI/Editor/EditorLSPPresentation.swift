// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorLSPPresentation.swift - UI-facing state for local LSP editor responses.

import Foundation

struct EditorLSPPresentation: Equatable {
    var hoverText: String?
    var completionItems: [LSPCompletionItem] = []
    var definitionLocations: [LSPLocation] = []
    var referenceLocations: [LSPLocation] = []

    var accessoryText: String? {
        accessoryText(using: AppLocalizer(languagePreference: .english))
    }

    var resultItemTitles: [String] {
        resultItemTitles(using: AppLocalizer(languagePreference: .english))
    }

    func accessoryText(using localizer: AppLocalizer) -> String? {
        if let completion = completionItems.first {
            return completionTitle(completion)
        }
        if let hoverText, !hoverText.isEmpty {
            return hoverText
        }
        if let definition = definitionLocations.first {
            return locationSummary(definition)
        }
        if !referenceLocations.isEmpty {
            return Self.localizedReferences(referenceLocations.count, using: localizer)
        }
        return nil
    }

    func resultItemTitles(using _: AppLocalizer) -> [String] {
        if !completionItems.isEmpty {
            return completionItems.map(completionTitle)
        }
        if !definitionLocations.isEmpty {
            return definitionLocations.map(locationSummary)
        }
        if !referenceLocations.isEmpty {
            return referenceLocations.map(locationSummary)
        }
        return []
    }

    static func localizedReferences(_ count: Int, using localizer: AppLocalizer) -> String {
        let key = count == 1 ? "editor.lsp.references.one" : "editor.lsp.references.many"
        let fallback = count == 1 ? "%d reference" : "%d references"
        return String(format: localizer.string(key, fallback: fallback), count)
    }

    mutating func apply(_ event: LSPClientEvent) {
        switch event {
        case let .hover(_, hover):
            hoverText = hover?.contents
        case let .completion(_, items):
            completionItems = items
        case let .definition(_, locations):
            definitionLocations = locations
        case let .references(_, locations):
            referenceLocations = locations
        case .diagnostics:
            break
        }
    }

    mutating func clearDocumentScopedState() {
        hoverText = nil
        completionItems = []
        definitionLocations = []
        referenceLocations = []
    }

    private func locationSummary(_ location: LSPLocation) -> String {
        let name = URL(string: location.uri)?.lastPathComponent ?? location.uri
        return "\(name):\(location.range.start.line + 1)"
    }

    private func completionTitle(_ completion: LSPCompletionItem) -> String {
        [completion.label, completion.detail]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " - ")
    }
}
