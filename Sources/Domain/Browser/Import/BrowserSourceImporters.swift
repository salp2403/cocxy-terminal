// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserSourceImporters.swift - Browser-specific history, cookie, and bookmark readers.

import Foundation

private enum BrowserSourceImportSupport {
    private enum HistoryTimestampFormat {
        case chromium
        case firefox
        case safari
    }

    static let maximumImportedHistoryVisitCount = 50_000
    static let maximumScannedHistoryRowCount = 200_000
    static let historySQLLimit = maximumScannedHistoryRowCount + 1

    static func singleLocation(for plan: BrowserImportPlan) throws -> BrowserImportLocation {
        let locations = plan.locations()
        guard locations.count == 1, let location = locations.first else {
            let requested = plan.sourceProfile ?? plan.source.displayName
            throw BrowserImportError.sourceProfileUnavailable(requested)
        }
        return location
    }

    static func issue(_ location: BrowserImportLocation, _ message: String) -> BrowserImportIssue {
        BrowserImportIssue(source: location.source, profileName: location.profileName, message: message)
    }

    static func appendMissingIssue(
        path: URL?,
        component: String,
        location: BrowserImportLocation,
        preview: inout BrowserImportPreview
    ) -> Bool {
        guard let path, FileManager.default.fileExists(atPath: path.path) else {
            preview.errors.append(issue(location, "\(component) source file is unavailable"))
            return true
        }
        return false
    }

    static func applyURLFilter<T>(
        _ values: [T],
        plan: BrowserImportPlan,
        url: (T) -> String,
        preview: inout BrowserImportPreview
    ) -> [T] {
        values.filter { value in
            let allowed = plan.allows(urlString: url(value))
            if !allowed { preview.skippedCount += 1 }
            return allowed
        }
    }

    static func chromiumHistoryRows(
        databaseURL: URL,
        query: String,
        location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) throws -> [BrowserImportedHistoryVisit] {
        try historyRows(
            databaseURL: databaseURL,
            query: query,
            timestampFormat: .chromium,
            location: location,
            plan: plan,
            preview: &preview
        )
    }

    static func firefoxHistoryRows(
        databaseURL: URL,
        query: String,
        location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) throws -> [BrowserImportedHistoryVisit] {
        try historyRows(
            databaseURL: databaseURL,
            query: query,
            timestampFormat: .firefox,
            location: location,
            plan: plan,
            preview: &preview
        )
    }

    static func safariHistoryRows(
        databaseURL: URL,
        query: String,
        location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) throws -> [BrowserImportedHistoryVisit] {
        try historyRows(
            databaseURL: databaseURL,
            query: query,
            timestampFormat: .safari,
            location: location,
            plan: plan,
            preview: &preview
        )
    }

    static func isMissingTable(_ error: Error, named table: String) -> Bool {
        guard let importError = error as? BrowserImportError,
              case .statementFailed(let message) = importError else { return false }
        return message.localizedCaseInsensitiveContains("no such table: \(table)")
    }

    static func rethrowCancellation(_ error: Error) throws {
        if error is CancellationError || (error as? BrowserImportError) == .cancelled {
            throw BrowserImportError.cancelled
        }
    }

    private static func historyRows(
        databaseURL: URL,
        query: String,
        timestampFormat: HistoryTimestampFormat,
        location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) throws -> [BrowserImportedHistoryVisit] {
        var scannedCount = 0
        var acceptedCount = 0
        var matchingOverflowCount = 0
        let rows: [BrowserImportedHistoryVisit] = try BrowserSQLiteImportReader.readRows(
            databaseURL: databaseURL,
            query: query
        ) { statement in
            scannedCount += 1
            guard scannedCount <= maximumScannedHistoryRowCount else { return nil }
            guard let url = BrowserSQLiteImportReader.text(statement, 0) else { return nil }

            let visitedAt: Date?
            switch timestampFormat {
            case .chromium:
                visitedAt = BrowserImportDateConverter.chromeDate(
                    microsecondsSince1601: BrowserSQLiteImportReader.int64(statement, 2)
                )
            case .firefox:
                visitedAt = BrowserImportDateConverter.firefoxDate(
                    microsecondsSince1970: BrowserSQLiteImportReader.int64(statement, 2)
                )
            case .safari:
                visitedAt = BrowserImportDateConverter.safariDate(
                    secondsSince2001: BrowserSQLiteImportReader.double(statement, 2)
                )
            }
            guard let visitedAt else { return nil }
            guard plan.allows(urlString: url), plan.allows(visitDate: visitedAt) else {
                preview.skippedCount += 1
                return nil
            }
            guard acceptedCount < maximumImportedHistoryVisitCount else {
                matchingOverflowCount += 1
                preview.skippedCount += 1
                return nil
            }
            acceptedCount += 1
            return BrowserImportedHistoryVisit(
                url: url,
                title: BrowserSQLiteImportReader.text(statement, 1, maximumByteCount: 2_048),
                visitedAt: visitedAt
            )
        }

        if matchingOverflowCount > 0 || scannedCount > maximumScannedHistoryRowCount {
            var details: [String] = []
            if matchingOverflowCount > 0 {
                details.append(
                    "skipped \(matchingOverflowCount) additional matching visits after the \(maximumImportedHistoryVisitCount)-visit import limit"
                )
            }
            if scannedCount > maximumScannedHistoryRowCount {
                details.append(
                    "stopped after scanning the \(maximumScannedHistoryRowCount) most recent source visits; older visits may remain"
                )
            }
            preview.errors.append(issue(
                location,
                "History safety limit reached: \(details.joined(separator: "; "))"
            ))
        }
        return rows
    }
}

struct ChromiumBrowserImporter: BrowserSourceImporting {
    let cookieDecryptor: any ChromiumCookieDecrypting

    init(cookieDecryptor: any ChromiumCookieDecrypting = ChromiumCookieDecryptor()) {
        self.cookieDecryptor = cookieDecryptor
    }

    func preview(plan: BrowserImportPlan) throws -> BrowserImportPreview {
        try Task.checkCancellation()
        let location = try BrowserSourceImportSupport.singleLocation(for: plan)
        var preview = BrowserImportPreview.empty
        if plan.importHistory {
            try appendHistory(from: location, plan: plan, preview: &preview)
        }
        try Task.checkCancellation()
        if plan.importCookies {
            try appendCookies(from: location, plan: plan, preview: &preview)
        }
        try Task.checkCancellation()
        if plan.importBookmarks {
            try appendBookmarks(from: location, plan: plan, preview: &preview)
        }
        return preview
    }

    private func appendHistory(
        from location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) throws {
        if BrowserSourceImportSupport.appendMissingIssue(
            path: location.historyPath,
            component: "History",
            location: location,
            preview: &preview
        ) { return }
        do {
            let rows = try BrowserSourceImportSupport.chromiumHistoryRows(
                databaseURL: location.historyPath,
                query: """
                    SELECT urls.url, urls.title, visits.visit_time
                    FROM visits
                    INNER JOIN urls ON urls.id = visits.url
                    WHERE urls.url IS NOT NULL AND visits.visit_time IS NOT NULL
                    ORDER BY visits.visit_time DESC, visits.id DESC
                    LIMIT \(BrowserSourceImportSupport.historySQLLimit)
                    """,
                location: location,
                plan: plan,
                preview: &preview
            )
            preview.history.append(contentsOf: rows)
        } catch {
            try BrowserSourceImportSupport.rethrowCancellation(error)
            if BrowserSourceImportSupport.isMissingTable(error, named: "visits") {
                do {
                    let rows = try BrowserSourceImportSupport.chromiumHistoryRows(
                        databaseURL: location.historyPath,
                        query: """
                            SELECT url, title, last_visit_time
                            FROM urls
                            WHERE url IS NOT NULL AND last_visit_time IS NOT NULL
                            ORDER BY last_visit_time DESC, id DESC
                            LIMIT \(BrowserSourceImportSupport.historySQLLimit)
                            """,
                        location: location,
                        plan: plan,
                        preview: &preview
                    )
                    preview.history.append(contentsOf: rows)
                    preview.errors.append(BrowserSourceImportSupport.issue(
                        location,
                        "Per-visit history is unavailable in this source; imported only the latest visit for each URL"
                    ))
                    return
                } catch {
                    try BrowserSourceImportSupport.rethrowCancellation(error)
                }
            }
            preview.errors.append(BrowserSourceImportSupport.issue(location, "History import failed: \(error)"))
        }
    }

    private func appendCookies(
        from location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) throws {
        guard let cookiesPath = location.cookiesPath else {
            preview.errors.append(BrowserSourceImportSupport.issue(location, "Cookie source file is unavailable"))
            return
        }
        if BrowserSourceImportSupport.appendMissingIssue(
            path: cookiesPath,
            component: "Cookie",
            location: location,
            preview: &preview
        ) { return }

        do {
            let databaseVersion = try BrowserSQLiteImportReader.chromiumCookieDatabaseVersion(
                databaseURL: cookiesPath
            )
            var decryptionFailureCount = 0
            var partitionedCookieCount = 0
            var lastDecryptionError: String?
            let rows: [BrowserImportedCookie] = try BrowserSQLiteImportReader.readRows(
                databaseURL: cookiesPath,
                table: "cookies",
                query: { columns in
                    let sameSite = columns.contains("samesite") ? "samesite" : "-1"
                    let partitionKey = columns.contains("top_frame_site_key")
                        ? "top_frame_site_key"
                        : "''"
                    let encryptedValue = columns.contains("encrypted_value")
                        ? "encrypted_value"
                        : "X''"
                    return """
                        SELECT host_key, name, path, value, expires_utc, is_secure, is_httponly,
                               \(encryptedValue), \(sameSite), \(partitionKey)
                        FROM cookies
                        WHERE host_key IS NOT NULL AND name IS NOT NULL
                        ORDER BY host_key, name, path
                        LIMIT 50000
                        """
                },
                decode: { statement in
                    guard let domain = BrowserSQLiteImportReader.text(statement, 0),
                          let name = BrowserSQLiteImportReader.text(statement, 1) else { return nil }
                    guard plan.allows(host: domain) else {
                        preview.skippedCount += 1
                        return nil
                    }
                    let partitionKey = BrowserSQLiteImportReader.text(statement, 9) ?? ""
                    guard partitionKey.isEmpty else {
                        partitionedCookieCount += 1
                        preview.skippedCount += 1
                        return nil
                    }

                    let encryptedValue = BrowserSQLiteImportReader.blob(statement, 7)
                    let plainValue = BrowserSQLiteImportReader.text(statement, 3) ?? ""
                    let sourceValueFingerprint: String
                    if let encryptedValue, !encryptedValue.isEmpty {
                        sourceValueFingerprint = BrowserImportPreviewToken.fingerprint(encryptedValue)
                    } else {
                        sourceValueFingerprint = BrowserImportPreviewToken.fingerprint(Data(plainValue.utf8))
                    }

                    let value: String?
                    if plan.readCookieValues {
                        if let encryptedValue, !encryptedValue.isEmpty {
                            do {
                                value = try cookieDecryptor.decrypt(
                                    encryptedValue,
                                    domain: domain,
                                    source: location.source,
                                    databaseVersion: databaseVersion
                                )
                            } catch {
                                decryptionFailureCount += 1
                                lastDecryptionError = (error as? LocalizedError)?.errorDescription
                                    ?? String(describing: error)
                                value = nil
                            }
                        } else {
                            value = plainValue
                        }
                    } else {
                        value = nil
                    }

                    return BrowserImportedCookie(
                        domain: domain,
                        name: name,
                        path: BrowserSQLiteImportReader.text(statement, 2) ?? "/",
                        value: value,
                        expiresAt: BrowserImportDateConverter.chromeDate(
                            microsecondsSince1601: BrowserSQLiteImportReader.int64(statement, 4)
                        ),
                        isSecure: BrowserSQLiteImportReader.bool(statement, 5),
                        isHTTPOnly: BrowserSQLiteImportReader.bool(statement, 6),
                        sameSite: chromiumSameSite(BrowserSQLiteImportReader.int64(statement, 8)),
                        sourceValueFingerprint: sourceValueFingerprint
                    )
                }
            )
            preview.cookies.append(contentsOf: rows)
            if partitionedCookieCount > 0 {
                preview.errors.append(BrowserSourceImportSupport.issue(
                    location,
                    "Skipped \(partitionedCookieCount) partitioned cookies because WebKit cannot preserve their partition key"
                ))
            }
            if decryptionFailureCount > 0 {
                let detail = lastDecryptionError.map { ": \($0)" } ?? ""
                preview.errors.append(BrowserSourceImportSupport.issue(
                    location,
                    "Skipped \(decryptionFailureCount) encrypted cookies\(detail)"
                ))
            }
        } catch {
            try BrowserSourceImportSupport.rethrowCancellation(error)
            preview.errors.append(BrowserSourceImportSupport.issue(location, "Cookie import failed: \(error)"))
        }
    }

    private func appendBookmarks(
        from location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) throws {
        guard let bookmarksPath = location.bookmarksPath else {
            preview.errors.append(BrowserSourceImportSupport.issue(location, "Bookmark source file is unavailable"))
            return
        }
        if BrowserSourceImportSupport.appendMissingIssue(
            path: bookmarksPath,
            component: "Bookmark",
            location: location,
            preview: &preview
        ) { return }
        do {
            let decoded = try BrowserBookmarkImportDecoder.chromiumBookmarks(from: bookmarksPath)
            preview.bookmarks.append(contentsOf: BrowserSourceImportSupport.applyURLFilter(
                decoded,
                plan: plan,
                url: \BrowserImportedBookmark.url,
                preview: &preview
            ))
        } catch {
            try BrowserSourceImportSupport.rethrowCancellation(error)
            preview.errors.append(BrowserSourceImportSupport.issue(location, "Bookmark import failed: \(error)"))
        }
    }

    private func chromiumSameSite(_ rawValue: Int64) -> BrowserImportedCookie.SameSite {
        switch rawValue {
        case 0: return .none
        case 1: return .lax
        case 2: return .strict
        default: return .unspecified
        }
    }
}

struct FirefoxBrowserImporter: BrowserSourceImporting {
    private struct BookmarkRow {
        let id: Int64
        let parentID: Int64
        let position: Int
        let type: Int64
        let title: String
        let url: String?
        let createdAt: Date?
    }

    func preview(plan: BrowserImportPlan) throws -> BrowserImportPreview {
        try Task.checkCancellation()
        let location = try BrowserSourceImportSupport.singleLocation(for: plan)
        var preview = BrowserImportPreview.empty
        if plan.importHistory {
            try appendHistory(from: location, plan: plan, preview: &preview)
        }
        try Task.checkCancellation()
        if plan.importCookies {
            try appendCookies(from: location, plan: plan, preview: &preview)
        }
        try Task.checkCancellation()
        if plan.importBookmarks {
            try appendBookmarks(from: location, plan: plan, preview: &preview)
        }
        return preview
    }

    private func appendHistory(
        from location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) throws {
        if BrowserSourceImportSupport.appendMissingIssue(
            path: location.historyPath,
            component: "History",
            location: location,
            preview: &preview
        ) { return }
        do {
            let rows = try BrowserSourceImportSupport.firefoxHistoryRows(
                databaseURL: location.historyPath,
                query: """
                    SELECT moz_places.url, moz_places.title, moz_historyvisits.visit_date
                    FROM moz_historyvisits
                    INNER JOIN moz_places ON moz_places.id = moz_historyvisits.place_id
                    WHERE moz_places.url IS NOT NULL AND moz_historyvisits.visit_date IS NOT NULL
                    ORDER BY moz_historyvisits.visit_date DESC, moz_historyvisits.id DESC
                    LIMIT \(BrowserSourceImportSupport.historySQLLimit)
                    """,
                location: location,
                plan: plan,
                preview: &preview
            )
            preview.history.append(contentsOf: rows)
        } catch {
            try BrowserSourceImportSupport.rethrowCancellation(error)
            if BrowserSourceImportSupport.isMissingTable(error, named: "moz_historyvisits") {
                do {
                    let rows = try BrowserSourceImportSupport.firefoxHistoryRows(
                        databaseURL: location.historyPath,
                        query: """
                            SELECT url, title, last_visit_date
                            FROM moz_places
                            WHERE url IS NOT NULL AND last_visit_date IS NOT NULL
                            ORDER BY last_visit_date DESC, id DESC
                            LIMIT \(BrowserSourceImportSupport.historySQLLimit)
                            """,
                        location: location,
                        plan: plan,
                        preview: &preview
                    )
                    preview.history.append(contentsOf: rows)
                    preview.errors.append(BrowserSourceImportSupport.issue(
                        location,
                        "Per-visit history is unavailable in this source; imported only the latest visit for each URL"
                    ))
                    return
                } catch {
                    try BrowserSourceImportSupport.rethrowCancellation(error)
                }
            }
            preview.errors.append(BrowserSourceImportSupport.issue(location, "History import failed: \(error)"))
        }
    }

    private func appendCookies(
        from location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) throws {
        guard let cookiesPath = location.cookiesPath else {
            preview.errors.append(BrowserSourceImportSupport.issue(location, "Cookie source file is unavailable"))
            return
        }
        if BrowserSourceImportSupport.appendMissingIssue(
            path: cookiesPath,
            component: "Cookie",
            location: location,
            preview: &preview
        ) { return }
        do {
            var isolatedCookieCount = 0
            let rows: [BrowserImportedCookie] = try BrowserSQLiteImportReader.readRows(
                databaseURL: cookiesPath,
                table: "moz_cookies",
                query: { columns in
                    let sameSite = columns.contains("sameSite") ? "sameSite" : "256"
                    let originAttributes = columns.contains("originAttributes") ? "originAttributes" : "''"
                    let partitioned = columns.contains("isPartitionedAttributeSet")
                        ? "isPartitionedAttributeSet"
                        : "0"
                    return """
                        SELECT host, name, path, value, expiry, isSecure, isHttpOnly,
                               \(sameSite), \(originAttributes), \(partitioned)
                        FROM moz_cookies
                        WHERE host IS NOT NULL AND name IS NOT NULL
                        ORDER BY host, name, path
                        LIMIT 50000
                        """
                },
                decode: { statement in
                    guard let domain = BrowserSQLiteImportReader.text(statement, 0),
                          let name = BrowserSQLiteImportReader.text(statement, 1) else { return nil }
                    guard plan.allows(host: domain) else {
                        preview.skippedCount += 1
                        return nil
                    }
                    let originAttributes = BrowserSQLiteImportReader.text(statement, 8) ?? ""
                    let isPartitioned = BrowserSQLiteImportReader.bool(statement, 9)
                    guard originAttributes.isEmpty, !isPartitioned else {
                        isolatedCookieCount += 1
                        preview.skippedCount += 1
                        return nil
                    }
                    let rawValue = BrowserSQLiteImportReader.text(statement, 3) ?? ""
                    return BrowserImportedCookie(
                        domain: domain,
                        name: name,
                        path: BrowserSQLiteImportReader.text(statement, 2) ?? "/",
                        value: plan.readCookieValues ? rawValue : nil,
                        expiresAt: BrowserImportDateConverter.unixDate(
                            secondsSince1970: BrowserSQLiteImportReader.int64(statement, 4)
                        ),
                        isSecure: BrowserSQLiteImportReader.bool(statement, 5),
                        isHTTPOnly: BrowserSQLiteImportReader.bool(statement, 6),
                        sameSite: firefoxSameSite(BrowserSQLiteImportReader.int64(statement, 7)),
                        sourceValueFingerprint: BrowserImportPreviewToken.fingerprint(Data(rawValue.utf8))
                    )
                }
            )
            preview.cookies.append(contentsOf: rows)
            if isolatedCookieCount > 0 {
                preview.errors.append(BrowserSourceImportSupport.issue(
                    location,
                    "Skipped \(isolatedCookieCount) container or partitioned cookies because their isolation context cannot be preserved"
                ))
            }
        } catch {
            try BrowserSourceImportSupport.rethrowCancellation(error)
            preview.errors.append(BrowserSourceImportSupport.issue(location, "Cookie import failed: \(error)"))
        }
    }

    private func appendBookmarks(
        from location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) throws {
        guard let bookmarksPath = location.bookmarksPath else {
            preview.errors.append(BrowserSourceImportSupport.issue(location, "Bookmark source file is unavailable"))
            return
        }
        if BrowserSourceImportSupport.appendMissingIssue(
            path: bookmarksPath,
            component: "Bookmark",
            location: location,
            preview: &preview
        ) { return }
        do {
            let rows: [BookmarkRow] = try BrowserSQLiteImportReader.readRows(
                databaseURL: bookmarksPath,
                table: "moz_bookmarks",
                query: { columns in
                    let createdAt = columns.contains("dateAdded") ? "b.dateAdded" : "0"
                    return """
                        SELECT b.id, b.parent, b.position, b.type, b.title, p.url, \(createdAt)
                        FROM moz_bookmarks b
                        LEFT JOIN moz_places p ON p.id = b.fk
                        WHERE b.type IN (1, 2)
                        ORDER BY b.parent, b.position
                        LIMIT 100000
                        """
                },
                decode: { statement in
                    BookmarkRow(
                        id: BrowserSQLiteImportReader.int64(statement, 0),
                        parentID: BrowserSQLiteImportReader.int64(statement, 1),
                        position: Int(BrowserSQLiteImportReader.int64(statement, 2)),
                        type: BrowserSQLiteImportReader.int64(statement, 3),
                        title: BrowserSQLiteImportReader.text(statement, 4) ?? "",
                        url: BrowserSQLiteImportReader.text(statement, 5),
                        createdAt: BrowserImportDateConverter.firefoxDate(
                            microsecondsSince1970: BrowserSQLiteImportReader.int64(statement, 6)
                        )
                    )
                }
            )
            var folders: [Int64: BookmarkRow] = [:]
            for row in rows where row.type == 2 {
                guard folders.updateValue(row, forKey: row.id) == nil else {
                    throw BrowserImportError.invalidSourceFile(location.historyPath.path)
                }
            }
            for row in rows where row.type == 1 {
                guard let url = row.url, plan.allows(urlString: url) else {
                    preview.skippedCount += 1
                    continue
                }
                preview.bookmarks.append(BrowserImportedBookmark(
                    title: row.title.isEmpty ? url : row.title,
                    url: url,
                    folderPath: firefoxFolderPath(parentID: row.parentID, folders: folders),
                    createdAt: row.createdAt,
                    sortOrder: row.position
                ))
            }
        } catch {
            try BrowserSourceImportSupport.rethrowCancellation(error)
            preview.errors.append(BrowserSourceImportSupport.issue(location, "Bookmark import failed: \(error)"))
        }
    }

    private func firefoxFolderPath(parentID: Int64, folders: [Int64: BookmarkRow]) -> [String] {
        var path: [String] = []
        var currentID = parentID
        var visited = Set<Int64>()
        while let folder = folders[currentID], visited.insert(currentID).inserted, path.count < 64 {
            let title = folder.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { path.append(String(title.prefix(2_048))) }
            currentID = folder.parentID
        }
        return path.reversed()
    }

    private func firefoxSameSite(_ rawValue: Int64) -> BrowserImportedCookie.SameSite {
        switch rawValue {
        case 0: return .none
        case 1: return .lax
        case 2: return .strict
        default: return .unspecified
        }
    }
}

struct SafariBrowserImporter: BrowserSourceImporting {
    func preview(plan: BrowserImportPlan) throws -> BrowserImportPreview {
        try Task.checkCancellation()
        let location = try BrowserSourceImportSupport.singleLocation(for: plan)
        var preview = BrowserImportPreview.empty
        if plan.importHistory {
            try appendHistory(from: location, plan: plan, preview: &preview)
        }
        try Task.checkCancellation()
        if plan.importCookies {
            try appendCookies(from: location, plan: plan, preview: &preview)
        }
        try Task.checkCancellation()
        if plan.importBookmarks {
            try appendBookmarks(from: location, plan: plan, preview: &preview)
        }
        return preview
    }

    private func appendHistory(
        from location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) throws {
        if BrowserSourceImportSupport.appendMissingIssue(
            path: location.historyPath,
            component: "History",
            location: location,
            preview: &preview
        ) { return }
        do {
            let rows = try safariHistory(location: location, plan: plan, preview: &preview)
            preview.history.append(contentsOf: rows)
        } catch {
            try BrowserSourceImportSupport.rethrowCancellation(error)
            if location.source == .orion {
                do {
                    let fallback = try chromiumStyleHistory(
                        location: location,
                        plan: plan,
                        preview: &preview
                    )
                    preview.history.append(contentsOf: fallback)
                    return
                } catch {
                    try BrowserSourceImportSupport.rethrowCancellation(error)
                }
            }
            preview.errors.append(BrowserSourceImportSupport.issue(location, "History import failed: \(error)"))
        }
    }

    private func safariHistory(
        location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) throws -> [BrowserImportedHistoryVisit] {
        try BrowserSourceImportSupport.safariHistoryRows(
            databaseURL: location.historyPath,
            query: """
                SELECT history_items.url, history_items.title, history_visits.visit_time
                FROM history_visits
                INNER JOIN history_items ON history_items.id = history_visits.history_item
                WHERE history_items.url IS NOT NULL
                ORDER BY history_visits.visit_time DESC, history_visits.id DESC
                LIMIT \(BrowserSourceImportSupport.historySQLLimit)
                """,
            location: location,
            plan: plan,
            preview: &preview
        )
    }

    private func chromiumStyleHistory(
        location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) throws -> [BrowserImportedHistoryVisit] {
        do {
            return try BrowserSourceImportSupport.chromiumHistoryRows(
                databaseURL: location.historyPath,
                query: """
                    SELECT urls.url, urls.title, visits.visit_time
                    FROM visits
                    INNER JOIN urls ON urls.id = visits.url
                    WHERE urls.url IS NOT NULL AND visits.visit_time IS NOT NULL
                    ORDER BY visits.visit_time DESC, visits.id DESC
                    LIMIT \(BrowserSourceImportSupport.historySQLLimit)
                    """,
                location: location,
                plan: plan,
                preview: &preview
            )
        } catch {
            try BrowserSourceImportSupport.rethrowCancellation(error)
            guard BrowserSourceImportSupport.isMissingTable(error, named: "visits") else {
                throw error
            }
            let rows = try BrowserSourceImportSupport.chromiumHistoryRows(
                databaseURL: location.historyPath,
                query: """
                    SELECT url, title, last_visit_time
                    FROM urls
                    WHERE url IS NOT NULL AND last_visit_time IS NOT NULL
                    ORDER BY last_visit_time DESC, id DESC
                    LIMIT \(BrowserSourceImportSupport.historySQLLimit)
                    """,
                location: location,
                plan: plan,
                preview: &preview
            )
            preview.errors.append(BrowserSourceImportSupport.issue(
                location,
                "Per-visit history is unavailable in this source; imported only the latest visit for each URL"
            ))
            return rows
        }
    }

    private func appendCookies(
        from location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) throws {
        guard let cookiesPath = location.cookiesPath else {
            preview.errors.append(BrowserSourceImportSupport.issue(location, "Cookie source file is unavailable"))
            return
        }
        if BrowserSourceImportSupport.appendMissingIssue(
            path: cookiesPath,
            component: "Cookie",
            location: location,
            preview: &preview
        ) { return }
        do {
            let rows: [BrowserImportedCookie]
            if cookiesPath.lastPathComponent.lowercased().contains("binarycookies") {
                rows = try SafariBinaryCookieDecoder.cookies(
                    from: cookiesPath,
                    includeValues: plan.readCookieValues
                )
            } else {
                rows = try orionSQLiteCookies(
                    from: cookiesPath,
                    plan: plan,
                    preview: &preview
                )
            }
            for cookie in rows {
                if plan.allows(host: cookie.domain) {
                    preview.cookies.append(cookie)
                } else {
                    preview.skippedCount += 1
                }
            }
        } catch {
            try BrowserSourceImportSupport.rethrowCancellation(error)
            preview.errors.append(BrowserSourceImportSupport.issue(location, "Cookie import failed: \(error)"))
        }
    }

    private func orionSQLiteCookies(
        from path: URL,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) throws -> [BrowserImportedCookie] {
        var encryptedCookieCount = 0
        let rows: [BrowserImportedCookie] = try BrowserSQLiteImportReader.readRows(
            databaseURL: path,
            table: "cookies",
            query: { columns in
                let encrypted = columns.contains("encrypted_value") ? "encrypted_value" : "X''"
                return """
                    SELECT host_key, name, path, value, expires_utc, is_secure, is_httponly, \(encrypted)
                    FROM cookies
                    ORDER BY host_key, name, path
                    LIMIT 50000
                    """
            },
            decode: { statement in
                guard let domain = BrowserSQLiteImportReader.text(statement, 0),
                      let name = BrowserSQLiteImportReader.text(statement, 1) else { return nil }
                let encryptedValue = BrowserSQLiteImportReader.blob(statement, 7)
                let rawValue = BrowserSQLiteImportReader.text(statement, 3) ?? ""
                if encryptedValue != nil, rawValue.isEmpty {
                    encryptedCookieCount += 1
                    preview.skippedCount += 1
                    return nil
                }
                return BrowserImportedCookie(
                    domain: domain,
                    name: name,
                    path: BrowserSQLiteImportReader.text(statement, 2) ?? "/",
                    value: plan.readCookieValues ? rawValue : nil,
                    expiresAt: BrowserImportDateConverter.chromeDate(
                        microsecondsSince1601: BrowserSQLiteImportReader.int64(statement, 4)
                    ),
                    isSecure: BrowserSQLiteImportReader.bool(statement, 5),
                    isHTTPOnly: BrowserSQLiteImportReader.bool(statement, 6),
                    sourceValueFingerprint: BrowserImportPreviewToken.fingerprint(Data(rawValue.utf8))
                )
            }
        )
        if encryptedCookieCount > 0 {
            preview.errors.append(BrowserImportIssue(
                source: .orion,
                profileName: "Orion",
                message: "Skipped \(encryptedCookieCount) encrypted Orion cookies because their key format is unavailable"
            ))
        }
        return rows
    }

    private func appendBookmarks(
        from location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) throws {
        guard let bookmarksPath = location.bookmarksPath else {
            preview.errors.append(BrowserSourceImportSupport.issue(location, "Bookmark source file is unavailable"))
            return
        }
        if BrowserSourceImportSupport.appendMissingIssue(
            path: bookmarksPath,
            component: "Bookmark",
            location: location,
            preview: &preview
        ) { return }
        do {
            let decoded: [BrowserImportedBookmark]
            do {
                decoded = try BrowserBookmarkImportDecoder.safariBookmarks(from: bookmarksPath)
            } catch {
                guard location.source == .orion else { throw error }
                decoded = try BrowserBookmarkImportDecoder.chromiumBookmarks(from: bookmarksPath)
            }
            preview.bookmarks.append(contentsOf: BrowserSourceImportSupport.applyURLFilter(
                decoded,
                plan: plan,
                url: \BrowserImportedBookmark.url,
                preview: &preview
            ))
        } catch {
            try BrowserSourceImportSupport.rethrowCancellation(error)
            preview.errors.append(BrowserSourceImportSupport.issue(location, "Bookmark import failed: \(error)"))
        }
    }
}

enum BrowserSourceImporterFactory {
    static func importer(for source: BrowserImportSource) -> any BrowserSourceImporting {
        if source.isChromiumBased {
            return ChromiumBrowserImporter()
        }
        switch source {
        case .firefox, .firefoxDeveloperEdition, .firefoxNightly,
             .librewolf, .waterfox, .floorp, .zen:
            return FirefoxBrowserImporter()
        case .safari, .orion:
            return SafariBrowserImporter()
        case .chrome, .chromeCanary, .chromium,
             .edge, .edgeBeta, .edgeDev,
             .brave, .braveBeta, .braveNightly,
             .opera, .operaGX,
             .vivaldi, .vivaldiSnapshot,
             .arc, .arcBeta:
            return ChromiumBrowserImporter()
        }
    }
}
