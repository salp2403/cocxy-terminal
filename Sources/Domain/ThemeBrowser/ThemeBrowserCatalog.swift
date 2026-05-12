// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ThemeBrowserCatalog.swift - Searchable catalog projection for visual themes.

import Foundation

enum ThemeBrowserSourceKind: String, CaseIterable, Sendable, Equatable {
    case builtIn
    case custom
    case imported

    var displayName: String {
        switch self {
        case .builtIn: return "Built-in"
        case .custom: return "Custom"
        case .imported: return "Imported"
        }
    }
}

enum ThemeBrowserFilter: String, CaseIterable, Identifiable, Sendable, Equatable {
    case all
    case dark
    case light
    case builtIn
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .dark: return "Dark"
        case .light: return "Light"
        case .builtIn: return "Built-in"
        case .custom: return "Custom"
        }
    }
}

struct ThemeBrowserItem: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let variant: ThemeVariant
    let author: String?
    let sourceKind: ThemeBrowserSourceKind
    let palette: ThemePalette

    init(theme: Theme) {
        self.id = theme.metadata.name
        self.name = theme.metadata.name
        self.variant = theme.metadata.variant
        self.author = theme.metadata.author
        self.sourceKind = Self.sourceKind(for: theme.metadata.source)
        self.palette = theme.palette
    }

    private static func sourceKind(for source: ThemeSource) -> ThemeBrowserSourceKind {
        switch source {
        case .builtIn:
            return .builtIn
        case .legacyImport:
            return .imported
        case .custom:
            return .custom
        }
    }
}

@MainActor
struct ThemeBrowserCatalog {
    let items: [ThemeBrowserItem]

    init(themeEngine: ThemeEngineImpl) {
        self.items = themeEngine.availableThemes.compactMap { metadata in
            guard let theme = try? themeEngine.themeByName(metadata.name) else { return nil }
            return ThemeBrowserItem(theme: theme)
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func filteredItems(
        query: String,
        filter: ThemeBrowserFilter
    ) -> [ThemeBrowserItem] {
        items
            .filter { item in filter.includes(item) }
            .filter { item in ThemeFuzzyMatcher.matches(query: query, item: item) }
            .sorted { lhs, rhs in
                ThemeFuzzyMatcher.score(query: query, item: lhs)
                    > ThemeFuzzyMatcher.score(query: query, item: rhs)
            }
    }
}

extension ThemeBrowserFilter {
    func includes(_ item: ThemeBrowserItem) -> Bool {
        switch self {
        case .all:
            return true
        case .dark:
            return item.variant == .dark
        case .light:
            return item.variant == .light
        case .builtIn:
            return item.sourceKind == .builtIn
        case .custom:
            return item.sourceKind == .custom || item.sourceKind == .imported
        }
    }
}

enum ThemeFuzzyMatcher {
    static func matches(query: String, item: ThemeBrowserItem) -> Bool {
        score(query: query, item: item) > 0
    }

    static func score(query: String, item: ThemeBrowserItem) -> Int {
        let tokens = query
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
            .map { String($0).lowercased() }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return 1 }

        let haystack = [
            item.name,
            item.author ?? "",
            item.variant.rawValue,
            item.sourceKind.displayName
        ]
        .joined(separator: " ")
        .lowercased()

        var score = 0
        for token in tokens {
            if haystack.contains(token) {
                score += 10
            } else if isSubsequence(token, of: haystack) {
                score += 2
            } else {
                return 0
            }
        }
        if item.name.lowercased().hasPrefix(tokens.joined(separator: " ")) {
            score += 20
        }
        return score
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var searchIndex = haystack.startIndex
        for character in needle {
            guard let match = haystack[searchIndex...].firstIndex(of: character) else {
                return false
            }
            searchIndex = haystack.index(after: match)
        }
        return true
    }
}
