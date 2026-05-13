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
}
