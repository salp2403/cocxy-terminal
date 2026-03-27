// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// InlineImageRendererTests.swift - Tests for inline image rendering logic.

import XCTest
@testable import CocxyTerminal

@MainActor
final class InlineImageRendererTests: XCTestCase {

    // MARK: - Setup

    private var hostView: NSView!
    private var renderer: InlineImageRenderer!

    override func setUp() {
        super.setUp()
        hostView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        renderer = InlineImageRenderer(terminalView: hostView)
    }

    override func tearDown() {
        renderer.clearAllImages()
        renderer = nil
        hostView = nil
        super.tearDown()
    }

    // MARK: - Render Inline Image

    func testRenderInlineImageReturnsImageID() {
        let imageData = createInlineImageData(inline: true)

        let imageID = renderer.renderImage(imageData, at: 100)

        XCTAssertNotNil(imageID)
    }

    func testRenderInlineImageAddsSubviewToHostView() {
        let imageData = createInlineImageData(inline: true)

        renderer.renderImage(imageData, at: 100)

        XCTAssertEqual(hostView.subviews.count, 1)
    }

    func testRenderMultipleImagesAssignsSequentialIDs() {
        let imageData = createInlineImageData(inline: true)

        let firstID = renderer.renderImage(imageData, at: 100)
        let secondID = renderer.renderImage(imageData, at: 200)

        XCTAssertNotNil(firstID)
        XCTAssertNotNil(secondID)
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(hostView.subviews.count, 2)
    }

    func testActiveImageCountTracksRenderedImages() {
        let imageData = createInlineImageData(inline: true)

        XCTAssertEqual(renderer.activeImageCount, 0)

        renderer.renderImage(imageData, at: 100)
        XCTAssertEqual(renderer.activeImageCount, 1)

        renderer.renderImage(imageData, at: 200)
        XCTAssertEqual(renderer.activeImageCount, 2)
    }

    // MARK: - Non-Inline Images

    func testNonInlineImageReturnsNil() {
        let imageData = createInlineImageData(inline: false)

        let imageID = renderer.renderImage(imageData, at: 100)

        XCTAssertNil(imageID)
        XCTAssertEqual(hostView.subviews.count, 0)
    }

    // MARK: - Remove Image

    func testRemoveImageRemovesSubview() {
        let imageData = createInlineImageData(inline: true)
        let imageID = renderer.renderImage(imageData, at: 100)!

        renderer.removeImage(imageID)

        XCTAssertEqual(hostView.subviews.count, 0)
        XCTAssertEqual(renderer.activeImageCount, 0)
    }

    func testRemoveNonexistentImageIsNoOp() {
        renderer.removeImage(999)

        XCTAssertEqual(renderer.activeImageCount, 0)
    }

    // MARK: - Clear All Images

    func testClearAllImagesRemovesAllSubviews() {
        let imageData = createInlineImageData(inline: true)
        renderer.renderImage(imageData, at: 100)
        renderer.renderImage(imageData, at: 200)
        renderer.renderImage(imageData, at: 300)

        renderer.clearAllImages()

        XCTAssertEqual(hostView.subviews.count, 0)
        XCTAssertEqual(renderer.activeImageCount, 0)
    }

    func testClearAllImagesResetsIDCounter() {
        let imageData = createInlineImageData(inline: true)
        renderer.renderImage(imageData, at: 100)
        renderer.renderImage(imageData, at: 200)

        renderer.clearAllImages()

        let newID = renderer.renderImage(imageData, at: 100)
        XCTAssertEqual(newID, 0, "ID counter should reset to 0 after clearAllImages")
    }

    // MARK: - Max Dimension Clamping

    func testMaxDimensionConstantIsReasonable() {
        XCTAssertEqual(InlineImageRenderer.maxDimension, 2048)
    }

    // MARK: - Helpers

    /// Creates an InlineImageData with a tiny valid PNG.
    private func createInlineImageData(
        inline: Bool,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        preserveAspectRatio: Bool = true,
        filename: String? = nil
    ) -> InlineImageData {
        // Minimal 1x1 pixel red PNG.
        let pngBytes: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
            0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
            0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
            0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC,
            0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
            0x44, 0xAE, 0x42, 0x60, 0x82,
        ]

        return InlineImageData(
            imageData: Data(pngBytes),
            width: width,
            height: height,
            preserveAspectRatio: preserveAspectRatio,
            inline: inline,
            filename: filename
        )
    }
}
