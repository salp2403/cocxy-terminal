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
}

extension BrowserImportIssue {
    /// The raw error can carry browser profile paths, so it only reaches the private log.
    static func sourceReadFailure(
        _ location: BrowserImportLocation,
        _ data: BrowserImportDataKind,
        _ error: any Error
    ) -> BrowserImportIssue {
        let summary = "\(data.rawValue.capitalized) import failed"
        BrowserImportPrivacyLog.record(summary, error: error)
        return BrowserImportIssue(
            source: location.source,
            profileName: location.profileName,
            message: summary,
            kind: .sourceReadFailed(data)
        )
    }
}
