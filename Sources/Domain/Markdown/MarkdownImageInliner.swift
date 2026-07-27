// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownImageInliner.swift - Contained local images and consent-bound remote images.

import Darwin
import Foundation
import ImageIO

public struct MarkdownImageProcessingResult: Equatable, Sendable {
    public let html: String
    public let remoteHosts: Set<String>
    public let blockedRemoteHosts: Set<String>
    public let blockedLocalImageCount: Int
}

/// Applies the image authority policy shared by Markdown previews and exports.
public enum MarkdownImageInliner {
    private static let maxImageBytes = 25 * 1_024 * 1_024
    private static let maxDataURIBytes = 36 * 1_024 * 1_024
    private static let imageRegex = try! NSRegularExpression(
        pattern: #"(<img\b[^>]*?\s)src\s*=\s*(['"])([^'"]+)\2([^>]*>)"#,
        options: [.caseInsensitive]
    )

    /// Produces HTML whose local images come only from the approved directory
    /// and whose remote image URLs are present only for explicitly approved hosts.
    public static func makeSafeHTML(
        in html: String,
        baseDirectory: URL?,
        approvedRemoteHosts: Set<String> = []
    ) -> MarkdownImageProcessingResult {
        let normalizedApprovedHosts = Set(approvedRemoteHosts.map(normalizedHost))
        let nsHTML = html as NSString
        var result = html
        var remoteHosts: Set<String> = []
        var blockedRemoteHosts: Set<String> = []
        var blockedLocalImageCount = 0
        let matches = imageRegex.matches(
            in: html,
            range: NSRange(location: 0, length: nsHTML.length)
        )

        for match in matches.reversed() {
            guard match.numberOfRanges == 5,
                  let swiftRange = Range(match.range(at: 0), in: result)
            else {
                continue
            }

            let prefix = nsHTML.substring(with: match.range(at: 1))
            let quote = nsHTML.substring(with: match.range(at: 2))
            let source = nsHTML.substring(with: match.range(at: 3))
            let suffix = nsHTML.substring(with: match.range(at: 4))

            switch classify(source) {
            case .remote(let host):
                remoteHosts.insert(host)
                guard normalizedApprovedHosts.contains(host) else {
                    blockedRemoteHosts.insert(host)
                    result.replaceSubrange(
                        swiftRange,
                        with: blockedTag(prefix: prefix, suffix: suffix, reason: "remote")
                    )
                    continue
                }
            case .dataImage:
                guard isValidDataImageURI(source) else {
                    blockedLocalImageCount += 1
                    result.replaceSubrange(
                        swiftRange,
                        with: blockedTag(prefix: prefix, suffix: suffix, reason: "data")
                    )
                    continue
                }
            case .local:
                guard let baseDirectory,
                      let image = containedImage(source: source, under: baseDirectory)
                else {
                    blockedLocalImageCount += 1
                    result.replaceSubrange(
                        swiftRange,
                        with: blockedTag(prefix: prefix, suffix: suffix, reason: "local")
                    )
                    continue
                }
                let dataURI = "data:\(mimeTypeForExtension(image.extension));base64,\(image.data.base64EncodedString())"
                result.replaceSubrange(
                    swiftRange,
                    with: prefix + "src=" + quote + dataURI + quote + suffix
                )
            case .unsupported:
                blockedLocalImageCount += 1
                result.replaceSubrange(
                    swiftRange,
                    with: blockedTag(prefix: prefix, suffix: suffix, reason: "unsupported")
                )
            }
        }

        return MarkdownImageProcessingResult(
            html: result,
            remoteHosts: remoteHosts,
            blockedRemoteHosts: blockedRemoteHosts,
            blockedLocalImageCount: blockedLocalImageCount
        )
    }

    /// Compatibility entry point used by standalone local-image consumers.
    /// Remote images remain present, while every local read is still contained.
    public static func inlineLocalImages(in html: String, baseDirectory: URL) -> String {
        makeSafeHTML(
            in: html,
            baseDirectory: baseDirectory,
            approvedRemoteHosts: remoteImageHosts(in: html)
        ).html
    }

    public static func remoteImageHosts(in html: String) -> Set<String> {
        let nsHTML = html as NSString
        let matches = imageRegex.matches(
            in: html,
            range: NSRange(location: 0, length: nsHTML.length)
        )
        return Set(matches.compactMap { match in
            guard match.numberOfRanges == 5 else { return nil }
            let source = nsHTML.substring(with: match.range(at: 3))
            if case .remote(let host) = classify(source) {
                return host
            }
            return nil
        })
    }

    private enum SourceKind {
        case remote(String)
        case dataImage
        case local
        case unsupported
    }

    private struct ContainedImage {
        let data: Data
        let `extension`: String
    }

    private static func classify(_ source: String) -> SourceKind {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            return .unsupported
        }

        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("data:") {
            return lowered.hasPrefix("data:image/") ? .dataImage : .unsupported
        }
        if let components = URLComponents(string: trimmed),
           let scheme = components.scheme?.lowercased() {
            if scheme == "http" || scheme == "https" {
                guard let host = components.host, !host.isEmpty else { return .unsupported }
                return .remote(normalizedHost(host))
            }
            return scheme == "file" ? .local : .unsupported
        }
        guard !trimmed.hasPrefix("//") else { return .unsupported }
        return .local
    }

    private static func normalizedHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func blockedTag(prefix: String, suffix: String, reason: String) -> String {
        prefix + "data-cocxy-image-blocked=\"\(reason)\"" + suffix
    }

    private static let allowedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "tiff", "tif",
    ]

    private static func containedImage(source: String, under baseDirectory: URL) -> ContainedImage? {
        let root = baseDirectory.resolvingSymlinksInPath().standardizedFileURL
        let candidate: URL
        let lowered = source.lowercased()
        if lowered.hasPrefix("file:") {
            guard let fileURL = URL(string: source), fileURL.isFileURL else { return nil }
            candidate = fileURL.standardizedFileURL
        } else if source.hasPrefix("/") {
            candidate = URL(fileURLWithPath: source).standardizedFileURL
        } else {
            candidate = root.appendingPathComponent(source).standardizedFileURL
        }

        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidateComponents.count > rootComponents.count,
              candidateComponents.starts(with: rootComponents)
        else {
            return nil
        }

        let relativeComponents = Array(candidateComponents.dropFirst(rootComponents.count))
        guard relativeComponents.allSatisfy(isSafePathComponent) else { return nil }
        let ext = candidate.pathExtension.lowercased()
        guard allowedImageExtensions.contains(ext),
              let data = readRegularFile(
                relativeComponents: relativeComponents,
                under: root,
                maxBytes: maxImageBytes
              ),
              isValidImageData(data, extension: ext)
        else {
            return nil
        }
        return ContainedImage(data: data, extension: ext)
    }

    private static func isSafePathComponent(_ component: String) -> Bool {
        !component.isEmpty
            && component != "."
            && component != ".."
            && !component.contains("/")
            && !component.unicodeScalars.contains(where: { $0.value == 0 })
    }

    private static func readRegularFile(
        relativeComponents: [String],
        under root: URL,
        maxBytes: Int
    ) -> Data? {
        guard !relativeComponents.isEmpty else { return nil }
        var descriptor = root.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        for (index, component) in relativeComponents.enumerated() {
            let isFinal = index == relativeComponents.count - 1
            let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | (isFinal ? 0 : O_DIRECTORY)
            let nextDescriptor = component.withCString {
                Darwin.openat(descriptor, $0, flags)
            }
            guard nextDescriptor >= 0 else { return nil }
            Darwin.close(descriptor)
            descriptor = nextDescriptor
        }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              metadata.st_size >= 0,
              metadata.st_size <= off_t(maxBytes)
        else {
            return nil
        }

        var data = Data()
        data.reserveCapacity(Int(metadata.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { return nil }
            if count == 0 { break }
            guard count <= maxBytes - data.count else { return nil }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    private static func isValidImageData(_ data: Data, extension ext: String) -> Bool {
        guard !data.isEmpty else { return false }
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif":
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return false
            }
            return CGImageSourceGetCount(source) > 0
        case "svg":
            return isSelfContainedSVG(data)
        default:
            return false
        }
    }

    private static func isValidDataImageURI(_ source: String) -> Bool {
        guard source.utf8.count <= maxDataURIBytes,
              let separator = source.firstIndex(of: ",")
        else {
            return false
        }
        let metadata = source[..<separator].lowercased()
        guard metadata.hasSuffix(";base64") else { return false }
        let ext: String
        switch metadata.dropLast(";base64".count) {
        case "data:image/png": ext = "png"
        case "data:image/jpeg": ext = "jpeg"
        case "data:image/gif": ext = "gif"
        case "data:image/webp": ext = "webp"
        case "data:image/bmp": ext = "bmp"
        case "data:image/tiff": ext = "tiff"
        case "data:image/svg+xml": ext = "svg"
        default: return false
        }
        let encoded = String(source[source.index(after: separator)...])
        guard let data = Data(base64Encoded: encoded), data.count <= maxImageBytes else {
            return false
        }
        return isValidImageData(data, extension: ext)
    }

    private static func isSelfContainedSVG(_ data: Data) -> Bool {
        guard var text = String(data: data, encoding: .utf8) else { return false }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let lowered = text.lowercased()
        guard lowered.contains("<svg"),
              !lowered.contains("<script"),
              !lowered.contains("<foreignobject"),
              !lowered.contains("<!entity"),
              !lowered.contains("<!doctype"),
              !lowered.contains("@import")
        else {
            return false
        }

        if let externalReference = try? NSRegularExpression(
            pattern: #"\b(?:href|xlink:href|src)\s*=\s*['"]\s*(?!#)[^'"]+['"]"#,
            options: [.caseInsensitive]
        ), externalReference.firstMatch(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length)
        ) != nil {
            return false
        }
        if let externalCSSURL = try? NSRegularExpression(
            pattern: #"url\(\s*['"]?(?!#)"#,
            options: [.caseInsensitive]
        ), externalCSSURL.firstMatch(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length)
        ) != nil {
            return false
        }
        return true
    }

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
