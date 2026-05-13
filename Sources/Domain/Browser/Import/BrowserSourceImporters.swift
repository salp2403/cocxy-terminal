// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserSourceImporters.swift - Browser-specific history and cookie readers.

import Foundation

struct ChromiumBrowserImporter: BrowserSourceImporting {
    func preview(plan: BrowserImportPlan) throws -> BrowserImportPreview {
        var preview = BrowserImportPreview.empty

        for location in plan.locations() {
            if plan.importHistory {
                appendHistory(from: location, plan: plan, preview: &preview)
            }
            if plan.importCookies {
                appendCookies(from: location, plan: plan, preview: &preview)
            }
        }

        return preview
    }

    private func appendHistory(
        from location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) {
        guard FileManager.default.fileExists(atPath: location.historyPath.path) else { return }
        do {
            let rows: [BrowserImportedHistoryVisit] = try BrowserSQLiteImportReader.readRows(
                databaseURL: location.historyPath,
                query: """
                    SELECT url, title, last_visit_time
                    FROM urls
                    WHERE url IS NOT NULL AND last_visit_time IS NOT NULL
                    ORDER BY last_visit_time DESC
                    LIMIT 50000
                    """
            ) { statement in
                guard let url = BrowserSQLiteImportReader.text(statement, 0),
                      let visitedAt = BrowserImportDateConverter.chromeDate(
                        microsecondsSince1601: BrowserSQLiteImportReader.int64(statement, 2)
                      ),
                      plan.allows(urlString: url),
                      plan.allows(visitDate: visitedAt) else { return nil }
                return BrowserImportedHistoryVisit(
                    url: url,
                    title: BrowserSQLiteImportReader.text(statement, 1),
                    visitedAt: visitedAt
                )
            }
            preview.history.append(contentsOf: rows)
        } catch {
            preview.errors.append(issue(location, "History import failed: \(error)"))
        }
    }

    private func appendCookies(
        from location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) {
        guard let cookiesPath = location.cookiesPath,
              FileManager.default.fileExists(atPath: cookiesPath.path) else { return }
        do {
            let rows: [BrowserImportedCookie] = try BrowserSQLiteImportReader.readRows(
                databaseURL: cookiesPath,
                query: """
                    SELECT host_key, name, path, value, expires_utc, is_secure, is_httponly, length(encrypted_value)
                    FROM cookies
                    WHERE host_key IS NOT NULL AND name IS NOT NULL
                    LIMIT 50000
                    """
            ) { statement in
                guard let domain = BrowserSQLiteImportReader.text(statement, 0),
                      let name = BrowserSQLiteImportReader.text(statement, 1),
                      plan.allows(host: domain) else { return nil }
                let value = BrowserSQLiteImportReader.text(statement, 3)
                let encryptedLength = BrowserSQLiteImportReader.int64(statement, 7)
                let effectiveValue = value?.isEmpty == false ? value : nil
                if effectiveValue == nil && encryptedLength > 0 {
                    return nil
                }
                return BrowserImportedCookie(
                    domain: domain,
                    name: name,
                    path: BrowserSQLiteImportReader.text(statement, 2) ?? "/",
                    value: effectiveValue,
                    expiresAt: BrowserImportDateConverter.chromeDate(
                        microsecondsSince1601: BrowserSQLiteImportReader.int64(statement, 4)
                    ),
                    isSecure: BrowserSQLiteImportReader.bool(statement, 5),
                    isHTTPOnly: BrowserSQLiteImportReader.bool(statement, 6)
                )
            }
            preview.cookies.append(contentsOf: rows)
        } catch {
            preview.errors.append(issue(location, "Cookie import failed: \(error)"))
        }
    }

    private func issue(_ location: BrowserImportLocation, _ message: String) -> BrowserImportIssue {
        BrowserImportIssue(source: location.source, profileName: location.profileName, message: message)
    }
}

struct FirefoxBrowserImporter: BrowserSourceImporting {
    func preview(plan: BrowserImportPlan) throws -> BrowserImportPreview {
        var preview = BrowserImportPreview.empty

        for location in plan.locations() {
            if plan.importHistory {
                appendHistory(from: location, plan: plan, preview: &preview)
            }
            if plan.importCookies {
                appendCookies(from: location, plan: plan, preview: &preview)
            }
        }

        return preview
    }

    private func appendHistory(
        from location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) {
        guard FileManager.default.fileExists(atPath: location.historyPath.path) else { return }
        do {
            let rows: [BrowserImportedHistoryVisit] = try BrowserSQLiteImportReader.readRows(
                databaseURL: location.historyPath,
                query: """
                    SELECT url, title, last_visit_date
                    FROM moz_places
                    WHERE url IS NOT NULL AND last_visit_date IS NOT NULL
                    ORDER BY last_visit_date DESC
                    LIMIT 50000
                    """
            ) { statement in
                guard let url = BrowserSQLiteImportReader.text(statement, 0),
                      let visitedAt = BrowserImportDateConverter.firefoxDate(
                        microsecondsSince1970: BrowserSQLiteImportReader.int64(statement, 2)
                      ),
                      plan.allows(urlString: url),
                      plan.allows(visitDate: visitedAt) else { return nil }
                return BrowserImportedHistoryVisit(
                    url: url,
                    title: BrowserSQLiteImportReader.text(statement, 1),
                    visitedAt: visitedAt
                )
            }
            preview.history.append(contentsOf: rows)
        } catch {
            preview.errors.append(issue(location, "History import failed: \(error)"))
        }
    }

    private func appendCookies(
        from location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) {
        guard let cookiesPath = location.cookiesPath,
              FileManager.default.fileExists(atPath: cookiesPath.path) else { return }
        do {
            let rows: [BrowserImportedCookie] = try BrowserSQLiteImportReader.readRows(
                databaseURL: cookiesPath,
                query: """
                    SELECT host, name, path, value, expiry, isSecure, isHttpOnly
                    FROM moz_cookies
                    WHERE host IS NOT NULL AND name IS NOT NULL
                    LIMIT 50000
                    """
            ) { statement in
                guard let domain = BrowserSQLiteImportReader.text(statement, 0),
                      let name = BrowserSQLiteImportReader.text(statement, 1),
                      plan.allows(host: domain) else { return nil }
                return BrowserImportedCookie(
                    domain: domain,
                    name: name,
                    path: BrowserSQLiteImportReader.text(statement, 2) ?? "/",
                    value: BrowserSQLiteImportReader.text(statement, 3),
                    expiresAt: BrowserImportDateConverter.unixDate(
                        secondsSince1970: BrowserSQLiteImportReader.int64(statement, 4)
                    ),
                    isSecure: BrowserSQLiteImportReader.bool(statement, 5),
                    isHTTPOnly: BrowserSQLiteImportReader.bool(statement, 6)
                )
            }
            preview.cookies.append(contentsOf: rows)
        } catch {
            preview.errors.append(issue(location, "Cookie import failed: \(error)"))
        }
    }

    private func issue(_ location: BrowserImportLocation, _ message: String) -> BrowserImportIssue {
        BrowserImportIssue(source: location.source, profileName: location.profileName, message: message)
    }
}

struct SafariBrowserImporter: BrowserSourceImporting {
    func preview(plan: BrowserImportPlan) throws -> BrowserImportPreview {
        var preview = BrowserImportPreview.empty

        for location in plan.locations() {
            if plan.importHistory {
                appendHistory(from: location, plan: plan, preview: &preview)
            }
            if plan.importCookies,
               let cookiesPath = location.cookiesPath,
               FileManager.default.fileExists(atPath: cookiesPath.path) {
                preview.errors.append(BrowserImportIssue(
                    source: location.source,
                    profileName: location.profileName,
                    message: "Cookies.binarycookies import requires a binary cookie decoder and was skipped"
                ))
            }
        }

        return preview
    }

    private func appendHistory(
        from location: BrowserImportLocation,
        plan: BrowserImportPlan,
        preview: inout BrowserImportPreview
    ) {
        guard FileManager.default.fileExists(atPath: location.historyPath.path) else { return }
        do {
            let rows: [BrowserImportedHistoryVisit] = try BrowserSQLiteImportReader.readRows(
                databaseURL: location.historyPath,
                query: """
                    SELECT history_items.url, history_items.title, history_visits.visit_time
                    FROM history_visits
                    INNER JOIN history_items ON history_items.id = history_visits.history_item
                    WHERE history_items.url IS NOT NULL
                    ORDER BY history_visits.visit_time DESC
                    LIMIT 50000
                    """
            ) { statement in
                guard let url = BrowserSQLiteImportReader.text(statement, 0),
                      let visitedAt = BrowserImportDateConverter.safariDate(
                        secondsSince2001: BrowserSQLiteImportReader.double(statement, 2)
                      ),
                      plan.allows(urlString: url),
                      plan.allows(visitDate: visitedAt) else { return nil }
                return BrowserImportedHistoryVisit(
                    url: url,
                    title: BrowserSQLiteImportReader.text(statement, 1),
                    visitedAt: visitedAt
                )
            }
            preview.history.append(contentsOf: rows)
        } catch {
            preview.errors.append(BrowserImportIssue(
                source: location.source,
                profileName: location.profileName,
                message: "History import failed: \(error)"
            ))
        }
    }
}

enum BrowserSourceImporterFactory {
    static func importer(for source: BrowserImportSource) -> any BrowserSourceImporting {
        if source.isChromiumBased {
            return ChromiumBrowserImporter()
        }
        switch source {
        case .firefox:
            return FirefoxBrowserImporter()
        case .safari:
            return SafariBrowserImporter()
        case .chrome, .edge, .brave, .opera, .vivaldi, .arc:
            return ChromiumBrowserImporter()
        }
    }
}
