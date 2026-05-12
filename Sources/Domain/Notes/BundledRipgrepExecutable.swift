// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BundledRipgrepExecutable.swift - Resolves the local ripgrep helper.

import Foundation

enum BundledRipgrepExecutable {

    static let resourceName = "rg"

    static func resolve(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        developmentRoot: URL? = nil,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"]
    ) -> URL? {
        let candidates = [
            bundle.resourceURL?.appendingPathComponent(resourceName),
            developmentRoot?.appendingPathComponent("Resources").appendingPathComponent(resourceName),
        ].compactMap { $0 }

        for candidate in candidates where isExecutable(candidate, fileManager: fileManager) {
            return candidate
        }

        return resolveFromPATH(pathEnvironment, fileManager: fileManager)
    }

    static func resolveFromPATH(
        _ pathEnvironment: String?,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let pathEnvironment, !pathEnvironment.isEmpty else { return nil }
        for component in pathEnvironment.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = URL(fileURLWithPath: String(component), isDirectory: true)
                .appendingPathComponent(resourceName)
            if isExecutable(candidate, fileManager: fileManager) {
                return candidate
            }
        }
        return nil
    }

    static func isExecutable(_ url: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.isExecutableFile(atPath: url.path)
    }
}
