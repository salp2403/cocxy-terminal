// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserWebKitAutomationBridge.swift - Synchronous local automation bridge for WKWebView.

import AppKit
import Foundation
import WebKit

enum BrowserWebKitAutomationBridge {
    @MainActor
    static func install(on viewModel: BrowserViewModel, webView: WKWebView) {
        viewModel.installAutomationWebView(identifier: ObjectIdentifier(webView))
        BrowserInitScriptWebKitSupport.install(on: webView, viewModel: viewModel)
        viewModel.scriptEvaluator = { [weak webView] script, timeout in
            guard let webView else {
                return .failure("Browser web view is not available")
            }
            return evaluate(script, in: webView, timeout: timeout)
        }
        viewModel.automationBridge.authorizedScriptEvaluator = {
            [weak viewModel, weak webView] authorizedPage, script, timeout in
            guard let viewModel, let webView else {
                return .failure("Browser web view is not available")
            }
            return evaluate(
                script,
                in: webView,
                timeout: timeout,
                authorizedPage: authorizedPage,
                viewModel: viewModel
            )
        }
        viewModel.screenshotCapturer = { [weak webView] outputPath, timeout in
            guard let webView else {
                return .failure("Browser web view is not available")
            }
            return captureScreenshot(outputPath: outputPath, in: webView, timeout: timeout)
        }
        viewModel.automationBridge.authorizedScreenshotCapturer = {
            [weak viewModel, weak webView] authorizedPage, outputPath, timeout in
            guard let viewModel, let webView else {
                return .failure("Browser web view is not available")
            }
            return captureScreenshot(
                outputPath: outputPath,
                in: webView,
                timeout: timeout,
                authorizedPage: authorizedPage,
                viewModel: viewModel
            )
        }
        viewModel.automationBridge.authorizedNavigationPerformer = {
            [weak viewModel, weak webView] authorizedPage, operation, _ in
            guard let viewModel, let webView else { return false }
            return performNavigation(
                operation,
                authorizedPage: authorizedPage,
                viewModel: viewModel,
                webView: webView
            )
        }
        viewModel.cookieImporter = { cookie, profileID, timeout in
            BrowserWebKitCookieImportStore.importCookie(
                cookie,
                profileID: profileID,
                timeout: timeout
            )
        }
    }

    private static func evaluate(
        _ script: String,
        in webView: WKWebView,
        timeout: TimeInterval,
        authorizedPage: BrowserAutomationPageIdentity? = nil,
        viewModel: BrowserViewModel? = nil
    ) -> BrowserScriptEvaluationResult {
        if Thread.isMainThread {
            return .failure("Synchronous browser evaluation cannot run on the main thread")
        }

        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var result: BrowserScriptEvaluationResult = .failure("Browser evaluation did not complete")
        }
        let box = Box()

        DispatchQueue.main.async {
            if let authorizedPage {
                guard let viewModel,
                      viewModel.isCurrentAutomationPage(
                        authorizedPage,
                        webViewIdentifier: ObjectIdentifier(webView),
                        webViewURL: webView.url?.absoluteString
                      ) else {
                    box.result = .failure("Approved browser page is no longer current")
                    semaphore.signal()
                    return
                }
            }
            if script.contains("waitForCocxyActionable") {
                Task { @MainActor in
                    if let authorizedPage {
                        guard let viewModel,
                              viewModel.isCurrentAutomationPage(
                                authorizedPage,
                                webViewIdentifier: ObjectIdentifier(webView),
                                webViewURL: webView.url?.absoluteString
                              ) else {
                            box.result = .failure("Approved browser page is no longer current")
                            semaphore.signal()
                            return
                        }
                    }
                    do {
                        let value = try await webView.callAsyncJavaScript(
                            "return await \(script)",
                            arguments: [:],
                            in: nil,
                            contentWorld: .page
                        )
                        if let authorizedPage {
                            guard let viewModel,
                                  viewModel.isCurrentAutomationPage(
                                    authorizedPage,
                                    webViewIdentifier: ObjectIdentifier(webView),
                                    webViewURL: webView.url?.absoluteString
                                  ) else {
                                box.result = .failure("Approved browser page is no longer current")
                                semaphore.signal()
                                return
                            }
                        }
                        box.result = .success(stringValue(for: value))
                    } catch {
                        box.result = .failure(error.localizedDescription)
                    }
                    semaphore.signal()
                }
            } else {
                webView.evaluateJavaScript(script) { value, error in
                    if let authorizedPage {
                        guard let viewModel,
                              viewModel.isCurrentAutomationPage(
                                authorizedPage,
                                webViewIdentifier: ObjectIdentifier(webView),
                                webViewURL: webView.url?.absoluteString
                              ) else {
                            box.result = .failure("Approved browser page is no longer current")
                            semaphore.signal()
                            return
                        }
                    }
                    if let error {
                        box.result = .failure(error.localizedDescription)
                    } else {
                        box.result = .success(stringValue(for: value))
                    }
                    semaphore.signal()
                }
            }
        }

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            return .failure("Browser evaluation timed out")
        }
        return box.result
    }

    private static func performNavigation(
        _ operation: BrowserAutomationNavigationOperation,
        authorizedPage: BrowserAutomationPageIdentity,
        viewModel: BrowserViewModel,
        webView: WKWebView
    ) -> Bool {
        let work = {
            MainActor.assumeIsolated { () -> Bool in
                guard viewModel.isCurrentAutomationPage(
                    authorizedPage,
                    webViewIdentifier: ObjectIdentifier(webView),
                    webViewURL: webView.url?.absoluteString
                ) else {
                    return false
                }
                switch operation {
                case .load(let url):
                    viewModel.applyAutomationNavigationURL(url)
                    webView.load(URLRequest(url: url))
                case .goBack:
                    webView.goBack()
                case .goForward:
                    webView.goForward()
                case .reload:
                    webView.reload()
                }
                return true
            }
        }
        if Thread.isMainThread {
            return work()
        }
        return DispatchQueue.main.sync(execute: work)
    }

    private static func captureScreenshot(
        outputPath: String?,
        in webView: WKWebView,
        timeout: TimeInterval,
        authorizedPage: BrowserAutomationPageIdentity? = nil,
        viewModel: BrowserViewModel? = nil
    ) -> BrowserScreenshotCaptureResult {
        if Thread.isMainThread {
            return .failure("Synchronous browser screenshot cannot run on the main thread")
        }

        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var result: BrowserScreenshotCaptureResult = .failure("Browser screenshot did not complete")
        }
        let box = Box()

        DispatchQueue.main.async {
            if let authorizedPage {
                guard let viewModel,
                      viewModel.isCurrentAutomationPage(
                        authorizedPage,
                        webViewIdentifier: ObjectIdentifier(webView),
                        webViewURL: webView.url?.absoluteString
                      ) else {
                    box.result = .failure("Approved browser page is no longer current")
                    semaphore.signal()
                    return
                }
            }
            webView.takeSnapshot(with: nil) { image, error in
                if let authorizedPage {
                    guard let viewModel,
                          viewModel.isCurrentAutomationPage(
                            authorizedPage,
                            webViewIdentifier: ObjectIdentifier(webView),
                            webViewURL: webView.url?.absoluteString
                          ) else {
                        box.result = .failure("Approved browser page is no longer current")
                        semaphore.signal()
                        return
                    }
                }
                if let error {
                    box.result = .failure(error.localizedDescription)
                    semaphore.signal()
                    return
                }
                guard let image,
                      let pngData = pngData(for: image) else {
                    box.result = .failure("Browser screenshot did not produce PNG data")
                    semaphore.signal()
                    return
                }
                if let outputPath, !outputPath.isEmpty {
                    do {
                        let url = URL(fileURLWithPath: outputPath)
                        let parent = url.deletingLastPathComponent()
                        try FileManager.default.createDirectory(
                            at: parent,
                            withIntermediateDirectories: true
                        )
                        try pngData.write(to: url, options: .atomic)
                        box.result = .file(path: url.path, byteCount: pngData.count)
                    } catch {
                        box.result = .failure(error.localizedDescription)
                    }
                } else {
                    let base64 = pngData.base64EncodedString()
                    box.result = .dataURL("data:image/png;base64,\(base64)", byteCount: pngData.count)
                }
                semaphore.signal()
            }
        }

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            return .failure("Browser screenshot timed out")
        }
        return box.result
    }

    private static func stringValue(for value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    private static func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

}

enum BrowserWebKitCookieImportError: LocalizedError {
    case missingValue
    case invalidCookie
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingValue:
            return "Imported cookie has no readable value"
        case .invalidCookie:
            return "Imported cookie could not be converted to HTTPCookie"
        case .timedOut:
            return "Timed out while importing cookie into WebKit storage"
        case .failed(let message):
            return message
        }
    }
}

enum BrowserCookieBatchWaitResult: Equatable {
    case completed(Int)
    case timedOut(Int)
    case cancelled(Int)
}

private final class BrowserCookieBatchCompletionState: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var completedCount = 0

    func completeOne() {
        lock.lock()
        completedCount += 1
        lock.unlock()
        semaphore.signal()
    }

    func snapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return completedCount
    }
}

enum BrowserWebsiteDataStoreWaitResult {
    case completed(WKWebsiteDataStore)
    case timedOut
    case cancelled
}

private final class BrowserWebsiteDataStoreCompletionState: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var value: WKWebsiteDataStore?

    func complete(_ value: WKWebsiteDataStore) {
        lock.lock()
        guard self.value == nil else {
            lock.unlock()
            return
        }
        self.value = value
        lock.unlock()
        semaphore.signal()
    }

    func snapshot() -> WKWebsiteDataStore? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class BrowserWebKitCookieImportStore: BrowserImportedCookieStoring, @unchecked Sendable {
    @MainActor
    private enum DataStoreRegistry {
        static var stores: [UUID: WKWebsiteDataStore] = [:]

        static func store(for profileID: UUID) -> WKWebsiteDataStore {
            if let existing = stores[profileID] { return existing }
            let created = WKWebsiteDataStore(forIdentifier: profileID)
            stores[profileID] = created
            return created
        }
    }

    private let viewModelProvider: @Sendable () -> BrowserViewModel?
    private let timeout: TimeInterval
    private let batchSize: Int

    init(
        viewModelProvider: @escaping @Sendable () -> BrowserViewModel? = { nil },
        timeout: TimeInterval = 3,
        batchSize: Int = 128
    ) {
        self.viewModelProvider = viewModelProvider
        self.timeout = timeout
        self.batchSize = min(max(batchSize, 1), 512)
    }

    func saveImportedCookie(_ cookie: BrowserImportedCookie, profileID: UUID) throws {
        try saveImportedCookies([cookie], profileID: profileID)
    }

    func saveImportedCookies(_ cookies: [BrowserImportedCookie], profileID: UUID) throws {
        guard !cookies.isEmpty else { return }
        guard !Task.isCancelled else { throw BrowserImportError.cancelled }
        if cookies.count == 1,
           let result = viewModelProvider()?.automationBridge.importCookie(
               cookies[0],
               profileID: profileID,
               timeout: timeout
           ) {
            switch result {
            case .success: return
            case .partial(let importedCount, let totalCount, let message):
                throw BrowserImportedCookieBatchWriteError(
                    importedCount: importedCount,
                    totalCount: totalCount,
                    detail: message
                )
            case .indeterminate(
                let importedCount,
                let totalCount,
                let uncertainCount,
                let message
            ):
                throw BrowserImportedCookieBatchWriteError(
                    importedCount: importedCount,
                    totalCount: totalCount,
                    uncertainCount: uncertainCount,
                    detail: message
                )
            case .failure(let message): throw BrowserWebKitCookieImportError.failed(message)
            }
        }

        let result = Self.importCookies(
            cookies,
            profileID: profileID,
            timeout: timeout,
            batchSize: batchSize
        )
        switch result {
        case .success:
            return
        case .partial(let importedCount, let totalCount, let message):
            throw BrowserImportedCookieBatchWriteError(
                importedCount: importedCount,
                totalCount: totalCount,
                detail: message
            )
        case .indeterminate(
            let importedCount,
            let totalCount,
            let uncertainCount,
            let message
        ):
            throw BrowserImportedCookieBatchWriteError(
                importedCount: importedCount,
                totalCount: totalCount,
                uncertainCount: uncertainCount,
                detail: message
            )
        case .failure(let message):
            throw BrowserWebKitCookieImportError.failed(message)
        }
    }

    static func importCookie(
        _ imported: BrowserImportedCookie,
        profileID: UUID,
        timeout: TimeInterval
    ) -> BrowserCookieImportResult {
        importCookies([imported], profileID: profileID, timeout: timeout, batchSize: 1)
    }

    static func importCookies(
        _ importedCookies: [BrowserImportedCookie],
        profileID: UUID,
        timeout: TimeInterval,
        batchSize: Int = 128
    ) -> BrowserCookieImportResult {
        guard !Thread.isMainThread else {
            return .failure("Synchronous browser cookie import cannot run on the main thread")
        }
        let cookies = importedCookies.compactMap(httpCookie)
        guard cookies.count == importedCookies.count else {
            return .failure(BrowserWebKitCookieImportError.invalidCookie.localizedDescription)
        }
        guard !cookies.isEmpty else { return .success }
        guard !Task.isCancelled else {
            return .failure(BrowserImportError.cancelled.localizedDescription)
        }

        let operationTimeout = timeout.isFinite ? max(timeout, 0) : 0
        let operationDeadline = monotonicDeadline(after: operationTimeout)
        let batchCompletionTimeout = timeout.isFinite
            ? min(max(timeout, 1), 30)
            : 3
        let dataStore: WKWebsiteDataStore
        switch waitForDataStore(
            hardTimeout: batchCompletionTimeout,
            submit: { completion in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        completion(DataStoreRegistry.store(for: profileID))
                    }
                }
            }
        ) {
        case .completed(let value):
            dataStore = value
        case .timedOut:
            return .failure("Timed out while opening WebKit cookie storage")
        case .cancelled:
            return .failure(BrowserImportError.cancelled.localizedDescription)
        }
        let boundedBatchSize = min(max(batchSize, 1), 512)
        var completedCount = 0
        while completedCount < cookies.count {
            guard !Task.isCancelled else {
                return .partial(
                    importedCount: completedCount,
                    totalCount: cookies.count,
                    message: BrowserImportError.cancelled.localizedDescription
                )
            }
            let upperBound = min(completedCount + boundedBatchSize, cookies.count)
            let batch = Array(cookies[completedCount..<upperBound])
            let waitResult = waitForCookieBatch(
                cookieCount: batch.count,
                hardTimeout: batchCompletionTimeout,
                settleAfterTimeout: true
            ) { completion in
                DispatchQueue.main.async {
                    for cookie in batch {
                        dataStore.httpCookieStore.setCookie(
                            cookie,
                            completionHandler: completion
                        )
                    }
                }
            }
            let completedInBatch: Int
            switch waitResult {
            case .completed(let count):
                completedInBatch = count
            case .timedOut(let count):
                return .indeterminate(
                    importedCount: completedCount + count,
                    totalCount: cookies.count,
                    uncertainCount: batch.count - count,
                    message: BrowserWebKitCookieImportError.timedOut.localizedDescription
                )
            case .cancelled(let count):
                return .partial(
                    importedCount: completedCount + count,
                    totalCount: cookies.count,
                    message: BrowserImportError.cancelled.localizedDescription
                )
            }
            completedCount += completedInBatch
            if completedCount < cookies.count,
               DispatchTime.now().uptimeNanoseconds >= operationDeadline {
                return .partial(
                    importedCount: completedCount,
                    totalCount: cookies.count,
                    message: "the cookie import time budget was reached before another batch began"
                )
            }
        }
        return .success
    }

    static func waitForDataStore(
        hardTimeout: TimeInterval,
        submit: (@escaping @Sendable (WKWebsiteDataStore) -> Void) -> Void
    ) -> BrowserWebsiteDataStoreWaitResult {
        let state = BrowserWebsiteDataStoreCompletionState()
        submit { state.complete($0) }
        let safeTimeout = hardTimeout.isFinite ? max(hardTimeout, 0) : 0
        let deadline = monotonicDeadline(after: safeTimeout)

        while true {
            if let value = state.snapshot() { return .completed(value) }
            if Task.isCancelled { return .cancelled }
            let now = DispatchTime.now().uptimeNanoseconds
            if now >= deadline { return .timedOut }
            let waitNanoseconds = min(deadline - now, 25_000_000)
            _ = state.semaphore.wait(
                timeout: DispatchTime(uptimeNanoseconds: now + waitNanoseconds)
            )
        }
    }

    static func waitForCookieBatch(
        cookieCount: Int,
        hardTimeout: TimeInterval,
        settleAfterTimeout: Bool = false,
        settlementTimeout: TimeInterval = 5,
        submit: (@escaping @Sendable () -> Void) -> Void
    ) -> BrowserCookieBatchWaitResult {
        guard cookieCount > 0 else { return .completed(0) }
        let state = BrowserCookieBatchCompletionState()
        submit { state.completeOne() }
        let safeTimeout = hardTimeout.isFinite ? max(hardTimeout, 0) : 0
        let deadline = monotonicDeadline(after: safeTimeout)
        let safeSettlementTimeout = settlementTimeout.isFinite
            ? max(settlementTimeout, 0)
            : 0
        var cancellationObserved = Task.isCancelled
        var boundaryResult: BrowserCookieBatchWaitResult?
        var settlementDeadline: UInt64?

        while true {
            let completed = min(state.snapshot(), cookieCount)
            cancellationObserved = cancellationObserved || Task.isCancelled
            if completed == cookieCount {
                if cancellationObserved { return .cancelled(completed) }
                if boundaryResult != nil { return .timedOut(completed) }
                return .completed(completed)
            }
            let now = DispatchTime.now().uptimeNanoseconds
            if boundaryResult == nil, now >= deadline {
                let timedOut = BrowserCookieBatchWaitResult.timedOut(completed)
                guard settleAfterTimeout else { return timedOut }
                boundaryResult = timedOut
                settlementDeadline = monotonicDeadline(after: safeSettlementTimeout)
            }
            if let settlementDeadline, now >= settlementDeadline {
                return .timedOut(completed)
            }
            let nextDeadline = settlementDeadline ?? deadline
            let waitNanoseconds = min(nextDeadline - now, 25_000_000)
            _ = state.semaphore.wait(
                timeout: DispatchTime(uptimeNanoseconds: now + waitNanoseconds)
            )
        }
    }

    private static func monotonicDeadline(after seconds: TimeInterval) -> UInt64 {
        let now = DispatchTime.now().uptimeNanoseconds
        guard seconds > 0 else { return now }
        let maximumSeconds = Double(UInt64.max - now) / 1_000_000_000
        let boundedSeconds = min(seconds, maximumSeconds)
        return now + UInt64(boundedSeconds * 1_000_000_000)
    }

    fileprivate static func httpCookie(from imported: BrowserImportedCookie) -> HTTPCookie? {
        guard let value = imported.value, !imported.isPartitioned else { return nil }
        let normalizedDomain = imported.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let scheme = imported.isSecure ? "https" : "http"
        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: imported.domain,
            .path: imported.path.isEmpty ? "/" : imported.path,
            .name: imported.name,
            .value: value,
        ]
        if !normalizedDomain.isEmpty,
           let originURL = URL(string: "\(scheme)://\(normalizedDomain)") {
            properties[.originURL] = originURL
        }
        if let expiresAt = imported.expiresAt {
            properties[.expires] = expiresAt
        }
        if imported.isSecure {
            properties[.secure] = "TRUE"
        }
        if imported.isHTTPOnly {
            properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        }
        switch imported.sameSite {
        case .none:
            properties[HTTPCookiePropertyKey("SameSite")] = "None"
        case .lax:
            properties[HTTPCookiePropertyKey("SameSite")] = "Lax"
        case .strict:
            properties[HTTPCookiePropertyKey("SameSite")] = "Strict"
        case .unspecified:
            break
        }
        return HTTPCookie(properties: properties)
    }
}
