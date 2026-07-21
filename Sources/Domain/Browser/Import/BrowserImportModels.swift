// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserImportModels.swift - Browser import plans, results, and shared contracts.

import Foundation

enum BrowserImportSource: String, CaseIterable, Codable, Sendable, Hashable {
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
            let root = support.appendingPathComponent("Orion")
            return [
                BrowserImportLocation(
                    source: self,
                    profileName: "Default",
                    historyPath: root.appendingPathComponent("History.db"),
                    cookiesPath: root.appendingPathComponent("Cookies.binarycookies"),
                    bookmarksPath: root.appendingPathComponent("Bookmarks.plist")
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
    let profileIdentifier: String
    let historyPath: URL
    let cookiesPath: URL?
    let bookmarksPath: URL?

    init(
        source: BrowserImportSource,
        profileName: String,
        profileIdentifier: String? = nil,
        historyPath: URL,
        cookiesPath: URL?,
        bookmarksPath: URL?
    ) {
        self.source = source
        self.profileName = profileName
        self.profileIdentifier = profileIdentifier ?? profileName
        self.historyPath = historyPath
        self.cookiesPath = cookiesPath
        self.bookmarksPath = bookmarksPath
    }
}

enum BrowserImportLocationPathBinding {
    private static let keyPrefix = "browser-import."

    static func requestedLocations(
        source: BrowserImportSource,
        profileName: String? = nil,
        discoverProfiles: Bool = true,
        importHistory: Bool = true,
        importCookies: Bool = true,
        importBookmarks: Bool = true,
        historyPath: String?,
        cookiesPath: String?,
        bookmarksPath: String?
    ) -> [BrowserImportLocation] {
        let discovered = discoverProfiles ? source.discoveredLocations() : []
        let defaults = discovered.isEmpty ? source.defaultLocations() : discovered
        let selectedDefaults = selectedLocations(defaults, profileName: profileName)
        let hasExplicitPath = historyPath != nil || cookiesPath != nil || bookmarksPath != nil
        guard hasExplicitPath else {
            return selectedDefaults
        }
        guard let base = selectedDefaults.first ?? defaults.first,
              (!importHistory || historyPath != nil),
              (!importCookies || cookiesPath != nil),
              (!importBookmarks || bookmarksPath != nil) else { return [] }

        return [BrowserImportLocation(
            source: source,
            profileName: profileName ?? base.profileName,
            profileIdentifier: profileName ?? base.profileIdentifier,
            historyPath: historyPath.map(URL.init(fileURLWithPath:)) ?? base.historyPath,
            cookiesPath: importCookies ? cookiesPath.map(URL.init(fileURLWithPath:)) : nil,
            bookmarksPath: importBookmarks ? bookmarksPath.map(URL.init(fileURLWithPath:)) : nil
        )]
    }

    static func canonicalResourcePaths(
        for locations: [BrowserImportLocation],
        importHistory: Bool = true,
        importCookies: Bool = true,
        importBookmarks: Bool = true,
        canonicalize: (URL) -> URL?
    ) -> [String: String]? {
        var paths: [String: String] = [:]
        for (index, location) in locations.enumerated() {
            if importHistory {
                guard let historyURL = canonicalize(location.historyPath) else { return nil }
                paths[key(component: "history", index: index)] = historyURL.path
                guard appendSQLiteSidecars(
                    for: historyURL,
                    component: "history",
                    index: index,
                    canonicalize: canonicalize,
                    paths: &paths
                ) else { return nil }
            }

            if importCookies, let cookiesPath = location.cookiesPath {
                guard let cookiesURL = canonicalize(cookiesPath) else { return nil }
                paths[key(component: "cookies", index: index)] = cookiesURL.path
                if usesSQLite(location: location, component: "cookies") {
                    guard appendSQLiteSidecars(
                        for: cookiesURL,
                        component: "cookies",
                        index: index,
                        canonicalize: canonicalize,
                        paths: &paths
                    ) else { return nil }
                }
            }
            if importBookmarks, let bookmarksPath = location.bookmarksPath {
                guard let bookmarksURL = canonicalize(bookmarksPath) else { return nil }
                paths[key(component: "bookmarks", index: index)] = bookmarksURL.path
                if usesSQLite(location: location, component: "bookmarks") {
                    guard appendSQLiteSidecars(
                        for: bookmarksURL,
                        component: "bookmarks",
                        index: index,
                        canonicalize: canonicalize,
                        paths: &paths
                    ) else { return nil }
                }
            }
        }
        return paths
    }

    static func applyingApprovedResourcePaths(
        _ resourcePaths: [String: String],
        to locations: [BrowserImportLocation],
        importHistory: Bool = true,
        importCookies: Bool = true,
        importBookmarks: Bool = true
    ) -> [BrowserImportLocation]? {
        var expectedKeys = Set<String>()
        var approvedLocations: [BrowserImportLocation] = []
        approvedLocations.reserveCapacity(locations.count)

        for (index, location) in locations.enumerated() {
            let historyPath: URL
            if importHistory {
                let historyKey = key(component: "history", index: index)
                expectedKeys.insert(historyKey)
                guard let approvedPath = resourcePaths[historyKey] else { return nil }
                historyPath = URL(fileURLWithPath: approvedPath).standardizedFileURL
                guard validateSQLiteSidecars(
                    for: historyPath,
                    component: "history",
                    index: index,
                    resourcePaths: resourcePaths,
                    expectedKeys: &expectedKeys
                ) else { return nil }
            } else {
                historyPath = location.historyPath
            }

            let cookiesPath: URL?
            if importCookies, location.cookiesPath != nil {
                let cookiesKey = key(component: "cookies", index: index)
                expectedKeys.insert(cookiesKey)
                guard let approvedPath = resourcePaths[cookiesKey] else { return nil }
                let approvedURL = URL(fileURLWithPath: approvedPath).standardizedFileURL
                cookiesPath = approvedURL
                if usesSQLite(location: location, component: "cookies") {
                    guard validateSQLiteSidecars(
                        for: approvedURL,
                        component: "cookies",
                        index: index,
                        resourcePaths: resourcePaths,
                        expectedKeys: &expectedKeys
                    ) else { return nil }
                }
            } else {
                cookiesPath = location.cookiesPath
            }

            let bookmarksPath: URL?
            if importBookmarks, location.bookmarksPath != nil {
                let bookmarksKey = key(component: "bookmarks", index: index)
                expectedKeys.insert(bookmarksKey)
                guard let approvedPath = resourcePaths[bookmarksKey] else { return nil }
                let approvedURL = URL(fileURLWithPath: approvedPath).standardizedFileURL
                bookmarksPath = approvedURL
                if usesSQLite(location: location, component: "bookmarks") {
                    guard validateSQLiteSidecars(
                        for: approvedURL,
                        component: "bookmarks",
                        index: index,
                        resourcePaths: resourcePaths,
                        expectedKeys: &expectedKeys
                    ) else { return nil }
                }
            } else {
                bookmarksPath = location.bookmarksPath
            }

            approvedLocations.append(BrowserImportLocation(
                source: location.source,
                profileName: location.profileName,
                profileIdentifier: location.profileIdentifier,
                historyPath: historyPath,
                cookiesPath: cookiesPath,
                bookmarksPath: bookmarksPath
            ))
        }

        let suppliedKeys = Set(resourcePaths.keys.filter { $0.hasPrefix(keyPrefix) })
        guard suppliedKeys == expectedKeys else { return nil }
        return approvedLocations
    }

    private static func key(component: String, index: Int) -> String {
        "\(keyPrefix)\(index).\(component)"
    }

    private static func appendSQLiteSidecars(
        for databaseURL: URL,
        component: String,
        index: Int,
        canonicalize: (URL) -> URL?,
        paths: inout [String: String]
    ) -> Bool {
        for suffix in ["-wal", "-journal"] {
            let expected = URL(fileURLWithPath: databaseURL.path + suffix).standardizedFileURL
            guard let canonical = canonicalize(expected), canonical.path == expected.path else {
                return false
            }
            paths[key(component: component + suffix, index: index)] = canonical.path
        }
        return true
    }

    private static func validateSQLiteSidecars(
        for databaseURL: URL,
        component: String,
        index: Int,
        resourcePaths: [String: String],
        expectedKeys: inout Set<String>
    ) -> Bool {
        for suffix in ["-wal", "-journal"] {
            let sidecarKey = key(component: component + suffix, index: index)
            expectedKeys.insert(sidecarKey)
            let expectedPath = URL(fileURLWithPath: databaseURL.path + suffix).standardizedFileURL.path
            guard resourcePaths[sidecarKey] == expectedPath else { return false }
        }
        return true
    }

    private static func usesSQLite(location: BrowserImportLocation, component: String) -> Bool {
        switch component {
        case "cookies":
            return location.cookiesPath?.lastPathComponent
                .localizedCaseInsensitiveContains("binarycookies") != true
        case "bookmarks":
            switch location.source {
            case .firefox, .firefoxDeveloperEdition, .firefoxNightly,
                 .librewolf, .waterfox, .floorp, .zen:
                return true
            default:
                return location.bookmarksPath?.standardizedFileURL
                    == location.historyPath.standardizedFileURL
            }
        default:
            return true
        }
    }

    private static func selectedLocations(
        _ locations: [BrowserImportLocation],
        profileName: String?
    ) -> [BrowserImportLocation] {
        guard let profileName = profileName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !profileName.isEmpty else {
            return Array(locations.prefix(1))
        }
        return locations.filter {
            $0.profileIdentifier.caseInsensitiveCompare(profileName) == .orderedSame
                || $0.profileName.caseInsensitiveCompare(profileName) == .orderedSame
        }
    }
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
    let sourceProfile: String?
    let explicitLocations: [BrowserImportLocation]?
    let readCookieValues: Bool
    let expectedPreviewToken: String?

    init(
        source: BrowserImportSource,
        profileID: UUID,
        importCookies: Bool = true,
        importHistory: Bool = true,
        importBookmarks: Bool = true,
        maxHistoryDays: Int? = nil,
        domainWhitelist: [String] = [],
        domainBlacklist: [String] = [],
        sourceProfile: String? = nil,
        explicitLocations: [BrowserImportLocation]? = nil,
        readCookieValues: Bool = false,
        expectedPreviewToken: String? = nil
    ) {
        self.source = source
        self.profileID = profileID
        self.importCookies = importCookies
        self.importHistory = importHistory
        self.importBookmarks = importBookmarks
        self.maxHistoryDays = maxHistoryDays
        self.domainWhitelist = domainWhitelist.map(Self.normalizedDomain)
        self.domainBlacklist = domainBlacklist.map(Self.normalizedDomain)
        self.sourceProfile = sourceProfile?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.explicitLocations = explicitLocations
        self.readCookieValues = readCookieValues
        self.expectedPreviewToken = expectedPreviewToken?.lowercased()
    }

    func locations(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [BrowserImportLocation] {
        if let explicitLocations {
            return explicitLocations
        }
        let discovered = source.discoveredLocations(homeDirectory: homeDirectory)
        let candidates = discovered.isEmpty
            ? source.defaultLocations(homeDirectory: homeDirectory)
            : discovered
        guard let sourceProfile, !sourceProfile.isEmpty else {
            return Array(candidates.prefix(1))
        }
        return candidates.filter {
            $0.profileIdentifier.caseInsensitiveCompare(sourceProfile) == .orderedSame
                || $0.profileName.caseInsensitiveCompare(sourceProfile) == .orderedSame
        }
    }

    func readingCookieValues() -> BrowserImportPlan {
        BrowserImportPlan(
            source: source,
            profileID: profileID,
            importCookies: importCookies,
            importHistory: importHistory,
            importBookmarks: importBookmarks,
            maxHistoryDays: maxHistoryDays,
            domainWhitelist: domainWhitelist,
            domainBlacklist: domainBlacklist,
            sourceProfile: sourceProfile,
            explicitLocations: explicitLocations,
            readCookieValues: true,
            expectedPreviewToken: expectedPreviewToken
        )
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
    enum SameSite: String, Sendable, Equatable {
        case unspecified
        case none
        case lax
        case strict
    }

    let domain: String
    let name: String
    let path: String
    let value: String?
    let expiresAt: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool
    let sameSite: SameSite
    let isPartitioned: Bool
    let sourceValueFingerprint: String?

    init(
        domain: String,
        name: String,
        path: String,
        value: String?,
        expiresAt: Date?,
        isSecure: Bool,
        isHTTPOnly: Bool,
        sameSite: SameSite = .unspecified,
        isPartitioned: Bool = false,
        sourceValueFingerprint: String? = nil
    ) {
        self.domain = domain
        self.name = name
        self.path = path
        self.value = value
        self.expiresAt = expiresAt
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
        self.sameSite = sameSite
        self.isPartitioned = isPartitioned
        self.sourceValueFingerprint = sourceValueFingerprint
    }
}

struct BrowserImportedCookieBatchWriteError: LocalizedError, Sendable, Equatable {
    let importedCount: Int
    let totalCount: Int
    let detail: String

    var errorDescription: String? {
        "Imported \(importedCount) of \(totalCount) cookies: \(detail)"
    }
}

struct BrowserImportedBookmark: Sendable, Equatable {
    let title: String
    let url: String
    let folderPath: [String]
    let createdAt: Date?
    let sortOrder: Int

    init(
        title: String,
        url: String,
        folderPath: [String] = [],
        createdAt: Date? = nil,
        sortOrder: Int = 0
    ) {
        self.title = title
        self.url = url
        self.folderPath = folderPath
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
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
    var skippedCount: Int

    init(
        history: [BrowserImportedHistoryVisit],
        cookies: [BrowserImportedCookie],
        bookmarks: [BrowserImportedBookmark],
        errors: [BrowserImportIssue],
        skippedCount: Int = 0
    ) {
        self.history = history
        self.cookies = cookies
        self.bookmarks = bookmarks
        self.errors = errors
        self.skippedCount = skippedCount
    }

    var itemCount: Int {
        history.count + cookies.count + bookmarks.count
    }

    static let empty = BrowserImportPreview(
        history: [],
        cookies: [],
        bookmarks: [],
        errors: [],
        skippedCount: 0
    )
}

struct BrowserImportResult: Sendable, Equatable {
    let runID: UUID
    let status: BrowserImportStatus
    let sourceProfile: String
    let importedHistoryCount: Int
    let importedCookieCount: Int
    let importedBookmarkCount: Int
    let skippedCount: Int
    let errors: [BrowserImportIssue]
}

enum BrowserImportStatus: String, Codable, Sendable, Equatable {
    case completed
    case partial
    case failed
}

struct BrowserImportAuditEntry: Codable, Sendable, Equatable {
    let runID: UUID
    let source: BrowserImportSource
    let sourceProfile: String
    let targetProfileID: UUID
    let status: BrowserImportStatus
    let importedHistoryCount: Int
    let importedCookieCount: Int
    let importedBookmarkCount: Int
    let skippedCount: Int
    let issueCount: Int
    let timestamp: Date
}

protocol BrowserSourceImporting: Sendable {
    func preview(plan: BrowserImportPlan) throws -> BrowserImportPreview
}

protocol BrowserImportedCookieStoring: Sendable {
    func saveImportedCookie(_ cookie: BrowserImportedCookie, profileID: UUID) throws
    func saveImportedCookies(_ cookies: [BrowserImportedCookie], profileID: UUID) throws
}

extension BrowserImportedCookieStoring {
    func saveImportedCookies(_ cookies: [BrowserImportedCookie], profileID: UUID) throws {
        for cookie in cookies {
            try saveImportedCookie(cookie, profileID: profileID)
        }
    }
}

protocol BrowserImportAuditLogging: Sendable {
    func record(_ entry: BrowserImportAuditEntry) throws
}

enum BrowserImportError: LocalizedError, Sendable, Equatable {
    case databaseOpenFailed(String)
    case statementFailed(String)
    case sourceChangedDuringRead(String)
    case invalidSourceFile(String)
    case sourceProfileUnavailable(String)
    case noImportableData(String)
    case cookieDecryptionFailed(String)
    case sourceChangedAfterPreview
    case cancelled

    var errorDescription: String? {
        switch self {
        case .databaseOpenFailed(let message):
            return "Browser database could not be opened: \(message)"
        case .statementFailed(let message):
            return "Browser database could not be read: \(message)"
        case .sourceChangedDuringRead:
            return "Browser source changed while it was being read"
        case .invalidSourceFile:
            return "Browser source file is invalid or unavailable"
        case .sourceProfileUnavailable(let profile):
            return "Browser source profile is unavailable: \(profile)"
        case .noImportableData(let message):
            return message
        case .cookieDecryptionFailed(let message):
            return message
        case .sourceChangedAfterPreview:
            return "Browser data changed after review; refresh the preview before importing"
        case .cancelled:
            return "Browser import was cancelled"
        }
    }
}
