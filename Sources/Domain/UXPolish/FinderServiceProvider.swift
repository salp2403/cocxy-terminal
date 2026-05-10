// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// FinderServiceProvider.swift - Finder Services bridge and path normalization.

import AppKit
import Foundation

@MainActor
final class FinderServiceProvider: NSObject {
    typealias OpenHandler = @MainActor ([URL]) -> Void

    private let openWorkspaceHandler: OpenHandler
    private let openWindowHandler: OpenHandler

    init(openWorkspace: @escaping OpenHandler, openWindow: @escaping OpenHandler) {
        self.openWorkspaceHandler = openWorkspace
        self.openWindowHandler = openWindow
        super.init()
    }

    nonisolated static func normalizedWorkspaceURLs(from urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []

        for url in urls {
            guard let directory = normalizedWorkspaceURL(from: url) else { continue }
            let key = directory.path
            guard seen.insert(key).inserted else { continue }
            result.append(directory)
        }

        return result
    }

    static func pasteboardURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            return urls
        }

        guard let paths = pasteboard.propertyList(forType: .init("NSFilenamesPboardType")) as? [String] else {
            return []
        }
        return paths.map { URL(fileURLWithPath: $0) }
    }

    @objc(openWorkspaceHere:userData:error:)
    func openWorkspaceHere(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        open(
            Self.normalizedWorkspaceURLs(from: Self.pasteboardURLs(from: pasteboard)),
            using: openWorkspaceHandler,
            error: error
        )
    }

    @objc(openWindowHere:userData:error:)
    func openWindowHere(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        open(
            Self.normalizedWorkspaceURLs(from: Self.pasteboardURLs(from: pasteboard)),
            using: openWindowHandler,
            error: error
        )
    }

    nonisolated private static func normalizedWorkspaceURL(from url: URL) -> URL? {
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue {
            return standardized
        }
        return standardized.deletingLastPathComponent().standardizedFileURL
    }

    private func open(
        _ urls: [URL],
        using handler: OpenHandler,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard !urls.isEmpty else {
            error.pointee = "No Finder folder was provided."
            return
        }
        handler(urls)
    }
}
