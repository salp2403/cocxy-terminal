// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownImageInliner.swift - Converts local image references to inline data URIs.

import Foundation
import ImageIO

// MARK: - Image Inliner

/// Replaces local `<img src="...">` references in HTML with inline `data:` URIs.
///
/// This makes an exported HTML file truly standalone — it carries its images
/// embedded in base64 instead of depending on the original filesystem paths.
enum MarkdownImageInliner {

    /// Replaces local image `src` attributes with base64 data URIs.
    ///
    /// - Parameters:
    ///   - html: The HTML string to process.
    ///   - baseDirectory: The directory used to resolve relative image paths.
    /// - Returns: The HTML with local images inlined. Remote URLs are left unchanged.
    static func inlineLocalImages(in html: String, baseDirectory: URL) -> String {
        // Match <img ... src="..." ...> — capture the src value
        guard let regex = try? NSRegularExpression(
            pattern: #"(<img\b[^>]*\bsrc\s*=\s*")([^"]+)("[^>]*>)"#,
            options: []
        ) else { return html }

        let nsHTML = html as NSString
        var result = html
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        // Process in reverse order so replacements don't shift indices
        for match in matches.reversed() {
            guard match.numberOfRanges == 4 else { continue }

            let srcRange = match.range(at: 2)
            let src = nsHTML.substring(with: srcRange)

            // Skip remote URLs and data URIs
            if src.hasPrefix("http://") || src.hasPrefix("https://") || src.hasPrefix("data:") {
                continue
            }

            // Resolve the path relative to baseDirectory
            let imageURL: URL
            if src.hasPrefix("/") {
                imageURL = URL(fileURLWithPath: src)
            } else if src.hasPrefix("file://") {
                guard let url = URL(string: src) else { continue }
                imageURL = url
            } else {
                imageURL = baseDirectory.appendingPathComponent(src)
            }

            // Only inline files with known image extensions AND valid image
            // magic bytes to prevent exfiltration of arbitrary local files.
            let ext = imageURL.pathExtension.lowercased()
            guard allowedImageExtensions.contains(ext) else { continue }

            guard FileManager.default.fileExists(atPath: imageURL.path),
                  let data = try? Data(contentsOf: imageURL) else { continue }

            // Verify the file content is actually an image, not just a file
            // renamed to look like one.
            guard isValidImageData(data, extension: ext) else { continue }

            let mimeType = mimeTypeForExtension(ext)
            let base64 = data.base64EncodedString()
            let dataURI = "data:\(mimeType);base64,\(base64)"

            // Replace the src value
            let fullRange = match.range(at: 0)
            let prefix = nsHTML.substring(with: match.range(at: 1))
            let suffix = nsHTML.substring(with: match.range(at: 3))
            let replacement = prefix + dataURI + suffix

            let swiftRange = Range(fullRange, in: result)!
            result.replaceSubrange(swiftRange, with: replacement)
        }

        return result
    }

    /// File extensions that are safe to inline. Only actual image formats
    /// are allowed — arbitrary files (keys, configs, etc.) are never read.
    private static let allowedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "tiff", "tif"
    ]

    /// Validates that file data is an actual image of the expected type.
    ///
    /// Raster formats are validated with ImageIO so renamed local files do not
    /// pass just by sharing a magic-byte prefix. SVG remains a text-based check
    /// because ImageIO does not guarantee vector parsing for raw SVG data.
    private static func isValidImageData(_ data: Data, extension ext: String) -> Bool {
        guard !data.isEmpty else { return false }

        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif":
            return isValidRasterImageData(data)
        case "svg":
            return containsSVGRootElement(in: data)
        default:
            return false
        }
    }

    private static func isValidRasterImageData(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
    }

    private static func containsSVGRootElement(in data: Data) -> Bool {
        var prefix = String(data: data.prefix(1024), encoding: .utf8) ?? ""
        if prefix.hasPrefix("\u{FEFF}") {
            prefix.removeFirst()
        }
        let lowered = prefix.lowercased()
        return lowered.contains("<svg") || lowered.contains("<svg:")
    }

    /// Returns the MIME type for a file extension.
    private static func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "tiff", "tif": return "image/tiff"
        default: return "application/octet-stream"
        }
    }
}
