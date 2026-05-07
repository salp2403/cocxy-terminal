// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserNavigationPolicy.swift - Shared navigation allow-list for browser hosts.

import Foundation

enum BrowserNavigationPolicy {
    static func allows(_ url: URL?) -> Bool {
        guard let url,
              let scheme = url.scheme?.lowercased() else {
            return false
        }

        switch scheme {
        case "http", "https":
            return true
        case "about":
            return url.absoluteString.lowercased() == "about:blank"
        default:
            return false
        }
    }
}
