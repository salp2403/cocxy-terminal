// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserImportIssuePrivacySwiftTestingTests.swift - User-visible import error boundaries.

import Foundation
import SQLite3
import Testing
@testable import CocxyTerminal

@Suite("Browser import issue privacy", .serialized)
struct BrowserImportIssuePrivacySwiftTestingTests {
    private static let privateErrorDetail = "/Users/private/Library/browser.db: database is full"

    @Test("history write failures are counted and localized without private details")
    @MainActor
    func historyWriteFailureIsLocalized() throws {
        let importer = BrowserImporter(
            sourceImporter: PrivacyPreviewImporter(preview: BrowserImportPreview(
                history: [BrowserImportedHistoryVisit(
                    url: "https://example.com",
                    title: "Example",
                    visitedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )],
                cookies: [],
                bookmarks: [],
                errors: []
            )),
            historyStore: PrivateFailureHistoryStore(detail: Self.privateErrorDetail),
            bookmarkStore: nil,
            cookieStore: nil
        )

        let result = try importer.importData(BrowserImportPlan(
            source: .chrome,
            profileID: UUID(),
            importCookies: false,
            importBookmarks: false
        ))
        let issue = try #require(result.errors.first)
        let message = BrowserImportWizardView.localizedIssueMessage(
            issue,
            localizer: try spanishLocalizer()
        )

        #expect(issue.kind == .historyWriteFailed(count: 1))
        #expect(message == "Visitas del historial sin guardar: 1.")
        #expect(!issue.message.contains(Self.privateErrorDetail))
        #expect(!message.contains(Self.privateErrorDetail))
    }

    @Test("bookmark write failures are counted and localized without private details")
    @MainActor
    func bookmarkWriteFailureIsLocalized() throws {
        let importer = BrowserImporter(
            sourceImporter: PrivacyPreviewImporter(preview: BrowserImportPreview(
                history: [],
                cookies: [],
                bookmarks: [BrowserImportedBookmark(
                    title: "Example",
                    url: "https://example.com"
                )],
                errors: []
            )),
            historyStore: nil,
            bookmarkStore: PrivateFailureBookmarkStore(detail: Self.privateErrorDetail),
            cookieStore: nil
        )

        let result = try importer.importData(BrowserImportPlan(
            source: .chrome,
            profileID: UUID(),
            importCookies: false,
            importHistory: false
        ))
        let issue = try #require(result.errors.first)
        let message = BrowserImportWizardView.localizedIssueMessage(
            issue,
            localizer: try spanishLocalizer()
        )

        #expect(issue.kind == .bookmarkWriteFailed(count: 1))
        #expect(message == "Marcadores sin guardar: 1.")
        #expect(!issue.message.contains(Self.privateErrorDetail))
        #expect(!message.contains(Self.privateErrorDetail))
    }

    @Test("cookie decryption failures use the real source importer and hide private details")
    @MainActor
    func cookieDecryptionFailureIsLocalized() throws {
        let fixture = try ChromiumCookiePrivacyFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let location = BrowserImportLocation(
            source: .chrome,
            profileName: "Default",
            historyPath: fixture.root.appendingPathComponent("History"),
            cookiesPath: fixture.database,
            bookmarksPath: nil
        )
        let importer = ChromiumBrowserImporter(
            cookieDecryptor: PrivateFailureCookieDecryptor(detail: Self.privateErrorDetail)
        )

        let preview = try importer.preview(plan: BrowserImportPlan(
            source: .chrome,
            profileID: UUID(),
            importHistory: false,
            importBookmarks: false,
            explicitLocations: [location],
            readCookieValues: true
        ))
        let issue = try #require(preview.errors.first)
        let message = BrowserImportWizardView.localizedIssueMessage(
            issue,
            localizer: try spanishLocalizer()
        )

        #expect(preview.cookies.count == 1)
        #expect(issue.kind == .cookieDecryptionFailed(count: 1))
        #expect(message == "Cookies cifradas omitidas: 1.")
        #expect(!issue.message.contains(Self.privateErrorDetail))
        #expect(!message.contains(Self.privateErrorDetail))
    }

    @Test("source read failures are localized without profile paths")
    @MainActor
    func sourceReadFailureIsLocalized() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowserImportReadFailure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let unreadableHistory = root.appendingPathComponent("History", isDirectory: true)
        try FileManager.default.createDirectory(at: unreadableHistory, withIntermediateDirectories: true)

        let preview = try ChromiumBrowserImporter().preview(plan: BrowserImportPlan(
            source: .chrome,
            profileID: UUID(),
            importCookies: false,
            importBookmarks: false,
            explicitLocations: [BrowserImportLocation(
                source: .chrome,
                profileName: "Default",
                historyPath: unreadableHistory,
                cookiesPath: nil,
                bookmarksPath: nil
            )]
        ))
        let issue = try #require(preview.errors.first)
        let message = BrowserImportWizardView.localizedIssueMessage(
            issue,
            localizer: try spanishLocalizer()
        )

        #expect(issue.kind == .sourceReadFailed(.history))
        #expect(message == "No se pudo leer el historial de este perfil del navegador.")
        #expect(!issue.message.contains(root.lastPathComponent))
        #expect(!message.contains(root.lastPathComponent))
    }

    @Test("audit write failures are localized without private details")
    @MainActor
    func auditWriteFailureIsLocalized() throws {
        let importer = BrowserImporter(
            sourceImporter: PrivacyPreviewImporter(preview: BrowserImportPreview(
                history: [BrowserImportedHistoryVisit(
                    url: "https://example.com",
                    title: "Example",
                    visitedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )],
                cookies: [],
                bookmarks: [],
                errors: []
            )),
            historyStore: nil,
            bookmarkStore: nil,
            cookieStore: nil,
            auditLogger: PrivateFailureAuditLogger(detail: Self.privateErrorDetail)
        )

        let result = try importer.importData(BrowserImportPlan(source: .chrome, profileID: UUID()))
        let issue = try #require(result.errors.first { $0.kind == .auditWriteFailed })
        let message = BrowserImportWizardView.localizedIssueMessage(issue, localizer: try spanishLocalizer())

        #expect(message == "La importación terminó, pero no se pudo guardar su registro local de auditoría.")
        #expect(!issue.message.contains(Self.privateErrorDetail))
    }

    @Test("missing browser sources and unavailable storage reach the wizard in the app language")
    @MainActor
    func missingSourcesAndStorageAreLocalized() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowserImportMissing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let preview = try ChromiumBrowserImporter().preview(plan: BrowserImportPlan(
            source: .chrome,
            profileID: UUID(),
            explicitLocations: [BrowserImportLocation(
                source: .chrome,
                profileName: "Default",
                historyPath: root.appendingPathComponent("History"),
                cookiesPath: nil,
                bookmarksPath: nil
            )]
        ))
        let storage = try BrowserImporter(
            sourceImporter: PrivacyPreviewImporter(preview: BrowserImportPreview(
                history: [BrowserImportedHistoryVisit(url: "https://example.com", title: nil, visitedAt: Date())],
                cookies: [BrowserImportedCookie(
                    domain: "example.com",
                    name: "session",
                    path: "/",
                    value: "value",
                    expiresAt: nil,
                    isSecure: true,
                    isHTTPOnly: true
                )],
                bookmarks: [BrowserImportedBookmark(title: "Example", url: "https://example.com")],
                errors: []
            )),
            historyStore: nil,
            bookmarkStore: nil,
            cookieStore: nil
        ).importData(BrowserImportPlan(source: .chrome, profileID: UUID()))
        let localizer = try spanishLocalizer()
        let messages = (preview.errors + storage.errors).map {
            BrowserImportWizardView.localizedIssueMessage($0, localizer: localizer)
        }

        #expect(Set(messages) == [
            "No se encontró ningún archivo de historial en este perfil del navegador.",
            "No se encontró ningún archivo de cookies en este perfil del navegador.",
            "No se encontró ningún archivo de marcadores en este perfil del navegador.",
            "El almacenamiento del historial del navegador de Cocxy no está disponible.",
            "El almacenamiento de cookies del navegador de Cocxy no está disponible.",
            "El almacenamiento de marcadores del navegador de Cocxy no está disponible.",
        ])
        #expect(!messages.contains { $0.contains(root.lastPathComponent) })
    }

    @Test("source limitations reach the wizard in the app language")
    @MainActor
    func sourceLimitationsAreLocalized() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowserImportLimits-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let history = try makeDatabase(root.appendingPathComponent("History"), """
            CREATE TABLE urls(id INTEGER PRIMARY KEY, url TEXT, title TEXT, last_visit_time INTEGER);
            INSERT INTO urls VALUES(1, 'https://example.com', 'Example', 13300000000000000);
            """)
        let chromiumCookies = try makeDatabase(root.appendingPathComponent("Cookies"), """
            CREATE TABLE cookies(host_key TEXT, name TEXT, path TEXT, value TEXT,
                expires_utc INTEGER, is_secure INTEGER, is_httponly INTEGER, top_frame_site_key TEXT);
            INSERT INTO cookies VALUES('.example.com', 'id', '/', 'v', 0, 1, 1, 'https://top.example');
            """)
        let firefoxCookies = try makeDatabase(root.appendingPathComponent("cookies.sqlite"), """
            CREATE TABLE moz_cookies(host TEXT, name TEXT, path TEXT, value TEXT, expiry INTEGER,
                isSecure INTEGER, isHttpOnly INTEGER, originAttributes TEXT);
            INSERT INTO moz_cookies VALUES('.example.com', 'id', '/', 'v', 0, 1, 1, '^userContextId=1');
            """)
        let chromium = try ChromiumBrowserImporter().preview(plan: BrowserImportPlan(
            source: .chrome,
            profileID: UUID(),
            importBookmarks: false,
            explicitLocations: [BrowserImportLocation(
                source: .chrome,
                profileName: "Default",
                historyPath: history,
                cookiesPath: chromiumCookies,
                bookmarksPath: nil
            )]
        ))
        let firefox = try FirefoxBrowserImporter().preview(plan: BrowserImportPlan(
            source: .firefox,
            profileID: UUID(),
            importHistory: false,
            importBookmarks: false,
            explicitLocations: [BrowserImportLocation(
                source: .firefox,
                profileName: "Default",
                historyPath: root.appendingPathComponent("places.sqlite"),
                cookiesPath: firefoxCookies,
                bookmarksPath: nil
            )]
        ))
        let localizer = try spanishLocalizer()
        let messages = Set((chromium.errors + firefox.errors).map {
            BrowserImportWizardView.localizedIssueMessage($0, localizer: localizer)
        })
        let safetyLimit = BrowserImportWizardView.localizedIssueMessage(
            .historySafetyLimit(
                BrowserImportLocation(
                    source: .chrome,
                    profileName: "Default",
                    historyPath: history,
                    cookiesPath: nil,
                    bookmarksPath: nil
                ),
                skipped: 2,
                importLimit: 50_000,
                scanLimit: 60_000
            ),
            localizer: localizer
        )

        #expect(messages == [
            "Este navegador solo guarda la última visita a cada página, así que solo se importaron esas visitas.",
            "Cookies particionadas omitidas porque no se puede conservar su partición: 1.",
            "Cookies de contenedor o particionadas omitidas porque no se puede conservar su aislamiento: 1.",
        ])
        #expect(safetyLimit == "La importación del historial se detuvo en 50000 visitas; visitas coincidentes omitidas: 2. El análisis del historial se detuvo tras las 60000 visitas más recientes; puede haber visitas anteriores sin importar.")
    }

    private func makeDatabase(_ url: URL, _ sql: String) throws -> URL {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
            throw PrivateBrowserImportFailure.operation("fixture open failed")
        }
        defer { sqlite3_close(handle) }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw PrivateBrowserImportFailure.operation("fixture SQL failed")
        }
        return url
    }

    @MainActor
    private func spanishLocalizer() throws -> AppLocalizer {
        let localizationURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Localization", isDirectory: true)
        return AppLocalizer(
            languagePreference: .spanish,
            bundle: try #require(Bundle(url: localizationURL))
        )
    }
}

private enum PrivateBrowserImportFailure: Error {
    case operation(String)
}

private struct PrivateFailureAuditLogger: BrowserImportAuditLogging {
    let detail: String

    func record(_ entry: BrowserImportAuditEntry) throws {
        throw PrivateBrowserImportFailure.operation(detail)
    }
}

private struct PrivacyPreviewImporter: BrowserSourceImporting {
    let preview: BrowserImportPreview

    func preview(plan: BrowserImportPlan) throws -> BrowserImportPreview {
        preview
    }
}

private struct PrivateFailureHistoryStore: BrowserHistoryStoring {
    let detail: String

    func recordVisit(url: String, title: String?, profileID: UUID) throws {
        throw PrivateBrowserImportFailure.operation(detail)
    }

    func search(query: String, profileID: UUID?, limit: Int) throws -> [HistoryEntry] { [] }
    func recentHistory(profileID: UUID?, limit: Int) throws -> [HistoryEntry] { [] }
    func deleteByDateRange(from: Date, to: Date, profileID: UUID?) throws {}
    func deleteAll(profileID: UUID?) throws {}
    func groupedByDate(profileID: UUID?, limit: Int) throws -> [DateGroup<HistoryEntry>] { [] }
}

private struct PrivateFailureBookmarkStore: BrowserBookmarkStoring {
    let detail: String

    func loadAll() throws -> [BrowserBookmark] { [] }
    func save(_ bookmark: BrowserBookmark) throws {}
    func saveBatch(_ bookmarks: [BrowserBookmark]) throws {
        throw PrivateBrowserImportFailure.operation(detail)
    }
    func update(_ bookmark: BrowserBookmark) throws {}
    func delete(id: UUID) throws {}
    func move(id: UUID, toParent: UUID?, sortOrder: Int) throws {}
    func search(query: String) -> [BrowserBookmark] { [] }
    func children(of parentID: UUID?) -> [BrowserBookmark] { [] }
}

private struct PrivateFailureCookieDecryptor: ChromiumCookieDecrypting {
    let detail: String

    func decrypt(
        _ encryptedValue: Data,
        domain: String,
        source: BrowserImportSource,
        databaseVersion: Int?
    ) throws -> String {
        throw PrivateBrowserImportFailure.operation(detail)
    }
}

private struct ChromiumCookiePrivacyFixture {
    let root: URL
    let database: URL

    static func make() throws -> ChromiumCookiePrivacyFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("browser-import-privacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = root.appendingPathComponent("Cookies")
        var handle: OpaquePointer?
        guard sqlite3_open(database.path, &handle) == SQLITE_OK, let handle else {
            throw PrivateBrowserImportFailure.operation("fixture open failed")
        }
        defer { sqlite3_close(handle) }
        try execute(
            """
            CREATE TABLE cookies(
                host_key TEXT,
                name TEXT,
                path TEXT,
                value TEXT,
                encrypted_value BLOB,
                expires_utc INTEGER,
                is_secure INTEGER,
                is_httponly INTEGER
            );
            INSERT INTO cookies VALUES(
                '.example.com', 'session', '/', '', X'76313001020304', 0, 1, 1
            );
            """,
            in: handle
        )
        return ChromiumCookiePrivacyFixture(root: root, database: database)
    }

    private static func execute(_ sql: String, in database: OpaquePointer) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &message) == SQLITE_OK else {
            defer { sqlite3_free(message) }
            throw PrivateBrowserImportFailure.operation(
                message.map { String(cString: $0) } ?? "fixture SQL failed"
            )
        }
    }
}
