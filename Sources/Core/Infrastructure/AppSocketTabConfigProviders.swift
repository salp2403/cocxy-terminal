// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

typealias TabConfigSaveSocketProvider = @Sendable (
    String, String?, String?, [String: String]
) -> (name: String, path: String, warning: String?)?

typealias TabConfigOpenSocketProvider = @Sendable (
    String
) -> (id: String, title: String, path: String, warning: String?)?
