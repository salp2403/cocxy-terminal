// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+BrowserImportCLI.swift - Bridges browser import socket commands.

import Foundation

extension AppDelegate {
    private struct BrowserImportCLIContext: Sendable {
        let profileID: UUID
        let historyStore: (any BrowserHistoryStoring)?
        let bookmarkStore: (any BrowserBookmarkStoring)?
    }

    nonisolated func handleBrowserImportCLIRequest(
        kind: String,
        params: [String: String]
    ) -> (success: Bool, data: [String: String]) {
        let semaphore = DispatchSemaphore(value: 0)
        let box = LockedBox<(Bool, [String: String])>((
            false,
            ["error": "Browser import dispatch did not complete"]
        ))

        Task.detached { [self] in
            let result = await performBrowserImportCLIRequest(kind: kind, params: params)
            box.withValue { $0 = result }
            semaphore.signal()
        }

        semaphore.wait()
        return box.withValue { $0 }
    }

    nonisolated func performBrowserImportCLIRequest(
        kind: String,
        params: [String: String]
    ) async -> (Bool, [String: String]) {
        do {
            let delegateRef = WeakReference(self)
            let context = await MainActor.run {
                self.browserImportContext(from: params)
            }
            let plan = try buildBrowserImportPlan(params: params, defaultProfileID: context.profileID)

            switch kind {
            case "preview":
                let preview = try BrowserSourceImporterFactory.importer(for: plan.source)
                    .preview(plan: plan)
                return (true, browserImportPreviewData(preview, plan: plan))
            case "run":
                let cookieStore = plan.importCookies
                    ? BrowserWebKitCookieImportStore(viewModelProvider: {
                        syncOnMainActor {
                            delegateRef.value?.activeBrowserViewModelForCLI()
                        }
                    })
                    : nil
                let importer = BrowserImporter(
                    source: plan.source,
                    historyStore: context.historyStore,
                    bookmarkStore: context.bookmarkStore,
                    cookieStore: cookieStore,
                    auditLogger: FileBrowserImportAuditLogger()
                )
                let result = try importer.importData(plan)
                return (true, browserImportResultData(result, plan: plan))
            default:
                return (false, ["error": "Unknown browser import action: \(kind)"])
            }
        } catch {
            return (false, ["error": browserImportErrorMessage(error)])
        }
    }

    @MainActor
    private func browserImportContext(from params: [String: String]) -> BrowserImportCLIContext {
        if browserProfileManager == nil {
            setupBrowserPro()
        }
        return BrowserImportCLIContext(
            profileID: browserImportProfileID(from: params),
            historyStore: browserHistoryStore,
            bookmarkStore: browserBookmarkStore
        )
    }

    @MainActor
    private func browserImportProfileID(from params: [String: String]) -> UUID {
        if let rawProfile = params["profile"],
           let profileID = UUID(uuidString: rawProfile) {
            return profileID
        }
        return browserProfileManager?.activeProfileID ?? UUID()
    }

    nonisolated private func buildBrowserImportPlan(
        params: [String: String],
        defaultProfileID: UUID
    ) throws -> BrowserImportPlan {
        guard let rawSource = params["source"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              let source = BrowserImportSource(rawValue: rawSource) else {
            throw BrowserImportCLIError.invalidSource(params["source"] ?? "")
        }

        let profileID: UUID
        if let rawProfile = params["profile"] {
            guard let parsed = UUID(uuidString: rawProfile) else {
                throw BrowserImportCLIError.invalidProfile(rawProfile)
            }
            profileID = parsed
        } else {
            profileID = defaultProfileID
        }

        let maxHistoryDays: Int?
        if let rawDays = params["max-history-days"] {
            guard let parsed = Int(rawDays), parsed >= 0 else {
                throw BrowserImportCLIError.invalidMaxHistoryDays(rawDays)
            }
            maxHistoryDays = parsed
        } else {
            maxHistoryDays = nil
        }

        return BrowserImportPlan(
            source: source,
            profileID: profileID,
            importCookies: boolParam(params["import-cookies"], defaultValue: true),
            importHistory: boolParam(params["import-history"], defaultValue: true),
            importBookmarks: boolParam(params["import-bookmarks"], defaultValue: true),
            maxHistoryDays: maxHistoryDays,
            domainWhitelist: splitListParam(params["domain-whitelist"]),
            domainBlacklist: splitListParam(params["domain-blacklist"]),
            explicitLocations: explicitLocations(source: source, params: params)
        )
    }

    nonisolated private func explicitLocations(
        source: BrowserImportSource,
        params: [String: String]
    ) -> [BrowserImportLocation]? {
        let historyPath = params["history"]
        let cookiesPath = params["cookies"]
        let bookmarksPath = params["bookmarks"]
        guard historyPath != nil || cookiesPath != nil || bookmarksPath != nil else {
            return nil
        }

        let base = source.defaultLocations().first
        let location = BrowserImportLocation(
            source: source,
            profileName: params["source-profile"] ?? base?.profileName ?? "Imported",
            historyPath: historyPath.map(URL.init(fileURLWithPath:))
                ?? base?.historyPath
                ?? URL(fileURLWithPath: "/dev/null"),
            cookiesPath: cookiesPath.map(URL.init(fileURLWithPath:)) ?? base?.cookiesPath,
            bookmarksPath: bookmarksPath.map(URL.init(fileURLWithPath:)) ?? base?.bookmarksPath
        )
        return [location]
    }

    nonisolated private func boolParam(_ rawValue: String?, defaultValue: Bool) -> Bool {
        guard let rawValue else { return defaultValue }
        switch rawValue.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return defaultValue
        }
    }

    nonisolated private func splitListParam(_ rawValue: String?) -> [String] {
        guard let rawValue else { return [] }
        return rawValue
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    nonisolated private func browserImportPreviewData(
        _ preview: BrowserImportPreview,
        plan: BrowserImportPlan
    ) -> [String: String] {
        var data: [String: String] = [
            "status": "previewed",
            "source": plan.source.rawValue,
            "profile": plan.profileID.uuidString,
            "history": "\(preview.history.count)",
            "cookies": "\(preview.cookies.count)",
            "bookmarks": "\(preview.bookmarks.count)",
            "errors": "\(preview.errors.count)",
        ]
        for (index, issue) in preview.errors.prefix(5).enumerated() {
            data["error_\(index)"] = "\(issue.profileName): \(issue.message)"
        }
        return data
    }

    nonisolated private func browserImportResultData(
        _ result: BrowserImportResult,
        plan: BrowserImportPlan
    ) -> [String: String] {
        var data: [String: String] = [
            "status": "imported",
            "source": plan.source.rawValue,
            "profile": plan.profileID.uuidString,
            "history": "\(result.importedHistoryCount)",
            "cookies": "\(result.importedCookieCount)",
            "bookmarks": "\(result.importedBookmarkCount)",
            "skipped": "\(result.skippedCount)",
            "errors": "\(result.errors.count)",
        ]
        for (index, issue) in result.errors.prefix(5).enumerated() {
            data["error_\(index)"] = "\(issue.profileName): \(issue.message)"
        }
        return data
    }

    nonisolated private func browserImportErrorMessage(_ error: Error) -> String {
        if let error = error as? BrowserImportCLIError {
            return error.localizedDescription
        }
        return String(describing: error)
    }
}

private enum BrowserImportCLIError: LocalizedError {
    case invalidSource(String)
    case invalidProfile(String)
    case invalidMaxHistoryDays(String)

    var errorDescription: String? {
        switch self {
        case .invalidSource(let value):
            return "Unsupported browser import source: \(value)"
        case .invalidProfile(let value):
            return "Invalid browser profile UUID: \(value)"
        case .invalidMaxHistoryDays(let value):
            return "Invalid max history days: \(value)"
        }
    }
}
