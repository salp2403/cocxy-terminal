// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import os.log

enum BrowserImportPrivacyLog {
    private static let logger = Logger(
        subsystem: "dev.cocxy.terminal",
        category: "BrowserImport"
    )

    static func record(_ operation: String, error: any Error) {
        logger.error(
            "\(operation, privacy: .public): \(String(describing: error), privacy: .private)"
        )
    }
}
