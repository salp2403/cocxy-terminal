// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserImporter.swift - Browser import orchestration into Cocxy-owned stores.

import Foundation

struct BrowserImporter: Sendable {
    let sourceImporter: any BrowserSourceImporting
    let historyStore: (any BrowserHistoryStoring)?
    let bookmarkStore: (any BrowserBookmarkStoring)?
    let cookieStore: (any BrowserImportedCookieStoring)?
    let auditLogger: (any BrowserImportAuditLogging)?

    init(
        sourceImporter: any BrowserSourceImporting,
        historyStore: (any BrowserHistoryStoring)?,
        bookmarkStore: (any BrowserBookmarkStoring)?,
        cookieStore: (any BrowserImportedCookieStoring)?,
        auditLogger: (any BrowserImportAuditLogging)? = nil
    ) {
        self.sourceImporter = sourceImporter
        self.historyStore = historyStore
        self.bookmarkStore = bookmarkStore
        self.cookieStore = cookieStore
        self.auditLogger = auditLogger
    }

    init(
        source: BrowserImportSource,
        historyStore: (any BrowserHistoryStoring)?,
        bookmarkStore: (any BrowserBookmarkStoring)?,
        cookieStore: (any BrowserImportedCookieStoring)?,
        auditLogger: (any BrowserImportAuditLogging)? = nil
    ) {
        self.init(
            sourceImporter: BrowserSourceImporterFactory.importer(for: source),
            historyStore: historyStore,
            bookmarkStore: bookmarkStore,
            cookieStore: cookieStore,
            auditLogger: auditLogger
        )
    }

    func importData(_ plan: BrowserImportPlan) throws -> BrowserImportResult {
        let preview = try sourceImporter.preview(plan: plan)
        var importedHistoryCount = 0
        var importedCookieCount = 0
        var importedBookmarkCount = 0
        var skippedCount = 0

        if plan.importHistory, let historyStore {
            for visit in preview.history where plan.allows(urlString: visit.url) {
                try historyStore.recordVisit(url: visit.url, title: visit.title, profileID: plan.profileID)
                importedHistoryCount += 1
            }
        } else {
            skippedCount += preview.history.count
        }

        if plan.importCookies, let cookieStore {
            for cookie in preview.cookies where plan.allows(host: cookie.domain) {
                guard cookie.value != nil else {
                    skippedCount += 1
                    continue
                }
                try cookieStore.saveImportedCookie(cookie, profileID: plan.profileID)
                importedCookieCount += 1
            }
        } else {
            skippedCount += preview.cookies.count
        }

        if plan.importBookmarks, let bookmarkStore {
            for imported in preview.bookmarks where plan.allows(urlString: imported.url) {
                try bookmarkStore.save(BrowserBookmark.bookmark(title: imported.title, url: imported.url))
                importedBookmarkCount += 1
            }
        } else {
            skippedCount += preview.bookmarks.count
        }

        let result = BrowserImportResult(
            importedHistoryCount: importedHistoryCount,
            importedCookieCount: importedCookieCount,
            importedBookmarkCount: importedBookmarkCount,
            skippedCount: skippedCount,
            errors: preview.errors
        )

        try auditLogger?.record(BrowserImportAuditEntry(
            source: plan.source,
            profileID: plan.profileID,
            importedHistoryCount: importedHistoryCount,
            importedCookieCount: importedCookieCount,
            importedBookmarkCount: importedBookmarkCount,
            skippedCount: skippedCount,
            timestamp: Date()
        ))

        return result
    }
}

final class FileBrowserImportAuditLogger: BrowserImportAuditLogging, @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.cocxy.browser-import-audit")

    init(fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/Cocxy/browser-import-audit.jsonl")) {
        self.fileURL = fileURL
    }

    func record(_ entry: BrowserImportAuditEntry) throws {
        try queue.sync {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entry)
            let line = data + Data([0x0A])
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: fileURL, options: .atomic)
            }
        }
    }
}
