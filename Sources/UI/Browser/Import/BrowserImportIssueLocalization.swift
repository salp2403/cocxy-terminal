// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

extension BrowserImportWizardView {
    static func uncertainCookieMessage(count: Int, localizer: AppLocalizer) -> String {
        let key = count == 1
            ? "browser.import.result.cookieUnconfirmed.one"
            : "browser.import.result.cookieUnconfirmed.many"
        let fallback = count == 1
            ? "%d cookie write could not be confirmed."
            : "%d cookie writes could not be confirmed."
        return String(format: localizer.string(key, fallback: fallback), count)
    }

    static func localizedIssueMessage(
        _ issue: BrowserImportIssue,
        localizer: AppLocalizer
    ) -> String {
        guard let kind = issue.kind else { return issue.message }
        switch kind {
        case .historyWriteFailed(let count):
            return formattedIssue(
                localizer,
                key: "browser.import.issue.historyWriteFailed",
                fallback: "History visits not saved: %d.",
                count
            )
        case .bookmarkWriteFailed(let count):
            return formattedIssue(
                localizer,
                key: "browser.import.issue.bookmarkWriteFailed",
                fallback: "Bookmarks not saved: %d.",
                count
            )
        case .cookieDecryptionFailed(let count):
            return formattedIssue(
                localizer,
                key: "browser.import.issue.cookieDecryptionFailed",
                fallback: "Encrypted cookies skipped: %d.",
                count
            )
        case .bookmarkRootConflict:
            return localizer.string(
                "browser.import.issue.bookmarkRootConflict",
                fallback: "The imported bookmark folder conflicts with an existing item."
            )
        case .cancelled:
            return localizer.string(
                "browser.import.issue.cancelled",
                fallback: "The browser import was cancelled."
            )
        case .sourceReadFailed(.history):
            return localizer.string(
                "browser.import.issue.historyReadFailed",
                fallback: "History could not be read from this browser profile."
            )
        case .sourceReadFailed(.cookies):
            return localizer.string(
                "browser.import.issue.cookieReadFailed",
                fallback: "Cookies could not be read from this browser profile."
            )
        case .sourceReadFailed(.bookmarks):
            return localizer.string(
                "browser.import.issue.bookmarkReadFailed",
                fallback: "Bookmarks could not be read from this browser profile."
            )
        case .auditWriteFailed:
            return localizer.string(
                "browser.import.issue.auditWriteFailed",
                fallback: "The import finished, but its local audit record could not be saved."
            )
        case .cookieBatchWrite(let imported, let total, let uncertain) where uncertain > 0:
            return formattedIssue(
                localizer,
                key: "browser.import.issue.cookiesPartialUnconfirmed",
                fallback: "Imported %d of %d cookies; %d could not be confirmed by WebKit.",
                imported,
                total,
                uncertain
            )
        case .cookieBatchWrite(let imported, let total, _):
            return formattedIssue(
                localizer,
                key: "browser.import.issue.cookiesPartial",
                fallback: "Imported %d of %d cookies before the write stopped.",
                imported,
                total
            )
        }
    }

    private static func formattedIssue(
        _ localizer: AppLocalizer,
        key: String,
        fallback: String,
        _ values: any CVarArg...
    ) -> String {
        String(
            format: localizer.string(key, fallback: fallback),
            arguments: values
        )
    }
}
