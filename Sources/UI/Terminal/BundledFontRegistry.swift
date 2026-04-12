// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BundledFontRegistry.swift - Registers Cocxy-shipped terminal fonts.

import AppKit
import CoreText
import Foundation

/// Registers the small set of terminal fonts shipped inside the app bundle.
///
/// Cocxy should render consistently even on clean Macs that do not have our
/// preferred fonts installed system-wide. This helper discovers bundled font
/// files under `Resources/Fonts`, registers them once for the current process,
/// and exposes lightweight metadata for the preferences UI and fallback logic.
@MainActor
enum BundledFontRegistry {

    /// Curated families shipped with the app.
    static let bundledFamilies = [
        FontFallbackResolver.jetBrainsMonoNerdFontMono,
        FontFallbackResolver.monaspaceNeon,
    ]

    private static var didRegister = false

    /// Registers all bundled fonts for the current process.
    ///
    /// Safe to call repeatedly; subsequent calls are no-ops. Already-registered
    /// errors are ignored so tests and app relaunch flows stay quiet.
    static func ensureRegistered() {
        guard !didRegister else { return }
        didRegister = true

        for url in fontResourceURLs() {
            registerFont(at: url)
        }
        FontFallbackResolver.invalidateCaches()
    }

    /// Returns URLs for font files shipped with the target resources.
    static func fontResourceURLs(bundle: Bundle = .module) -> [URL] {
        var discovered = Set<URL>()

        for directory in candidateDirectories(bundle: bundle) {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for url in urls where ["otf", "ttf"].contains(url.pathExtension.lowercased()) {
                discovered.insert(url.standardizedFileURL)
            }
        }

        return discovered.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    static func isBundledFamily(_ family: String) -> Bool {
        bundledFamilies.contains {
            $0.caseInsensitiveCompare(family) == .orderedSame
        }
    }

    private static func registerFont(at url: URL) {
        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)

        guard !registered, let cfError = error?.takeRetainedValue() else { return }
        guard !isAlreadyRegisteredError(cfError) else { return }

        let message = CFErrorCopyDescription(cfError) as String? ?? "unknown error"
        NSLog("Cocxy bundled font registration failed for %@: %@", url.lastPathComponent, message)
    }

    private static func isAlreadyRegisteredError(_ error: CFError) -> Bool {
        let domain = CFErrorGetDomain(error) as String
        return domain == (kCTFontManagerErrorDomain as String)
            && CFErrorGetCode(error) == CTFontManagerError.alreadyRegistered.rawValue
    }

    private static func candidateDirectories(bundle: Bundle) -> [URL] {
        // We only look in the two bundles that ship the `Fonts/` directory
        // as a real resource: the Swift Package target bundle (which is
        // also what `Bundle.main` resolves to under `swift run` and `swift
        // test`) and the application `.app` bundle in production.
        //
        // Earlier iterations of this helper tried to be extra-defensive by
        // walking every entry in `Bundle.allBundles` and
        // `Bundle.allFrameworks`, plus every ancestor of those bundles'
        // `resourceURL`, plus every ancestor of `currentDirectoryPath`
        // and `executableURL`. In a typical xctest process that exploded
        // into >200 bundles × ~10 ancestor levels each, each level doing
        // three CoreFoundation URL allocations and a `stat(2)` syscall.
        // Measured with `sample`, the loop was emitting ~766 iterations
        // per second — meaning one call to `candidateDirectories` would
        // spend several minutes inside CoreFoundation and never return,
        // silently hanging any test that exercised the resolver (most
        // visibly `FontFallbackTests.testAvailableFixedPitchFamiliesContainsMenlo`).
        //
        // Keep this simple: Swift Package / main bundle only. `Bundle.module`
        // is populated by SwiftPM from the `.copy("../Resources/Fonts")`
        // entry in `Package.swift`, and the release bundle script copies
        // the same folder into `Contents/Resources/Fonts`, so both paths
        // find the files.
        var discovered = Set<URL>()

        if let resourceURL = bundle.resourceURL {
            collectFontsDirectory(at: resourceURL, into: &discovered)
        }

        if let mainResourceURL = Bundle.main.resourceURL,
           mainResourceURL != bundle.resourceURL {
            collectFontsDirectory(at: mainResourceURL, into: &discovered)
        }

        return discovered.sorted {
            $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
        }
    }

    private static func collectFontsDirectory(at resourceURL: URL, into discovered: inout Set<URL>) {
        let fontsDirectory = resourceURL.appendingPathComponent("Fonts", isDirectory: true)
        if FileManager.default.fileExists(atPath: fontsDirectory.path) {
            discovered.insert(fontsDirectory.standardizedFileURL)
        }
    }
}
