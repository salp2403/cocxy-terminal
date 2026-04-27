// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserDOMGrabPayload.swift - Captured DOM-grab payload model.

import Foundation

/// One DOM-grab capture: the user toggled grab mode in the browser
/// panel, clicked an HTML element, and the in-page JS reported the
/// selector, the visible text, and (optionally) the page screenshot
/// back to the host.
///
/// Stays a value type with no AppKit / WebKit dependency so the model
/// is shared trivially between the JS-bridged handler, the in-process
/// formatter that turns it into the agent-prompt payload, and any
/// future history / replay surface.
struct BrowserDOMGrabPayload: Sendable, Equatable {

    /// CSS selector pointing at the element the user clicked. Produced
    /// by the in-page JS; the algorithm prefers `id`, falls back to
    /// `[data-testid]`, then a `tag.class` combination, and finally an
    /// `nth-child` chain so the selector always identifies a unique
    /// node even on pages without stable identifiers.
    let selector: String

    /// URL of the page the grab was captured from. Carried through so
    /// the agent on the receiving end can fetch / re-load it without
    /// the user having to retype the address.
    let pageURL: URL

    /// `<title>` of the page when the grab was captured, used as the
    /// human-friendly header in the formatted payload.
    let pageTitle: String

    /// Visible text of the clicked element (`innerText` from JS).
    /// May be empty when the user grabbed an icon-only or image-only
    /// node; the formatter omits the corresponding line in that case.
    let visibleText: String

    /// Wall-clock instant the grab was captured. Pinned at the host
    /// side rather than read from the browser context so two grabs on
    /// the same page get a strictly increasing timestamp regardless of
    /// the page's own clock skew.
    let timestamp: Date

    /// Optional URL on disk where the page snapshot was saved. `nil`
    /// when the snapshot pipeline has not been wired yet, when the
    /// snapshot failed, or when the user opted out. The formatter
    /// omits the screenshot line entirely in that case.
    let screenshotPath: URL?

    init(
        selector: String,
        pageURL: URL,
        pageTitle: String,
        visibleText: String,
        timestamp: Date = Date(),
        screenshotPath: URL? = nil
    ) {
        self.selector = selector
        self.pageURL = pageURL
        self.pageTitle = pageTitle
        self.visibleText = visibleText
        self.timestamp = timestamp
        self.screenshotPath = screenshotPath
    }
}
