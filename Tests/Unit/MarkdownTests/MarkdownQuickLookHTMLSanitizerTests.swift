// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownQuickLookHTMLSanitizerTests.swift - Tests for Quick Look offline preview sanitization.

import Testing
import Foundation
import AppKit
@testable import CocxyTerminal
@testable import CocxyMarkdownLib

@Suite("MarkdownQuickLookHTMLSanitizer")
struct MarkdownQuickLookHTMLSanitizerTests {

    @Test("Remote images become placeholders instead of network fetches")
    func remoteImagesBecomePlaceholders() {
        let html = #"<p><img src="https://img.shields.io/badge/test" alt="Build badge" /></p>"#
        let result = MarkdownQuickLookHTMLSanitizer.makeOfflinePreviewHTML(
            from: html,
            baseDirectory: FileManager.default.temporaryDirectory
        )

        #expect(result.contains("Remote image unavailable in Quick Look"))
        #expect(result.contains("Build badge"))
        #expect(!result.contains("https://img.shields.io"))
        #expect(!result.contains("<img "))
    }

    @Test("Remote image placeholder falls back to host when alt is missing")
    func remoteImagesUseHostFallback() {
        let html = #"<img src="https://example.com/assets/logo.png" />"#
        let result = MarkdownQuickLookHTMLSanitizer.makeOfflinePreviewHTML(
            from: html,
            baseDirectory: FileManager.default.temporaryDirectory
        )

        #expect(result.contains("example.com"))
        #expect(!result.contains("src=\"https://example.com/assets/logo.png\""))
    }

    @Test("Local images stay available via inline data URIs")
    func localImagesAreInlined() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        try makePNGData().write(to: dir.appendingPathComponent("local.png"))

        let html = #"<img src="local.png" alt="Local" />"#
        let result = MarkdownQuickLookHTMLSanitizer.makeOfflinePreviewHTML(
            from: html,
            baseDirectory: dir
        )

        #expect(result.contains("data:image/png;base64,"))
        #expect(!result.contains("src=\"local.png\""))
    }

    @Test("Data URIs remain untouched")
    func dataURIsRemainUntouched() {
        let html = #"<img src="data:image/png;base64,abc123" alt="Inline" />"#
        let result = MarkdownQuickLookHTMLSanitizer.makeOfflinePreviewHTML(
            from: html,
            baseDirectory: FileManager.default.temporaryDirectory
        )

        #expect(result == html)
    }

    private func createTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ql-sanitize-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func makePNGData() throws -> Data {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.systemGreen.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1, height: 1)).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}
