// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserNetworkMonitor.swift - Captures network requests from WKWebView pages.

import Foundation
import WebKit
import Combine

// MARK: - Network Entry

/// A single network request captured from a web page.
///
/// Populated from the browser's Performance API (`performance.getEntriesByType('resource')`).
/// The method is inferred from the `initiatorType` since the Performance API does not
/// expose HTTP methods directly.
///
/// - SeeAlso: ``BrowserNetworkMonitor`` for the polling mechanism.
struct NetworkEntry: Identifiable, Sendable {

    /// Unique identifier for this entry.
    let id: UUID

    /// The resource URL.
    let url: String

    /// Inferred HTTP method based on initiator type.
    let method: String

    /// Total request duration in milliseconds.
    let duration: Double

    /// Transfer size in bytes. Zero if the browser does not expose this value.
    let transferSize: Int64

    /// When this request was captured.
    let timestamp: Date

    /// The Performance API initiator type (e.g., "fetch", "xmlhttprequest", "script", "css", "img").
    let initiatorType: String
}

// MARK: - Browser Network Monitor

/// Polls a WKWebView's Performance API to capture network request entries.
///
/// ## Polling Strategy
///
/// Every ``pollInterval`` seconds, evaluates JavaScript that reads
/// `performance.getEntriesByType('resource')` and clears the buffer.
/// New entries are deduplicated by URL + start time to avoid duplicates
/// across poll cycles.
///
/// ## Ring Buffer
///
/// Entries are capped at ``maxEntries`` (200). When the cap is reached,
/// the oldest entries are removed to make room.
///
/// ## Method Inference
///
/// The Performance Resource Timing API does not expose HTTP methods.
/// The monitor infers the method from the `initiatorType`:
/// - `fetch` and `xmlhttprequest` map to the generic "XHR/Fetch".
/// - All other types map to "GET" (which covers script, css, img, link, etc.).
///
/// - SeeAlso: ``BrowserDevToolsView`` for the UI that displays network entries.
@MainActor
final class BrowserNetworkMonitor: ObservableObject {

    // MARK: - Published State

    /// All captured network entries, newest last.
    @Published private(set) var entries: [NetworkEntry] = []

    // MARK: - Configuration

    /// Maximum number of entries to retain.
    let maxEntries: Int = 200

    /// Interval between Performance API polls, in seconds.
    let pollInterval: TimeInterval = 2.0

    // MARK: - Private State

    private var pollTimer: AnyCancellable?
    private weak var webView: WKWebView?

    /// Set of keys used to deduplicate entries across poll cycles.
    /// Each key is `url|startTime` to uniquely identify a request.
    private var seenEntryKeys: Set<String> = []

    // MARK: - JavaScript

    /// JavaScript that reads resource timing entries and clears the buffer.
    ///
    /// Returns a JSON array of objects with the fields needed to construct
    /// ``NetworkEntry`` values. Calls `clearResourceTimings()` after reading
    /// to avoid processing the same entries on the next poll.
    private static let pollScript: String = """
    (function() {
        var entries = performance.getEntriesByType('resource');
        var result = entries.map(function(e) {
            return {
                name: e.name,
                initiatorType: e.initiatorType || 'other',
                duration: e.duration,
                transferSize: e.transferSize || 0,
                startTime: e.startTime
            };
        });
        performance.clearResourceTimings();
        return JSON.stringify(result);
    })();
    """

    // MARK: - Lifecycle

    /// Starts polling the given WKWebView for network entries.
    ///
    /// Any previous polling session is stopped first. The first poll
    /// executes immediately, then repeats at ``pollInterval``.
    ///
    /// - Parameter webView: The web view to monitor.
    func startMonitoring(_ webView: WKWebView) {
        stopMonitoring()
        self.webView = webView

        pollTimer = Timer.publish(every: pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pollEntries()
            }

        pollEntries()
    }

    /// Stops polling and releases the web view reference.
    func stopMonitoring() {
        pollTimer?.cancel()
        pollTimer = nil
        webView = nil
    }

    /// Removes all captured entries and resets deduplication state.
    func clear() {
        entries.removeAll()
        seenEntryKeys.removeAll()
    }

    // MARK: - Polling

    private func pollEntries() {
        guard let webView else { return }

        webView.evaluateJavaScript(Self.pollScript) { [weak self] result, error in
            guard let self,
                  error == nil,
                  let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8),
                  let rawEntries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return
            }

            Task { @MainActor [weak self] in
                self?.processRawEntries(rawEntries)
            }
        }
    }

    private func processRawEntries(_ rawEntries: [[String: Any]]) {
        let now = Date()

        for raw in rawEntries {
            guard let urlString = raw["name"] as? String,
                  let startTime = raw["startTime"] as? Double else {
                continue
            }

            let deduplicationKey = "\(urlString)|\(startTime)"
            guard !seenEntryKeys.contains(deduplicationKey) else { continue }
            seenEntryKeys.insert(deduplicationKey)

            let initiatorType = raw["initiatorType"] as? String ?? "other"
            let duration = raw["duration"] as? Double ?? 0
            let transferSize = raw["transferSize"] as? Int64
                ?? (raw["transferSize"] as? Double).map { Int64($0) }
                ?? 0

            let method = inferMethod(from: initiatorType)

            let entry = NetworkEntry(
                id: UUID(),
                url: urlString,
                method: method,
                duration: duration,
                transferSize: transferSize,
                timestamp: now,
                initiatorType: initiatorType
            )

            if entries.count >= maxEntries {
                entries.removeFirst()
            }
            entries.append(entry)
        }
    }

    // MARK: - Method Inference

    /// Infers the HTTP method from the Performance API initiator type.
    ///
    /// Fetch and XMLHttpRequest initiators could be any method, so they
    /// are labeled generically. All other initiator types are resource
    /// loads that use GET.
    private func inferMethod(from initiatorType: String) -> String {
        switch initiatorType {
        case "fetch", "xmlhttprequest":
            return "XHR"
        default:
            return "GET"
        }
    }
}
