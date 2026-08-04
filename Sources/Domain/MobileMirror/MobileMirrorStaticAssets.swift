// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorStaticAssets.swift - Public web assets sourced from CocxyCore.

import CocxyCoreKit
import Foundation

enum MobileMirrorStaticAssets {
    static let orderedPaths: [String] = loadCompiledPaths()
    static let allowedPaths = Set(orderedPaths)

    private static func loadCompiledPaths() -> [String] {
        var length: UInt32 = 0
        guard let pointer = cocxycore_web_static_asset_paths(&length), length > 0 else {
            return []
        }
        let bytes = UnsafeBufferPointer(start: pointer, count: Int(length))
        return String(decoding: bytes, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }
}
