// Copyright (c) 2026 Said Arturo Lopez. MIT License.

enum BrowserImportIssueKind: Sendable, Equatable {
    case cookieBatchWrite(imported: Int, total: Int, uncertain: Int)
    case cookieDecryptionFailed(count: Int)
    case historyWriteFailed(count: Int)
    case bookmarkWriteFailed(count: Int)
    case bookmarkRootConflict
    case cancelled
    case sourceReadFailed(BrowserImportDataKind)
    case auditWriteFailed
    case sourceFileUnavailable(BrowserImportDataKind)
    case storageUnavailable(BrowserImportDataKind)
    case historyLatestVisitOnly
    case partitionedCookiesSkipped(count: Int)
    case isolatedCookiesSkipped(count: Int)
    case historySafetyLimit(skipped: Int, importLimit: Int, scanLimit: Int?)
}

/// `message` stays in English for the CLI; the wizard renders `kind`.
extension BrowserImportIssue {
    /// The raw error can carry browser profile paths, so it only reaches the private log.
    static func sourceReadFailure(
        _ location: BrowserImportLocation,
        _ data: BrowserImportDataKind,
        _ error: any Error
    ) -> BrowserImportIssue {
        let summary = "\(data.rawValue.capitalized) import failed"
        BrowserImportPrivacyLog.record(summary, error: error)
        return issue(location, summary, .sourceReadFailed(data))
    }

    static func sourceFileUnavailable(
        _ location: BrowserImportLocation,
        _ data: BrowserImportDataKind
    ) -> BrowserImportIssue {
        let noun: String
        switch data {
        case .history: noun = "History"
        case .cookies: noun = "Cookie"
        case .bookmarks: noun = "Bookmark"
        }
        return issue(location, "\(noun) source file is unavailable", .sourceFileUnavailable(data))
    }

    static func latestHistoryVisitsOnly(_ location: BrowserImportLocation) -> BrowserImportIssue {
        issue(
            location,
            "Per-visit history is unavailable in this source; imported only the latest visit for each URL",
            .historyLatestVisitOnly
        )
    }

    static func skippedPartitionedCookies(
        _ location: BrowserImportLocation,
        count: Int
    ) -> BrowserImportIssue {
        issue(
            location,
            "Skipped \(count) partitioned cookies because WebKit cannot preserve their partition key",
            .partitionedCookiesSkipped(count: count)
        )
    }

    static func skippedIsolatedCookies(
        _ location: BrowserImportLocation,
        count: Int
    ) -> BrowserImportIssue {
        issue(
            location,
            "Skipped \(count) container or partitioned cookies because their isolation context cannot be preserved",
            .isolatedCookiesSkipped(count: count)
        )
    }

    static func historySafetyLimit(
        _ location: BrowserImportLocation,
        skipped: Int,
        importLimit: Int,
        scanLimit: Int?
    ) -> BrowserImportIssue {
        var details: [String] = []
        if skipped > 0 {
            details.append(
                "skipped \(skipped) additional matching visits after the \(importLimit)-visit import limit"
            )
        }
        if let scanLimit {
            details.append(
                "stopped after scanning the \(scanLimit) most recent source visits; older visits may remain"
            )
        }
        return issue(
            location,
            "History safety limit reached: \(details.joined(separator: "; "))",
            .historySafetyLimit(skipped: skipped, importLimit: importLimit, scanLimit: scanLimit)
        )
    }

    private static func issue(
        _ location: BrowserImportLocation,
        _ message: String,
        _ kind: BrowserImportIssueKind
    ) -> BrowserImportIssue {
        BrowserImportIssue(
            source: location.source,
            profileName: location.profileName,
            message: message,
            kind: kind
        )
    }
}
