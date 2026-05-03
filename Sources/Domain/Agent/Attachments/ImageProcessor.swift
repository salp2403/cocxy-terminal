// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ImageProcessor.swift - Local resize/compression for Agent Mode attachments.

import AppKit
import Foundation

enum AgentImageProcessorError: Error, Sendable, Equatable {
    case unsupportedImageData
    case bitmapRepresentationUnavailable
    case encodedRepresentationUnavailable
}

extension AgentImageProcessorError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedImageData:
            return "Unsupported image data."
        case .bitmapRepresentationUnavailable:
            return "Unable to prepare image bitmap."
        case .encodedRepresentationUnavailable:
            return "Unable to encode image attachment."
        }
    }
}

struct ProcessedAgentImage: Sendable, Equatable {
    let data: Data
    let mimeType: String
    let fileExtension: String
    let pixelWidth: Int
    let pixelHeight: Int
}

struct AgentImageProcessor: Sendable {
    let maxPixelDimension: Int
    let jpegCompressionQuality: Double

    init(maxPixelDimension: Int = 1_600, jpegCompressionQuality: Double = 0.82) {
        self.maxPixelDimension = max(1, maxPixelDimension)
        self.jpegCompressionQuality = min(1.0, max(0.1, jpegCompressionQuality))
    }

    func process(data: Data) throws -> ProcessedAgentImage {
        guard let image = NSImage(data: data) else {
            throw AgentImageProcessorError.unsupportedImageData
        }
        return try process(image: image)
    }

    func process(fileURL: URL) throws -> ProcessedAgentImage {
        try process(data: Data(contentsOf: fileURL))
    }

    private func process(image: NSImage) throws -> ProcessedAgentImage {
        let sourceSize = pixelSize(for: image)
        let targetSize = scaledSize(for: sourceSize)
        let preservesAlpha = sourceHasAlpha(image)
        guard let bitmap = bitmapRepresentation(
            for: image,
            targetSize: targetSize,
            hasAlpha: preservesAlpha
        ) else {
            throw AgentImageProcessorError.bitmapRepresentationUnavailable
        }

        let usesPNG = preservesAlpha
        let fileType: NSBitmapImageRep.FileType = usesPNG ? .png : .jpeg
        let properties: [NSBitmapImageRep.PropertyKey: Any] = usesPNG
            ? [:]
            : [.compressionFactor: jpegCompressionQuality]
        guard let encoded = bitmap.representation(using: fileType, properties: properties) else {
            throw AgentImageProcessorError.encodedRepresentationUnavailable
        }

        return ProcessedAgentImage(
            data: encoded,
            mimeType: usesPNG ? "image/png" : "image/jpeg",
            fileExtension: usesPNG ? "png" : "jpg",
            pixelWidth: bitmap.pixelsWide,
            pixelHeight: bitmap.pixelsHigh
        )
    }

    private func pixelSize(for image: NSImage) -> NSSize {
        if let representation = image.representations.first {
            return NSSize(
                width: max(1, representation.pixelsWide),
                height: max(1, representation.pixelsHigh)
            )
        }
        return NSSize(width: max(1, image.size.width), height: max(1, image.size.height))
    }

    private func scaledSize(for size: NSSize) -> NSSize {
        let largestDimension = max(size.width, size.height)
        guard largestDimension > CGFloat(maxPixelDimension) else { return size }
        let scale = CGFloat(maxPixelDimension) / largestDimension
        return NSSize(
            width: max(1, floor(size.width * scale)),
            height: max(1, floor(size.height * scale))
        )
    }

    private func sourceHasAlpha(_ image: NSImage) -> Bool {
        image.representations.contains { $0.hasAlpha }
    }

    private func bitmapRepresentation(
        for image: NSImage,
        targetSize: NSSize,
        hasAlpha: Bool
    ) -> NSBitmapImageRep? {
        let width = max(1, Int(targetSize.width.rounded()))
        let height = max(1, Int(targetSize.height.rounded()))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: hasAlpha ? 4 : 3,
            hasAlpha: hasAlpha,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        (hasAlpha ? NSColor.clear : NSColor.white).setFill()
        NSRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height).fill()
        image.draw(
            in: NSRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        return bitmap
    }
}
