// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserImportModels.swift - Browser import plans, results, and shared contracts.

import Foundation

enum BrowserImportSource: String, CaseIterable, Codable, Sendable, Equatable {
    case chrome
    case chromeCanary = "chrome-canary"
    case chromium
    case edge
    case edgeBeta = "edge-beta"
    case edgeDev = "edge-dev"
    case brave
    case braveBeta = "brave-beta"
    case braveNightly = "brave-nightly"
    case opera
    case operaGX = "opera-gx"
    case vivaldi
    case vivaldiSnapshot = "vivaldi-snapshot"
    case arc
    case arcBeta = "arc-beta"
    case firefox
    case firefoxDeveloperEdition = "firefox-developer-edition"
    case firefoxNightly = "firefox-nightly"
    case librewolf
    case waterfox
    case floorp
    case zen
    case safari
    case orion

    var displayName: String {
        switch self {
        case .chrome: return "Chrome"
        case .chromeCanary: return "Chrome Canary"
        case .chromium: return "Chromium"
        case .edge: return "Edge"
        case .edgeBeta: return "Edge Beta"
        case .edgeDev: return "Edge Dev"
        case .brave: return "Brave"
        case .braveBeta: return "Brave Beta"
        case .braveNightly: return "Brave Nightly"
        case .opera: return "Opera"
        case .operaGX: return "Opera GX"
        case .vivaldi: return "Vivaldi"
        case .vivaldiSnapshot: return "Vivaldi Snapshot"
        case .arc: return "Arc"
        case .arcBeta: return "Arc Beta"
        case .firefox: return "Firefox"
        case .firefoxDeveloperEdition: return "Firefox Developer Edition"
        case .firefoxNightly: return "Firefox Nightly"
        case .librewolf: return "LibreWolf"
        case .waterfox: return "Waterfox"
        case .floorp: return "Floorp"
        case .zen: return "Zen"
        case .safari: return "Safari"
        case .orion: return "Orion"
        }
    }

    var isChromiumBased: Bool {
        switch self {
        case .chrome, .chromeCanary, .chromium,
             .edge, .edgeBeta, .edgeDev,
             .brave, .braveBeta, .braveNightly,
             .opera, .operaGX,
             .vivaldi, .vivaldiSnapshot,
             .arc, .arcBeta:
            return true
        case .firefox, .firefoxDeveloperEdition, .firefoxNightly,
             .librewolf, .waterfox, .floorp, .zen,
             .safari, .orion:
            return false
        }
    }

    func defaultLocations(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [BrowserImportLocation] {
        let support = homeDirectory.appendingPathComponent("Library/Application Support")
        switch self {
        case .chrome:
            return chromiumLocations(root: support.appendingPathComponent("Google/Chrome"), source: self)
        case .chromeCanary:
            return chromiumLocations(root: support.appendingPathComponent("Google/Chrome Canary"), source: self)
        case .chromium:
            return chromiumLocations(root: support.appendingPathComponent("Chromium"), source: self)
        case .edge:
            return chromiumLocations(root: support.appendingPathComponent("Microsoft Edge"), source: self)
        case .edgeBeta:
            return chromiumLocations(root: support.appendingPathComponent("Microsoft Edge Beta"), source: self)
        case .edgeDev:
            return chromiumLocations(root: support.appendingPathComponent("Microsoft Edge Dev"), source: self)
        case .brave:
            return chromiumLocations(root: support.appendingPathComponent("BraveSoftware/Brave-Browser"), source: self)
        case .braveBeta:
            return chromiumLocations(root: support.appendingPathComponent("BraveSoftware/Brave-Browser-Beta"), source: self)
        case .braveNightly:
            return chromiumLocations(root: support.appendingPathComponent("BraveSoftware/Brave-Browser-Nightly"), source: self)
        case .opera:
            return operaLocations(root: support.appendingPathComponent("com.operasoftware.Opera"), source: self)
        case .operaGX:
            return operaLocations(root: support.appendingPathComponent("com.operasoftware.OperaGX"), source: self)
        case .vivaldi:
            return chromiumLocations(root: support.appendingPathComponent("Vivaldi"), source: self)
        case .vivaldiSnapshot:
            return chromiumLocations(root: support.appendingPathComponent("Vivaldi Snapshot"), source: self)
        case .arc:
            return chromiumLocations(root: support.appendingPathComponent("Arc/User Data"), source: self)
        case .arcBeta:
            return chromiumLocations(root: support.appendingPathComponent("Arc Beta/User Data"), source: self)
        case .firefox:
            return firefoxLocations(root: support.appendingPathComponent("Firefox/Profiles"), profileName: "default-release", source: self)
        case .firefoxDeveloperEdition:
            return firefoxLocations(root: support.appendingPathComponent("Firefox/Profiles"), profileName: "dev-edition-default", source: self)
        case .firefoxNightly:
            return firefoxLocations(root: support.appendingPathComponent("Firefox/Profiles"), profileName: "nightly", source: self)
        case .librewolf:
            return firefoxLocations(root: support.appendingPathComponent("LibreWolf/Profiles"), profileName: "default-release", source: self)
        case .waterfox:
            return firefoxLocations(root: support.appendingPathComponent("Waterfox/Profiles"), profileName: "default-release", source: self)
        case .floorp:
            return firefoxLocations(root: support.appendingPathComponent("Floorp/Profiles"), profileName: "default-release", source: self)
        case .zen:
            return firefoxLocations(root: support.appendingPathComponent("Zen/Profiles"), profileName: "default-release", source: self)
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
        case .orion:
            return [
                BrowserImportLocation(
                    source: self,
                    profileName: "Default",
                    historyPath: support.appendingPathComponent("Orion/History.db"),
                    cookiesPath: homeDirectory.appendingPathComponent("Library/Cookies/Cookies.binarycookies"),
                    bookmarksPath: support.appendingPathComponent("Orion/Bookmarks.plist")
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

    private func operaLocations(root: URL, source: BrowserImportSource) -> [BrowserImportLocation] {
        [
            BrowserImportLocation(
                source: source,
                profileName: "Default",
                historyPath: root.appendingPathComponent("History"),
                cookiesPath: root.appendingPathComponent("Cookies"),
                bookmarksPath: root.appendingPathComponent("Bookmarks")
            ),
        ]
    }

    private func firefoxLocations(root: URL, profileName: String, source: BrowserImportSource) -> [BrowserImportLocation] {
        let profile = root.appendingPathComponent(profileName)
        return [
            BrowserImportLocation(
                source: source,
                profileName: profileName,
                historyPath: profile.appendingPathComponent("places.sqlite"),
                cookiesPath: profile.appendingPathComponent("cookies.sqlite"),
                bookmarksPath: nil
            ),
        ]
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
