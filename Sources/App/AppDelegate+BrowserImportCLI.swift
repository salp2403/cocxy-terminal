// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+BrowserImportCLI.swift - Bridges browser import socket commands.

import Foundation

extension AppDelegate {
    private struct BrowserImportCLIContext: Sendable {
        let profileID: UUID
        let approvedResourcePaths: [String: String]?
        let historyStore: (any BrowserHistoryStoring)?
        let bookmarkStore: (any BrowserBookmarkStoring)?
    }

    nonisolated func handleBrowserImportCLIRequest(
        kind: String,
        params: [String: String],
        authorizationContext: SocketPrivilegedCommandContext
    ) -> (success: Bool, data: [String: String]) {
        let semaphore = DispatchSemaphore(value: 0)
        let box = LockedBox<(Bool, [String: String])>((
            false,
            ["error": "Browser import dispatch did not complete"]
        ))

        Task.detached { [self] in
            let result = await performBrowserImportCLIRequest(
                kind: kind,
                params: params,
                authorizationContext: authorizationContext
            )
            box.withValue { $0 = result }
            semaphore.signal()
        }

        semaphore.wait()
        return box.withValue { $0 }
    }

    nonisolated func performBrowserImportCLIRequest(
        kind: String,
        params: [String: String],
        authorizationContext: SocketPrivilegedCommandContext
    ) async -> (Bool, [String: String]) {
        do {
            let context = try await MainActor.run {
                try self.browserImportContext(
                    from: params,
                    authorizationContext: authorizationContext
                )
            }
            let plan = try buildBrowserImportPlan(
                params: params,
                context: context
            )

            switch kind {
            case "preview":
                let preview = try BrowserSourceImporterFactory.importer(for: plan.source)
                    .preview(plan: plan)
                return (true, browserImportPreviewData(preview, plan: plan))
            case "run":
                let cookieStore = plan.importCookies
                    ? BrowserWebKitCookieImportStore()
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
    private func browserImportContext(
        from params: [String: String],
        authorizationContext: SocketPrivilegedCommandContext
    ) throws -> BrowserImportCLIContext {
        guard authorizationContext.scope == .browserGlobal
            || authorizationContext.scope == .internalTrusted else {
            throw BrowserImportCLIError.authorizationTargetUnavailable
        }
        if browserProfileManager == nil {
            setupBrowserPro()
        }
        guard let profileManager = browserProfileManager else {
            throw BrowserImportCLIError.authorizationTargetUnavailable
        }

        let profileID: UUID
        if authorizationContext.scope == .browserGlobal {
            guard let approvedProfileID = authorizationContext.browserProfileID else {
                throw BrowserImportCLIError.authorizationTargetUnavailable
            }
            profileID = approvedProfileID
        } else if let rawProfile = params["profile"] {
            guard let parsedProfileID = UUID(uuidString: rawProfile) else {
                throw BrowserImportCLIError.invalidProfile(rawProfile)
            }
            profileID = parsedProfileID
        } else {
            profileID = profileManager.activeProfileID
        }
        guard profileManager.profiles.contains(where: { $0.id == profileID }) else {
            throw BrowserImportCLIError.profileUnavailable(profileID.uuidString)
        }

        return BrowserImportCLIContext(
            profileID: profileID,
            approvedResourcePaths: authorizationContext.scope == .browserGlobal
                ? authorizationContext.localResourcePaths
                : nil,
            historyStore: browserHistoryStore,
            bookmarkStore: browserBookmarkStore
        )
    }

    nonisolated private func buildBrowserImportPlan(
        params: [String: String],
        context: BrowserImportCLIContext
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
            profileID = context.profileID
        }
        guard profileID == context.profileID else {
            throw BrowserImportCLIError.authorizationTargetUnavailable
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

        var canonicalExplicitPaths: [String: String] = [:]
        for key in ["history", "cookies", "bookmarks"] {
            guard let rawPath = params[key] else { continue }
            guard let canonicalURL = canonicalBrowserImportURL(fromPath: rawPath) else {
                throw BrowserImportCLIError.invalidPath
            }
            canonicalExplicitPaths[key] = canonicalURL.path
        }

        let requestedLocations = BrowserImportLocationPathBinding.requestedLocations(
            source: source,
            profileName: params["source-profile"],
            historyPath: canonicalExplicitPaths["history"],
            cookiesPath: canonicalExplicitPaths["cookies"],
            bookmarksPath: canonicalExplicitPaths["bookmarks"]
        )
        let approvedLocations: [BrowserImportLocation]
        if let approvedResourcePaths = context.approvedResourcePaths {
            guard let locations = BrowserImportLocationPathBinding.applyingApprovedResourcePaths(
                approvedResourcePaths,
                to: requestedLocations
            ) else {
                throw BrowserImportCLIError.authorizationTargetUnavailable
            }
            approvedLocations = locations
        } else {
            guard let canonicalPaths = BrowserImportLocationPathBinding.canonicalResourcePaths(
                for: requestedLocations,
                canonicalize: canonicalBrowserImportURL
            ),
                  let locations = BrowserImportLocationPathBinding.applyingApprovedResourcePaths(
                    canonicalPaths,
                    to: requestedLocations
                  ) else {
                throw BrowserImportCLIError.invalidPath
            }
            approvedLocations = locations
        }

        return BrowserImportPlan(
            source: source,
            profileID: profileID,
            importCookies: try boolParam(
                params["import-cookies"],
                name: "import-cookies",
                defaultValue: true
            ),
            importHistory: try boolParam(
                params["import-history"],
                name: "import-history",
                defaultValue: true
            ),
            importBookmarks: try boolParam(
                params["import-bookmarks"],
                name: "import-bookmarks",
                defaultValue: true
            ),
            maxHistoryDays: maxHistoryDays,
            domainWhitelist: splitListParam(params["domain-whitelist"]),
            domainBlacklist: splitListParam(params["domain-blacklist"]),
            explicitLocations: approvedLocations
        )
    }

    nonisolated private func boolParam(
        _ rawValue: String?,
        name: String,
        defaultValue: Bool
    ) throws -> Bool {
        guard let rawValue else { return defaultValue }
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: throw BrowserImportCLIError.invalidBoolean(name, rawValue)
        }
    }

    nonisolated private func canonicalBrowserImportURL(_ url: URL) -> URL? {
        canonicalBrowserImportURL(fromPath: url.path)
    }

    nonisolated private func canonicalBrowserImportURL(fromPath rawPath: String) -> URL? {
        guard !rawPath.isEmpty,
              rawPath.utf8.count <= 4_096,
              !rawPath.contains("\0") else {
            return nil
        }
        let expandedPath = (rawPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
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
    case invalidBoolean(String, String)
    case invalidPath
    case profileUnavailable(String)
    case authorizationTargetUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidSource(let value):
            return "Unsupported browser import source: \(value)"
        case .invalidProfile(let value):
            return "Invalid browser profile UUID: \(value)"
        case .invalidMaxHistoryDays(let value):
            return "Invalid max history days: \(value)"
        case .invalidBoolean(let name, let value):
            return "Invalid boolean for \(name): \(value)"
        case .invalidPath:
            return "Invalid browser import path"
        case .profileUnavailable(let value):
            return "Browser profile is no longer available: \(value)"
        case .authorizationTargetUnavailable:
            return "Approved browser import target is no longer available"
        }
    }
}
