// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SystemClipboardService.swift - NSPasteboard-backed clipboard service.

import AppKit

// MARK: - System Clipboard Service

/// Production implementation of `ClipboardServiceProtocol` backed by `NSPasteboard.general`.
///
/// All operations target the general pasteboard (system clipboard).
/// This service is `@MainActor` because `NSPasteboard` must be accessed from the main thread.
@MainActor
final class SystemClipboardService: ClipboardServiceProtocol {
    private let pasteboard: NSPasteboard
    private let configuredClipboardImageDirectory: URL?

    init(
        pasteboard: NSPasteboard = .general,
        clipboardImageDirectory: URL? = nil
    ) {
        self.pasteboard = pasteboard
        self.configuredClipboardImageDirectory = clipboardImageDirectory
    }

    /// Reads the current string from the system clipboard.
    ///
    /// - Returns: The clipboard text, or `nil` if empty or not plain text.
    func read() -> String? {
        pasteboard.string(forType: .string)
    }

    func readImageAttachment() -> ClipboardImageAttachment? {
        if let fileURL = readImageFileURL(from: pasteboard) {
            return ClipboardImageAttachment(fileURL: fileURL)
        }

        guard let pngData = readPNGData(from: pasteboard),
              let storedURL = try? storeClipboardImage(pngData) else {
            return nil
        }
        return ClipboardImageAttachment(fileURL: storedURL)
    }

    func readTerminalPastePayload() -> ClipboardTerminalPastePayload? {
        if let fileURL = readImageFileURL(from: pasteboard) {
            return .fileURLs([fileURL])
        }

        let text = read()
        let hasImageData = containsInlineImageData(in: pasteboard)
        let hasRichTextPayload = containsRichTextPayload(in: pasteboard)

        if let text,
           !text.isEmpty,
           !Self.isAttachmentPlaceholderText(text),
           hasRichTextPayload || !hasImageData {
            return .text(text)
        }

        if let imageAttachment = readImageAttachment() {
            return .fileURLs([imageAttachment.fileURL])
        }

        if let text, !text.isEmpty {
            return .text(text)
        }

        return nil
    }

    /// Writes text to the system clipboard.
    ///
    /// Clears existing content before writing the new text.
    /// - Parameter text: The text to write to the clipboard.
    func write(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Clears all content from the system clipboard.
    func clear() {
        pasteboard.clearContents()
    }

    private func readImageFileURL(from pasteboard: NSPasteboard) -> URL? {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        return urls?.first(where: Self.isSupportedImageFile)
    }

    private func readPNGData(from pasteboard: NSPasteboard) -> Data? {
        if let pngData = pasteboard.data(forType: .png) {
            return pngData
        }
        if let jpegData = pasteboard.data(forType: Self.jpegPasteboardType) {
            return convertImageDataToPNG(jpegData)
        }
        if let tiffData = pasteboard.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: tiffData) {
            return bitmap.representation(using: .png, properties: [:])
        }
        return nil
    }

    private func containsInlineImageData(in pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: [.png, Self.jpegPasteboardType, .tiff]) != nil
    }

    private func containsRichTextPayload(in pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: [.rtf, .html]) != nil
    }

    private static func isAttachmentPlaceholderText(_ text: String) -> Bool {
        text
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func convertImageDataToPNG(_ data: Data) -> Data? {
        guard let bitmap = NSBitmapImageRep(data: data) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func storeClipboardImage(_ data: Data) throws -> URL {
        let directory = try clipboardImageDirectory()
        pruneOldClipboardImages(in: directory)

        let fileURL = directory.appendingPathComponent(
            "clipboard-image-\(UUID().uuidString.lowercased()).png",
            isDirectory: false
        )
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    private func clipboardImageDirectory() throws -> URL {
        if let configuredClipboardImageDirectory {
            try FileManager.default.createDirectory(
                at: configuredClipboardImageDirectory,
                withIntermediateDirectories: true
            )
            return configuredClipboardImageDirectory
        }
        let baseDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let directory = baseDirectory
            .appendingPathComponent("Cocxy", isDirectory: true)
            .appendingPathComponent("ClipboardImages", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func pruneOldClipboardImages(in directory: URL) {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in urls where url.pathExtension.lowercased() == "png" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values?.contentModificationDate, modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func isSupportedImageFile(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp":
            return true
        default:
            return false
        }
    }

    private static let jpegPasteboardType = NSPasteboard.PasteboardType("public.jpeg")
}
