// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserImportPreviewToken.swift - Stable binding between reviewed and imported browser data.

import CryptoKit
import Foundation

enum BrowserImportPreviewToken {
    static func make(preview: BrowserImportPreview, plan: BrowserImportPlan) -> String {
        var hasher = SHA256()
        append("cocxy-browser-import-preview-v1", to: &hasher)
        append(plan.source.rawValue, to: &hasher)
        append(plan.profileID.uuidString, to: &hasher)
        append(plan.importHistory, to: &hasher)
        append(plan.importCookies, to: &hasher)
        append(plan.importBookmarks, to: &hasher)
        append(plan.maxHistoryDays.map { String($0) }, to: &hasher)
        append(plan.sourceProfile, to: &hasher)
        append(plan.domainWhitelist, to: &hasher)
        append(plan.domainBlacklist, to: &hasher)
        append(plan.locations().map { location in
            [
                location.source.rawValue,
                location.profileIdentifier,
                location.historyPath.standardizedFileURL.path,
                location.cookiesPath?.standardizedFileURL.path ?? "",
                location.bookmarksPath?.standardizedFileURL.path ?? "",
            ].joined(separator: "\u{1F}")
        }, to: &hasher)

        append(preview.history.count, to: &hasher)
        for visit in preview.history {
            append("history", to: &hasher)
            append(visit.url, to: &hasher)
            append(visit.title, to: &hasher)
            append(visit.visitedAt.timeIntervalSinceReferenceDate.bitPattern, to: &hasher)
        }

        append(preview.cookies.count, to: &hasher)
        for cookie in preview.cookies {
            append("cookie", to: &hasher)
            append(cookie.domain, to: &hasher)
            append(cookie.name, to: &hasher)
            append(cookie.path, to: &hasher)
            append(cookie.expiresAt?.timeIntervalSinceReferenceDate.bitPattern, to: &hasher)
            append(cookie.isSecure, to: &hasher)
            append(cookie.isHTTPOnly, to: &hasher)
            append(cookie.sameSite.rawValue, to: &hasher)
            append(cookie.isPartitioned, to: &hasher)
            append(
                cookie.sourceValueFingerprint
                    ?? cookie.value.map { fingerprint(Data($0.utf8)) }
                    ?? "unavailable",
                to: &hasher
            )
        }

        append(preview.bookmarks.count, to: &hasher)
        for bookmark in preview.bookmarks {
            append("bookmark", to: &hasher)
            append(bookmark.title, to: &hasher)
            append(bookmark.url, to: &hasher)
            append(bookmark.folderPath, to: &hasher)
            append(bookmark.createdAt?.timeIntervalSinceReferenceDate.bitPattern, to: &hasher)
            append(bookmark.sortOrder, to: &hasher)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isValid(_ token: String) -> Bool {
        token.utf8.count == 64 && token.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
    }

    private static func append(_ values: [String], to hasher: inout SHA256) {
        append(values.count, to: &hasher)
        for value in values { append(value, to: &hasher) }
    }

    private static func append(_ value: String?, to hasher: inout SHA256) {
        guard let value else {
            appendLength(UInt64.max, to: &hasher)
            return
        }
        let data = Data(value.utf8)
        appendLength(UInt64(data.count), to: &hasher)
        hasher.update(data: data)
    }

    private static func append(_ value: Bool, to hasher: inout SHA256) {
        append(value ? "1" : "0", to: &hasher)
    }

    private static func append(_ value: Int, to hasher: inout SHA256) {
        append(String(value), to: &hasher)
    }

    private static func append(_ value: UInt64, to hasher: inout SHA256) {
        append(String(value), to: &hasher)
    }

    private static func append(_ value: UInt64?, to hasher: inout SHA256) {
        append(value.map { String($0) }, to: &hasher)
    }

    private static func appendLength(_ value: UInt64, to hasher: inout SHA256) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes in
            hasher.update(data: Data(bytes))
        }
    }
}
