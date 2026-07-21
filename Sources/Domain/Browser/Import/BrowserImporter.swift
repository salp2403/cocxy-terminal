// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserImporter.swift - Browser import orchestration into Cocxy-owned stores.

import Darwin
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
        let runID = UUID()
        let sourceProfile = plan.locations().first?.profileName
            ?? plan.sourceProfile
            ?? plan.source.displayName
        let preview: BrowserImportPreview
        do {
            preview = try sourceImporter.preview(plan: plan.readingCookieValues())
        } catch {
            recordFailedAudit(
                runID: runID,
                plan: plan,
                sourceProfile: sourceProfile,
                issueCount: 1
            )
            throw error
        }
        guard preview.itemCount > 0 else {
            recordFailedAudit(
                runID: runID,
                plan: plan,
                sourceProfile: sourceProfile,
                issueCount: max(preview.errors.count, 1)
            )
            throw BrowserImportError.noImportableData(
                "No importable data was found for \(plan.source.displayName) profile \(sourceProfile)"
            )
        }
        if let expectedPreviewToken = plan.expectedPreviewToken,
           BrowserImportPreviewToken.make(preview: preview, plan: plan) != expectedPreviewToken {
            recordFailedAudit(
                runID: runID,
                plan: plan,
                sourceProfile: sourceProfile,
                issueCount: 1
            )
            throw BrowserImportError.sourceChangedAfterPreview
        }

        var importedHistoryCount = 0
        var importedCookieCount = 0
        var importedBookmarkCount = 0
        var skippedCount = preview.skippedCount
        var issues = preview.errors

        if plan.importHistory, let historyStore {
            var failedHistoryCount = 0
            var lastHistoryError: String?
            for visit in preview.history {
                do {
                    let inserted = try historyStore.recordVisitIfNew(
                        url: visit.url,
                        title: visit.title,
                        profileID: plan.profileID,
                        visitedAt: visit.visitedAt
                    )
                    if inserted {
                        importedHistoryCount += 1
                    } else {
                        skippedCount += 1
                    }
                } catch {
                    skippedCount += 1
                    failedHistoryCount += 1
                    lastHistoryError = (error as? LocalizedError)?.errorDescription
                        ?? String(describing: error)
                }
            }
            if failedHistoryCount > 0 {
                let detail = lastHistoryError.map { ": \($0)" } ?? ""
                issues.append(issue(
                    plan,
                    sourceProfile,
                    "Skipped \(failedHistoryCount) history visits after write failures\(detail)"
                ))
            }
        } else if !preview.history.isEmpty {
            skippedCount += preview.history.count
            if plan.importHistory {
                issues.append(issue(plan, sourceProfile, "Browser history storage is unavailable"))
            }
        }

        if plan.importCookies, let cookieStore {
            let cookies = preview.cookies.filter { cookie in
                if cookie.value == nil || cookie.isPartitioned {
                    skippedCount += 1
                    return false
                }
                return true
            }
            if !cookies.isEmpty {
                do {
                    try cookieStore.saveImportedCookies(cookies, profileID: plan.profileID)
                    importedCookieCount += cookies.count
                } catch let error as BrowserImportedCookieBatchWriteError {
                    let completed = min(max(error.importedCount, 0), cookies.count)
                    importedCookieCount += completed
                    skippedCount += cookies.count - completed
                    issues.append(issue(plan, sourceProfile, error.localizedDescription))
                } catch {
                    skippedCount += cookies.count
                    issues.append(issue(plan, sourceProfile, "Cookie write failed: \(error)"))
                }
            }
        } else if !preview.cookies.isEmpty {
            skippedCount += preview.cookies.count
            if plan.importCookies {
                issues.append(issue(plan, sourceProfile, "Browser cookie storage is unavailable"))
            }
        }

        if plan.importBookmarks, let bookmarkStore {
            do {
                let bookmarkResult = try importBookmarks(
                    preview.bookmarks,
                    plan: plan,
                    sourceProfile: sourceProfile,
                    store: bookmarkStore
                )
                importedBookmarkCount += bookmarkResult.imported
                skippedCount += bookmarkResult.skipped
                if bookmarkResult.failed > 0 {
                    let detail = bookmarkResult.lastError.map { ": \($0)" } ?? ""
                    issues.append(issue(
                        plan,
                        sourceProfile,
                        "Skipped \(bookmarkResult.failed) bookmarks after write failures\(detail)"
                    ))
                }
            } catch {
                skippedCount += preview.bookmarks.count
                issues.append(issue(plan, sourceProfile, "Bookmark write failed: \(error)"))
            }
        } else if !preview.bookmarks.isEmpty {
            skippedCount += preview.bookmarks.count
            if plan.importBookmarks {
                issues.append(issue(plan, sourceProfile, "Browser bookmark storage is unavailable"))
            }
        }

        let importedTotal = importedHistoryCount + importedCookieCount + importedBookmarkCount
        var status: BrowserImportStatus = importedTotal == 0
            ? .failed
            : (issues.isEmpty ? .completed : .partial)
        let entry = BrowserImportAuditEntry(
            runID: runID,
            source: plan.source,
            sourceProfile: sourceProfile,
            targetProfileID: plan.profileID,
            status: status,
            importedHistoryCount: importedHistoryCount,
            importedCookieCount: importedCookieCount,
            importedBookmarkCount: importedBookmarkCount,
            skippedCount: skippedCount,
            issueCount: issues.count,
            timestamp: Date()
        )
        do {
            try auditLogger?.record(entry)
        } catch {
            issues.append(issue(plan, sourceProfile, "Import audit write failed: \(error)"))
            if status == .completed { status = .partial }
        }

        return BrowserImportResult(
            runID: runID,
            status: status,
            sourceProfile: sourceProfile,
            importedHistoryCount: importedHistoryCount,
            importedCookieCount: importedCookieCount,
            importedBookmarkCount: importedBookmarkCount,
            skippedCount: skippedCount,
            errors: issues
        )
    }

    private func importBookmarks(
        _ imported: [BrowserImportedBookmark],
        plan: BrowserImportPlan,
        sourceProfile: String,
        store: any BrowserBookmarkStoring
    ) throws -> (imported: Int, skipped: Int, failed: Int, lastError: String?) {
        guard !imported.isEmpty else { return (0, 0, 0, nil) }
        let existing = try store.loadAll()
        var pending: [BrowserBookmark] = []
        let rootTitle = "Imported from \(plan.source.displayName) - \(sourceProfile)"
        let rootID: UUID
        if let root = existing.first(where: {
            $0.isFolder && $0.parentID == nil && $0.title == rootTitle
        }) {
            rootID = root.id
        } else {
            let root = BrowserBookmark.folder(name: rootTitle)
            pending.append(root)
            rootID = root.id
        }

        var foldersByPath: [[String]: UUID] = Dictionary(
            uniqueKeysWithValues: [([String](), rootID)]
        )
        var skippedCount = 0
        var knownBookmarks = Set(existing.compactMap { bookmark -> String? in
            guard !bookmark.isFolder, let url = bookmark.url else { return nil }
            return duplicateKey(parentID: bookmark.parentID, title: bookmark.title, url: url)
        })
        var sourceBookmarkIDs = Set<UUID>()

        for item in imported {
            var path: [String] = []
            var parentID = rootID
            for rawComponent in item.folderPath.prefix(64) {
                let component = String(
                    rawComponent.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_048)
                )
                guard !component.isEmpty else { continue }
                path.append(component)
                if let existingID = foldersByPath[path] {
                    parentID = existingID
                    continue
                }
                if let folder = existing.first(where: {
                    $0.isFolder && $0.parentID == parentID && $0.title == component
                }) {
                    foldersByPath[path] = folder.id
                    parentID = folder.id
                    continue
                }
                let folder = BrowserBookmark.folder(name: component, parentID: parentID)
                pending.append(folder)
                foldersByPath[path] = folder.id
                parentID = folder.id
            }

            let title = String(
                item.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_048)
            )
            let normalizedTitle = title.isEmpty ? item.url : title
            let key = duplicateKey(parentID: parentID, title: normalizedTitle, url: item.url)
            guard !knownBookmarks.contains(key) else {
                skippedCount += 1
                continue
            }
            let bookmark = BrowserBookmark(
                title: normalizedTitle,
                url: item.url,
                parentID: parentID,
                isFolder: false,
                sortOrder: item.sortOrder,
                createdAt: item.createdAt ?? Date()
            )
            pending.append(bookmark)
            sourceBookmarkIDs.insert(bookmark.id)
            knownBookmarks.insert(key)
        }

        do {
            try store.saveBatch(pending)
            return (sourceBookmarkIDs.count, skippedCount, 0, nil)
        } catch let error as BrowserBookmarkBatchSaveError {
            let importedCount = sourceBookmarkIDs.intersection(error.savedItemIDs).count
            let failedCount = sourceBookmarkIDs.count - importedCount
            return (
                importedCount,
                skippedCount + failedCount,
                failedCount,
                error.localizedDescription
            )
        } catch {
            let failedCount = sourceBookmarkIDs.count
            return (
                0,
                skippedCount + failedCount,
                failedCount,
                (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            )
        }
    }

    private func duplicateKey(parentID: UUID?, title: String, url: String) -> String {
        "\(parentID?.uuidString ?? "root")\u{1F}\(title)\u{1F}\(url)"
    }

    private func issue(
        _ plan: BrowserImportPlan,
        _ sourceProfile: String,
        _ message: String
    ) -> BrowserImportIssue {
        BrowserImportIssue(source: plan.source, profileName: sourceProfile, message: message)
    }

    private func recordFailedAudit(
        runID: UUID,
        plan: BrowserImportPlan,
        sourceProfile: String,
        issueCount: Int
    ) {
        try? auditLogger?.record(BrowserImportAuditEntry(
            runID: runID,
            source: plan.source,
            sourceProfile: sourceProfile,
            targetProfileID: plan.profileID,
            status: .failed,
            importedHistoryCount: 0,
            importedCookieCount: 0,
            importedBookmarkCount: 0,
            skippedCount: 0,
            issueCount: issueCount,
            timestamp: Date()
        ))
    }
}

final class FileBrowserImportAuditLogger: BrowserImportAuditLogging, @unchecked Sendable {
    private static let directoryOpenFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.cocxy.browser-import-audit")

    init(fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cocxy/Audit/browser-import.jsonl")) {
        self.fileURL = fileURL
    }

    func record(_ entry: BrowserImportAuditEntry) throws {
        try queue.sync {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let line = try encoder.encode(entry) + Data([0x0A])
            let descriptor = try openAuditFile()
            defer { Darwin.close(descriptor) }

            var metadata = stat()
            guard Darwin.fstat(descriptor, &metadata) == 0,
                  (metadata.st_mode & S_IFMT) == S_IFREG,
                  metadata.st_nlink == 1,
                  Darwin.fchmod(descriptor, 0o600) == 0 else {
                throw BrowserImportError.invalidSourceFile(fileURL.path)
            }
            guard Darwin.lockf(descriptor, F_LOCK, 0) == 0 else {
                throw BrowserImportError.invalidSourceFile(fileURL.path)
            }
            defer { Darwin.lockf(descriptor, F_ULOCK, 0) }

            try line.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                var written = 0
                while written < bytes.count {
                    let result = Darwin.write(
                        descriptor,
                        base.advanced(by: written),
                        bytes.count - written
                    )
                    if result < 0, errno == EINTR { continue }
                    guard result > 0 else {
                        throw BrowserImportError.invalidSourceFile(fileURL.path)
                    }
                    written += result
                }
            }
        }
    }

    private func openAuditFile() throws -> Int32 {
        let originalPath = fileURL.path
        let path = Self.normalizedMacOSRootAlias(in: fileURL.standardizedFileURL.path)
        guard fileURL.isFileURL,
              originalPath.hasPrefix("/"),
              !originalPath.contains("\0") else {
            throw BrowserImportError.invalidSourceFile(originalPath)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count >= 2,
              components.allSatisfy(Self.isSafePathComponent) else {
            throw BrowserImportError.invalidSourceFile(originalPath)
        }

        var parentDescriptor = "/".withCString {
            Darwin.open($0, Self.directoryOpenFlags)
        }
        guard parentDescriptor >= 0 else {
            throw BrowserImportError.invalidSourceFile(originalPath)
        }

        for component in components.dropLast() {
            var nextDescriptor = component.withCString {
                Darwin.openat(parentDescriptor, $0, Self.directoryOpenFlags)
            }
            if nextDescriptor < 0, errno == ENOENT {
                let createResult = component.withCString {
                    Darwin.mkdirat(parentDescriptor, $0, S_IRWXU)
                }
                guard createResult == 0 || errno == EEXIST else {
                    Darwin.close(parentDescriptor)
                    throw BrowserImportError.invalidSourceFile(originalPath)
                }
                nextDescriptor = component.withCString {
                    Darwin.openat(parentDescriptor, $0, Self.directoryOpenFlags)
                }
            }
            guard nextDescriptor >= 0 else {
                Darwin.close(parentDescriptor)
                throw BrowserImportError.invalidSourceFile(originalPath)
            }
            Darwin.close(parentDescriptor)
            parentDescriptor = nextDescriptor
        }
        defer { Darwin.close(parentDescriptor) }

        var directoryMetadata = stat()
        guard Darwin.fstat(parentDescriptor, &directoryMetadata) == 0,
              (directoryMetadata.st_mode & S_IFMT) == S_IFDIR,
              directoryMetadata.st_uid == Darwin.geteuid(),
              Darwin.fchmod(parentDescriptor, S_IRWXU) == 0 else {
            throw BrowserImportError.invalidSourceFile(originalPath)
        }

        let descriptor = components[components.count - 1].withCString {
            Darwin.openat(
                parentDescriptor,
                $0,
                O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw BrowserImportError.invalidSourceFile(originalPath)
        }

        var fileMetadata = stat()
        guard Darwin.fstat(descriptor, &fileMetadata) == 0,
              (fileMetadata.st_mode & S_IFMT) == S_IFREG,
              fileMetadata.st_nlink == 1,
              fileMetadata.st_uid == Darwin.geteuid() else {
            Darwin.close(descriptor)
            throw BrowserImportError.invalidSourceFile(originalPath)
        }
        return descriptor
    }

    private static func isSafePathComponent(_ component: String) -> Bool {
        !component.isEmpty
            && component != "."
            && component != ".."
            && !component.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func normalizedMacOSRootAlias(in path: String) -> String {
        for (alias, destination) in [
            ("/var", "/private/var"),
            ("/tmp", "/private/tmp"),
            ("/etc", "/private/etc"),
        ] {
            if path == alias { return destination }
            if path.hasPrefix(alias + "/") {
                return destination + path.dropFirst(alias.count)
            }
        }
        return path
    }
}
