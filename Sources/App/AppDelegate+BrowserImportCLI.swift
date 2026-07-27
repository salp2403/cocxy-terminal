// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+BrowserImportCLI.swift - Bridges browser import socket commands.

import Foundation

enum BrowserImportSynchronousBridgeOutcome<Result: Sendable>: Sendable {
    case completed(Result)
    case timedOut(settledResult: Result)
    case unavailable
}

enum BrowserImportSynchronousBridge {
    static let requestTimeout: TimeInterval = 5 * 60

    /// Upper bound on how long a cancelled import may take to settle.
    ///
    /// The wait exists so a reply never races a store mutation, but it must not
    /// be unbounded: the thread that signals it is a task, and a caller that
    /// parks a cooperative thread here can starve the very task it waits for.
    /// Generous enough that a settling import always wins it in practice.
    static let cancellationSettlementTimeout: TimeInterval = 30

    static func run<Result: Sendable>(
        timeout: TimeInterval,
        operation: @escaping @Sendable () async -> Result
    ) -> BrowserImportSynchronousBridgeOutcome<Result> {
        guard !Thread.isMainThread else { return .unavailable }
        let semaphore = DispatchSemaphore(value: 0)
        let box = LockedBox<Result?>(nil)
        let task = Task.detached {
            let result = await operation()
            box.withValue { $0 = result }
            semaphore.signal()
        }
        let boundedTimeout = timeout.isFinite ? max(timeout, 0) : 0
        guard semaphore.wait(timeout: .now() + boundedTimeout) == .success else {
            task.cancel()
            // Imports mutate app-owned stores, so cancellation must settle before
            // replying — but only within a bound. An unbounded wait deadlocks
            // whenever the caller occupies the thread the settling task needs.
            guard semaphore.wait(
                timeout: .now() + Self.cancellationSettlementTimeout
            ) == .success else {
                // Settlement is unattestable, so report no result rather than one
                // that a still-running import could contradict.
                return .unavailable
            }
            guard let result = box.withValue({ $0 }) else { return .unavailable }
            return .timedOut(settledResult: result)
        }
        guard let result = box.withValue({ $0 }) else { return .unavailable }
        return .completed(result)
    }
}

extension AppDelegate {
    private struct BrowserImportCLIContext: Sendable {
        let profileID: UUID
        let approvedResourcePaths: [String: String]?
        let historyStore: (any BrowserHistoryStoring)?
        let bookmarkStore: (any BrowserBookmarkStoring)?
        let bookmarkRootTitleFormat: String
        let bookmarkRootTitleAliases: [String]
    }

    nonisolated func handleBrowserImportCLIRequest(
        kind: String,
        params: [String: String],
        authorizationContext: SocketPrivilegedCommandContext
    ) -> (success: Bool, data: [String: String]) {
        let outcome = BrowserImportSynchronousBridge.run(
            timeout: BrowserImportSynchronousBridge.requestTimeout,
            operation: { [self] in
                await performBrowserImportCLIRequest(
                    kind: kind,
                    params: params,
                    authorizationContext: authorizationContext
                )
            }
        )
        switch outcome {
        case .completed(let result):
            return result
        case .timedOut(let settledResult):
            return Self.browserImportTimedOutResponse(settledResult)
        case .unavailable:
            return (false, ["error": "Browser import bridge is unavailable"])
        }
    }

    nonisolated static func browserImportTimedOutResponse(
        _ settledResult: (success: Bool, data: [String: String])
    ) -> (success: Bool, data: [String: String]) {
        var data = settledResult.data
        data["error"] = "Browser import exceeded the five-minute request limit; cancellation was requested"
        data["timed_out"] = "true"
        data["cancelled"] = "true"
        data["settled_after_cancellation"] = "true"
        return (false, data)
    }

    nonisolated func performBrowserImportCLIRequest(
        kind: String,
        params: [String: String],
        authorizationContext: SocketPrivilegedCommandContext
    ) async -> (Bool, [String: String]) {
        do {
            try Task.checkCancellation()
            if kind == "preview", params["preview-token"] != nil {
                throw BrowserImportCLIError.previewTokenNotAllowed
            }
            let context = try await MainActor.run {
                try self.browserImportContext(
                    from: params,
                    authorizationContext: authorizationContext
                )
            }
            try Task.checkCancellation()
            let plan = try buildBrowserImportPlan(
                params: params,
                context: context
            )

            switch kind {
            case "preview":
                try Task.checkCancellation()
                let preview = try BrowserSourceImporterFactory.importer(for: plan.source)
                    .preview(plan: plan)
                try Task.checkCancellation()
                guard preview.itemCount > 0 else {
                    throw BrowserImportError.noImportableData(
                        "No importable data was found for the selected browser profile"
                    )
                }
                return (true, browserImportPreviewData(preview, plan: plan))
            case "run":
                let reservation = try await MainActor.run {
                    try self.beginBrowserImportReservation(profileID: plan.profileID)
                }
                let cookieStore = plan.importCookies
                    ? BrowserWebKitCookieImportStore()
                    : nil
                let importer = BrowserImporter(
                    source: plan.source,
                    historyStore: context.historyStore,
                    bookmarkStore: context.bookmarkStore,
                    cookieStore: cookieStore,
                    auditLogger: FileBrowserImportAuditLogger(),
                    bookmarkRootTitleFormat: context.bookmarkRootTitleFormat,
                    bookmarkRootTitleAliases: context.bookmarkRootTitleAliases
                )
                do {
                    let result = try importer.importData(plan)
                    await MainActor.run {
                        self.browserProfileManager?.endImport(reservation)
                    }
                    return (
                        Self.browserImportCommandSucceeded(status: result.status),
                        browserImportResultData(result, plan: plan)
                    )
                } catch {
                    await MainActor.run {
                        self.browserProfileManager?.endImport(reservation)
                    }
                    throw error
                }
            default:
                return (false, ["error": "Unknown browser import action: \(kind)"])
            }
        } catch {
            return (false, ["error": browserImportErrorMessage(error)])
        }
    }

    nonisolated static func browserImportCommandSucceeded(
        status: BrowserImportStatus
    ) -> Bool {
        status == .completed || status == .partial
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
        guard let profile = profileManager.profiles.first(where: { $0.id == profileID }) else {
            throw BrowserImportCLIError.profileUnavailable(profileID.uuidString)
        }
        guard !profile.isRemoteBacked else {
            throw BrowserImportCLIError.remoteProfile(profileID.uuidString)
        }

        let bookmarkRootTitleFormat = appLocalizer().string(
            BrowserImportBookmarkRootLocalization.key,
            fallback: BrowserImportBookmarkRootLocalization.fallback
        )
        return BrowserImportCLIContext(
            profileID: profileID,
            approvedResourcePaths: authorizationContext.scope == .browserGlobal
                ? authorizationContext.localResourcePaths
                : nil,
            historyStore: browserHistoryStore,
            bookmarkStore: browserBookmarkStore,
            bookmarkRootTitleFormat: bookmarkRootTitleFormat,
            bookmarkRootTitleAliases: BrowserImportBookmarkRootLocalization.formats(
                current: bookmarkRootTitleFormat
            )
        )
    }

    @MainActor
    private func beginBrowserImportReservation(
        profileID: UUID
    ) throws -> BrowserProfileImportReservation {
        guard let profileManager = browserProfileManager,
              let profile = profileManager.profiles.first(where: { $0.id == profileID }) else {
            throw BrowserImportCLIError.profileUnavailable(profileID.uuidString)
        }
        guard !profile.isRemoteBacked else {
            throw BrowserImportCLIError.remoteProfile(profileID.uuidString)
        }
        guard let reservation = profileManager.beginImport(to: profileID) else {
            throw BrowserImportCLIError.destinationBusy(profileID.uuidString)
        }
        return reservation
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

        let importCookies = try boolParam(
            params["import-cookies"],
            name: "import-cookies",
            defaultValue: true
        )
        let importHistory = try boolParam(
            params["import-history"],
            name: "import-history",
            defaultValue: true
        )
        let importBookmarks = try boolParam(
            params["import-bookmarks"],
            name: "import-bookmarks",
            defaultValue: true
        )
        guard importCookies || importHistory || importBookmarks else {
            throw BrowserImportCLIError.noDataTypesSelected
        }

        let expectedPreviewToken: String?
        if let token = params["preview-token"] {
            guard BrowserImportPreviewToken.isValid(token) else {
                throw BrowserImportCLIError.invalidPreviewToken
            }
            expectedPreviewToken = token.lowercased()
        } else {
            expectedPreviewToken = nil
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
            discoverProfiles: context.approvedResourcePaths == nil,
            importHistory: importHistory,
            importCookies: importCookies,
            importBookmarks: importBookmarks,
            historyPath: canonicalExplicitPaths["history"],
            cookiesPath: canonicalExplicitPaths["cookies"],
            bookmarksPath: canonicalExplicitPaths["bookmarks"]
        )
        guard !requestedLocations.isEmpty else {
            if let sourceProfile = params["source-profile"] {
                throw BrowserImportError.sourceProfileUnavailable(sourceProfile)
            }
            throw BrowserImportCLIError.incompleteExplicitPaths
        }
        let approvedLocations: [BrowserImportLocation]
        if let approvedResourcePaths = context.approvedResourcePaths {
            guard let locations = BrowserImportLocationPathBinding.applyingApprovedResourcePaths(
                approvedResourcePaths,
                to: requestedLocations,
                importHistory: importHistory,
                importCookies: importCookies,
                importBookmarks: importBookmarks
            ) else {
                throw BrowserImportCLIError.authorizationTargetUnavailable
            }
            approvedLocations = locations
        } else {
            guard let canonicalPaths = BrowserImportLocationPathBinding.canonicalResourcePaths(
                for: requestedLocations,
                importHistory: importHistory,
                importCookies: importCookies,
                importBookmarks: importBookmarks,
                canonicalize: canonicalBrowserImportURL
            ),
                  let locations = BrowserImportLocationPathBinding.applyingApprovedResourcePaths(
                    canonicalPaths,
                    to: requestedLocations,
                    importHistory: importHistory,
                    importCookies: importCookies,
                    importBookmarks: importBookmarks
                  ) else {
                throw BrowserImportCLIError.invalidPath
            }
            approvedLocations = locations
        }

        return BrowserImportPlan(
            source: source,
            profileID: profileID,
            importCookies: importCookies,
            importHistory: importHistory,
            importBookmarks: importBookmarks,
            maxHistoryDays: maxHistoryDays,
            domainWhitelist: splitListParam(params["domain-whitelist"]),
            domainBlacklist: splitListParam(params["domain-blacklist"]),
            sourceProfile: params["source-profile"],
            explicitLocations: approvedLocations,
            expectedPreviewToken: expectedPreviewToken
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
            "status": preview.itemCount == 0 ? "empty" : (preview.errors.isEmpty ? "ready" : "partial"),
            "source": plan.source.rawValue,
            "source_profile": plan.locations().first?.profileName ?? plan.sourceProfile ?? "",
            "profile": plan.profileID.uuidString,
            "history": "\(preview.history.count)",
            "cookies": "\(preview.cookies.count)",
            "bookmarks": "\(preview.bookmarks.count)",
            "skipped": "\(preview.skippedCount)",
            "errors": "\(preview.errors.count)",
            "preview_token": BrowserImportPreviewToken.make(preview: preview, plan: plan),
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
            "status": result.status.rawValue,
            "run_id": result.runID.uuidString,
            "source": plan.source.rawValue,
            "source_profile": result.sourceProfile,
            "profile": plan.profileID.uuidString,
            "history": "\(result.importedHistoryCount)",
            "cookies": "\(result.importedCookieCount)",
            "cookies_uncertain": "\(result.uncertainCookieCount)",
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
        if let error = error as? LocalizedError,
           let description = error.errorDescription {
            return description
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
    case remoteProfile(String)
    case destinationBusy(String)
    case authorizationTargetUnavailable
    case noDataTypesSelected
    case incompleteExplicitPaths
    case invalidPreviewToken
    case previewTokenNotAllowed

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
        case .remoteProfile(let value):
            return "Browser data cannot be imported into remote-backed profile: \(value)"
        case .destinationBusy(let value):
            return "Another browser import is already using profile: \(value)"
        case .authorizationTargetUnavailable:
            return "Approved browser import target is no longer available"
        case .noDataTypesSelected:
            return "Select at least one browser data type to import"
        case .incompleteExplicitPaths:
            return "When overriding browser paths, provide every enabled data path"
        case .invalidPreviewToken:
            return "Invalid browser import preview token"
        case .previewTokenNotAllowed:
            return "preview-token is only valid for browser-import-run"
        }
    }
}
