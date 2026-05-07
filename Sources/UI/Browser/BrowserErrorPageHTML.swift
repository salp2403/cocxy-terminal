// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserErrorPageHTML.swift - Shared themed error page rendering for browser hosts.

import Foundation
import WebKit

@MainActor
protocol BrowserErrorPageLoading: AnyObject {
    func loadBrowserErrorHTML(_ string: String, baseURL: URL?)
}

extension WKWebView: BrowserErrorPageLoading {
    func loadBrowserErrorHTML(_ string: String, baseURL: URL?) {
        loadHTMLString(string, baseURL: baseURL)
    }
}

enum BrowserWebViewAppearance {
    @MainActor
    static func configure(_ webView: WKWebView) {
        webView.wantsLayer = true
        webView.layer?.backgroundColor = CocxyColors.base.cgColor

        // WKWebView has its own white background on macOS. Keep the app-owned
        // browser surface visually stable while local dev pages load or fail.
        webView.setValue(false, forKey: "drawsBackground")
    }
}

enum BrowserErrorPageRenderer {
    @MainActor
    static func render(
        error: Error,
        failedURL: URL?,
        fallbackURLString: String,
        localizer: AppLocalizer,
        into loader: BrowserErrorPageLoading
    ) {
        let urlDisplay = failedURL?.absoluteString ?? fallbackURLString
        loader.loadBrowserErrorHTML(
            BrowserErrorPageHTML.make(
                error: error,
                failedURLString: urlDisplay,
                localizer: localizer
            ),
            baseURL: nil
        )
    }
}

enum BrowserErrorPageHTML {
    static func make(
        error: Error,
        failedURLString: String,
        localizer: AppLocalizer
    ) -> String {
        let title = localizer.string(
            "browser.content.error.title",
            fallback: "Cannot reach this page"
        )
        let hint = localizer.string(
            "browser.content.error.hint",
            fallback: "Type a URL in the address bar above or start a dev server."
        )

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            body {
                background: #1e1e2e;
                color: #cdd6f4;
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                display: flex;
                align-items: center;
                justify-content: center;
                min-height: 100vh;
                margin: 0;
                padding: 20px;
                box-sizing: border-box;
            }
            .container {
                text-align: center;
                max-width: 480px;
            }
            .icon {
                width: 44px;
                height: 44px;
                border-radius: 12px;
                display: inline-flex;
                align-items: center;
                justify-content: center;
                margin-bottom: 16px;
                background: #313244;
                color: #f38ba8;
                font: 600 24px -apple-system, BlinkMacSystemFont, sans-serif;
            }
            h1 {
                font-size: 18px;
                font-weight: 600;
                color: #f38ba8;
                margin: 0 0 8px;
            }
            .url {
                font-family: ui-monospace, SFMono-Regular, monospace;
                font-size: 12px;
                color: #89b4fa;
                word-break: break-all;
                margin: 12px 0;
                padding: 8px 12px;
                background: #313244;
                border-radius: 6px;
            }
            .detail {
                font-size: 13px;
                color: #a6adc8;
                line-height: 1.5;
            }
            .hint {
                margin-top: 20px;
                font-size: 12px;
                color: #6c7086;
            }
        </style>
        </head>
        <body>
        <div class="container">
            <div class="icon">!</div>
            <h1>\(htmlEscape(title))</h1>
            <div class="url">\(htmlEscape(failedURLString))</div>
            <p class="detail">\(htmlEscape(error.localizedDescription))</p>
            <p class="hint">\(htmlEscape(hint))</p>
        </div>
        </body>
        </html>
        """
    }

    private static func htmlEscape(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
