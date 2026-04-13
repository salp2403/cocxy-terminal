// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownQuickLookHTMLSanitizer.swift - Makes Quick Look markdown previews deterministic.

import Foundation

/// Rewrites rendered markdown HTML into a self-contained fragment suitable for
/// the sandboxed Quick Look preview extension.
///
/// Quick Look is most reliable when the rendered document is fully local:
/// local images are inlined as `data:` URIs and remote images are replaced
/// with explicit placeholders instead of depending on network fetches that the
/// extension sandbox may block or delay.
public enum MarkdownQuickLookHTMLSanitizer {

    /// Produces offline-first HTML for the Quick Look extension.
    ///
    /// - Parameters:
    ///   - html: The HTML fragment rendered from the markdown document.
    ///   - baseDirectory: The directory used to resolve local relative images.
    /// - Returns: HTML with local images inlined and remote images replaced by
    ///   placeholders that preserve useful context for the reader.
    public static func makeOfflinePreviewHTML(from html: String, baseDirectory: URL) -> String {
        let localImagesInlined = MarkdownImageInliner.inlineLocalImages(in: html, baseDirectory: baseDirectory)
        return replaceRemoteImages(in: localImagesInlined)
    }

    private static func replaceRemoteImages(in html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(<img\b[^>]*\bsrc\s*=\s*)(['"])([^'"]+)\2([^>]*>)"#,
            options: [.caseInsensitive]
        ) else { return html }

        let nsHTML = html as NSString
        var result = html
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        for match in matches.reversed() {
            guard match.numberOfRanges == 5 else { continue }

            let src = nsHTML.substring(with: match.range(at: 3))
            guard isRemoteURL(src) else { continue }

            let fullTag = nsHTML.substring(with: match.range(at: 0))
            let altText = extractAttribute(named: "alt", from: fullTag)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let label = resolvedPlaceholderLabel(for: src, altText: altText)

            let replacement = """
            <figure class="ql-remote-image-placeholder" data-remote-image="true">
              <div class="ql-remote-image-label">Remote image unavailable in Quick Look</div>
              <figcaption>\(escapeHTML(label))</figcaption>
            </figure>
            """

            guard let swiftRange = Range(match.range(at: 0), in: result) else { continue }
            result.replaceSubrange(swiftRange, with: replacement)
        }

        return result
    }

    private static func isRemoteURL(_ src: String) -> Bool {
        src.hasPrefix("https://") || src.hasPrefix("http://")
    }

    private static func extractAttribute(named name: String, from tag: String) -> String? {
        let pattern = #"\b\#(name)\s*=\s*(['"])(.*?)\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsTag = tag as NSString
        let range = NSRange(location: 0, length: nsTag.length)
        guard let match = regex.firstMatch(in: tag, range: range), match.numberOfRanges == 3 else {
            return nil
        }
        return nsTag.substring(with: match.range(at: 2))
    }

    private static func resolvedPlaceholderLabel(for src: String, altText: String?) -> String {
        if let altText, !altText.isEmpty {
            return altText
        }
        if let url = URL(string: src), let host = url.host, !host.isEmpty {
            return host
        }
        return src
    }

    private static func escapeHTML(_ value: String) -> String {
        var escaped = value
        escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        escaped = escaped.replacingOccurrences(of: "'", with: "&#39;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        return escaped
    }
}
