// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserConsoleCapture.swift - Captures console output from WKWebView pages.

import WebKit

// MARK: - Console Entry

/// A single console output captured from a web page.
///
/// Each entry records the log level, message text, and timestamp.
/// Entries are displayed in the DevTools console tab, color-coded by level.
///
/// - SeeAlso: ``BrowserConsoleCapture`` for the capture mechanism.
struct ConsoleEntry: Identifiable, Sendable {

    /// Unique identifier for this entry.
    let id: UUID

    /// Severity level of the console output.
    let level: Level

    /// The text content of the console message.
    let message: String

    /// When this console output was produced.
    let timestamp: Date

    /// Console output severity levels matching the JavaScript console API.
    enum Level: String, CaseIterable, Sendable {
        case log
        case warn
        case error
        case info
    }
}

// MARK: - Browser Console Capture

/// Captures `console.log`, `console.warn`, `console.error`, and `console.info`
/// output from a WKWebView by injecting JavaScript that forwards messages
/// via `WKScriptMessageHandler`.
///
/// ## Architecture
///
/// 1. A user script is injected at document start that overrides the four
///    console methods. Each override calls the original method (preserving
///    DevTools output) and posts a structured message to the native side.
///
/// 2. This class implements `WKScriptMessageHandler` to receive those messages,
///    parse them into ``ConsoleEntry`` values, and maintain a ring buffer.
///
/// ## Ring Buffer
///
/// The entries array is capped at ``maxEntries`` (500). When the cap is
/// reached, the oldest entry is removed before appending the new one.
///
/// ## Usage
///
/// ```swift
/// let capture = BrowserConsoleCapture()
/// capture.install(on: webView)
/// capture.onNewEntry = { entry in print(entry.message) }
/// ```
///
/// - SeeAlso: ``BrowserDevToolsView`` for the UI that displays captured entries.
final class BrowserConsoleCapture: NSObject, WKScriptMessageHandler {

    // MARK: - Properties

    /// All captured console entries, newest last.
    private(set) var entries: [ConsoleEntry] = []

    /// Maximum number of entries to retain.
    let maxEntries: Int = 500

    /// Called each time a new entry is captured.
    var onNewEntry: ((ConsoleEntry) -> Void)?

    /// The message handler name registered with WKUserContentController.
    static let handlerName = "cocxyConsole"

    // MARK: - JavaScript Injection

    /// JavaScript source that overrides console methods to forward output
    /// to the native message handler.
    ///
    /// Each override preserves the original console method behavior so that
    /// the browser's built-in DevTools continue to work normally.
    static let captureScript: String = """
    (function() {
        var levels = ['log', 'warn', 'error', 'info'];
        var original = {};
        levels.forEach(function(level) {
            original[level] = console[level];
            console[level] = function() {
                var args = Array.prototype.slice.call(arguments);
                original[level].apply(console, args);
                try {
                    window.webkit.messageHandlers.cocxyConsole.postMessage({
                        level: level,
                        message: args.map(function(a) {
                            return typeof a === 'object' ? JSON.stringify(a) : String(a);
                        }).join(' '),
                        timestamp: Date.now()
                    });
                } catch(e) {}
            };
        });
    })();
    """

    // MARK: - Installation

    /// Installs the console capture on a WKWebView.
    ///
    /// Adds the JavaScript user script and registers this instance as the
    /// message handler. Must be called before the web view loads any content
    /// for full coverage.
    ///
    /// - Parameter webView: The web view to instrument.
    func install(on webView: WKWebView) {
        let script = WKUserScript(
            source: Self.captureScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        webView.configuration.userContentController.addUserScript(script)
        webView.configuration.userContentController.add(self, name: Self.handlerName)
    }

    /// Removes this handler from the web view's content controller.
    ///
    /// Call this when the capture is no longer needed to break the
    /// strong reference cycle between WKUserContentController and this object.
    ///
    /// - Parameter webView: The web view to detach from.
    func uninstall(from webView: WKWebView) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.handlerName
        )
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let levelString = body["level"] as? String,
              let level = ConsoleEntry.Level(rawValue: levelString),
              let messageText = body["message"] as? String else {
            return
        }

        let timestampMillis = body["timestamp"] as? Double ?? Date().timeIntervalSince1970 * 1000
        let timestamp = Date(timeIntervalSince1970: timestampMillis / 1000)

        let entry = ConsoleEntry(
            id: UUID(),
            level: level,
            message: messageText,
            timestamp: timestamp
        )

        if entries.count >= maxEntries {
            entries.removeFirst()
        }
        entries.append(entry)

        onNewEntry?(entry)
    }

    // MARK: - Management

    /// Removes all captured entries.
    func clear() {
        entries.removeAll()
    }
}
