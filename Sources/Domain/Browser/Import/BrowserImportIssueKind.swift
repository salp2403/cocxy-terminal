// Copyright (c) 2026 Said Arturo Lopez. MIT License.

enum BrowserImportIssueKind: Sendable, Equatable {
    case cookieBatchWrite(imported: Int, total: Int, uncertain: Int)
    case cookieDecryptionFailed(count: Int)
    case historyWriteFailed(count: Int)
    case bookmarkWriteFailed(count: Int)
    case bookmarkRootConflict
    case cancelled
}
