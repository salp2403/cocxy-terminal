// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentPromptAttachmentPasteboardReader.swift - Pasteboard decoding for Agent image attachments.

import AppKit
import Foundation

enum AgentPromptAttachmentPasteboardPayload: Equatable {
    case fileURLs([URL])
    case imageData(Data, suggestedFilename: String)
}

struct AgentPromptAttachmentPasteboardReader {
    static let jpegPasteboardType = NSPasteboard.PasteboardType("public.jpeg")

    static let supportedPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .png,
        .tiff,
        jpegPasteboardType,
    ]

    func payload(from pasteboard: NSPasteboard) -> AgentPromptAttachmentPasteboardPayload? {
        let fileURLs = fileURLs(from: pasteboard)
        if !fileURLs.isEmpty {
            return .fileURLs(fileURLs)
        }

        for imageType in Self.imagePasteboardTypes {
            if let data = pasteboard.data(forType: imageType.type) {
                return .imageData(data, suggestedFilename: imageType.filename)
            }
        }

        return nil
    }

    func containsSupportedAttachment(_ pasteboard: NSPasteboard) -> Bool {
        guard fileURLs(from: pasteboard).isEmpty else { return true }
        return Self.imagePasteboardTypes.contains { pasteboard.availableType(from: [$0.type]) != nil }
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) ?? []
        return objects.compactMap { object -> URL? in
            if let url = object as? URL {
                return url.isFileURL ? url : nil
            }
            if let nsURL = object as? NSURL {
                let url = nsURL as URL
                return url.isFileURL ? url : nil
            }
            return nil
        }
    }

    private static let imagePasteboardTypes: [(type: NSPasteboard.PasteboardType, filename: String)] = [
        (.png, "pasted-image.png"),
        (jpegPasteboardType, "pasted-image.jpg"),
        (.tiff, "pasted-image.tiff"),
    ]
}
