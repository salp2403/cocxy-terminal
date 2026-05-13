// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserErrorPageSwiftTestingTests.swift - Browser navigation failure rendering contracts.

import Foundation
import Testing
import WebKit
@testable import CocxyTerminal

@Suite("Browser error page rendering")
struct BrowserErrorPageSwiftTestingTests {

    @Test("error page is dark themed and escapes dynamic content")
    func errorPageIsDarkThemedAndEscapesDynamicContent() throws {
        let bundle = try #require(localizationBundle())
        let error = NSError(
            domain: "BrowserErrorPageTests",
            code: -1,
            userInfo: [
                NSLocalizedDescriptionKey: #"Bad <script>alert("x")</script> & "quoted""#,
            ]
        )

        let html = BrowserErrorPageHTML.make(
            error: error,
            failedURLString: #"http://localhost:3000/?q=<unsafe>&name="dev""#,
            localizer: AppLocalizer(languagePreference: .english, bundle: bundle)
        )

        #expect(html.contains("background: #1e1e2e"))
        #expect(html.contains("color: #cdd6f4"))
        #expect(html.contains("Cannot reach this page"))
        #expect(html.contains("http://localhost:3000/?q=&lt;unsafe&gt;&amp;name=&quot;dev&quot;"))
        #expect(html.contains("Bad &lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; &amp; &quot;quoted&quot;"))
        #expect(!html.contains("<unsafe>"))
        #expect(!html.contains("<script>alert"))
    }

    @MainActor
    @Test("renderer loads themed error HTML into browser host")
    func rendererLoadsThemedErrorHTMLIntoBrowserHost() throws {
        let bundle = try #require(localizationBundle())
        let loader = CapturingBrowserErrorPageLoader()
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotConnectToHost,
            userInfo: [NSLocalizedDescriptionKey: "Connection refused"]
        )

        BrowserErrorPageRenderer.render(
            error: error,
            failedURL: Optional<URL>.none,
            fallbackURLString: "http://localhost:3000/",
            localizer: AppLocalizer(languagePreference: .english, bundle: bundle),
            into: loader
        )

        #expect(loader.loadedHTML?.contains("Cannot reach this page") == true)
        #expect(loader.loadedHTML?.contains("http://localhost:3000/") == true)
        #expect(loader.baseURL == nil)
    }

    @Test("renderer ignores internal about blank failed URL")
    func rendererIgnoresInternalAboutBlankFailedURL() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotConnectToHost,
            userInfo: [NSLocalizedDescriptionKey: "Connection refused"]
        )

        let displayURL = BrowserErrorPageRenderer.userFacingURLString(
            error: error,
            failedURL: URL(string: "about:blank"),
            fallbackURLString: "http://localhost:3000/"
        )

        #expect(displayURL == "http://localhost:3000/")
    }

    @Test("renderer prefers explicit failing web URL from error")
    func rendererPrefersExplicitFailingWebURLFromError() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotConnectToHost,
            userInfo: [
                NSLocalizedDescriptionKey: "Connection refused",
                NSURLErrorFailingURLStringErrorKey: "http://localhost:5173/"
            ]
        )

        let displayURL = BrowserErrorPageRenderer.userFacingURLString(
            error: error,
            failedURL: URL(string: "about:blank"),
            fallbackURLString: "http://localhost:3000/"
        )

        #expect(displayURL == "http://localhost:5173/")
    }

    @MainActor
    @Test("shared web view appearance disables the default white background")
    func sharedWebViewAppearanceDisablesDefaultWhiteBackground() {
        let webView = WKWebView(frame: .zero)

        BrowserWebViewAppearance.configure(webView)

        #expect(webView.wantsLayer)
        #expect(webView.layer?.backgroundColor == CocxyColors.base.cgColor)
        #expect(webView.value(forKey: "drawsBackground") as? Bool == false)
    }

    @Test("navigation policy allows only web URLs and owned error pages")
    func navigationPolicyAllowsOnlyWebURLsAndOwnedErrorPages() {
        #expect(BrowserNavigationPolicy.allows(URL(string: "http://localhost:3000/")))
        #expect(BrowserNavigationPolicy.allows(URL(string: "https://cocxy.dev/")))
        #expect(BrowserNavigationPolicy.allows(URL(string: "about:blank")))

        #expect(!BrowserNavigationPolicy.allows(URL(string: "about:config")))
        #expect(!BrowserNavigationPolicy.allows(URL(string: "file:///tmp/index.html")))
        #expect(!BrowserNavigationPolicy.allows(URL(string: "javascript:alert(1)")))
        #expect(!BrowserNavigationPolicy.allows(nil))
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}

@MainActor
private final class CapturingBrowserErrorPageLoader: BrowserErrorPageLoading {
    private(set) var loadedHTML: String?
    private(set) var baseURL: URL?

    func loadBrowserErrorHTML(_ string: String, baseURL: URL?) {
        loadedHTML = string
        self.baseURL = baseURL
    }
}
