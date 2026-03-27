// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// InlineImageRenderer.swift - Renders inline images from OSC 1337 sequences.

import AppKit

// MARK: - Inline Image Data

/// Parsed data from an OSC 1337 inline image sequence.
///
/// The OSC 1337 protocol (originally from iTerm2) encodes images as:
/// `ESC ] 1337 ; File=[params] : [base64-data] BEL`
///
/// This struct holds the decoded result, ready for rendering.
struct InlineImageData: Sendable {

    /// The decoded image data (from base64).
    let imageData: Data

    /// Desired display width in pixels, or nil for auto-sizing.
    let width: CGFloat?

    /// Desired display height in pixels, or nil for auto-sizing.
    let height: CGFloat?

    /// Whether to preserve the image's aspect ratio when both dimensions are set.
    let preserveAspectRatio: Bool

    /// Whether to display inline (true) or treat as a file download (false).
    let inline: Bool

    /// Original filename if provided in the sequence (base64-decoded).
    let filename: String?
}

// MARK: - OSC 1337 Parser

/// Parses OSC 1337 File= sequences into structured image data.
///
/// Expected input format (the payload after stripping the OSC wrapper):
/// ```
/// File=[key=value;...]:base64data
/// ```
///
/// Supported parameters:
/// - `name`: Base64-encoded original filename.
/// - `size`: File size in bytes (informational, not validated).
/// - `width`: Display width (`N`, `Npx`, or `auto`).
/// - `height`: Display height (`N`, `Npx`, or `auto`).
/// - `preserveAspectRatio`: `0` or `1` (defaults to `1`).
/// - `inline`: `0` or `1` (defaults to `0`).
enum OSC1337Parser {

    /// Attempts to parse an OSC 1337 payload into inline image data.
    ///
    /// - Parameter payload: The raw payload string after "1337;".
    ///   Must start with "File=" followed by parameters, a colon,
    ///   and base64-encoded image data.
    /// - Returns: Parsed image data, or nil if the payload is malformed.
    static func parse(_ payload: String) -> InlineImageData? {
        guard payload.hasPrefix("File=") else { return nil }

        let content = String(payload.dropFirst(5))

        guard let colonIndex = content.firstIndex(of: ":") else { return nil }

        let paramsString = String(content[content.startIndex..<colonIndex])
        let base64String = String(content[content.index(after: colonIndex)...])

        guard !base64String.isEmpty else { return nil }

        guard let imageData = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters),
              !imageData.isEmpty else {
            return nil
        }

        let params = parseParams(paramsString)

        let isInline = params["inline"] == "1"
        let preserveAR = params["preserveAspectRatio"] != "0"

        let width = parseDimension(params["width"])
        let height = parseDimension(params["height"])

        var filename: String?
        if let nameBase64 = params["name"],
           let nameData = Data(base64Encoded: nameBase64),
           let decoded = String(data: nameData, encoding: .utf8) {
            filename = decoded
        }

        return InlineImageData(
            imageData: imageData,
            width: width,
            height: height,
            preserveAspectRatio: preserveAR,
            inline: isInline,
            filename: filename
        )
    }

    // MARK: - Private Helpers

    /// Parses semicolon-separated key=value parameters.
    ///
    /// Example: `"width=100;height=50;inline=1"` yields
    /// `["width": "100", "height": "50", "inline": "1"]`.
    private static func parseParams(_ string: String) -> [String: String] {
        var params: [String: String] = [:]
        let pairs = string.components(separatedBy: ";")
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            params[String(parts[0])] = String(parts[1])
        }
        return params
    }

    /// Parses a dimension value from the protocol.
    ///
    /// Valid inputs: `"100"`, `"200px"`, `"auto"`.
    /// Returns nil for `"auto"`, empty strings, or non-numeric values.
    private static func parseDimension(_ value: String?) -> CGFloat? {
        guard let value, !value.isEmpty, value != "auto" else { return nil }
        let numericString = value.replacingOccurrences(of: "px", with: "")
        guard let doubleValue = Double(numericString) else { return nil }
        return CGFloat(doubleValue)
    }
}

// MARK: - Inline Image Renderer

/// Manages rendering of inline images as overlay subviews on the terminal.
///
/// Creates `NSImageView` instances positioned over the terminal content.
/// Images are tracked by ID and cleaned up on tab switch, terminal clear,
/// or when they scroll out of the visible area.
///
/// Security: Image data is validated by `NSImage(data:)` before rendering.
/// Only images that AppKit can decode are displayed. No external network
/// requests are made.
@MainActor
final class InlineImageRenderer {

    /// Active image views keyed by their sequential ID.
    private var imageViews: [Int: NSImageView] = [:]

    /// Next ID to assign to a rendered image.
    private var nextImageID: Int = 0

    /// The terminal view that hosts the image overlays.
    private weak var terminalView: NSView?

    /// Maximum image dimension to prevent excessive memory usage.
    static let maxDimension: CGFloat = 2048

    /// Number of currently rendered images.
    var activeImageCount: Int { imageViews.count }

    init(terminalView: NSView) {
        self.terminalView = terminalView
    }

    /// Renders an inline image from parsed OSC 1337 data.
    ///
    /// The image is positioned at the given y-coordinate with a 10pt
    /// left margin. If the image data cannot be decoded by AppKit,
    /// nothing is rendered and nil is returned.
    ///
    /// - Parameters:
    ///   - data: The parsed inline image data.
    ///   - position: The y-position in the terminal view for the image.
    /// - Returns: An image ID for later cleanup, or nil on failure.
    @discardableResult
    func renderImage(_ data: InlineImageData, at position: CGFloat) -> Int? {
        guard data.inline else { return nil }
        guard let image = NSImage(data: data.imageData) else { return nil }
        guard let terminalView else { return nil }

        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = data.preserveAspectRatio
            ? .scaleProportionallyUpOrDown
            : .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4

        let originalSize = image.size
        let maxWidth = terminalView.bounds.width - 20
        var displaySize = calculateDisplaySize(
            originalSize: originalSize,
            requestedWidth: data.width,
            requestedHeight: data.height,
            preserveAspectRatio: data.preserveAspectRatio,
            maxWidth: maxWidth
        )

        displaySize.width = min(displaySize.width, Self.maxDimension)
        displaySize.height = min(displaySize.height, Self.maxDimension)

        imageView.frame = NSRect(
            x: 10,
            y: position,
            width: displaySize.width,
            height: displaySize.height
        )

        terminalView.addSubview(imageView)

        let imageID = nextImageID
        nextImageID += 1
        imageViews[imageID] = imageView

        return imageID
    }

    /// Removes a specific inline image by its ID.
    func removeImage(_ imageID: Int) {
        imageViews[imageID]?.removeFromSuperview()
        imageViews.removeValue(forKey: imageID)
    }

    /// Removes all inline images.
    ///
    /// Called on tab switch, terminal clear, or when the surface is destroyed.
    func clearAllImages() {
        for (_, view) in imageViews {
            view.removeFromSuperview()
        }
        imageViews.removeAll()
        nextImageID = 0
    }

    // MARK: - Size Calculation

    /// Calculates the display size for an image based on protocol parameters.
    ///
    /// When only one dimension is specified and aspect ratio preservation is on,
    /// the other dimension is computed proportionally. Both dimensions are clamped
    /// to the maximum allowed width.
    private func calculateDisplaySize(
        originalSize: NSSize,
        requestedWidth: CGFloat?,
        requestedHeight: CGFloat?,
        preserveAspectRatio: Bool,
        maxWidth: CGFloat
    ) -> NSSize {
        var width = requestedWidth ?? min(originalSize.width, maxWidth)
        var height = requestedHeight ?? originalSize.height

        if preserveAspectRatio {
            if requestedWidth != nil && requestedHeight == nil {
                let ratio = originalSize.height / max(originalSize.width, 1)
                height = width * ratio
            } else if requestedHeight != nil && requestedWidth == nil {
                let ratio = originalSize.width / max(originalSize.height, 1)
                width = height * ratio
            }
        }

        width = min(width, maxWidth)

        return NSSize(width: width, height: height)
    }
}
