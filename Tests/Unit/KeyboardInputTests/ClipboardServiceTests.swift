// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ClipboardServiceTests.swift - Tests for clipboard read/write abstraction.

import AppKit
import XCTest
@testable import CocxyTerminal

// MARK: - Clipboard Service Protocol Tests

/// Tests that the clipboard service protocol and implementation work correctly.
///
/// The clipboard service abstracts NSPasteboard access for testability.
/// Tests use a mock implementation to verify behavior without touching
/// the real system clipboard.
@MainActor
final class ClipboardServiceTests: XCTestCase {

    // MARK: - Mock Clipboard

    func testMockClipboardWriteAndRead() {
        let clipboard = MockClipboardService()
        clipboard.write("hello world")
        XCTAssertEqual(clipboard.read(), "hello world",
                       "Written text must be readable")
    }

    func testMockClipboardReadReturnsNilWhenEmpty() {
        let clipboard = MockClipboardService()
        XCTAssertNil(clipboard.read(), "Empty clipboard must return nil")
    }

    func testMockClipboardImageAttachmentDefaultsToNil() {
        let clipboard = MockClipboardService()
        XCTAssertNil(clipboard.readImageAttachment(),
                     "Mock clipboard should not expose image attachments by default")
    }

    func testMockClipboardOverwritesPrevious() {
        let clipboard = MockClipboardService()
        clipboard.write("first")
        clipboard.write("second")
        XCTAssertEqual(clipboard.read(), "second",
                       "Writing must overwrite previous content")
    }

    func testMockClipboardClearRemovesContent() {
        let clipboard = MockClipboardService()
        clipboard.write("something")
        clipboard.clear()
        XCTAssertNil(clipboard.read(), "Clear must remove clipboard content")
    }

    // MARK: - System Clipboard Service

    func testSystemClipboardServiceConformsToProtocol() {
        let clipboard: ClipboardServiceProtocol = SystemClipboardService()
        XCTAssertNotNil(clipboard, "SystemClipboardService must conform to protocol")
    }

    func testSystemClipboardTerminalPastePrefersTextOverRichImageSideData() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("cocxy-clipboard-text-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("notes text", forType: .string)
        pasteboard.setData(Self.pngData, forType: .png)
        let imageDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: imageDirectory) }
        let clipboard = SystemClipboardService(
            pasteboard: pasteboard,
            clipboardImageDirectory: imageDirectory
        )

        XCTAssertEqual(clipboard.readTerminalPastePayload(), .text("notes text"))
        let storedImages = try FileManager.default.contentsOfDirectory(
            at: imageDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(storedImages.isEmpty, "Text paste must not decode or store image side data")
    }

    func testSystemClipboardTerminalPastePrefersImageFileURLOverCompanionText() throws {
        let imageURL = try makeTemporaryDirectory()
            .appendingPathComponent("Pasted Image.png", isDirectory: false)
        try Self.pngData.write(to: imageURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("cocxy-clipboard-file-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([imageURL as NSURL])
        pasteboard.setString(imageURL.path, forType: .string)
        let clipboard = SystemClipboardService(pasteboard: pasteboard)

        XCTAssertEqual(clipboard.readTerminalPastePayload(), .fileURLs([imageURL]))
    }

    func testSystemClipboardTerminalPasteStoresRawPNGImage() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("cocxy-clipboard-image-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setData(Self.pngData, forType: .png)
        let imageDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: imageDirectory) }
        let clipboard = SystemClipboardService(
            pasteboard: pasteboard,
            clipboardImageDirectory: imageDirectory
        )

        let payload = try XCTUnwrap(clipboard.readTerminalPastePayload())
        guard case .fileURLs(let urls) = payload else {
            return XCTFail("Expected image paste to produce file URLs")
        }

        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls[0].path))
        XCTAssertEqual(urls[0].pathExtension, "png")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-clipboard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static let pngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
    )!
}
