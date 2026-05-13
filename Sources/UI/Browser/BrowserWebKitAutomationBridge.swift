// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserWebKitAutomationBridge.swift - Synchronous local automation bridge for WKWebView.

import AppKit
import Foundation
import WebKit

enum BrowserWebKitAutomationBridge {
    @MainActor
    static func install(on viewModel: BrowserViewModel, webView: WKWebView) {
        viewModel.scriptEvaluator = { [weak webView] script, timeout in
            guard let webView else {
                return .failure("Browser web view is not available")
            }
            return evaluate(script, in: webView, timeout: timeout)
        }
        viewModel.screenshotCapturer = { [weak webView] outputPath, timeout in
            guard let webView else {
                return .failure("Browser web view is not available")
            }
            return captureScreenshot(outputPath: outputPath, in: webView, timeout: timeout)
        }
        viewModel.cookieImporter = { cookie, profileID, timeout in
            BrowserWebKitCookieImportStore.importCookie(
                cookie,
                profileID: profileID,
                timeout: timeout
            )
        }
        installPendingCookies(on: webView, profileID: viewModel.activeProfileID)
    }

    private static func evaluate(
        _ script: String,
        in webView: WKWebView,
        timeout: TimeInterval
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
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    box.result = .failure(error.localizedDescription)
                } else {
                    box.result = .success(stringValue(for: value))
                }
                semaphore.signal()
            }
        }

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            return .failure("Browser evaluation timed out")
        }
        return box.result
    }

    private static func captureScreenshot(
        outputPath: String?,
        in webView: WKWebView,
        timeout: TimeInterval
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
            webView.takeSnapshot(with: nil) { image, error in
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

    private static func installPendingCookies(on webView: WKWebView, profileID: UUID?) {
        guard let profileID else { return }
        let pendingCookies = BrowserPendingCookieImportStore.shared.drain(profileID: profileID)
        guard !pendingCookies.isEmpty else { return }

        let store = webView.configuration.websiteDataStore.httpCookieStore
        for imported in pendingCookies {
            guard let cookie = BrowserWebKitCookieImportStore.httpCookie(from: imported) else { continue }
            store.setCookie(cookie) { [weak webView] in
                guard let webView, webView.url != nil else { return }
                webView.reload()
            }
        }
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

final class BrowserWebKitCookieImportStore: BrowserImportedCookieStoring, @unchecked Sendable {
    private let viewModelProvider: @Sendable () -> BrowserViewModel?
    private let timeout: TimeInterval

    init(
        viewModelProvider: @escaping @Sendable () -> BrowserViewModel? = { nil },
        timeout: TimeInterval = 3
    ) {
        self.viewModelProvider = viewModelProvider
        self.timeout = timeout
    }

    func saveImportedCookie(_ cookie: BrowserImportedCookie, profileID: UUID) throws {
        if let result = viewModelProvider()?.automationBridge.importCookie(
            cookie,
            profileID: profileID,
            timeout: timeout
        ) {
            switch result {
            case .success:
                return
            case .failure(let message):
                throw BrowserWebKitCookieImportError.failed(message)
            }
        }

        switch Self.importCookie(cookie, profileID: profileID, timeout: timeout) {
        case .success:
            BrowserPendingCookieImportStore.shared.save(cookie, profileID: profileID)
            return
        case .failure(let message):
            throw BrowserWebKitCookieImportError.failed(message)
        }
    }

    static func importCookie(
        _ imported: BrowserImportedCookie,
        profileID: UUID,
        timeout: TimeInterval
    ) -> BrowserCookieImportResult {
        guard !Thread.isMainThread else {
            return .failure("Synchronous browser cookie import cannot run on the main thread")
        }
        guard let cookie = httpCookie(from: imported) else {
            return .failure(BrowserWebKitCookieImportError.invalidCookie.localizedDescription)
        }

        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var completed = false
            var webView: WKWebView?
        }
        let box = Box()

        DispatchQueue.main.async {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: profileID)
            let webView = WKWebView(frame: .zero, configuration: configuration)
            box.webView = webView
            let store = webView.configuration.websiteDataStore.httpCookieStore
            store.setCookie(cookie) {
                box.completed = true
                box.webView = nil
                semaphore.signal()
            }
        }

        guard semaphore.wait(timeout: .now() + timeout) == .success,
              box.completed else {
            return .failure(BrowserWebKitCookieImportError.timedOut.localizedDescription)
        }
        return .success
    }

    fileprivate static func httpCookie(from imported: BrowserImportedCookie) -> HTTPCookie? {
        guard let value = imported.value else { return nil }
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
        return HTTPCookie(properties: properties)
    }
}

final class BrowserPendingCookieImportStore: @unchecked Sendable {
    static let shared = BrowserPendingCookieImportStore()

    private let lock = NSLock()
    private var cookiesByProfile: [UUID: [BrowserImportedCookie]] = [:]

    private init() {}

    func save(_ cookie: BrowserImportedCookie, profileID: UUID) {
        lock.lock()
        cookiesByProfile[profileID, default: []].append(cookie)
        lock.unlock()
    }

    func drain(profileID: UUID) -> [BrowserImportedCookie] {
        lock.lock()
        defer { lock.unlock() }
        let cookies = cookiesByProfile[profileID] ?? []
        cookiesByProfile[profileID] = nil
        return cookies
    }
}
