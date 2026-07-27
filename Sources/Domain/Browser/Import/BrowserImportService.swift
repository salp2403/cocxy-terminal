// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserImportService.swift - Shared discovery, preview, and import operations.

import Foundation

enum BrowserImportDataKind: String, CaseIterable, Sendable, Hashable {
    case history
    case cookies
    case bookmarks
}

struct BrowserImportSourceProfile: Identifiable, Sendable, Equatable {
    let location: BrowserImportLocation
    let availableData: Set<BrowserImportDataKind>

    var id: String {
        "\(location.source.rawValue)|\(location.profileIdentifier)|\(location.historyPath.path)"
    }
}

struct BrowserImportSourceDiscovery: Identifiable, Sendable, Equatable {
    let source: BrowserImportSource
    let profiles: [BrowserImportSourceProfile]

    var id: String { source.rawValue }
    var isDetected: Bool { !profiles.isEmpty }
}

protocol BrowserImportServicing: Sendable {
    func discoverSources() -> [BrowserImportSourceDiscovery]
    func preview(_ plan: BrowserImportPlan) throws -> BrowserImportPreview
    func run(_ plan: BrowserImportPlan) throws -> BrowserImportResult
}

struct BrowserImportService: BrowserImportServicing, Sendable {
    let historyStore: (any BrowserHistoryStoring)?
    let bookmarkStore: (any BrowserBookmarkStoring)?
    let cookieStore: (any BrowserImportedCookieStoring)?
    let auditLogger: (any BrowserImportAuditLogging)?
    let bookmarkRootTitleFormat: String
    let bookmarkRootTitleAliases: [String]

    init(
        historyStore: (any BrowserHistoryStoring)?,
        bookmarkStore: (any BrowserBookmarkStoring)?,
        cookieStore: (any BrowserImportedCookieStoring)?,
        auditLogger: (any BrowserImportAuditLogging)? = FileBrowserImportAuditLogger(),
        bookmarkRootTitleFormat: String = "Imported from %@ - %@",
        bookmarkRootTitleAliases: [String] = []
    ) {
        self.historyStore = historyStore
        self.bookmarkStore = bookmarkStore
        self.cookieStore = cookieStore
        self.auditLogger = auditLogger
        self.bookmarkRootTitleFormat = bookmarkRootTitleFormat
        self.bookmarkRootTitleAliases = bookmarkRootTitleAliases
    }

    func discoverSources() -> [BrowserImportSourceDiscovery] {
        var discoveries: [BrowserImportSourceDiscovery] = []
        discoveries.reserveCapacity(BrowserImportSource.allCases.count)
        for source in BrowserImportSource.allCases {
            guard !Task.isCancelled else { break }
            let profiles = source.discoveredLocations().map { location in
                BrowserImportSourceProfile(
                    location: location,
                    availableData: availableData(at: location)
                )
            }
            discoveries.append(BrowserImportSourceDiscovery(source: source, profiles: profiles))
        }
        return discoveries
    }

    func preview(_ plan: BrowserImportPlan) throws -> BrowserImportPreview {
        try Task.checkCancellation()
        let preview = try BrowserSourceImporterFactory.importer(for: plan.source).preview(plan: plan)
        try Task.checkCancellation()
        return preview
    }

    func run(_ plan: BrowserImportPlan) throws -> BrowserImportResult {
        try Task.checkCancellation()
        return try BrowserImporter(
            source: plan.source,
            historyStore: historyStore,
            bookmarkStore: bookmarkStore,
            cookieStore: cookieStore,
            auditLogger: auditLogger,
            bookmarkRootTitleFormat: bookmarkRootTitleFormat,
            bookmarkRootTitleAliases: bookmarkRootTitleAliases
        ).importData(plan)
    }

    private func availableData(at location: BrowserImportLocation) -> Set<BrowserImportDataKind> {
        var result = Set<BrowserImportDataKind>()
        if BrowserImportFileReader.isRegularFile(at: location.historyPath) {
            result.insert(.history)
        }
        if let cookiesPath = location.cookiesPath,
           BrowserImportFileReader.isRegularFile(at: cookiesPath) {
            result.insert(.cookies)
        }
        if let bookmarksPath = location.bookmarksPath,
           BrowserImportFileReader.isRegularFile(at: bookmarksPath) {
            result.insert(.bookmarks)
        }
        return result
    }
}

enum BrowserImportBookmarkRootLocalization {
    static let key = "browser.import.bookmarks.folder"
    static let fallback = "Imported from %@ - %@"

    static func formats(
        current: String,
        bundle: Bundle = .main
    ) -> [String] {
        var formats: [String] = []
        func append(_ format: String) {
            guard !format.isEmpty, !formats.contains(format) else { return }
            formats.append(format)
        }

        append(current)
        for language in AppLocalizationResolver.supportedLanguages {
            append(AppLocalizer(
                languagePreference: language,
                bundle: bundle
            ).string(key, fallback: fallback))
        }
        append(fallback)
        return formats
    }
}
