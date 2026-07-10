// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownImageInlinerTests.swift - Tests for local image to data URI conversion.

import Testing
import Foundation
import AppKit
@testable import CocxyTerminal
@testable import CocxyMarkdownLib

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
    func skipsDataURIs() throws {
        let dir = FileManager.default.temporaryDirectory
        let dataURI = "data:image/png;base64,\(try makePNGData().base64EncodedString())"
        let html = "<img src=\"\(dataURI)\" />"
        let result = MarkdownImageInliner.inlineLocalImages(in: html, baseDirectory: dir)

        #expect(result == html)
    }

    @Test("Missing file is neutralized instead of remaining load-bearing")
    func missingFileIsNeutralized() {
        let dir = FileManager.default.temporaryDirectory
        let html = "<img src=\"nonexistent.png\" />"
        let result = MarkdownImageInliner.inlineLocalImages(in: html, baseDirectory: dir)

        #expect(!result.contains("src="))
        #expect(result.contains("data-cocxy-image-blocked=\"local\""))
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

        // None of these may remain as a load-bearing image source.
        #expect(!result.contains("data:"))
        #expect(!result.contains("src="))
        #expect(result.components(separatedBy: "data-cocxy-image-blocked=\"local\"").count - 1 == 3)
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
        #expect(!result.contains("src="))
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
        #expect(!result.contains("src="))
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

    @Test("Nested local images remain available inside the approved root")
    func nestedContainedImageIsInlined() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }
        let assets = dir.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try makePNGData().write(to: assets.appendingPathComponent("diagram.png"))

        let result = MarkdownImageInliner.makeSafeHTML(
            in: #"<img src="assets/diagram.png" />"#,
            baseDirectory: dir
        )

        #expect(result.html.contains("data:image/png;base64,"))
        #expect(result.blockedLocalImageCount == 0)
    }

    @Test("Parent, absolute, and file URL escapes are neutralized")
    func outsidePathsAreNeutralized() throws {
        let root = createTempDir()
        defer { cleanup(root) }
        let documentDirectory = root.appendingPathComponent("document", isDirectory: true)
        try FileManager.default.createDirectory(at: documentDirectory, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("private.png")
        try makePNGData().write(to: outside)
        let html = """
        <img src="../private.png" />
        <img src="\(outside.path)" />
        <img src="\(outside.absoluteString)" />
        """

        let result = MarkdownImageInliner.makeSafeHTML(
            in: html,
            baseDirectory: documentDirectory
        )

        #expect(!result.html.contains("private.png"))
        #expect(!result.html.contains("data:image/png"))
        #expect(result.blockedLocalImageCount == 3)
    }

    @Test("Symlinks cannot escape the approved image root")
    func symlinkEscapeIsNeutralized() throws {
        let root = createTempDir()
        defer { cleanup(root) }
        let documentDirectory = root.appendingPathComponent("document", isDirectory: true)
        let outsideDirectory = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: documentDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        try makePNGData().write(to: outsideDirectory.appendingPathComponent("private.png"))
        try FileManager.default.createSymbolicLink(
            at: documentDirectory.appendingPathComponent("assets"),
            withDestinationURL: outsideDirectory
        )

        let result = MarkdownImageInliner.makeSafeHTML(
            in: #"<img src="assets/private.png" />"#,
            baseDirectory: documentDirectory
        )

        #expect(!result.html.contains("src="))
        #expect(!result.html.contains("data:image/png"))
        #expect(result.blockedLocalImageCount == 1)
    }

    @Test("Root prefix collisions do not satisfy containment")
    func rootPrefixCollisionIsNeutralized() throws {
        let root = createTempDir()
        defer { cleanup(root) }
        let approved = root.appendingPathComponent("doc", isDirectory: true)
        let collision = root.appendingPathComponent("document", isDirectory: true)
        try FileManager.default.createDirectory(at: approved, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: collision, withIntermediateDirectories: true)
        let outside = collision.appendingPathComponent("private.png")
        try makePNGData().write(to: outside)

        let result = MarkdownImageInliner.makeSafeHTML(
            in: "<img src=\"\(outside.path)\" />",
            baseDirectory: approved
        )

        #expect(!result.html.contains("src="))
        #expect(result.blockedLocalImageCount == 1)
    }

    @Test("Remote image URLs are blocked until their exact host is approved")
    func remoteImagesRequireHostApproval() {
        let html = """
        <img src="HTTPS://Tracker.Example/pixel.png?id=1" alt="One" />
        <img src="https://other.example/pixel.png" alt="Two" />
        """

        let blocked = MarkdownImageInliner.makeSafeHTML(in: html, baseDirectory: nil)
        #expect(blocked.remoteHosts == ["tracker.example", "other.example"])
        #expect(blocked.blockedRemoteHosts == blocked.remoteHosts)
        #expect(!blocked.html.lowercased().contains("https://"))

        let partiallyApproved = MarkdownImageInliner.makeSafeHTML(
            in: html,
            baseDirectory: nil,
            approvedRemoteHosts: ["tracker.example"]
        )
        #expect(partiallyApproved.html.contains("HTTPS://Tracker.Example/pixel.png?id=1"))
        #expect(!partiallyApproved.html.contains("https://other.example"))
        #expect(partiallyApproved.blockedRemoteHosts == ["other.example"])
    }

    @Test("External SVG resources and invalid data images are neutralized")
    func activeImagePayloadsAreNeutralized() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }
        try #"<svg><image href="https://tracker.example/pixel.png" /></svg>"#.write(
            to: dir.appendingPathComponent("external.svg"),
            atomically: true,
            encoding: .utf8
        )
        let html = #"<img src="external.svg" /><img src="data:image/png;base64,abc123" />"#

        let result = MarkdownImageInliner.makeSafeHTML(in: html, baseDirectory: dir)

        #expect(!result.html.contains("src="))
        #expect(result.blockedLocalImageCount == 2)
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
