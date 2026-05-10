// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HighFidelityClipboardSwiftTestingTests.swift - Multi-type pasteboard preservation.

import AppKit
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("High-fidelity clipboard")
@MainActor
struct HighFidelityClipboardSwiftTestingTests {

    @Test("captures and restores all representations on one pasteboard item")
    func capturesAndRestoresAllRepresentationsOnOneItem() throws {
        let source = NSPasteboard(name: NSPasteboard.Name("cocxy-hifi-source-\(UUID().uuidString)"))
        let target = NSPasteboard(name: NSPasteboard.Name("cocxy-hifi-target-\(UUID().uuidString)"))
        source.clearContents()
        target.clearContents()
        let item = NSPasteboardItem()
        item.setString("plain text", forType: .string)
        item.setString("<strong>plain text</strong>", forType: .html)
        item.setData(Self.pngData, forType: .png)
        #expect(source.writeObjects([item]))

        let snapshot = HighFidelityClipboard(pasteboard: source).capture()
        #expect(snapshot.items.count == 1)
        #expect(snapshot.items[0].types.contains(NSPasteboard.PasteboardType.string.rawValue))
        #expect(snapshot.items[0].types.contains(NSPasteboard.PasteboardType.html.rawValue))
        #expect(snapshot.items[0].types.contains(NSPasteboard.PasteboardType.png.rawValue))

        #expect(HighFidelityClipboard(pasteboard: target).restore(snapshot))
        #expect(target.string(forType: .string) == "plain text")
        #expect(target.string(forType: .html) == "<strong>plain text</strong>")
        #expect(target.data(forType: .png) == Self.pngData)
    }

    @Test("preserves file URL pasteboard representations")
    func preservesFileURLRepresentations() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-hifi-file-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let fileURL = tempDirectory.appendingPathComponent("image.png", isDirectory: false)
        try Self.pngData.write(to: fileURL, options: [.atomic])

        let source = NSPasteboard(name: NSPasteboard.Name("cocxy-hifi-file-source-\(UUID().uuidString)"))
        let target = NSPasteboard(name: NSPasteboard.Name("cocxy-hifi-file-target-\(UUID().uuidString)"))
        source.clearContents()
        target.clearContents()
        #expect(source.writeObjects([fileURL as NSURL]))

        let snapshot = HighFidelityClipboard(pasteboard: source).capture()
        #expect(snapshot.items.flatMap(\.types).contains("public.file-url"))

        #expect(HighFidelityClipboard(pasteboard: target).restore(snapshot))
        let restored = target.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        #expect(restored?.first == fileURL)
    }

    @Test("empty pasteboard captures an empty snapshot and restore clears target")
    func emptySnapshotClearsTargetOnRestore() {
        let source = NSPasteboard(name: NSPasteboard.Name("cocxy-hifi-empty-source-\(UUID().uuidString)"))
        let target = NSPasteboard(name: NSPasteboard.Name("cocxy-hifi-empty-target-\(UUID().uuidString)"))
        source.clearContents()
        target.clearContents()
        target.setString("previous", forType: .string)

        let snapshot = HighFidelityClipboard(pasteboard: source).capture()
        #expect(snapshot.isEmpty)

        #expect(HighFidelityClipboard(pasteboard: target).restore(snapshot))
        #expect(target.string(forType: .string) == nil)
    }

    private static let pngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
    )!
}
