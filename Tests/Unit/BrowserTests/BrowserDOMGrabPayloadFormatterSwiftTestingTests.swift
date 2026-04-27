// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Unit coverage for `BrowserDOMGrabPayloadFormatter`, the pure helper
/// that turns a captured DOM-grab payload into the multi-line text that
/// the surface lifecycle injects into the active terminal pane.
///
/// The contract the formatter must honour:
///
///   * The payload is human-readable and bounded — terminal-aware CLIs
///     read it as a single message and use the included selector / URL /
///     screenshot path to reason about the captured element.
///   * Visible text is trimmed and truncated above a fixed character
///     limit so a paste-like dump of an entire page does not blow past
///     the agent prompt's context window.
///   * Optional fields (`screenshotPath`, empty visible text) are
///     omitted from the output rather than rendered as blank lines —
///     blank lines confuse line-oriented prompters that look at the
///     first non-empty line as the command body.
@Suite("BrowserDOMGrabPayloadFormatter")
struct BrowserDOMGrabPayloadFormatterSwiftTestingTests {

    // MARK: - Helpers

    private static let frozenInstant = Date(timeIntervalSince1970: 1_750_000_000)

    private func makePayload(
        selector: String = "button#login",
        pageURL: URL = URL(string: "https://example.com/path?query=1")!,
        pageTitle: String = "Example Login",
        visibleText: String = "Sign in",
        screenshotPath: URL? = nil
    ) -> BrowserDOMGrabPayload {
        BrowserDOMGrabPayload(
            selector: selector,
            pageURL: pageURL,
            pageTitle: pageTitle,
            visibleText: visibleText,
            timestamp: Self.frozenInstant,
            screenshotPath: screenshotPath
        )
    }

    // MARK: - Full payload

    @Test("a full payload renders every field on its own line in stable order")
    func fullPayloadRendersEveryField() {
        let screenshot = URL(fileURLWithPath: "/tmp/dom-grabs/2026-04-27.png")
        let payload = makePayload(screenshotPath: screenshot)

        let result = BrowserDOMGrabPayloadFormatter.format(payload)

        let expected = """
        --- Browser DOM grab ---
        Page: Example Login
        URL: https://example.com/path?query=1
        Selector: button#login
        Text: Sign in
        Screenshot: /tmp/dom-grabs/2026-04-27.png
        ---

        """
        #expect(result == expected)
    }

    // MARK: - Optional fields

    @Test("payload without a screenshot omits the screenshot line entirely")
    func payloadWithoutScreenshotOmitsScreenshotLine() {
        let payload = makePayload(screenshotPath: nil)

        let result = BrowserDOMGrabPayloadFormatter.format(payload)

        #expect(!result.contains("Screenshot:"))
        #expect(result.contains("Text: Sign in"))
        #expect(result.contains("Selector: button#login"))
    }

    @Test("payload with empty visible text omits the text line so prompters do not see a blank")
    func emptyVisibleTextOmitsTextLine() {
        let payload = makePayload(visibleText: "")

        let result = BrowserDOMGrabPayloadFormatter.format(payload)

        #expect(!result.contains("Text:"))
        #expect(result.contains("Selector: button#login"))
    }

    @Test("payload with whitespace-only visible text is treated as empty and the text line is omitted")
    func whitespaceOnlyVisibleTextOmitsTextLine() {
        let payload = makePayload(visibleText: "   \n\t  ")

        let result = BrowserDOMGrabPayloadFormatter.format(payload)

        #expect(!result.contains("Text:"))
    }

    // MARK: - Truncation

    @Test("visible text longer than the limit is truncated with an ellipsis marker")
    func longVisibleTextIsTruncated() {
        // 600 characters of 'a', well above the 500-character limit.
        let longText = String(repeating: "a", count: 600)
        let payload = makePayload(visibleText: longText)

        let result = BrowserDOMGrabPayloadFormatter.format(payload)

        let textLine = result.split(separator: "\n").first(where: { $0.hasPrefix("Text: ") })
        let textValue = textLine.map { String($0.dropFirst("Text: ".count)) } ?? ""

        #expect(textValue.hasSuffix("..."))
        // Truncated body is exactly 500 chars + the 3-char ellipsis.
        #expect(textValue.count == BrowserDOMGrabPayloadFormatter.maxVisibleTextLength + 3)
    }

    @Test("visible text equal to the limit stays untouched and never gets the ellipsis")
    func visibleTextAtLimitIsNotTruncated() {
        let exact = String(
            repeating: "b",
            count: BrowserDOMGrabPayloadFormatter.maxVisibleTextLength
        )
        let payload = makePayload(visibleText: exact)

        let result = BrowserDOMGrabPayloadFormatter.format(payload)

        #expect(result.contains("Text: \(exact)\n"))
        #expect(!result.contains("..."))
    }

    // MARK: - Field preservation

    @Test("URL with query string and fragment is rendered verbatim")
    func urlWithQueryAndFragmentIsPreserved() {
        let url = URL(string: "https://example.com/search?q=swift+testing#results")!
        let payload = makePayload(pageURL: url)

        let result = BrowserDOMGrabPayloadFormatter.format(payload)

        #expect(result.contains("URL: https://example.com/search?q=swift+testing#results"))
    }

    @Test("complex selectors with brackets, attributes and pseudo-classes are emitted unchanged")
    func complexSelectorIsEmittedVerbatim() {
        let payload = makePayload(selector: #"div[data-testid="hero"] > a:nth-child(3)"#)

        let result = BrowserDOMGrabPayloadFormatter.format(payload)

        #expect(result.contains(#"Selector: div[data-testid="hero"] > a:nth-child(3)"#))
    }

    @Test("page title containing newlines is rendered on a single line so the format stays line-addressable")
    func pageTitleWithNewlinesIsCollapsed() {
        let payload = makePayload(pageTitle: "First line\nSecond line")

        let result = BrowserDOMGrabPayloadFormatter.format(payload)

        // The title field must occupy exactly one line; otherwise the
        // "Page:" / "URL:" prefix detector on the receiving end would
        // misalign on the embedded newline.
        let pageLines = result.split(separator: "\n").filter { $0.hasPrefix("Page:") }
        #expect(pageLines.count == 1)
        #expect(!pageLines.first!.contains("\nSecond"))
    }
}
