// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MetalTerminalRenderer.swift - Metal GPU renderer consuming CocxyCore frame data.

import Metal
import QuartzCore
import CocxyCoreKit

// MARK: - Metal Terminal Renderer

/// Renders the terminal grid using Metal, consuming CocxyCore's MetalCell data.
///
/// CocxyCore computes all cell positions, resolved RGBA colors, glyph UV
/// coordinates, and cursor geometry on the CPU. This renderer's job is purely
/// GPU upload + draw: it uploads the cell instance data to vertex buffers,
/// the glyph atlas bitmap to a Metal texture, and draws three passes:
///
/// 1. **Background pass** — colored rectangles for each cell's background.
/// 2. **Glyph pass** — textured quads sampling the glyph atlas with fg color.
/// 3. **Cursor pass** — single colored rectangle for the cursor.
///
/// ## Threading
///
/// All methods must be called from the main thread. The renderer does not
/// own any threads or dispatch queues. The caller (CocxyCoreView) drives
/// rendering from its CVDisplayLink or needsDisplay cycle.
@MainActor
final class MetalTerminalRenderer {

    // MARK: - Metal Objects

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let bgPipeline: MTLRenderPipelineState
    private let glyphPipeline: MTLRenderPipelineState
    private let imagePipeline: MTLRenderPipelineState
    private let cursorPipeline: MTLRenderPipelineState

    // MARK: - Buffers

    /// Instance data for all cells (background + glyph passes share this).
    private var cellBuffer: MTLBuffer?

    /// Single-instance buffer for the cursor quad.
    private var cursorBuffer: MTLBuffer?

    /// Instance data for inline image quads.
    private var imageQuadBuffer: MTLBuffer?

    /// Projection uniforms (viewport size for clip-space conversion).
    private var uniformBuffer: MTLBuffer?

    /// Glyph atlas texture (R8Unorm — single channel alpha).
    private var atlasTexture: MTLTexture?

    /// Inline image atlas texture (RGBA8).
    private var imageAtlasTexture: MTLTexture?

    /// Sampler state for atlas texture.
    private let atlasSampler: MTLSamplerState
    private let imageSampler: MTLSamplerState

    // MARK: - State

    private var rows: UInt16 = 0
    private var cols: UInt16 = 0
    private var lastAtlasGeneration: UInt32 = 0
    private var cellCount: Int = 0
    private var imageQuadCount: Int = 0
    private var backgroundImageCount: Int = 0
    private var viewportSize: SIMD2<Float> = .zero
    private var lastImageAtlasGeneration: UInt32 = 0

    /// Atlas dimensions requested from CocxyCore.
    private(set) var atlasWidth: UInt32 = 2048
    private(set) var atlasHeight: UInt32 = 2048

    // MARK: - GPU Structs (match shader layout)

    /// Per-cell instance data uploaded to the GPU.
    /// Layout must match the Metal shader's CellInstance struct.
    struct CellInstance {
        var x: Float
        var y: Float
        var width: Float
        var height: Float
        var glyphX: Float
        var glyphY: Float
        var glyphWidth: Float
        var glyphHeight: Float
        var u0: Float
        var v0: Float
        var u1: Float
        var v1: Float
        var fgR: UInt8; var fgG: UInt8; var fgB: UInt8; var fgA: UInt8
        var bgR: UInt8; var bgG: UInt8; var bgB: UInt8; var bgA: UInt8
        var flags: UInt8
        var _pad1: UInt8 = 0; var _pad2: UInt8 = 0; var _pad3: UInt8 = 0
    }

    /// Cursor instance data.
    struct CursorInstance {
        var x: Float
        var y: Float
        var width: Float
        var height: Float
        var r: UInt8; var g: UInt8; var b: UInt8; var a: UInt8
        var shape: UInt8
        var visible: UInt8
        var _pad1: UInt8 = 0; var _pad2: UInt8 = 0
    }

    struct ImageQuadInstance {
        var x: Float
        var y: Float
        var width: Float
        var height: Float
        var u0: Float
        var v0: Float
        var u1: Float
        var v1: Float
        var page: UInt8
        var _pad1: UInt8 = 0
        var _pad2: UInt8 = 0
        var _pad3: UInt8 = 0
        var zIndex: Int32
    }

    /// Uniforms passed to all shaders.
    struct Uniforms {
        var viewportWidth: Float
        var viewportHeight: Float
        var paddingX: Float
        var paddingY: Float
    }

    // MARK: - Initialization

    /// Creates a Metal renderer.
    ///
    /// - Parameters:
    ///   - device: Metal device. Pass nil to use system default.
    ///   - paddingX: Horizontal padding in points.
    ///   - paddingY: Vertical padding in points.
    /// - Throws: If Metal device, command queue, or shader compilation fails.
    init(device: MTLDevice? = nil, paddingX: Float = 8, paddingY: Float = 4) throws {
        guard let dev = device ?? MTLCreateSystemDefaultDevice() else {
            throw MetalRendererError.noDevice
        }
        self.device = dev

        guard let queue = dev.makeCommandQueue() else {
            throw MetalRendererError.commandQueueFailed
        }
        self.commandQueue = queue

        // Compile shaders
        let library = try dev.makeLibrary(source: Self.shaderSource, options: nil)

        // Background pipeline (solid color quads)
        let bgDesc = MTLRenderPipelineDescriptor()
        bgDesc.vertexFunction = library.makeFunction(name: "bg_vertex")
        bgDesc.fragmentFunction = library.makeFunction(name: "bg_fragment")
        bgDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        self.bgPipeline = try dev.makeRenderPipelineState(descriptor: bgDesc)

        // Glyph pipeline (textured quads with alpha blending)
        let glyphDesc = MTLRenderPipelineDescriptor()
        glyphDesc.vertexFunction = library.makeFunction(name: "glyph_vertex")
        glyphDesc.fragmentFunction = library.makeFunction(name: "glyph_fragment")
        glyphDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        glyphDesc.colorAttachments[0].isBlendingEnabled = true
        glyphDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        glyphDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        glyphDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        glyphDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        self.glyphPipeline = try dev.makeRenderPipelineState(descriptor: glyphDesc)

        let imageDesc = MTLRenderPipelineDescriptor()
        imageDesc.vertexFunction = library.makeFunction(name: "image_vertex")
        imageDesc.fragmentFunction = library.makeFunction(name: "image_fragment")
        imageDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        imageDesc.colorAttachments[0].isBlendingEnabled = true
        imageDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        imageDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        imageDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        imageDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        self.imagePipeline = try dev.makeRenderPipelineState(descriptor: imageDesc)

        // Cursor pipeline (solid color with alpha blending for hollow cursors)
        let cursorDesc = MTLRenderPipelineDescriptor()
        cursorDesc.vertexFunction = library.makeFunction(name: "cursor_vertex")
        cursorDesc.fragmentFunction = library.makeFunction(name: "cursor_fragment")
        cursorDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        cursorDesc.colorAttachments[0].isBlendingEnabled = true
        cursorDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        cursorDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        cursorDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        cursorDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        self.cursorPipeline = try dev.makeRenderPipelineState(descriptor: cursorDesc)

        // Sampler
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .nearest
        samplerDesc.magFilter = .nearest
        samplerDesc.sAddressMode = .clampToZero
        samplerDesc.tAddressMode = .clampToZero
        guard let sampler = dev.makeSamplerState(descriptor: samplerDesc) else {
            throw MetalRendererError.samplerFailed
        }
        self.atlasSampler = sampler

        let imageSamplerDesc = MTLSamplerDescriptor()
        imageSamplerDesc.minFilter = .linear
        imageSamplerDesc.magFilter = .linear
        imageSamplerDesc.sAddressMode = .clampToEdge
        imageSamplerDesc.tAddressMode = .clampToEdge
        guard let imageSampler = dev.makeSamplerState(descriptor: imageSamplerDesc) else {
            throw MetalRendererError.samplerFailed
        }
        self.imageSampler = imageSampler

        // Uniform buffer (small, reused every frame)
        guard let ub = dev.makeBuffer(
            length: MemoryLayout<Uniforms>.stride,
            options: .storageModeShared
        ) else {
            throw MetalRendererError.bufferAllocationFailed
        }
        self.uniformBuffer = ub
    }

    // MARK: - Public API

    /// Update the grid dimensions. Call when the terminal is resized.
    func updateGridSize(rows: UInt16, cols: UInt16) {
        guard rows != self.rows || cols != self.cols else { return }
        self.rows = rows
        self.cols = cols
        self.cellCount = Int(rows) * Int(cols)

        // Reallocate cell buffer for new grid size
        let byteCount = cellCount * MemoryLayout<CellInstance>.stride
        cellBuffer = device.makeBuffer(length: max(byteCount, 1), options: .storageModeShared)
        imageQuadBuffer = nil
        imageQuadCount = 0
        backgroundImageCount = 0
    }

    /// Update viewport size. Call when the view is resized.
    func updateViewportSize(_ size: CGSize, scale: CGFloat, paddingX: Float, paddingY: Float) {
        viewportSize = SIMD2<Float>(Float(size.width * scale), Float(size.height * scale))

        guard let ptr = uniformBuffer?.contents().assumingMemoryBound(to: Uniforms.self) else { return }
        ptr.pointee = Uniforms(
            viewportWidth: viewportSize.x,
            viewportHeight: viewportSize.y,
            paddingX: paddingX * Float(scale),
            paddingY: paddingY * Float(scale)
        )
    }

    /// Render one frame of the terminal.
    ///
    /// Reads cell/cursor data from the terminal handle, uploads to GPU,
    /// and submits a render pass to the given Metal layer.
    ///
    /// - Parameters:
    ///   - terminal: CocxyCore terminal handle (opaque pointer).
    ///   - layer: The CAMetalLayer to render into.
    func draw(terminal: OpaquePointer, layer: CAMetalLayer) {
        guard prepareFrameResources(terminal: terminal),
              let cellBuffer = cellBuffer,
              let uniformBuffer = uniformBuffer
        else { return }

        let cursorInst = readCursor(terminal: terminal)

        // 5. Get drawable and render
        guard let drawable = layer.nextDrawable() else { return }

        let bgColor = readBackgroundClearColor(terminal: terminal)

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = drawable.texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].clearColor = bgColor
        passDesc.colorAttachments[0].storeAction = .store

        guard let cmdBuffer = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: passDesc)
        else { return }

        let instanceCount = cellCount

        // Pass 1: Backgrounds
        encoder.setRenderPipelineState(bgPipeline)
        encoder.setVertexBuffer(cellBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(
            type: .triangle, vertexStart: 0, vertexCount: 6,
            instanceCount: instanceCount
        )

        // Pass 2: Glyphs (only if atlas exists)
        if imageQuadCount > 0, imageAtlasTexture != nil, let imageQuadBuffer {
            encoder.setRenderPipelineState(imagePipeline)
            encoder.setVertexBuffer(imageQuadBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.setFragmentTexture(imageAtlasTexture, index: 0)
            encoder.setFragmentSamplerState(imageSampler, index: 0)
            encoder.drawPrimitives(
                type: .triangle, vertexStart: 0, vertexCount: 6,
                instanceCount: backgroundImageCount
            )
        }

        if atlasTexture != nil {
            encoder.setRenderPipelineState(glyphPipeline)
            encoder.setVertexBuffer(cellBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.setFragmentTexture(atlasTexture, index: 0)
            encoder.setFragmentSamplerState(atlasSampler, index: 0)
            encoder.drawPrimitives(
                type: .triangle, vertexStart: 0, vertexCount: 6,
                instanceCount: instanceCount
            )
        }

        if imageQuadCount > backgroundImageCount,
           imageAtlasTexture != nil,
           let imageQuadBuffer {
            encoder.setRenderPipelineState(imagePipeline)
            encoder.setVertexBuffer(imageQuadBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.setFragmentTexture(imageAtlasTexture, index: 0)
            encoder.setFragmentSamplerState(imageSampler, index: 0)
            encoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 6,
                instanceCount: imageQuadCount - backgroundImageCount,
                baseInstance: backgroundImageCount
            )
        }

        // Pass 3: Cursor
        if cursorInst.visible != 0, let cursorBuf = cursorBuffer {
            encoder.setRenderPipelineState(cursorPipeline)
            encoder.setVertexBuffer(cursorBuf, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(
                type: .triangle, vertexStart: 0, vertexCount: 6,
                instanceCount: 1
            )
        }

        encoder.endEncoding()
        cmdBuffer.present(drawable)
        cmdBuffer.commit()
    }

    /// Builds CocxyCore frame resources without requiring a drawable.
    ///
    /// This keeps `draw` lean and gives tests a deterministic seam to verify
    /// atlas uploads, buffer allocation, and cursor preparation offscreen.
    @discardableResult
    func prepareFrameResources(terminal: OpaquePointer) -> Bool {
        guard cocxycore_terminal_build_frame(terminal) else { return false }

        let rows = cocxycore_terminal_rows(terminal)
        let cols = cocxycore_terminal_cols(terminal)
        if rows != self.rows || cols != self.cols {
            updateGridSize(rows: rows, cols: cols)
        }

        guard cellCount > 0,
              let cellBuffer = cellBuffer,
              cocxycore_terminal_build_metal_frame(terminal, atlasWidth, atlasHeight)
        else { return false }

        uploadAtlasIfNeeded(terminal: terminal)
        uploadImageAtlasIfNeeded(terminal: terminal)
        fillCellBuffer(terminal: terminal, buffer: cellBuffer)
        fillImageQuadBuffer(terminal: terminal)

        let cursorInst = readCursor(terminal: terminal)
        ensureCursorBuffer()
        if let cursorBuf = cursorBuffer {
            let ptr = cursorBuf.contents().assumingMemoryBound(to: CursorInstance.self)
            ptr.pointee = cursorInst
        }

        return true
    }

    /// Release Metal resources. Call before deallocation.
    func cleanup() {
        cellBuffer = nil
        cursorBuffer = nil
        uniformBuffer = nil
        atlasTexture = nil
        imageQuadBuffer = nil
        imageAtlasTexture = nil
    }

    // MARK: - Private: Data Upload

    private func fillCellBuffer(terminal: OpaquePointer, buffer: MTLBuffer) {
        let ptr = buffer.contents().assumingMemoryBound(to: CellInstance.self)
        let rows = self.rows
        let cols = self.cols

        var cell = cocxycore_metal_cell()
        var idx = 0

        for row in 0..<rows {
            for col in 0..<cols {
                cocxycore_terminal_metal_cell(terminal, row, col, &cell)

                ptr[idx] = CellInstance(
                    x: cell.x, y: cell.y,
                    width: cell.width, height: cell.height,
                    glyphX: cell.glyph_x, glyphY: cell.glyph_y,
                    glyphWidth: cell.glyph_width, glyphHeight: cell.glyph_height,
                    u0: cell.u0, v0: cell.v0, u1: cell.u1, v1: cell.v1,
                    fgR: cell.fg.r, fgG: cell.fg.g, fgB: cell.fg.b, fgA: cell.fg.a,
                    bgR: cell.bg.r, bgG: cell.bg.g, bgB: cell.bg.b, bgA: cell.bg.a,
                    flags: cell.flags
                )
                idx += 1
            }
        }
    }

    private func fillImageQuadBuffer(terminal: OpaquePointer) {
        let count = Int(cocxycore_frame_image_quad_count(terminal))
        guard count > 0 else {
            imageQuadCount = 0
            backgroundImageCount = 0
            imageQuadBuffer = nil
            return
        }

        var backgroundQuads: [ImageQuadInstance] = []
        backgroundQuads.reserveCapacity(count)
        var foregroundQuads: [ImageQuadInstance] = []
        foregroundQuads.reserveCapacity(count)

        var quad = cocxycore_image_quad()
        for index in 0..<count {
            guard cocxycore_frame_image_quad(terminal, UInt16(index), &quad) else { continue }

            let instance = ImageQuadInstance(
                x: quad.x,
                y: quad.y,
                width: quad.width,
                height: quad.height,
                u0: quad.u0,
                v0: quad.v0,
                u1: quad.u1,
                v1: quad.v1,
                page: quad.page,
                zIndex: quad.z_index
            )

            if quad.z_index < 0 {
                backgroundQuads.append(instance)
            } else {
                foregroundQuads.append(instance)
            }
        }

        let orderedQuads = backgroundQuads + foregroundQuads
        imageQuadCount = orderedQuads.count
        backgroundImageCount = backgroundQuads.count

        guard imageQuadCount > 0 else {
            imageQuadBuffer = nil
            return
        }

        let byteCount = imageQuadCount * MemoryLayout<ImageQuadInstance>.stride
        if imageQuadBuffer == nil || imageQuadBuffer?.length != byteCount {
            imageQuadBuffer = device.makeBuffer(length: byteCount, options: .storageModeShared)
        }
        guard let imageQuadBuffer else { return }

        let ptr = imageQuadBuffer.contents().assumingMemoryBound(to: ImageQuadInstance.self)
        for (index, quad) in orderedQuads.enumerated() {
            ptr[index] = quad
        }
    }

    private func readCursor(terminal: OpaquePointer) -> CursorInstance {
        var cursor = cocxycore_metal_cursor()
        cocxycore_terminal_metal_cursor(terminal, &cursor)
        return CursorInstance(
            x: cursor.x, y: cursor.y,
            width: cursor.width, height: cursor.height,
            r: cursor.color.r, g: cursor.color.g,
            b: cursor.color.b, a: cursor.color.a,
            shape: cursor.shape,
            visible: cursor.visible ? 1 : 0
        )
    }

    private func readBackgroundClearColor(terminal: OpaquePointer) -> MTLClearColor {
        // Read cell (0,0) background as the clear color
        var cell = cocxycore_metal_cell()
        cocxycore_terminal_metal_cell(terminal, 0, 0, &cell)
        return MTLClearColor(
            red: Double(cell.bg.r) / 255.0,
            green: Double(cell.bg.g) / 255.0,
            blue: Double(cell.bg.b) / 255.0,
            alpha: 1.0
        )
    }

    private func ensureCursorBuffer() {
        if cursorBuffer == nil {
            cursorBuffer = device.makeBuffer(
                length: MemoryLayout<CursorInstance>.stride,
                options: .storageModeShared
            )
        }
    }

    // MARK: - Private: Atlas Management

    private func uploadAtlasIfNeeded(terminal: OpaquePointer) {
        var info = cocxycore_metal_atlas_info()
        guard cocxycore_terminal_metal_atlas_info(terminal, &info) else { return }

        let needsUpload = info.dirty || info.generation != lastAtlasGeneration

        // Recreate texture if atlas dimensions changed
        if atlasTexture == nil ||
           atlasTexture?.width != Int(info.width) ||
           atlasTexture?.height != Int(info.height) {
            let texDesc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Unorm,
                width: Int(info.width),
                height: Int(info.height),
                mipmapped: false
            )
            texDesc.usage = .shaderRead
            texDesc.storageMode = .shared
            atlasTexture = device.makeTexture(descriptor: texDesc)
            atlasWidth = info.width
            atlasHeight = info.height
        }

        guard needsUpload, let texture = atlasTexture else { return }

        // Copy atlas bitmap from CocxyCore
        let byteCount = Int(info.width) * Int(info.height)
        var bitmap = [UInt8](repeating: 0, count: byteCount)
        let copied = cocxycore_terminal_metal_copy_atlas_bitmap(terminal, &bitmap, byteCount)

        if copied > 0 {
            texture.replace(
                region: MTLRegionMake2D(0, 0, Int(info.width), Int(info.height)),
                mipmapLevel: 0,
                withBytes: bitmap,
                bytesPerRow: Int(info.width)
            )
        }

        cocxycore_terminal_metal_clear_atlas_dirty(terminal)
        lastAtlasGeneration = info.generation
    }

    private func uploadImageAtlasIfNeeded(terminal: OpaquePointer) {
        var info = cocxycore_image_atlas_info()
        guard cocxycore_image_get_atlas_info(terminal, &info) else { return }

        let needsUpload = info.dirty || info.generation != lastImageAtlasGeneration

        if imageAtlasTexture == nil ||
           imageAtlasTexture?.width != Int(info.width) ||
           imageAtlasTexture?.height != Int(info.height) {
            let texDesc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: Int(info.width),
                height: Int(info.height),
                mipmapped: false
            )
            texDesc.usage = .shaderRead
            texDesc.storageMode = .shared
            imageAtlasTexture = device.makeTexture(descriptor: texDesc)
        }

        guard needsUpload, let imageAtlasTexture else { return }

        let byteCount = Int(info.width) * Int(info.height) * 4
        var bitmap = [UInt8](repeating: 0, count: byteCount)
        let copied = cocxycore_image_copy_atlas_bitmap(terminal, &bitmap, byteCount)

        if copied > 0 {
            imageAtlasTexture.replace(
                region: MTLRegionMake2D(0, 0, Int(info.width), Int(info.height)),
                mipmapLevel: 0,
                withBytes: bitmap,
                bytesPerRow: Int(info.width) * 4
            )
        }

        cocxycore_image_clear_atlas_dirty(terminal)
        lastImageAtlasGeneration = info.generation
    }

    // MARK: - Metal Shader Source

    /// Metal Shading Language source compiled at runtime.
    ///
    /// Three shader pairs (vertex + fragment):
    /// - bg: Solid colored rectangles for cell backgrounds.
    /// - glyph: Textured quads sampling the glyph atlas with foreground color.
    /// - cursor: Single colored rectangle for the cursor.
    ///
    /// All vertex shaders convert pixel coordinates to clip space using:
    ///   clip = pixel / viewport * 2 - 1, with Y flipped (Metal is top-left origin).
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    // ── Shared types ──────────────────────────────────────────────────

    struct Uniforms {
        float viewportWidth;
        float viewportHeight;
        float paddingX;
        float paddingY;
    };

    struct CellInstance {
        float x, y, width, height;
        float glyphX, glyphY, glyphWidth, glyphHeight;
        float u0, v0, u1, v1;
        uchar4 fg;
        uchar4 bg;
        uint8_t flags;
        uint8_t _pad1, _pad2, _pad3;
    };

    struct ImageQuadInstance {
        float x, y, width, height;
        float u0, v0, u1, v1;
        uint8_t page;
        uint8_t _pad1, _pad2, _pad3;
        int zIndex;
    };

    struct CursorInstance {
        float x, y, width, height;
        uchar4 color;
        uint8_t shape;
        uint8_t visible;
        uint8_t _pad1, _pad2;
    };

    // Quad corner offsets for 2 triangles (6 vertices).
    constant float2 quadOffsets[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(1, 0), float2(1, 1), float2(0, 1),
    };

    // Convert pixel position to clip space.
    float4 pixelToClip(float2 pos, float2 viewport) {
        float2 ndc = pos / viewport * 2.0 - 1.0;
        ndc.y = -ndc.y;
        return float4(ndc, 0.0, 1.0);
    }

    // ── Background pass ───────────────────────────────────────────────

    struct BgOut {
        float4 position [[position]];
        float4 color;
    };

    vertex BgOut bg_vertex(
        uint vid [[vertex_id]],
        uint iid [[instance_id]],
        const device CellInstance* cells [[buffer(0)]],
        constant Uniforms& u [[buffer(1)]]
    ) {
        CellInstance c = cells[iid];
        float2 corner = quadOffsets[vid];
        float2 pos = float2(c.x + u.paddingX, c.y + u.paddingY) + corner * float2(c.width, c.height);

        BgOut out;
        out.position = pixelToClip(pos, float2(u.viewportWidth, u.viewportHeight));
        out.color = float4(c.bg) / 255.0;
        return out;
    }

    fragment float4 bg_fragment(BgOut in [[stage_in]]) {
        return in.color;
    }

    // ── Glyph pass ────────────────────────────────────────────────────

    struct GlyphOut {
        float4 position [[position]];
        float4 fgColor;
        float2 uv;
        float hasGlyph;
    };

    vertex GlyphOut glyph_vertex(
        uint vid [[vertex_id]],
        uint iid [[instance_id]],
        const device CellInstance* cells [[buffer(0)]],
        constant Uniforms& u [[buffer(1)]]
    ) {
        CellInstance c = cells[iid];
        float2 corner = quadOffsets[vid];

        // Check if this cell has a renderable glyph (UV span > 0)
        float hasGlyph = (c.u1 - c.u0 > 0.0001 && c.v1 - c.v0 > 0.0001) ? 1.0 : 0.0;

        float2 pos = float2(c.glyphX + u.paddingX, c.glyphY + u.paddingY)
                     + corner * float2(c.glyphWidth, c.glyphHeight);
        float2 uv = float2(c.u0, c.v0) + corner * float2(c.u1 - c.u0, c.v1 - c.v0);

        GlyphOut out;
        out.position = pixelToClip(pos, float2(u.viewportWidth, u.viewportHeight));
        out.fgColor = float4(c.fg) / 255.0;
        out.uv = uv;
        out.hasGlyph = hasGlyph;
        return out;
    }

    fragment float4 glyph_fragment(
        GlyphOut in [[stage_in]],
        texture2d<float> atlas [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        if (in.hasGlyph < 0.5) discard_fragment();
        float alpha = atlas.sample(s, in.uv).r;
        if (alpha < 0.004) discard_fragment();
        return float4(in.fgColor.rgb, in.fgColor.a * alpha);
    }

    // ── Image pass ────────────────────────────────────────────────────

    struct ImageOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex ImageOut image_vertex(
        uint vid [[vertex_id]],
        uint iid [[instance_id]],
        const device ImageQuadInstance* quads [[buffer(0)]],
        constant Uniforms& u [[buffer(1)]]
    ) {
        ImageQuadInstance q = quads[iid];
        float2 corner = quadOffsets[vid];
        float2 pos = float2(q.x + u.paddingX, q.y + u.paddingY) + corner * float2(q.width, q.height);

        ImageOut out;
        out.position = pixelToClip(pos, float2(u.viewportWidth, u.viewportHeight));
        out.uv = float2(q.u0, q.v0) + corner * float2(q.u1 - q.u0, q.v1 - q.v0);
        return out;
    }

    fragment float4 image_fragment(
        ImageOut in [[stage_in]],
        texture2d<float> atlas [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float4 color = atlas.sample(s, in.uv);
        if (color.a < 0.004) discard_fragment();
        return color;
    }

    // ── Cursor pass ───────────────────────────────────────────────────

    struct CursorOut {
        float4 position [[position]];
        float4 color;
    };

    vertex CursorOut cursor_vertex(
        uint vid [[vertex_id]],
        uint iid [[instance_id]],
        const device CursorInstance* cursors [[buffer(0)]],
        constant Uniforms& u [[buffer(1)]]
    ) {
        CursorInstance c = cursors[iid];
        float2 corner = quadOffsets[vid];
        float2 pos = float2(c.x + u.paddingX, c.y + u.paddingY) + corner * float2(c.width, c.height);

        CursorOut out;
        out.position = pixelToClip(pos, float2(u.viewportWidth, u.viewportHeight));
        out.color = float4(c.color) / 255.0;
        return out;
    }

    fragment float4 cursor_fragment(CursorOut in [[stage_in]]) {
        return in.color;
    }
    """
}

// MARK: - Errors

enum MetalRendererError: Error {
    case noDevice
    case commandQueueFailed
    case shaderCompilationFailed(String)
    case samplerFailed
    case bufferAllocationFailed
}

// MARK: - Internal Test Support

extension MetalTerminalRenderer {
    struct DebugState {
        let rows: UInt16
        let cols: UInt16
        let cellCount: Int
        let imageQuadCount: Int
        let backgroundImageCount: Int
        let viewportWidth: Float
        let viewportHeight: Float
        let hasCellBuffer: Bool
        let hasImageQuadBuffer: Bool
        let hasCursorBuffer: Bool
        let hasUniformBuffer: Bool
        let hasAtlasTexture: Bool
        let hasImageAtlasTexture: Bool
        let atlasGeneration: UInt32
    }

    var debugState: DebugState {
        DebugState(
            rows: rows,
            cols: cols,
            cellCount: cellCount,
            imageQuadCount: imageQuadCount,
            backgroundImageCount: backgroundImageCount,
            viewportWidth: viewportSize.x,
            viewportHeight: viewportSize.y,
            hasCellBuffer: cellBuffer != nil,
            hasImageQuadBuffer: imageQuadBuffer != nil,
            hasCursorBuffer: cursorBuffer != nil,
            hasUniformBuffer: uniformBuffer != nil,
            hasAtlasTexture: atlasTexture != nil,
            hasImageAtlasTexture: imageAtlasTexture != nil,
            atlasGeneration: lastAtlasGeneration
        )
    }
}
