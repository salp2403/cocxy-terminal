// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserImportModels.swift - Browser import plans, results, and shared contracts.

import Foundation

enum BrowserImportSource: String, CaseIterable, Codable, Sendable, Equatable {
    case chrome
    case edge
    case brave
    case opera
    case vivaldi
    case arc
    case firefox
    case safari

    var displayName: String {
        switch self {
        case .chrome: return "Chrome"
        case .edge: return "Edge"
        case .brave: return "Brave"
        case .opera: return "Opera"
        case .vivaldi: return "Vivaldi"
        case .arc: return "Arc"
        case .firefox: return "Firefox"
        case .safari: return "Safari"
        }
    }

    var isChromiumBased: Bool {
        switch self {
        case .chrome, .edge, .brave, .opera, .vivaldi, .arc:
            return true
        case .firefox, .safari:
            return false
        }
    }

    func defaultLocations(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [BrowserImportLocation] {
        let support = homeDirectory.appendingPathComponent("Library/Application Support")
        switch self {
        case .chrome:
            return chromiumLocations(root: support.appendingPathComponent("Google/Chrome"), source: self)
        case .edge:
            return chromiumLocations(root: support.appendingPathComponent("Microsoft Edge"), source: self)
        case .brave:
            return chromiumLocations(root: support.appendingPathComponent("BraveSoftware/Brave-Browser"), source: self)
        case .opera:
            return [
                BrowserImportLocation(
                    source: self,
                    profileName: "Default",
                    historyPath: support.appendingPathComponent("com.operasoftware.Opera/History"),
                    cookiesPath: support.appendingPathComponent("com.operasoftware.Opera/Cookies"),
                    bookmarksPath: support.appendingPathComponent("com.operasoftware.Opera/Bookmarks")
                ),
            ]
        case .vivaldi:
            return chromiumLocations(root: support.appendingPathComponent("Vivaldi"), source: self)
        case .arc:
            return chromiumLocations(root: support.appendingPathComponent("Arc/User Data"), source: self)
        case .firefox:
            let profile = support.appendingPathComponent("Firefox/Profiles/default-release")
            return [
                BrowserImportLocation(
                    source: self,
                    profileName: "default-release",
                    historyPath: profile.appendingPathComponent("places.sqlite"),
                    cookiesPath: profile.appendingPathComponent("cookies.sqlite"),
                    bookmarksPath: nil
                ),
            ]
        case .safari:
            return [
                BrowserImportLocation(
                    source: self,
                    profileName: "Safari",
                    historyPath: homeDirectory.appendingPathComponent("Library/Safari/History.db"),
                    cookiesPath: homeDirectory.appendingPathComponent("Library/Cookies/Cookies.binarycookies"),
                    bookmarksPath: homeDirectory.appendingPathComponent("Library/Safari/Bookmarks.plist")
                ),
            ]
        }
    }

    private func chromiumLocations(root: URL, source: BrowserImportSource) -> [BrowserImportLocation] {
        ["Default", "Profile 1", "Profile 2"].map { profileName in
            let profile = root.appendingPathComponent(profileName)
            return BrowserImportLocation(
                source: source,
                profileName: profileName,
                historyPath: profile.appendingPathComponent("History"),
                cookiesPath: profile.appendingPathComponent("Cookies"),
                bookmarksPath: profile.appendingPathComponent("Bookmarks")
            )
        }
    }
}

struct BrowserImportLocation: Codable, Sendable, Equatable {
    let source: BrowserImportSource
    let profileName: String
    let historyPath: URL
    let cookiesPath: URL?
    let bookmarksPath: URL?
}

struct BrowserImportPlan: Codable, Sendable, Equatable {
    let source: BrowserImportSource
    let profileID: UUID
    let importCookies: Bool
    let importHistory: Bool
    let importBookmarks: Bool
    let maxHistoryDays: Int?
    let domainWhitelist: [String]
    let domainBlacklist: [String]
    let explicitLocations: [BrowserImportLocation]?

    init(
        source: BrowserImportSource,
        profileID: UUID,
        importCookies: Bool = true,
        importHistory: Bool = true,
        importBookmarks: Bool = true,
        maxHistoryDays: Int? = nil,
        domainWhitelist: [String] = [],
        domainBlacklist: [String] = [],
        explicitLocations: [BrowserImportLocation]? = nil
    ) {
        self.source = source
        self.profileID = profileID
        self.importCookies = importCookies
        self.importHistory = importHistory
        self.importBookmarks = importBookmarks
        self.maxHistoryDays = maxHistoryDays
        self.domainWhitelist = domainWhitelist.map(Self.normalizedDomain)
        self.domainBlacklist = domainBlacklist.map(Self.normalizedDomain)
        self.explicitLocations = explicitLocations
    }

    func locations(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [BrowserImportLocation] {
        explicitLocations ?? source.defaultLocations(homeDirectory: homeDirectory)
    }

    func allows(urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host else { return false }
        return allows(host: host)
    }

    func allows(host: String) -> Bool {
        let normalized = Self.normalizedDomain(host)
        guard !normalized.isEmpty else { return false }
        if domainBlacklist.contains(where: { Self.domain(normalized, matches: $0) }) {
            return false
        }
        guard !domainWhitelist.isEmpty else { return true }
        return domainWhitelist.contains(where: { Self.domain(normalized, matches: $0) })
    }

    func allows(visitDate: Date) -> Bool {
        guard let maxHistoryDays else { return true }
        let cutoff = Date().addingTimeInterval(-Double(max(maxHistoryDays, 0)) * 86_400)
        return visitDate >= cutoff
    }

    private static func normalizedDomain(_ domain: String) -> String {
        domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func domain(_ candidate: String, matches rule: String) -> Bool {
        candidate == rule || candidate.hasSuffix(".\(rule)")
    }
}

struct BrowserImportedHistoryVisit: Sendable, Equatable {
    let url: String
    let title: String?
    let visitedAt: Date
}

struct BrowserImportedCookie: Sendable, Equatable {
    let domain: String
    let name: String
    let path: String
    let value: String?
    let expiresAt: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool
}

struct BrowserImportedBookmark: Sendable, Equatable {
    let title: String
    let url: String
}

struct BrowserImportIssue: Sendable, Equatable {
    let source: BrowserImportSource
    let profileName: String
    let message: String
}

struct BrowserImportPreview: Sendable, Equatable {
    var history: [BrowserImportedHistoryVisit]
    var cookies: [BrowserImportedCookie]
    var bookmarks: [BrowserImportedBookmark]
    var errors: [BrowserImportIssue]

    static let empty = BrowserImportPreview(history: [], cookies: [], bookmarks: [], errors: [])
}

struct BrowserImportResult: Sendable, Equatable {
    let importedHistoryCount: Int
    let importedCookieCount: Int
    let importedBookmarkCount: Int
    let skippedCount: Int
    let errors: [BrowserImportIssue]
}

struct BrowserImportAuditEntry: Codable, Sendable, Equatable {
    let source: BrowserImportSource
    let profileID: UUID
    let importedHistoryCount: Int
    let importedCookieCount: Int
    let importedBookmarkCount: Int
    let skippedCount: Int
    let timestamp: Date
}

protocol BrowserSourceImporting: Sendable {
    func preview(plan: BrowserImportPlan) throws -> BrowserImportPreview
}

protocol BrowserImportedCookieStoring: Sendable {
    func saveImportedCookie(_ cookie: BrowserImportedCookie, profileID: UUID) throws
}

protocol BrowserImportAuditLogging: Sendable {
    func record(_ entry: BrowserImportAuditEntry) throws
}

enum BrowserImportError: Error, Sendable, Equatable {
    case databaseOpenFailed(String)
    case statementFailed(String)
}
