// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserImportSwiftTestingTests.swift - Browser import domain coverage.

import CommonCrypto
import CryptoKit
import Foundation
import SQLite3
import Testing
import WebKit
@testable import CocxyTerminal

@Suite("BrowserImport")
struct BrowserImportSwiftTestingTests {

    @Test("supported sources expose common browser default locations")
    func supportedSourcesExposeDefaultLocations() {
        let sources = BrowserImportSource.allCases

        #expect(sources.count >= 20)
        #expect(sources.contains(.chrome))
        #expect(sources.contains(.firefox))
        #expect(sources.contains(.safari))
        #expect(BrowserImportSource.arc.defaultLocations(homeDirectory: URL(fileURLWithPath: "/Users/me")).contains {
            $0.historyPath.path.contains("Arc")
        })
    }

    @Test("expanded browser source catalog keeps CLI aliases and importer families stable")
    func expandedBrowserSourceCatalogKeepsAliasesAndImporterFamiliesStable() {
        let sourcesByRawValue = Dictionary(uniqueKeysWithValues: BrowserImportSource.allCases.map {
            ($0.rawValue, $0)
        })

        let expectedRawValues = [
            "chrome", "chrome-canary", "chromium",
            "edge", "edge-beta", "edge-dev",
            "brave", "brave-beta", "brave-nightly",
            "opera", "opera-gx",
            "vivaldi", "vivaldi-snapshot",
            "arc", "arc-beta",
            "firefox", "firefox-developer-edition", "firefox-nightly",
            "librewolf", "waterfox", "floorp", "zen",
            "safari", "orion",
        ]

        for rawValue in expectedRawValues {
            #expect(sourcesByRawValue[rawValue] != nil, "Missing browser import source: \(rawValue)")
        }

        let home = URL(fileURLWithPath: "/Users/me")
        #expect(BrowserImportSource.chromeCanary.defaultLocations(homeDirectory: home).contains {
            $0.historyPath.path.contains("Google/Chrome Canary")
        })
        #expect(BrowserImportSource.librewolf.defaultLocations(homeDirectory: home).contains {
            $0.historyPath.path.contains("LibreWolf/Profiles")
        })
        #expect(BrowserImportSource.orion.defaultLocations(homeDirectory: home).contains {
            $0.historyPath.path.contains("Orion")
        })

        #expect(BrowserImportSource.braveNightly.isChromiumBased)
        #expect(!BrowserImportSource.firefoxNightly.isChromiumBased)
        #expect(type(of: BrowserSourceImporterFactory.importer(for: .edgeDev)) == ChromiumBrowserImporter.self)
        #expect(type(of: BrowserSourceImporterFactory.importer(for: .floorp)) == FirefoxBrowserImporter.self)
        #expect(type(of: BrowserSourceImporterFactory.importer(for: .orion)) == SafariBrowserImporter.self)
    }

    @Test("plan applies whitelist and blacklist before importing URLs")
    func planFiltersDomains() {
        let plan = BrowserImportPlan(
            source: .chrome,
            profileID: UUID(),
            domainWhitelist: ["example.com"],
            domainBlacklist: ["blocked.example.com"]
        )

        #expect(plan.allows(urlString: "https://docs.example.com/path"))
        #expect(!plan.allows(urlString: "https://blocked.example.com/path"))
        #expect(!plan.allows(urlString: "https://other.test"))
    }

    @Test("preview tokens bind source metadata without exposing cookie values")
    func previewTokensBindReviewedSourceMetadata() {
        let location = BrowserImportLocation(
            source: .chrome,
            profileName: "Work",
            profileIdentifier: "Profile 7",
            historyPath: URL(fileURLWithPath: "/fixture/Profile 7/History"),
            cookiesPath: URL(fileURLWithPath: "/fixture/Profile 7/Network/Cookies"),
            bookmarksPath: URL(fileURLWithPath: "/fixture/Profile 7/Bookmarks")
        )
        let plan = BrowserImportPlan(
            source: .chrome,
            profileID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            explicitLocations: [location]
        )
        let fingerprint = BrowserImportPreviewToken.fingerprint(Data("encrypted-cookie".utf8))
        let reviewed = BrowserImportPreview(
            history: [],
            cookies: [BrowserImportedCookie(
                domain: ".example.com",
                name: "session",
                path: "/",
                value: nil,
                expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
                isSecure: true,
                isHTTPOnly: true,
                sameSite: .lax,
                sourceValueFingerprint: fingerprint
            )],
            bookmarks: [],
            errors: []
        )
        let materialized = BrowserImportPreview(
            history: [],
            cookies: [BrowserImportedCookie(
                domain: ".example.com",
                name: "session",
                path: "/",
                value: "secret-value",
                expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
                isSecure: true,
                isHTTPOnly: true,
                sameSite: .lax,
                sourceValueFingerprint: fingerprint
            )],
            bookmarks: [],
            errors: []
        )
        let changed = BrowserImportPreview(
            history: [],
            cookies: [BrowserImportedCookie(
                domain: ".example.com",
                name: "session",
                path: "/",
                value: "different-value",
                expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
                isSecure: true,
                isHTTPOnly: true,
                sameSite: .lax,
                sourceValueFingerprint: BrowserImportPreviewToken.fingerprint(Data("changed-cookie".utf8))
            )],
            bookmarks: [],
            errors: []
        )

        let reviewedToken = BrowserImportPreviewToken.make(preview: reviewed, plan: plan)

        #expect(BrowserImportPreviewToken.isValid(reviewedToken))
        #expect(reviewedToken == BrowserImportPreviewToken.make(preview: materialized, plan: plan))
        #expect(reviewedToken != BrowserImportPreviewToken.make(preview: changed, plan: plan))
        #expect(!reviewedToken.contains("secret-value"))
    }

    @Test("approved import location binding replaces every caller path and fails closed")
    func approvedLocationBindingIsExactAndFailClosed() throws {
        let requested = BrowserImportLocationPathBinding.requestedLocations(
            source: .chrome,
            profileName: "Profile 7",
            historyPath: "/caller/History",
            cookiesPath: "/caller/Cookies",
            bookmarksPath: "/caller/Bookmarks"
        )
        let approvedPaths = try #require(
            BrowserImportLocationPathBinding.canonicalResourcePaths(
                for: requested,
                canonicalize: { url in
                    URL(fileURLWithPath: "/approved/\(url.lastPathComponent)")
                }
            )
        )
        let approved = try #require(
            BrowserImportLocationPathBinding.applyingApprovedResourcePaths(
                approvedPaths,
                to: requested
            )
        )

        #expect(approved.count == 1)
        #expect(approved[0].profileName == "Profile 7")
        #expect(approved[0].historyPath.path == "/approved/History")
        #expect(approved[0].cookiesPath?.path == "/approved/Cookies")
        #expect(approved[0].bookmarksPath?.path == "/approved/Bookmarks")
        #expect(!approved[0].historyPath.path.contains("/caller/"))
        #expect(approvedPaths["browser-import.0.history-wal"] == "/approved/History-wal")
        #expect(approvedPaths["browser-import.0.history-journal"] == "/approved/History-journal")
        #expect(approvedPaths["browser-import.0.cookies-wal"] == "/approved/Cookies-wal")
        #expect(approvedPaths["browser-import.0.cookies-journal"] == "/approved/Cookies-journal")

        var missingPath = approvedPaths
        missingPath.removeValue(forKey: try #require(missingPath.keys.sorted().first))
        #expect(BrowserImportLocationPathBinding.applyingApprovedResourcePaths(
            missingPath,
            to: requested
        ) == nil)

        var unexpectedPath = approvedPaths
        unexpectedPath["browser-import.1.history"] = "/approved/unexpected"
        #expect(BrowserImportLocationPathBinding.applyingApprovedResourcePaths(
            unexpectedPath,
            to: requested
        ) == nil)

        var changedSidecar = approvedPaths
        changedSidecar["browser-import.0.history-wal"] = "/approved/other-wal"
        #expect(BrowserImportLocationPathBinding.applyingApprovedResourcePaths(
            changedSidecar,
            to: requested
        ) == nil)
    }

    @Test("anchored file reads allow macOS root aliases and reject symbolic links")
    func anchoredFileReadsRejectSymbolicLinks() throws {
        let root = try BrowserImportFixture.temporaryDirectory("anchored-file-reader")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: false)
        let source = sourceDirectory.appendingPathComponent("Bookmarks")
        try Data("trusted".utf8).write(to: source)

        #expect(try BrowserImportFileReader.readData(from: source, maximumByteCount: 64) == Data("trusted".utf8))

        let linkedDirectory = root.appendingPathComponent("linked-source", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: sourceDirectory)
        let pathThroughLinkedDirectory = linkedDirectory.appendingPathComponent("Bookmarks")
        do {
            _ = try BrowserImportFileReader.readData(
                from: pathThroughLinkedDirectory,
                maximumByteCount: 64
            )
            Issue.record("Expected a symbolic parent directory to be rejected")
        } catch let error as BrowserImportError {
            #expect(error == .invalidSourceFile(pathThroughLinkedDirectory.path))
        }

        let linkedFile = root.appendingPathComponent("linked-bookmarks")
        try FileManager.default.createSymbolicLink(at: linkedFile, withDestinationURL: source)
        do {
            _ = try BrowserImportFileReader.readData(from: linkedFile, maximumByteCount: 64)
            Issue.record("Expected a symbolic source file to be rejected")
        } catch let error as BrowserImportError {
            #expect(error == .invalidSourceFile(linkedFile.path))
        }

        let history = sourceDirectory.appendingPathComponent("History")
        try Data().write(to: history)
        let historyWAL = URL(fileURLWithPath: history.path + "-wal")
        try FileManager.default.createSymbolicLink(at: historyWAL, withDestinationURL: source)
        let locations = [BrowserImportLocation(
            source: .chrome,
            profileName: "Default",
            historyPath: history,
            cookiesPath: nil,
            bookmarksPath: nil
        )]
        #expect(BrowserImportLocationPathBinding.canonicalResourcePaths(
            for: locations,
            importCookies: false,
            importBookmarks: false,
            canonicalize: { $0.resolvingSymlinksInPath().standardizedFileURL }
        ) == nil)
    }

    @Test("SQLite row decoding rejects oversized text and blob values")
    func sqliteRowDecodingRejectsOversizedValues() throws {
        let database = try BrowserImportFixture.oversizedSQLiteValues()
        defer { try? FileManager.default.removeItem(at: database.deletingLastPathComponent()) }

        let rows: [Bool] = try BrowserSQLiteImportReader.readRows(
            databaseURL: database,
            query: "SELECT large_text, large_blob FROM payload"
        ) { statement in
            BrowserSQLiteImportReader.text(statement, 0) == nil
                && BrowserSQLiteImportReader.blob(statement, 1) == nil
        }

        #expect(rows == [true])
    }

    @Test("resource authorization binds only enabled data types")
    func resourceAuthorizationBindsOnlyEnabledDataTypes() throws {
        let requested = BrowserImportLocationPathBinding.requestedLocations(
            source: .chrome,
            profileName: "Profile 9",
            importHistory: false,
            importCookies: true,
            importBookmarks: false,
            historyPath: nil,
            cookiesPath: "/caller/Cookies",
            bookmarksPath: nil
        )
        let approvedPaths = try #require(
            BrowserImportLocationPathBinding.canonicalResourcePaths(
                for: requested,
                importHistory: false,
                importCookies: true,
                importBookmarks: false,
                canonicalize: { URL(fileURLWithPath: "/approved/\($0.lastPathComponent)") }
            )
        )

        #expect(approvedPaths == [
            "browser-import.0.cookies": "/approved/Cookies",
            "browser-import.0.cookies-wal": "/approved/Cookies-wal",
            "browser-import.0.cookies-journal": "/approved/Cookies-journal",
        ])
        let approved = try #require(
            BrowserImportLocationPathBinding.applyingApprovedResourcePaths(
                approvedPaths,
                to: requested,
                importHistory: false,
                importCookies: true,
                importBookmarks: false
            )
        )
        #expect(approved[0].cookiesPath?.path == "/approved/Cookies")
        #expect(approved[0].historyPath == requested[0].historyPath)

        #expect(BrowserImportLocationPathBinding.requestedLocations(
            source: .chrome,
            importHistory: true,
            importCookies: true,
            importBookmarks: false,
            historyPath: "/only/History",
            cookiesPath: nil,
            bookmarksPath: nil
        ).isEmpty)
    }

    @Test("pre-consent path binding does not discover local browser metadata")
    func preConsentPathBindingUsesStaticOrExplicitLocations() {
        let undiscovered = BrowserImportLocationPathBinding.requestedLocations(
            source: .chrome,
            profileName: "Profile 999999",
            discoverProfiles: false,
            historyPath: nil,
            cookiesPath: nil,
            bookmarksPath: nil
        )
        #expect(undiscovered.isEmpty)

        let explicit = BrowserImportLocationPathBinding.requestedLocations(
            source: .chrome,
            profileName: "Profile 999999",
            discoverProfiles: false,
            historyPath: "/explicit/History",
            cookiesPath: "/explicit/Cookies",
            bookmarksPath: "/explicit/Bookmarks"
        )
        #expect(explicit.count == 1)
        #expect(explicit[0].profileIdentifier == "Profile 999999")
        #expect(explicit[0].historyPath.path == "/explicit/History")
    }

    @Test("Chromium discovery uses Local State and the modern cookie path")
    func chromiumDiscoveryUsesProfileMetadata() throws {
        let home = try BrowserImportFixture.temporaryDirectory("chromium-discovery")
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent("Library/Application Support/Google/Chrome")
        let defaultProfile = root.appendingPathComponent("Default")
        let workProfile = root.appendingPathComponent("Profile 7")
        try FileManager.default.createDirectory(
            at: workProfile.appendingPathComponent("Network"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: defaultProfile, withIntermediateDirectories: true)
        try Data().write(to: workProfile.appendingPathComponent("History"))
        try Data().write(to: workProfile.appendingPathComponent("Network/Cookies"))
        try Data().write(to: defaultProfile.appendingPathComponent("Bookmarks"))
        let localState: [String: Any] = [
            "profile": [
                "last_used": "Profile 7",
                "info_cache": [
                    "Default": ["name": "Personal"],
                    "Profile 7": ["name": "Work"],
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: localState)
            .write(to: root.appendingPathComponent("Local State"))

        let locations = BrowserImportDiscovery.chromiumLocations(
            source: .chrome,
            homeDirectory: home,
            fileManager: .default
        )

        #expect(locations.map(\.profileIdentifier) == ["Profile 7", "Default"])
        #expect(locations.first?.profileName == "Work")
        #expect(locations.first?.cookiesPath?.lastPathComponent == "Cookies")
        #expect(locations.first?.cookiesPath?.deletingLastPathComponent().lastPathComponent == "Network")
    }

    @Test("Firefox discovery resolves profiles.ini and random profile directories")
    func firefoxDiscoveryUsesProfilesINI() throws {
        let home = try BrowserImportFixture.temporaryDirectory("firefox-discovery")
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent("Library/Application Support/Firefox")
        let primary = root.appendingPathComponent("Profiles/abc.default-release")
        let secondary = root.appendingPathComponent("Profiles/zzz.extra")
        try FileManager.default.createDirectory(at: primary, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondary, withIntermediateDirectories: true)
        try Data().write(to: primary.appendingPathComponent("places.sqlite"))
        try Data().write(to: primary.appendingPathComponent("cookies.sqlite"))
        try Data().write(to: secondary.appendingPathComponent("places.sqlite"))
        try Data("""
            [Profile0]
            Name=Work
            IsRelative=1
            Path=Profiles/abc.default-release
            Default=1
            """.utf8).write(to: root.appendingPathComponent("profiles.ini"))

        let locations = BrowserImportDiscovery.firefoxLocations(
            source: .firefox,
            homeDirectory: home,
            fileManager: .default
        )

        #expect(locations.count == 2)
        #expect(locations.first?.profileName == "Work")
        #expect(locations.first?.profileIdentifier == "abc.default-release")
        #expect(locations.contains { $0.profileIdentifier == "zzz.extra" })
    }

    @Test("Firefox discovery separates stable, Developer Edition, and Nightly profiles")
    func firefoxDiscoverySeparatesInstallChannels() throws {
        let home = try BrowserImportFixture.temporaryDirectory("firefox-channels")
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent("Library/Application Support/Firefox")
        let profiles = [
            (identifier: "stable.default", app: "Firefox.app"),
            (identifier: "developer.dev-edition", app: "Firefox Developer Edition.app"),
            (identifier: "nightly.default-nightly", app: "Firefox Nightly.app"),
        ]
        for profile in profiles {
            let directory = root.appendingPathComponent("Profiles/\(profile.identifier)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: directory.appendingPathComponent("places.sqlite"))
            try Data("""
                [Compatibility]
                LastAppDir=/Applications/\(profile.app)/Contents/MacOS
                LastPlatformDir=/Applications/\(profile.app)/Contents/MacOS
                """.utf8).write(to: directory.appendingPathComponent("compatibility.ini"))
        }
        try Data("""
            [Profile0]
            Name=Stable
            IsRelative=1
            Path=Profiles/stable.default
            [Profile1]
            Name=Developer
            IsRelative=1
            Path=Profiles/developer.dev-edition
            [Profile2]
            Name=Nightly
            IsRelative=1
            Path=Profiles/nightly.default-nightly
            """.utf8).write(to: root.appendingPathComponent("profiles.ini"))

        let stable = BrowserImportDiscovery.firefoxLocations(
            source: .firefox,
            homeDirectory: home,
            fileManager: .default
        )
        let developer = BrowserImportDiscovery.firefoxLocations(
            source: .firefoxDeveloperEdition,
            homeDirectory: home,
            fileManager: .default
        )
        let nightly = BrowserImportDiscovery.firefoxLocations(
            source: .firefoxNightly,
            homeDirectory: home,
            fileManager: .default
        )

        #expect(stable.map(\.profileIdentifier) == ["stable.default"])
        #expect(developer.map(\.profileIdentifier) == ["developer.dev-edition"])
        #expect(nightly.map(\.profileIdentifier) == ["nightly.default-nightly"])
    }

    @Test("chromium importer reads history and cookies from profile database files")
    func chromiumImporterReadsHistoryAndCookies() throws {
        let fixture = try BrowserImportFixture.chromium()
        let plan = BrowserImportPlan(
            source: .chrome,
            profileID: UUID(),
            importBookmarks: false,
            explicitLocations: [
                BrowserImportLocation(
                    source: .chrome,
                    profileName: "Default",
                    historyPath: fixture.history,
                    cookiesPath: fixture.cookies,
                    bookmarksPath: nil
                ),
            ]
        )

        let result = try ChromiumBrowserImporter().preview(plan: plan)

        #expect(result.history.map(\.url) == [
            "https://example.com/docs",
            "https://example.com/docs",
        ])
        #expect(result.history[0].visitedAt > result.history[1].visitedAt)
        #expect(result.cookies.count == 1)
        #expect(result.cookies[0].name == "session")
        #expect(result.errors.isEmpty)
    }

    @Test("history importer caps matching visits and reports the overflow")
    func historyImporterCapsMatchingVisits() throws {
        let history = try BrowserImportFixture.chromiumHistory(visitCount: 50_002)
        defer { try? FileManager.default.removeItem(at: history.deletingLastPathComponent()) }
        let plan = BrowserImportPlan(
            source: .chrome,
            profileID: UUID(),
            importCookies: false,
            importBookmarks: false,
            explicitLocations: [BrowserImportLocation(
                source: .chrome,
                profileName: "Large",
                historyPath: history,
                cookiesPath: nil,
                bookmarksPath: nil
            )]
        )

        let result = try ChromiumBrowserImporter().preview(plan: plan)

        #expect(result.history.count == 50_000)
        #expect(result.skippedCount == 2)
        #expect(result.errors.contains {
            $0.message.contains("History safety limit reached")
                && $0.message.contains("50000-visit import limit")
        })
    }

    @Test("SQLite reader snapshots a locked browser database without exposing uncommitted changes")
    func sqliteReaderSnapshotsLockedBrowserDatabase() throws {
        let fixture = try BrowserImportFixture.chromium()
        var lockedDatabase: OpaquePointer?
        guard sqlite3_open_v2(
            fixture.history.path,
            &lockedDatabase,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let lockedDatabase else {
            throw BrowserImportFixtureError.databaseOpen
        }
        defer {
            sqlite3_exec(lockedDatabase, "ROLLBACK", nil, nil, nil)
            sqlite3_close(lockedDatabase)
        }
        guard sqlite3_exec(lockedDatabase, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK,
              sqlite3_exec(
                lockedDatabase,
                "UPDATE urls SET title = 'Uncommitted' WHERE id = 1",
                nil,
                nil,
                nil
              ) == SQLITE_OK else {
            throw BrowserImportFixtureError.statementFailed("lock fixture database")
        }

        let titles: [String] = try BrowserSQLiteImportReader.readRows(
            databaseURL: fixture.history,
            query: "SELECT title FROM urls ORDER BY id"
        ) { statement in
            BrowserSQLiteImportReader.text(statement, 0)
        }

        #expect(titles == ["Docs"])
    }

    @Test("SQLite reader preserves committed rows that are still resident in WAL")
    func sqliteReaderPreservesActiveWAL() throws {
        let root = try BrowserImportFixture.temporaryDirectory("active-wal")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("History")
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            throw BrowserImportFixtureError.databaseOpen
        }
        defer { sqlite3_close(database) }
        for statement in [
            "PRAGMA journal_mode=WAL",
            "PRAGMA wal_autocheckpoint=0",
            "CREATE TABLE urls(id INTEGER PRIMARY KEY, title TEXT NOT NULL)",
            "INSERT INTO urls(id, title) VALUES (1, 'Committed in WAL')",
        ] {
            guard sqlite3_exec(database, statement, nil, nil, nil) == SQLITE_OK else {
                throw BrowserImportFixtureError.statementFailed(statement)
            }
        }
        #expect(FileManager.default.fileExists(atPath: databaseURL.path + "-wal"))

        let titles: [String] = try BrowserSQLiteImportReader.readRows(
            databaseURL: databaseURL,
            query: "SELECT title FROM urls ORDER BY id"
        ) { statement in
            BrowserSQLiteImportReader.text(statement, 0)
        }

        #expect(titles == ["Committed in WAL"])
    }

    @Test("firefox importer reads places and cookies sqlite files")
    func firefoxImporterReadsPlacesAndCookies() throws {
        let fixture = try BrowserImportFixture.firefox()
        let plan = BrowserImportPlan(
            source: .firefox,
            profileID: UUID(),
            importBookmarks: false,
            explicitLocations: [
                BrowserImportLocation(
                    source: .firefox,
                    profileName: "default-release",
                    historyPath: fixture.history,
                    cookiesPath: fixture.cookies,
                    bookmarksPath: nil
                ),
            ]
        )

        let result = try FirefoxBrowserImporter().preview(plan: plan)

        #expect(result.history.map(\.url) == [
            "https://mozilla.example/start",
            "https://mozilla.example/start",
        ])
        #expect(result.history[0].visitedAt > result.history[1].visitedAt)
        #expect(result.cookies.map(\.domain) == [".mozilla.example"])
        #expect(result.errors.isEmpty)
    }

    @Test("Firefox importer preserves bookmark folders, order, and timestamps")
    func firefoxImporterReadsBookmarkTree() throws {
        let fixture = try BrowserImportFixture.firefox()
        let plan = BrowserImportPlan(
            source: .firefox,
            profileID: UUID(),
            importCookies: false,
            importHistory: false,
            importBookmarks: true,
            explicitLocations: [
                BrowserImportLocation(
                    source: .firefox,
                    profileName: "default-release",
                    historyPath: fixture.history,
                    cookiesPath: fixture.cookies,
                    bookmarksPath: fixture.history
                ),
            ]
        )

        let result = try FirefoxBrowserImporter().preview(plan: plan)

        #expect(result.bookmarks.count == 1)
        #expect(result.bookmarks[0].folderPath == ["Toolbar"])
        #expect(result.bookmarks[0].sortOrder == 3)
        #expect(result.bookmarks[0].createdAt != nil)
        #expect(result.errors.isEmpty)
    }

    @Test("Firefox importer rejects duplicate folder identifiers")
    func firefoxImporterRejectsDuplicateFolderIdentifiers() throws {
        let database = try BrowserImportFixture.firefoxDuplicateFolders()
        defer { try? FileManager.default.removeItem(at: database.deletingLastPathComponent()) }
        let plan = BrowserImportPlan(
            source: .firefox,
            profileID: UUID(),
            importCookies: false,
            importHistory: false,
            importBookmarks: true,
            explicitLocations: [BrowserImportLocation(
                source: .firefox,
                profileName: "Malformed",
                historyPath: database,
                cookiesPath: nil,
                bookmarksPath: database
            )]
        )

        let result = try FirefoxBrowserImporter().preview(plan: plan)

        #expect(result.bookmarks.isEmpty)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].message.contains("Bookmark import failed"))
    }

    @Test("Chromium and Safari bookmark decoders preserve nested folders")
    func bookmarkDecodersPreserveNestedFolders() throws {
        let chromium = try BrowserImportFixture.chromiumBookmarks()
        let safari = try BrowserImportFixture.safariBookmarks()

        let chromiumItems = try BrowserBookmarkImportDecoder.chromiumBookmarks(from: chromium)
        let safariItems = try BrowserBookmarkImportDecoder.safariBookmarks(from: safari)

        #expect(chromiumItems.count == 1)
        #expect(chromiumItems[0].folderPath == ["Bookmarks Bar", "Docs"])
        #expect(chromiumItems[0].title == "Cocxy Docs")
        #expect(chromiumItems[0].createdAt != nil)
        #expect(safariItems.count == 1)
        #expect(safariItems[0].folderPath == ["Reading"])
        #expect(safariItems[0].title == "WebKit Guide")
    }

    @Test("Safari binary cookie decoder validates structure and hides values during preview")
    func safariBinaryCookieDecoderReadsBoundedFixture() throws {
        let fixture = try BrowserImportFixture.safariBinaryCookies()

        let preview = try SafariBinaryCookieDecoder.cookies(from: fixture, includeValues: false)
        let imported = try SafariBinaryCookieDecoder.cookies(from: fixture, includeValues: true)

        #expect(preview.count == 1)
        #expect(preview[0].value == nil)
        #expect(imported[0].domain == ".example.com")
        #expect(imported[0].name == "session")
        #expect(imported[0].value == "private-value")
        #expect(imported[0].isSecure)
        #expect(imported[0].isHTTPOnly)

        let truncated = fixture.deletingLastPathComponent().appendingPathComponent("truncated.binarycookies")
        try Data("cook".utf8).write(to: truncated)
        do {
            _ = try SafariBinaryCookieDecoder.cookies(from: truncated, includeValues: true)
            Issue.record("Expected a truncated binary cookie file to fail")
        } catch let error as BrowserImportError {
            #expect(error == .invalidSourceFile(truncated.path))
        }
    }

    @Test("Chromium v24 cookie decryption enforces domain binding")
    func chromiumV24CookieDecryptionChecksDomainHash() throws {
        let password = Data("fixture-password".utf8)
        let domain = ".example.com"
        let encrypted = try BrowserImportFixture.chromiumEncryptedCookie(
            value: "private-value",
            domain: domain,
            password: password,
            bindDomain: true
        )
        let decryptor = ChromiumCookieDecryptor(
            passwordProvider: StaticSafeStoragePasswordProvider(password: password)
        )

        #expect(try decryptor.decrypt(
            encrypted,
            domain: domain,
            source: .chrome,
            databaseVersion: 24
        ) == "private-value")

        do {
            _ = try decryptor.decrypt(
                encrypted,
                domain: ".other.example",
                source: .chrome,
                databaseVersion: 24
            )
            Issue.record("Expected the v24 domain hash mismatch to fail")
        } catch let error as ChromiumCookieDecryptionError {
            #expect(error == .domainBindingMismatch)
        }
    }

    @Test("safari importer reads history database and fails soft for cookie files")
    func safariImporterReadsHistoryAndSkipsUnsupportedCookies() throws {
        let fixture = try BrowserImportFixture.safari()
        let plan = BrowserImportPlan(
            source: .safari,
            profileID: UUID(),
            explicitLocations: [
                BrowserImportLocation(
                    source: .safari,
                    profileName: "Safari",
                    historyPath: fixture.history,
                    cookiesPath: fixture.cookies,
                    bookmarksPath: nil
                ),
            ]
        )

        let result = try SafariBrowserImporter().preview(plan: plan)

        #expect(result.history.map(\.url) == [
            "https://webkit.example/history",
            "https://webkit.example/history",
        ])
        #expect(result.history[0].visitedAt > result.history[1].visitedAt)
        #expect(result.cookies.isEmpty)
        #expect(result.errors.contains { $0.message.contains("Cookies.binarycookies") })
    }

    @Test("orchestrator does not duplicate an imported history visit")
    func orchestratorDeduplicatesReimportedHistory() throws {
        let profileID = UUID()
        let visitedAt = Date(timeIntervalSince1970: 1_700_000_456)
        let historyStore = try SQLiteBrowserHistoryStore(databasePath: ":memory:")
        let importer = BrowserImporter(
            sourceImporter: StubBrowserSourceImporter(previewResult: BrowserImportPreview(
                history: [BrowserImportedHistoryVisit(
                    url: "https://example.com/reimport",
                    title: "Reimport",
                    visitedAt: visitedAt
                )],
                cookies: [],
                bookmarks: [],
                errors: []
            )),
            historyStore: historyStore,
            bookmarkStore: nil,
            cookieStore: nil,
            auditLogger: nil
        )
        let plan = BrowserImportPlan(
            source: .chrome,
            profileID: profileID,
            importCookies: false,
            importBookmarks: false
        )

        let first = try importer.importData(plan)
        let second = try importer.importData(plan)

        #expect(first.importedHistoryCount == 1)
        #expect(second.importedHistoryCount == 0)
        #expect(second.skippedCount == 1)
        #expect(try historyStore.recentHistory(profileID: profileID, limit: 10).count == 1)
    }

    @Test("orchestrator imports profile-scoped history and bookmarks with audit entries")
    func orchestratorImportsIntoStoresAndAudit() throws {
        let profileID = UUID()
        let historyStore = try SQLiteBrowserHistoryStore(databasePath: ":memory:")
        let bookmarkStore = InMemoryBrowserImportBookmarkStore()
        let cookieStore = InMemoryBrowserImportCookieStore()
        let auditLogger = InMemoryBrowserImportAuditLogger()
        let visitedAt = Date(timeIntervalSince1970: 1_700_000_123)
        let importer = BrowserImporter(
            sourceImporter: StubBrowserSourceImporter(previewResult: BrowserImportPreview(
                history: [
                    BrowserImportedHistoryVisit(
                        url: "https://example.com/imported",
                        title: "Imported",
                        visitedAt: visitedAt
                    ),
                ],
                cookies: [
                    BrowserImportedCookie(
                        domain: ".example.com",
                        name: "session",
                        path: "/",
                        value: "abc",
                        expiresAt: nil,
                        isSecure: true,
                        isHTTPOnly: true
                    ),
                ],
                bookmarks: [
                    BrowserImportedBookmark(title: "Imported Bookmark", url: "https://example.com/bookmark"),
                ],
                errors: []
            )),
            historyStore: historyStore,
            bookmarkStore: bookmarkStore,
            cookieStore: cookieStore,
            auditLogger: auditLogger
        )

        let result = try importer.importData(BrowserImportPlan(source: .chrome, profileID: profileID))

        #expect(result.importedHistoryCount == 1)
        #expect(result.importedCookieCount == 1)
        #expect(result.importedBookmarkCount == 1)
        let history = try historyStore.recentHistory(profileID: profileID, limit: 10)
        #expect(history.count == 1)
        #expect(abs(history[0].timestamp.timeIntervalSince(visitedAt)) < 0.001)
        #expect(try bookmarkStore.loadAll().contains {
            !$0.isFolder && $0.title == "Imported Bookmark"
        })
        #expect(cookieStore.cookies.first?.domain == ".example.com")
        #expect(auditLogger.entries.count == 1)
    }

    @Test("orchestrator refuses changed data before writing any destination")
    func orchestratorRejectsChangedPreviewBeforeWrites() throws {
        let profileID = UUID()
        let location = BrowserImportLocation(
            source: .chrome,
            profileName: "Default",
            historyPath: URL(fileURLWithPath: "/fixture/Default/History"),
            cookiesPath: URL(fileURLWithPath: "/fixture/Default/Cookies"),
            bookmarksPath: URL(fileURLWithPath: "/fixture/Default/Bookmarks")
        )
        let reviewed = BrowserImportPreview(
            history: [BrowserImportedHistoryVisit(
                url: "https://example.com/history",
                title: "Reviewed",
                visitedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )],
            cookies: [BrowserImportedCookie(
                domain: ".example.com",
                name: "session",
                path: "/",
                value: nil,
                expiresAt: nil,
                isSecure: true,
                isHTTPOnly: true,
                sourceValueFingerprint: BrowserImportPreviewToken.fingerprint(Data("cookie".utf8))
            )],
            bookmarks: [BrowserImportedBookmark(
                title: "Reviewed bookmark",
                url: "https://example.com/bookmark"
            )],
            errors: []
        )
        var changed = reviewed
        changed.history = [BrowserImportedHistoryVisit(
            url: "https://example.com/history",
            title: "Changed",
            visitedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )]
        let basePlan = BrowserImportPlan(
            source: .chrome,
            profileID: profileID,
            explicitLocations: [location]
        )
        let boundPlan = BrowserImportPlan(
            source: .chrome,
            profileID: profileID,
            explicitLocations: [location],
            expectedPreviewToken: BrowserImportPreviewToken.make(preview: reviewed, plan: basePlan)
        )
        let historyStore = try SQLiteBrowserHistoryStore(databasePath: ":memory:")
        let bookmarkStore = InMemoryBrowserImportBookmarkStore()
        let cookieStore = InMemoryBrowserImportCookieStore()
        let auditLogger = InMemoryBrowserImportAuditLogger()
        let importer = BrowserImporter(
            sourceImporter: PreviewThenRunBrowserSourceImporter(reviewed: reviewed, imported: changed),
            historyStore: historyStore,
            bookmarkStore: bookmarkStore,
            cookieStore: cookieStore,
            auditLogger: auditLogger
        )

        do {
            _ = try importer.importData(boundPlan)
            Issue.record("Expected changed source data to fail before writes")
        } catch let error as BrowserImportError {
            #expect(error == .sourceChangedAfterPreview)
        }

        #expect(try historyStore.recentHistory(profileID: profileID, limit: 10).isEmpty)
        #expect(try bookmarkStore.loadAll().isEmpty)
        #expect(cookieStore.cookies.isEmpty)
        #expect(auditLogger.entries.count == 1)
        #expect(auditLogger.entries.first?.status == .failed)
    }

    @Test("orchestrator records failed zero-data runs and partial write failures")
    func orchestratorAuditsFailureAndPartialResults() throws {
        let failedAudit = InMemoryBrowserImportAuditLogger()
        let emptyImporter = BrowserImporter(
            sourceImporter: StubBrowserSourceImporter(previewResult: .empty),
            historyStore: nil,
            bookmarkStore: nil,
            cookieStore: nil,
            auditLogger: failedAudit
        )
        do {
            _ = try emptyImporter.importData(BrowserImportPlan(source: .chrome, profileID: UUID()))
            Issue.record("Expected an empty import to fail")
        } catch let error as BrowserImportError {
            guard case .noImportableData = error else {
                Issue.record("Unexpected empty import error: \(error)")
                return
            }
        }
        #expect(failedAudit.entries.count == 1)
        #expect(failedAudit.entries.first?.status == .failed)

        let partialAudit = InMemoryBrowserImportAuditLogger()
        let bookmarkStore = InMemoryBrowserImportBookmarkStore()
        let partialImporter = BrowserImporter(
            sourceImporter: StubBrowserSourceImporter(previewResult: BrowserImportPreview(
                history: [BrowserImportedHistoryVisit(
                    url: "https://example.com/history",
                    title: "History",
                    visitedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )],
                cookies: [],
                bookmarks: [BrowserImportedBookmark(
                    title: "Bookmark",
                    url: "https://example.com/bookmark"
                )],
                errors: []
            )),
            historyStore: FailingBrowserImportHistoryStore(),
            bookmarkStore: bookmarkStore,
            cookieStore: nil,
            auditLogger: partialAudit
        )
        let partial = try partialImporter.importData(BrowserImportPlan(
            source: .chrome,
            profileID: UUID(),
            importCookies: false
        ))

        #expect(partial.status == .partial)
        #expect(partial.importedHistoryCount == 0)
        #expect(partial.importedBookmarkCount == 1)
        #expect(partial.skippedCount == 1)
        #expect(partialAudit.entries.count == 1)
        #expect(partialAudit.entries.first?.status == .partial)
    }

    @Test("orchestrator reports bookmark writes that partially succeed")
    func orchestratorCountsPartialBookmarkWrites() throws {
        let bookmarkStore = FailAfterBrowserImportBookmarkStore(successfulSaveLimit: 2)
        let auditLogger = InMemoryBrowserImportAuditLogger()
        let importer = BrowserImporter(
            sourceImporter: StubBrowserSourceImporter(previewResult: BrowserImportPreview(
                history: [],
                cookies: [],
                bookmarks: [
                    BrowserImportedBookmark(title: "First", url: "https://example.com/first"),
                    BrowserImportedBookmark(title: "Second", url: "https://example.com/second"),
                ],
                errors: []
            )),
            historyStore: nil,
            bookmarkStore: bookmarkStore,
            cookieStore: nil,
            auditLogger: auditLogger
        )

        let result = try importer.importData(BrowserImportPlan(
            source: .chrome,
            profileID: UUID(),
            importCookies: false,
            importHistory: false
        ))

        #expect(result.status == .partial)
        #expect(result.importedBookmarkCount == 1)
        #expect(result.skippedCount == 1)
        #expect(result.errors.contains { $0.message.contains("Skipped 1 bookmarks") })
        #expect(try bookmarkStore.loadAll().filter { !$0.isFolder }.map(\.title) == ["First"])
        #expect(auditLogger.entries.first?.importedBookmarkCount == 1)
        #expect(auditLogger.entries.first?.status == .partial)
    }

    @Test("orchestrator preserves exact cookie counts after a partial batch")
    func orchestratorCountsPartialCookieWrites() throws {
        let cookies = (0..<3).map { index in
            BrowserImportedCookie(
                domain: ".example.com",
                name: "session-\(index)",
                path: "/",
                value: "value-\(index)",
                expiresAt: nil,
                isSecure: true,
                isHTTPOnly: true
            )
        }
        let auditLogger = InMemoryBrowserImportAuditLogger()
        let importer = BrowserImporter(
            sourceImporter: StubBrowserSourceImporter(previewResult: BrowserImportPreview(
                history: [],
                cookies: cookies,
                bookmarks: [],
                errors: []
            )),
            historyStore: nil,
            bookmarkStore: nil,
            cookieStore: PartiallyFailingBrowserImportCookieStore(importedCount: 1),
            auditLogger: auditLogger
        )

        let result = try importer.importData(BrowserImportPlan(
            source: .chrome,
            profileID: UUID(),
            importHistory: false,
            importBookmarks: false
        ))

        #expect(result.status == .partial)
        #expect(result.importedCookieCount == 1)
        #expect(result.skippedCount == 2)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].message.contains("Imported 1 of 3 cookies"))
        #expect(auditLogger.entries.first?.importedCookieCount == 1)
        #expect(auditLogger.entries.first?.skippedCount == 2)
    }

    @Test("file audit logger creates private append-only metadata")
    func fileAuditLoggerUsesPrivatePermissions() throws {
        let root = try BrowserImportFixture.temporaryDirectory("audit")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("nested/browser-import.jsonl")
        let logger = FileBrowserImportAuditLogger(fileURL: file)
        let entry = BrowserImportAuditEntry(
            runID: UUID(),
            source: .firefox,
            sourceProfile: "default-release",
            targetProfileID: UUID(),
            status: .completed,
            importedHistoryCount: 1,
            importedCookieCount: 0,
            importedBookmarkCount: 0,
            skippedCount: 0,
            issueCount: 0,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try logger.record(entry)
        try logger.record(entry)

        let fileMode = try #require(
            FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        ).intValue & 0o777
        let directoryMode = try #require(
            FileManager.default.attributesOfItem(atPath: file.deletingLastPathComponent().path)[.posixPermissions]
                as? NSNumber
        ).intValue & 0o777
        let lines = try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)

        #expect(fileMode == 0o600)
        #expect(directoryMode == 0o700)
        #expect(lines.count == 2)

        let redirectedDirectory = root.appendingPathComponent("redirected", isDirectory: true)
        try FileManager.default.createDirectory(at: redirectedDirectory, withIntermediateDirectories: false)
        let linkedDirectory = root.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: linkedDirectory,
            withDestinationURL: redirectedDirectory
        )
        let redirectedFile = redirectedDirectory.appendingPathComponent("browser-import.jsonl")
        do {
            try FileBrowserImportAuditLogger(
                fileURL: linkedDirectory.appendingPathComponent("browser-import.jsonl")
            ).record(entry)
            Issue.record("Expected an audit path with a symbolic parent to fail")
        } catch let error as BrowserImportError {
            #expect(error == .invalidSourceFile(linkedDirectory.appendingPathComponent("browser-import.jsonl").path))
        }
        #expect(!FileManager.default.fileExists(atPath: redirectedFile.path))
    }

    @Test("browser import wizard completes all four validated steps")
    @MainActor
    func browserImportWizardStateMachineCompletes() async throws {
        let destination = BrowserProfile(name: "Personal", isDefault: true)
        let location = BrowserImportLocation(
            source: .chrome,
            profileName: "Work",
            profileIdentifier: "Profile 7",
            historyPath: URL(fileURLWithPath: "/fixture/Profile 7/History"),
            cookiesPath: URL(fileURLWithPath: "/fixture/Profile 7/Network/Cookies"),
            bookmarksPath: URL(fileURLWithPath: "/fixture/Profile 7/Bookmarks")
        )
        let preview = BrowserImportPreview(
            history: [BrowserImportedHistoryVisit(
                url: "https://example.com",
                title: "Example",
                visitedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )],
            cookies: [],
            bookmarks: [],
            errors: []
        )
        let result = BrowserImportResult(
            runID: UUID(),
            status: .completed,
            sourceProfile: "Work",
            importedHistoryCount: 1,
            importedCookieCount: 0,
            importedBookmarkCount: 0,
            skippedCount: 0,
            errors: []
        )
        let service = StubBrowserImportService(
            discoveries: [BrowserImportSourceDiscovery(
                source: .chrome,
                profiles: [BrowserImportSourceProfile(
                    location: location,
                    availableData: [.history]
                )]
            )],
            previewResult: preview,
            importResult: result
        )
        let viewModel = BrowserImportViewModel(
            destinationProfiles: [destination],
            initialDestinationProfileID: destination.id,
            historyDestinationAvailable: true,
            cookieDestinationAvailable: true,
            bookmarkDestinationAvailable: true,
            service: service,
            destinationProfileProvider: { [destination] in [destination] }
        )

        viewModel.start()
        #expect(await BrowserImportFixture.waitUntil { !viewModel.isDiscovering })
        #expect(viewModel.canAdvance)
        viewModel.advance()
        #expect(viewModel.step == .data)
        #expect(viewModel.importHistory)
        #expect(!viewModel.importCookies)
        viewModel.advance()
        #expect(viewModel.step == .filters)
        viewModel.domainAllowList = "https://invalid.example"
        #expect(!viewModel.canAdvance)
        viewModel.domainAllowList = "example.com"
        #expect(viewModel.canAdvance)
        viewModel.advance()
        #expect(viewModel.step == .review)
        #expect(await BrowserImportFixture.waitUntil { viewModel.preview != nil })
        #expect(viewModel.makePlan()?.sourceProfile == "Profile 7")
        #expect(viewModel.makePlan()?.expectedPreviewToken.map(BrowserImportPreviewToken.isValid) == true)
        viewModel.advance()
        #expect(await BrowserImportFixture.waitUntil { viewModel.result != nil })
        #expect(viewModel.result?.status == .completed)
    }

    @Test("browser import wizard invalidates stale review and supports retry")
    @MainActor
    func browserImportWizardRetriesAfterSourceChange() async throws {
        let destination = BrowserProfile(name: "Personal", isDefault: true)
        let location = BrowserImportLocation(
            source: .chrome,
            profileName: "Work",
            profileIdentifier: "Profile 7",
            historyPath: URL(fileURLWithPath: "/fixture/Profile 7/History"),
            cookiesPath: nil,
            bookmarksPath: nil
        )
        let preview = BrowserImportPreview(
            history: [BrowserImportedHistoryVisit(
                url: "https://example.com",
                title: "Example",
                visitedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )],
            cookies: [],
            bookmarks: [],
            errors: []
        )
        let service = SourceChangedBrowserImportService(
            discoveries: [BrowserImportSourceDiscovery(
                source: .chrome,
                profiles: [BrowserImportSourceProfile(
                    location: location,
                    availableData: [.history]
                )]
            )],
            previewResult: preview
        )
        let viewModel = BrowserImportViewModel(
            destinationProfiles: [destination],
            initialDestinationProfileID: destination.id,
            historyDestinationAvailable: true,
            cookieDestinationAvailable: true,
            bookmarkDestinationAvailable: true,
            service: service,
            destinationProfileProvider: { [destination] in [destination] }
        )

        viewModel.start()
        #expect(await BrowserImportFixture.waitUntil { !viewModel.isDiscovering })
        viewModel.advance()
        viewModel.advance()
        viewModel.advance()
        #expect(await BrowserImportFixture.waitUntil { viewModel.preview != nil })
        #expect(viewModel.makePlan()?.expectedPreviewToken != nil)

        viewModel.advance()

        #expect(await BrowserImportFixture.waitUntil { !viewModel.isImporting })
        #expect(viewModel.failure == .sourceChanged)
        #expect(viewModel.preview == nil)
        #expect(viewModel.makePlan()?.expectedPreviewToken == nil)
        #expect(!viewModel.canAdvance)

        viewModel.retryPreview()
        #expect(await BrowserImportFixture.waitUntil { viewModel.preview != nil })
        #expect(viewModel.failure == nil)
        #expect(viewModel.makePlan()?.expectedPreviewToken != nil)
    }

    @Test("browser import preview cancellation reaches the active source reader")
    @MainActor
    func browserImportPreviewCancellationPropagates() async throws {
        let destination = BrowserProfile(name: "Personal", isDefault: true)
        let location = BrowserImportLocation(
            source: .chrome,
            profileName: "Work",
            profileIdentifier: "Profile 7",
            historyPath: URL(fileURLWithPath: "/fixture/Profile 7/History"),
            cookiesPath: nil,
            bookmarksPath: nil
        )
        let service = CancellationAwareBrowserImportService(discoveries: [
            BrowserImportSourceDiscovery(
                source: .chrome,
                profiles: [BrowserImportSourceProfile(
                    location: location,
                    availableData: [.history]
                )]
            ),
        ])
        let viewModel = BrowserImportViewModel(
            destinationProfiles: [destination],
            initialDestinationProfileID: destination.id,
            historyDestinationAvailable: true,
            cookieDestinationAvailable: true,
            bookmarkDestinationAvailable: true,
            service: service,
            destinationProfileProvider: { [destination] in [destination] }
        )
        defer { viewModel.cancelPendingWork() }

        viewModel.start()
        #expect(await BrowserImportFixture.waitUntil { !viewModel.isDiscovering })
        viewModel.advance()
        viewModel.advance()
        viewModel.advance()
        #expect(viewModel.step == .review)
        #expect(await BrowserImportFixture.waitUntil { service.didStartPreview })

        viewModel.goBack()

        #expect(await BrowserImportFixture.waitUntil { service.didCancelPreview })
        #expect(viewModel.step == .filters)
        #expect(!viewModel.isPreviewing)
        #expect(viewModel.preview == nil)
        #expect(viewModel.failure == nil)
    }

    @Test("WebKit cookie store forwards imported cookies to active profile storage")
    @MainActor
    func webKitCookieStoreForwardsCookiesToActiveProfileStorage() throws {
        let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let viewModel = BrowserViewModel()
        viewModel.activeProfileID = profileID
        let imported = BrowserImportedCookie(
            domain: "example.com",
            name: "session",
            path: "/",
            value: "abc",
            expiresAt: nil,
            isSecure: false,
            isHTTPOnly: true
        )
        var capturedCookie: BrowserImportedCookie?
        var capturedProfileID: UUID?
        viewModel.cookieImporter = { cookie, profile, _ in
            capturedCookie = cookie
            capturedProfileID = profile
            return .success
        }
        let store = BrowserWebKitCookieImportStore(viewModelProvider: { viewModel })

        try store.saveImportedCookie(imported, profileID: profileID)

        #expect(capturedCookie == imported)
        #expect(capturedProfileID == profileID)
    }

    @Test("WebKit cookie store imports a batch without an active browser pane")
    @MainActor
    func webKitCookieStoreImportsBatchWithoutActivePane() async throws {
        let profileID = UUID()
        let imported = [
            BrowserImportedCookie(
                domain: "batch.example",
                name: "first",
                path: "/",
                value: "one",
                expiresAt: Date().addingTimeInterval(3_600),
                isSecure: true,
                isHTTPOnly: true,
                sameSite: .lax
            ),
            BrowserImportedCookie(
                domain: "batch.example",
                name: "second",
                path: "/",
                value: "two",
                expiresAt: Date().addingTimeInterval(3_600),
                isSecure: false,
                isHTTPOnly: false
            ),
        ]
        let providerCalls = LockedBox(0)
        let store = BrowserWebKitCookieImportStore(
            viewModelProvider: {
                providerCalls.withValue { $0 += 1 }
                return nil
            },
            timeout: 5
        )

        try await Task.detached {
            try store.saveImportedCookies(imported, profileID: profileID)
        }.value

        #expect(providerCalls.withValue { $0 } == 0)
        let dataStore = WKWebsiteDataStore(forIdentifier: profileID)
        let cookies = await BrowserImportFixture.cookies(in: dataStore)
        #expect(Set(cookies.filter { $0.domain == "batch.example" }.map(\.name)) == ["first", "second"])
        await BrowserImportFixture.removeAllData(from: dataStore)
    }

    @Test("WebKit cookie batches stop on a closed boundary with exact counts")
    @MainActor
    func webKitCookieBatchBudgetHasNoTrailingWrites() async throws {
        let profileID = UUID()
        let imported = ["first", "second"].map { name in
            BrowserImportedCookie(
                domain: "budget.example",
                name: name,
                path: "/",
                value: name,
                expiresAt: Date().addingTimeInterval(3_600),
                isSecure: true,
                isHTTPOnly: true
            )
        }
        let store = BrowserWebKitCookieImportStore(timeout: 0, batchSize: 1)

        do {
            try await Task.detached {
                try store.saveImportedCookies(imported, profileID: profileID)
            }.value
            Issue.record("Expected the second cookie batch to remain unstarted")
        } catch let error as BrowserImportedCookieBatchWriteError {
            #expect(error.importedCount == 1)
            #expect(error.totalCount == 2)
        }

        try? await Task.sleep(nanoseconds: 100_000_000)
        let dataStore = WKWebsiteDataStore(forIdentifier: profileID)
        let cookies = await BrowserImportFixture.cookies(in: dataStore)
            .filter { $0.domain == "budget.example" }
        #expect(cookies.map(\.name) == ["first"])
        await BrowserImportFixture.removeAllData(from: dataStore)
    }
}

private enum BrowserImportFixture {
    struct SQLitePair {
        let history: URL
        let cookies: URL
    }

    static func chromium() throws -> SQLitePair {
        let root = try temporaryDirectory("chromium")
        let history = root.appendingPathComponent("History")
        let cookies = root.appendingPathComponent("Cookies")
        try createDatabase(history, statements: [
            "CREATE TABLE urls(id INTEGER PRIMARY KEY, url TEXT NOT NULL, title TEXT, last_visit_time INTEGER NOT NULL)",
            "INSERT INTO urls(id, url, title, last_visit_time) VALUES (1, 'https://example.com/docs', 'Docs', 13359571200000000)",
            "CREATE TABLE visits(id INTEGER PRIMARY KEY, url INTEGER NOT NULL, visit_time INTEGER NOT NULL)",
            "INSERT INTO visits(id, url, visit_time) VALUES (1, 1, 13359571100000000)",
            "INSERT INTO visits(id, url, visit_time) VALUES (2, 1, 13359571200000000)",
        ])
        try createDatabase(cookies, statements: [
            "CREATE TABLE cookies(host_key TEXT, name TEXT, path TEXT, value TEXT, encrypted_value BLOB, expires_utc INTEGER, is_secure INTEGER, is_httponly INTEGER)",
            "INSERT INTO cookies(host_key, name, path, value, encrypted_value, expires_utc, is_secure, is_httponly) VALUES ('.example.com', 'session', '/', 'abc', X'', 0, 1, 1)",
        ])
        return SQLitePair(history: history, cookies: cookies)
    }

    static func firefox() throws -> SQLitePair {
        let root = try temporaryDirectory("firefox")
        let history = root.appendingPathComponent("places.sqlite")
        let cookies = root.appendingPathComponent("cookies.sqlite")
        try createDatabase(history, statements: [
            "CREATE TABLE moz_places(id INTEGER PRIMARY KEY, url TEXT NOT NULL, title TEXT, last_visit_date INTEGER)",
            "INSERT INTO moz_places(id, url, title, last_visit_date) VALUES (1, 'https://mozilla.example/start', 'Start', 1770000000000000)",
            "CREATE TABLE moz_historyvisits(id INTEGER PRIMARY KEY, place_id INTEGER NOT NULL, visit_date INTEGER NOT NULL)",
            "INSERT INTO moz_historyvisits(id, place_id, visit_date) VALUES (1, 1, 1769999999000000)",
            "INSERT INTO moz_historyvisits(id, place_id, visit_date) VALUES (2, 1, 1770000000000000)",
            "CREATE TABLE moz_bookmarks(id INTEGER PRIMARY KEY, parent INTEGER, position INTEGER, type INTEGER, title TEXT, fk INTEGER, dateAdded INTEGER)",
            "INSERT INTO moz_bookmarks(id, parent, position, type, title, fk, dateAdded) VALUES (10, 1, 0, 2, 'Toolbar', NULL, 1770000000000000)",
            "INSERT INTO moz_bookmarks(id, parent, position, type, title, fk, dateAdded) VALUES (11, 10, 3, 1, 'Mozilla Start', 1, 1770000000000000)",
        ])
        try createDatabase(cookies, statements: [
            "CREATE TABLE moz_cookies(host TEXT, name TEXT, path TEXT, value TEXT, expiry INTEGER, isSecure INTEGER, isHttpOnly INTEGER)",
            "INSERT INTO moz_cookies(host, name, path, value, expiry, isSecure, isHttpOnly) VALUES ('.mozilla.example', 'sid', '/', 'fire', 0, 1, 0)",
        ])
        return SQLitePair(history: history, cookies: cookies)
    }

    static func chromiumBookmarks() throws -> URL {
        let root = try temporaryDirectory("chromium-bookmarks")
        let url = root.appendingPathComponent("Bookmarks")
        let document: [String: Any] = [
            "roots": [
                "bookmark_bar": [
                    "name": "Bookmarks Bar",
                    "children": [[
                        "type": "folder",
                        "name": "Docs",
                        "children": [[
                            "type": "url",
                            "name": "Cocxy Docs",
                            "url": "https://example.com/docs",
                            "date_added": "13359571200000000",
                        ]],
                    ]],
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: document).write(to: url)
        return url
    }

    static func safariBookmarks() throws -> URL {
        let root = try temporaryDirectory("safari-bookmarks")
        let url = root.appendingPathComponent("Bookmarks.plist")
        let document: [String: Any] = [
            "Children": [[
                "Title": "Reading",
                "Children": [[
                    "URLString": "https://webkit.example/guide",
                    "URIDictionary": ["title": "WebKit Guide"],
                ]],
            ]],
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: document,
            format: .binary,
            options: 0
        )
        try data.write(to: url)
        return url
    }

    static func safariBinaryCookies() throws -> URL {
        let root = try temporaryDirectory("safari-binary-cookies")
        let url = root.appendingPathComponent("Cookies.binarycookies")

        var record = Data(repeating: 0, count: 56)
        let domainOffset = appendCString(".example.com", to: &record)
        let nameOffset = appendCString("session", to: &record)
        let pathOffset = appendCString("/", to: &record)
        let valueOffset = appendCString("private-value", to: &record)
        setUInt32LE(UInt32(record.count), in: &record, at: 0)
        setUInt32LE(0x5, in: &record, at: 8)
        setUInt32LE(domainOffset, in: &record, at: 16)
        setUInt32LE(nameOffset, in: &record, at: 20)
        setUInt32LE(pathOffset, in: &record, at: 24)
        setUInt32LE(valueOffset, in: &record, at: 28)
        setDoubleLE(800_000_000, in: &record, at: 40)
        setDoubleLE(700_000_000, in: &record, at: 48)

        var page = Data(repeating: 0, count: 16)
        setUInt32LE(0x0000_0100, in: &page, at: 0)
        setUInt32LE(1, in: &page, at: 4)
        setUInt32LE(16, in: &page, at: 8)
        page.append(record)

        var file = Data("cook".utf8)
        appendUInt32BE(1, to: &file)
        appendUInt32BE(UInt32(page.count), to: &file)
        file.append(page)
        try file.write(to: url)
        return url
    }

    static func oversizedSQLiteValues() throws -> URL {
        let root = try temporaryDirectory("oversized-values")
        let database = root.appendingPathComponent("oversized.sqlite")
        try createDatabase(database, statements: [
            "CREATE TABLE payload(large_text TEXT NOT NULL, large_blob BLOB NOT NULL)",
            "INSERT INTO payload VALUES (printf('%.*c', 16385, 'x'), zeroblob(1048577))",
        ])
        return database
    }

    static func chromiumHistory(visitCount: Int) throws -> URL {
        let root = try temporaryDirectory("chromium-history-limit")
        let database = root.appendingPathComponent("History")
        try createDatabase(database, statements: [
            "CREATE TABLE urls(id INTEGER PRIMARY KEY, url TEXT NOT NULL, title TEXT, last_visit_time INTEGER)",
            "CREATE TABLE visits(id INTEGER PRIMARY KEY, url INTEGER NOT NULL, visit_time INTEGER NOT NULL)",
            "INSERT INTO urls(id, url, title, last_visit_time) VALUES (1, 'https://limit.example/path', 'Limit', 13359571200000000)",
            "WITH RECURSIVE sequence(value) AS (SELECT 1 UNION ALL SELECT value + 1 FROM sequence WHERE value < \(visitCount)) INSERT INTO visits(id, url, visit_time) SELECT value, 1, 13359571200000000 + value FROM sequence",
        ])
        return database
    }

    static func firefoxDuplicateFolders() throws -> URL {
        let root = try temporaryDirectory("firefox-duplicate-folders")
        let database = root.appendingPathComponent("places.sqlite")
        try createDatabase(database, statements: [
            "CREATE TABLE moz_places(id INTEGER PRIMARY KEY, url TEXT, title TEXT, last_visit_date INTEGER)",
            "CREATE TABLE moz_bookmarks(id INTEGER, parent INTEGER, position INTEGER, type INTEGER, title TEXT, fk INTEGER, dateAdded INTEGER)",
            "INSERT INTO moz_places(id, url, title) VALUES (1, 'https://example.com', 'Example')",
            "INSERT INTO moz_bookmarks VALUES (10, 0, 0, 2, 'First', NULL, 1700000000000000)",
            "INSERT INTO moz_bookmarks VALUES (10, 0, 1, 2, 'Duplicate', NULL, 1700000000000001)",
            "INSERT INTO moz_bookmarks VALUES (11, 10, 0, 1, 'Example', 1, 1700000000000002)",
        ])
        return database
    }

    static func chromiumEncryptedCookie(
        value: String,
        domain: String,
        password: Data,
        bindDomain: Bool
    ) throws -> Data {
        var plaintext = Data()
        if bindDomain {
            plaintext.append(Data(SHA256.hash(data: Data(domain.utf8))))
        }
        plaintext.append(Data(value.utf8))

        let salt = Data("saltysalt".utf8)
        var key = Data(repeating: 0, count: kCCKeySizeAES128)
        let keyByteCount = key.count
        let derivationStatus = key.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1_003,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyByteCount
                    )
                }
            }
        }
        guard derivationStatus == kCCSuccess else { throw BrowserImportFixtureError.cryptoFailed }

        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var encrypted = Data(repeating: 0, count: plaintext.count + kCCBlockSizeAES128)
        let outputByteCount = encrypted.count
        var outputLength = 0
        let encryptionStatus = encrypted.withUnsafeMutableBytes { outputBytes in
            plaintext.withUnsafeBytes { plaintextBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            plaintextBytes.baseAddress,
                            plaintext.count,
                            outputBytes.baseAddress,
                            outputByteCount,
                            &outputLength
                        )
                    }
                }
            }
        }
        guard encryptionStatus == kCCSuccess else { throw BrowserImportFixtureError.cryptoFailed }
        encrypted.removeSubrange(outputLength..<encrypted.count)
        var result = Data("v10".utf8)
        result.append(encrypted)
        return result
    }

    static func safari() throws -> SQLitePair {
        let root = try temporaryDirectory("safari")
        let history = root.appendingPathComponent("History.db")
        let cookies = root.appendingPathComponent("Cookies.binarycookies")
        try createDatabase(history, statements: [
            "CREATE TABLE history_items(id INTEGER PRIMARY KEY, url TEXT NOT NULL, title TEXT)",
            "CREATE TABLE history_visits(id INTEGER PRIMARY KEY, history_item INTEGER NOT NULL, visit_time REAL NOT NULL)",
            "INSERT INTO history_items(id, url, title) VALUES (1, 'https://webkit.example/history', 'History')",
            "INSERT INTO history_visits(id, history_item, visit_time) VALUES (1, 1, 764294400)",
            "INSERT INTO history_visits(id, history_item, visit_time) VALUES (2, 1, 764294500)",
        ])
        try Data("unsupported".utf8).write(to: cookies)
        return SQLitePair(history: history, cookies: cookies)
    }

    static func temporaryDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-browser-import-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func createDatabase(_ url: URL, statements: [String]) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw BrowserImportFixtureError.databaseOpen
        }
        defer { sqlite3_close(db) }
        for statement in statements {
            guard sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK else {
                throw BrowserImportFixtureError.statementFailed(statement)
            }
        }
    }

    @MainActor
    static func waitUntil(
        timeout: TimeInterval = 3,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    @MainActor
    static func cookies(in dataStore: WKWebsiteDataStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    @MainActor
    static func removeAllData(from dataStore: WKWebsiteDataStore) async {
        await withCheckedContinuation { continuation in
            dataStore.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            ) {
                continuation.resume()
            }
        }
    }

    private static func appendCString(_ value: String, to data: inout Data) -> UInt32 {
        let offset = UInt32(data.count)
        data.append(Data(value.utf8))
        data.append(0)
        return offset
    }

    private static func setUInt32LE(_ value: UInt32, in data: inout Data, at offset: Int) {
        for index in 0..<4 {
            data[offset + index] = UInt8(truncatingIfNeeded: value >> UInt32(index * 8))
        }
    }

    private static func appendUInt32BE(_ value: UInt32, to data: inout Data) {
        for shift in stride(from: 24, through: 0, by: -8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    private static func setDoubleLE(_ value: Double, in data: inout Data, at offset: Int) {
        let bits = value.bitPattern
        for index in 0..<8 {
            data[offset + index] = UInt8(truncatingIfNeeded: bits >> UInt64(index * 8))
        }
    }
}

private enum BrowserImportFixtureError: Error {
    case databaseOpen
    case statementFailed(String)
    case cryptoFailed
}

private final class InMemoryBrowserImportCookieStore: BrowserImportedCookieStoring, @unchecked Sendable {
    private(set) var cookies: [BrowserImportedCookie] = []

    func saveImportedCookie(_ cookie: BrowserImportedCookie, profileID: UUID) throws {
        cookies.append(cookie)
    }
}

private struct PartiallyFailingBrowserImportCookieStore: BrowserImportedCookieStoring {
    let importedCount: Int

    func saveImportedCookie(_ cookie: BrowserImportedCookie, profileID: UUID) throws {}

    func saveImportedCookies(_ cookies: [BrowserImportedCookie], profileID: UUID) throws {
        throw BrowserImportedCookieBatchWriteError(
            importedCount: importedCount,
            totalCount: cookies.count,
            detail: "Synthetic batch boundary"
        )
    }
}

private final class InMemoryBrowserImportBookmarkStore: BrowserBookmarkStoring, @unchecked Sendable {
    private var bookmarks: [BrowserBookmark] = []

    func loadAll() throws -> [BrowserBookmark] {
        bookmarks
    }

    func save(_ bookmark: BrowserBookmark) throws {
        bookmarks.append(bookmark)
    }

    func update(_ bookmark: BrowserBookmark) throws {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[index] = bookmark
    }

    func delete(id: UUID) throws {
        bookmarks.removeAll { $0.id == id }
    }

    func move(id: UUID, toParent: UUID?, sortOrder: Int) throws {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[index].parentID = toParent
        bookmarks[index].sortOrder = sortOrder
    }

    func search(query: String) -> [BrowserBookmark] {
        bookmarks.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    func children(of parentID: UUID?) -> [BrowserBookmark] {
        bookmarks.filter { $0.parentID == parentID }
    }
}

private final class FailAfterBrowserImportBookmarkStore: BrowserBookmarkStoring, @unchecked Sendable {
    private let successfulSaveLimit: Int
    private var successfulSaveCount = 0
    private var bookmarks: [BrowserBookmark] = []

    init(successfulSaveLimit: Int) {
        self.successfulSaveLimit = successfulSaveLimit
    }

    func loadAll() throws -> [BrowserBookmark] {
        bookmarks
    }

    func save(_ bookmark: BrowserBookmark) throws {
        guard successfulSaveCount < successfulSaveLimit else {
            throw FailingBrowserImportBookmarkError.writeFailed
        }
        successfulSaveCount += 1
        bookmarks.append(bookmark)
    }

    func update(_ bookmark: BrowserBookmark) throws {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[index] = bookmark
    }

    func delete(id: UUID) throws {
        bookmarks.removeAll { $0.id == id }
    }

    func move(id: UUID, toParent: UUID?, sortOrder: Int) throws {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[index].parentID = toParent
        bookmarks[index].sortOrder = sortOrder
    }

    func search(query: String) -> [BrowserBookmark] {
        bookmarks.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    func children(of parentID: UUID?) -> [BrowserBookmark] {
        bookmarks.filter { $0.parentID == parentID }
    }
}

private final class InMemoryBrowserImportAuditLogger: BrowserImportAuditLogging, @unchecked Sendable {
    private(set) var entries: [BrowserImportAuditEntry] = []

    func record(_ entry: BrowserImportAuditEntry) throws {
        entries.append(entry)
    }
}

private struct StubBrowserSourceImporter: BrowserSourceImporting {
    let previewResult: BrowserImportPreview

    func preview(plan: BrowserImportPlan) throws -> BrowserImportPreview {
        previewResult
    }
}

private struct PreviewThenRunBrowserSourceImporter: BrowserSourceImporting {
    let reviewed: BrowserImportPreview
    let imported: BrowserImportPreview

    func preview(plan: BrowserImportPlan) throws -> BrowserImportPreview {
        plan.readCookieValues ? imported : reviewed
    }
}

private struct StaticSafeStoragePasswordProvider: BrowserSafeStoragePasswordProviding {
    let password: Data

    func password(for source: BrowserImportSource) throws -> Data {
        password
    }
}

private enum FailingBrowserImportHistoryError: Error {
    case writeFailed
}

private enum FailingBrowserImportBookmarkError: Error {
    case writeFailed
}

private struct FailingBrowserImportHistoryStore: BrowserHistoryStoring {
    func recordVisit(url: String, title: String?, profileID: UUID) throws {
        throw FailingBrowserImportHistoryError.writeFailed
    }

    func search(query: String, profileID: UUID?, limit: Int) throws -> [HistoryEntry] { [] }
    func recentHistory(profileID: UUID?, limit: Int) throws -> [HistoryEntry] { [] }
    func deleteByDateRange(from: Date, to: Date, profileID: UUID?) throws {}
    func deleteAll(profileID: UUID?) throws {}
    func groupedByDate(profileID: UUID?, limit: Int) throws -> [DateGroup<HistoryEntry>] { [] }
}

private struct StubBrowserImportService: BrowserImportServicing {
    let discoveries: [BrowserImportSourceDiscovery]
    let previewResult: BrowserImportPreview
    let importResult: BrowserImportResult

    func discoverSources() -> [BrowserImportSourceDiscovery] {
        discoveries
    }

    func preview(_ plan: BrowserImportPlan) throws -> BrowserImportPreview {
        previewResult
    }

    func run(_ plan: BrowserImportPlan) throws -> BrowserImportResult {
        importResult
    }
}

private struct SourceChangedBrowserImportService: BrowserImportServicing {
    let discoveries: [BrowserImportSourceDiscovery]
    let previewResult: BrowserImportPreview

    func discoverSources() -> [BrowserImportSourceDiscovery] {
        discoveries
    }

    func preview(_ plan: BrowserImportPlan) throws -> BrowserImportPreview {
        previewResult
    }

    func run(_ plan: BrowserImportPlan) throws -> BrowserImportResult {
        throw BrowserImportError.sourceChangedAfterPreview
    }
}

private final class CancellationAwareBrowserImportService: BrowserImportServicing, @unchecked Sendable {
    private let discoveries: [BrowserImportSourceDiscovery]
    private let stateLock = NSLock()
    private var previewStarted = false
    private var previewCancelled = false

    var didStartPreview: Bool { state(\.previewStarted) }
    var didCancelPreview: Bool { state(\.previewCancelled) }

    init(discoveries: [BrowserImportSourceDiscovery]) {
        self.discoveries = discoveries
    }

    func discoverSources() -> [BrowserImportSourceDiscovery] {
        discoveries
    }

    func preview(_ plan: BrowserImportPlan) throws -> BrowserImportPreview {
        updateState { $0.previewStarted = true }
        while !Task.isCancelled {
            Thread.sleep(forTimeInterval: 0.002)
        }
        updateState { $0.previewCancelled = true }
        throw BrowserImportError.cancelled
    }

    func run(_ plan: BrowserImportPlan) throws -> BrowserImportResult {
        throw BrowserImportError.cancelled
    }

    private func state(_ keyPath: KeyPath<CancellationState, Bool>) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return CancellationState(
            previewStarted: previewStarted,
            previewCancelled: previewCancelled
        )[keyPath: keyPath]
    }

    private func updateState(_ update: (inout CancellationState) -> Void) {
        stateLock.lock()
        defer { stateLock.unlock() }
        var state = CancellationState(
            previewStarted: previewStarted,
            previewCancelled: previewCancelled
        )
        update(&state)
        previewStarted = state.previewStarted
        previewCancelled = state.previewCancelled
    }

    private struct CancellationState {
        var previewStarted: Bool
        var previewCancelled: Bool
    }
}
