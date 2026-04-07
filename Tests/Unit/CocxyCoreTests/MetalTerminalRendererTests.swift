// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
import CocxyCoreKit
@testable import CocxyTerminal

@Suite("MetalTerminalRenderer")
@MainActor
struct MetalTerminalRendererTests {

    @Test("init starts with the default atlas size and empty buffers")
    func initStartsWithDefaultState() throws {
        let renderer = try MetalTerminalRenderer()
        let state = renderer.debugState

        #expect(renderer.atlasWidth == 2048)
        #expect(renderer.atlasHeight == 2048)
        #expect(state.rows == 0)
        #expect(state.cols == 0)
        #expect(state.cellCount == 0)
        #expect(state.hasCellBuffer == false)
        #expect(state.hasCursorBuffer == false)
        #expect(state.hasAtlasTexture == false)
        #expect(state.hasUniformBuffer == true)
    }

    @Test("updateGridSize stores rows, columns, and allocates the cell buffer")
    func updateGridSizeStoresDimensions() throws {
        let renderer = try MetalTerminalRenderer()

        renderer.updateGridSize(rows: 24, cols: 80)

        let state = renderer.debugState
        #expect(state.rows == 24)
        #expect(state.cols == 80)
        #expect(state.cellCount == 1_920)
        #expect(state.hasCellBuffer == true)
    }

    @Test("updateGridSize is idempotent for the same dimensions")
    func updateGridSizeIsIdempotent() throws {
        let renderer = try MetalTerminalRenderer()
        renderer.updateGridSize(rows: 6, cols: 12)
        let firstState = renderer.debugState

        renderer.updateGridSize(rows: 6, cols: 12)
        let secondState = renderer.debugState

        #expect(firstState.rows == secondState.rows)
        #expect(firstState.cols == secondState.cols)
        #expect(firstState.cellCount == secondState.cellCount)
    }

    @Test("updateViewportSize stores scaled viewport dimensions")
    func updateViewportSizeStoresScaledViewport() throws {
        let renderer = try MetalTerminalRenderer()

        renderer.updateViewportSize(
            CGSize(width: 320, height: 200),
            scale: 2,
            paddingX: 8,
            paddingY: 4
        )

        let state = renderer.debugState
        #expect(state.viewportWidth == 640)
        #expect(state.viewportHeight == 400)
    }

    @Test("prepareFrameResources fails when no font was configured")
    func prepareFrameResourcesFailsWithoutFont() throws {
        let renderer = try MetalTerminalRenderer()
        let terminal = try #require(cocxycore_terminal_create(6, 12))
        defer { cocxycore_terminal_destroy(terminal) }

        let prepared = renderer.prepareFrameResources(terminal: terminal)

        #expect(prepared == false)
        #expect(renderer.debugState.hasAtlasTexture == false)
    }

    @Test("prepareFrameResources succeeds with a configured font")
    func prepareFrameResourcesSucceedsWithFont() throws {
        let renderer = try MetalTerminalRenderer()
        let terminal = try makeConfiguredTerminal()
        defer { cocxycore_terminal_destroy(terminal) }

        let prepared = renderer.prepareFrameResources(terminal: terminal)

        #expect(prepared == true)
    }

    @Test("prepareFrameResources synchronizes the renderer grid with the terminal")
    func prepareFrameResourcesSynchronizesGrid() throws {
        let renderer = try MetalTerminalRenderer()
        let terminal = try makeConfiguredTerminal(rows: 9, cols: 17)
        defer { cocxycore_terminal_destroy(terminal) }

        _ = renderer.prepareFrameResources(terminal: terminal)

        let state = renderer.debugState
        #expect(state.rows == 9)
        #expect(state.cols == 17)
        #expect(state.cellCount == 153)
    }

    @Test("prepareFrameResources uploads atlas data when glyphs are present")
    func prepareFrameResourcesCreatesAtlasTexture() throws {
        let renderer = try MetalTerminalRenderer()
        let terminal = try makeConfiguredTerminal(text: "hello world\r\n")
        defer { cocxycore_terminal_destroy(terminal) }

        _ = renderer.prepareFrameResources(terminal: terminal)

        let state = renderer.debugState
        #expect(state.hasAtlasTexture == true)
        #expect(renderer.atlasWidth > 0)
        #expect(renderer.atlasHeight > 0)
    }

    @Test("prepareFrameResources allocates the cursor buffer")
    func prepareFrameResourcesAllocatesCursorBuffer() throws {
        let renderer = try MetalTerminalRenderer()
        let terminal = try makeConfiguredTerminal(text: "cursor\r\n")
        defer { cocxycore_terminal_destroy(terminal) }

        _ = renderer.prepareFrameResources(terminal: terminal)

        #expect(renderer.debugState.hasCursorBuffer == true)
    }

    @Test("prepareFrameResources uploads inline image quads and atlas data")
    func prepareFrameResourcesUploadsInlineImages() throws {
        let renderer = try MetalTerminalRenderer()
        let terminal = try makeConfiguredTerminal(text: "")
        defer { cocxycore_terminal_destroy(terminal) }

        let kittyImage = "\u{1B}_Ga=T,f=32,s=1,v=1;/wAA/w==\u{1B}\\"
        let bytes = Array(kittyImage.utf8)
        cocxycore_terminal_feed(terminal, bytes, bytes.count)

        let prepared = renderer.prepareFrameResources(terminal: terminal)
        let state = renderer.debugState

        #expect(prepared == true)
        #expect(state.hasImageAtlasTexture == true)
        #expect(state.hasImageQuadBuffer == true)
        #expect(state.imageQuadCount == 1)
        #expect(state.backgroundImageCount == 0)
    }

    @Test("prepareFrameResources partitions background and foreground image quads")
    func prepareFrameResourcesPartitionsImageLayers() throws {
        let renderer = try MetalTerminalRenderer()
        let terminal = try makeConfiguredTerminal(text: "")
        defer { cocxycore_terminal_destroy(terminal) }

        let backgroundImage = "\u{1B}_Ga=T,f=32,s=1,v=1,z=-1;/wAA/w==\u{1B}\\"
        let foregroundImage = "\u{1B}_Ga=T,f=32,s=1,v=1,z=2;/wAA/w==\u{1B}\\"
        let backgroundBytes = Array(backgroundImage.utf8)
        let foregroundBytes = Array(foregroundImage.utf8)
        cocxycore_terminal_feed(terminal, backgroundBytes, backgroundBytes.count)
        cocxycore_terminal_feed(terminal, foregroundBytes, foregroundBytes.count)

        let prepared = renderer.prepareFrameResources(terminal: terminal)
        let state = renderer.debugState

        #expect(prepared == true)
        #expect(state.imageQuadCount == 2)
        #expect(state.backgroundImageCount == 1)
    }

    @Test("cleanup releases atlas and working buffers")
    func cleanupReleasesWorkingBuffers() throws {
        let renderer = try MetalTerminalRenderer()
        let terminal = try makeConfiguredTerminal(text: "cleanup\r\n")
        defer { cocxycore_terminal_destroy(terminal) }

        _ = renderer.prepareFrameResources(terminal: terminal)
        renderer.cleanup()

        let state = renderer.debugState
        #expect(state.hasCellBuffer == false)
        #expect(state.hasCursorBuffer == false)
        #expect(state.hasAtlasTexture == false)
        #expect(state.hasUniformBuffer == false)
    }
}

private func makeConfiguredTerminal(
    rows: UInt16 = 6,
    cols: UInt16 = 12,
    text: String = "hello\r\n"
) throws -> OpaquePointer {
    let terminal = try #require(cocxycore_terminal_create(rows, cols))

    let fontConfigured = "Menlo".withCString { family in
        cocxycore_terminal_set_font(terminal, family, 14, 2.0, true)
    }
    #expect(fontConfigured == true)

    cocxycore_terminal_set_theme(
        terminal,
        235, 235, 235,
        30, 30, 30,
        255, 255, 255
    )

    let bytes = Array(text.utf8)
    cocxycore_terminal_feed(terminal, bytes, bytes.count)
    return terminal
}
