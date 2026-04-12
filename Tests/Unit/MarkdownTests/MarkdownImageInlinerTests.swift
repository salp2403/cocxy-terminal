// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownImageInlinerTests.swift - Tests for local image to data URI conversion.

import Testing
import Foundation
import AppKit
@testable import CocxyTerminal

@Suite("MarkdownImageInliner")
struct MarkdownImageInlinerTests {

    @Test("Relative image path is inlined as data URI")
    func inlinesRelativePath() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        let pngData = try makePNGData()
        let imageURL = dir.appendingPathComponent("photo.png")
        try pngData.write(to: imageURL)

        let html = "<html><body><img src=\"photo.png\" alt=\"test\" /></body></html>"
        let result = MarkdownImageInliner.inlineLocalImages(in: html, baseDirectory: dir)

        #expect(result.contains("data:image/png;base64,"))
        #expect(!result.contains("src=\"photo.png\""))
    }

    @Test("Absolute file path is inlined")
    func inlinesAbsolutePath() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        let pngData = try makePNGData()
        let imageURL = dir.appendingPathComponent("img.png")
        try pngData.write(to: imageURL)

        let html = "<img src=\"\(imageURL.path)\" />"
        let result = MarkdownImageInliner.inlineLocalImages(in: html, baseDirectory: dir)

        #expect(result.contains("data:image/png;base64,"))
    }

    @Test("Remote URLs are left unchanged")
    func skipsRemoteURLs() {
        let dir = FileManager.default.temporaryDirectory
        let html = "<img src=\"https://example.com/image.png\" />"
        let result = MarkdownImageInliner.inlineLocalImages(in: html, baseDirectory: dir)

        #expect(result == html)
    }

    @Test("Data URIs are left unchanged")
    func skipsDataURIs() {
        let dir = FileManager.default.temporaryDirectory
        let html = "<img src=\"data:image/png;base64,abc123\" />"
        let result = MarkdownImageInliner.inlineLocalImages(in: html, baseDirectory: dir)

        #expect(result == html)
    }

    @Test("Missing file leaves src unchanged")
    func missingFileUnchanged() {
        let dir = FileManager.default.temporaryDirectory
        let html = "<img src=\"nonexistent.png\" />"
        let result = MarkdownImageInliner.inlineLocalImages(in: html, baseDirectory: dir)

        #expect(result.contains("src=\"nonexistent.png\""))
    }

    @Test("JPEG extension uses correct MIME type")
    func jpegMimeType() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        try makeJPEGData().write(to: dir.appendingPathComponent("photo.jpg"))

        let html = "<img src=\"photo.jpg\" />"
        let result = MarkdownImageInliner.inlineLocalImages(in: html, baseDirectory: dir)

        #expect(result.contains("data:image/jpeg;base64,"))
    }

    @Test("Multiple images are all inlined")
    func multipleImages() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        let png = try makePNGData()
        try png.write(to: dir.appendingPathComponent("a.png"))
        try png.write(to: dir.appendingPathComponent("b.png"))

        let html = "<img src=\"a.png\" /><img src=\"b.png\" />"
        let result = MarkdownImageInliner.inlineLocalImages(in: html, baseDirectory: dir)

        let dataCount = result.components(separatedBy: "data:image/png;base64,").count - 1
        #expect(dataCount == 2)
    }

    @Test("HTML without images is returned unchanged")
    func noImagesUnchanged() {
        let dir = FileManager.default.temporaryDirectory
        let html = "<h1>Hello</h1><p>World</p>"
        let result = MarkdownImageInliner.inlineLocalImages(in: html, baseDirectory: dir)

        #expect(result == html)
    }

    @Test("Non-image file extensions are NOT inlined")
    func rejectsNonImageExtensions() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        // Create files with dangerous extensions
        try "secret-key".write(to: dir.appendingPathComponent("key.pem"), atomically: true, encoding: .utf8)
        try "DB_PASS=abc".write(to: dir.appendingPathComponent("config.env"), atomically: true, encoding: .utf8)
        try "{}".write(to: dir.appendingPathComponent("data.json"), atomically: true, encoding: .utf8)

        let html = """
        <img src="key.pem" /><img src="config.env" /><img src="data.json" />
        """
        let result = MarkdownImageInliner.inlineLocalImages(in: html, baseDirectory: dir)

        // None of these should be inlined — they must stay as-is
        #expect(!result.contains("data:"))
        #expect(result.contains("src=\"key.pem\""))
        #expect(result.contains("src=\"config.env\""))
        #expect(result.contains("src=\"data.json\""))
    }

    @Test("SVG images ARE inlined with correct MIME type")
    func inlinesSVG() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        try "<svg></svg>".write(to: dir.appendingPathComponent("icon.svg"), atomically: true, encoding: .utf8)

        let html = "<img src=\"icon.svg\" />"
        let result = MarkdownImageInliner.inlineLocalImages(in: html, baseDirectory: dir)

        #expect(result.contains("data:image/svg+xml;base64,"))
    }

    @Test("XML file renamed to .svg is NOT inlined")
    func rejectsXMLWithoutSVGRoot() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>Token</key><string>secret</string></dict></plist>
        """
        try xml.write(to: dir.appendingPathComponent("fake.svg"), atomically: true, encoding: .utf8)

        let html = "<img src=\"fake.svg\" />"
        let result = MarkdownImageInliner.inlineLocalImages(in: html, baseDirectory: dir)

        #expect(!result.contains("data:"))
        #expect(result.contains("src=\"fake.svg\""))
    }

    @Test("File with image extension but wrong magic bytes is NOT inlined")
    func rejectsWrongMagicBytes() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        // Write a text file with .png extension — wrong magic bytes
        try "this is not a PNG".write(to: dir.appendingPathComponent("fake.png"), atomically: true, encoding: .utf8)

        let html = "<img src=\"fake.png\" />"
        let result = MarkdownImageInliner.inlineLocalImages(in: html, baseDirectory: dir)

        // Must NOT be inlined because magic bytes don't match PNG
        #expect(!result.contains("data:"))
        #expect(result.contains("src=\"fake.png\""))
    }

    @Test("Real PNG with correct magic bytes IS inlined")
    func inlinesRealPNG() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        let pngData = try makePNGData()
        try pngData.write(to: dir.appendingPathComponent("real.png"))

        let html = "<img src=\"real.png\" />"
        let result = MarkdownImageInliner.inlineLocalImages(in: html, baseDirectory: dir)

        #expect(result.contains("data:image/png;base64,"))
    }

    // MARK: - Helpers

    private func createTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("img-inline-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func makePNGData() throws -> Data {
        try makeBitmapData(fileType: .png)
    }

    private func makeJPEGData() throws -> Data {
        try makeBitmapData(fileType: .jpeg)
    }

    private func makeBitmapData(fileType: NSBitmapImageRep.FileType) throws -> Data {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1, height: 1)).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: fileType, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}
