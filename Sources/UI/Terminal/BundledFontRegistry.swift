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

    /// Returns URLs for font files shipped inside the production `.app`.
    ///
    /// Scans `Bundle.main.resourceURL/Fonts/` which is populated by
    /// `build-app.sh` step 6d. In SwiftPM dev/test contexts this directory
    /// does not exist, so the method returns an empty array — the
    /// `FontFallbackResolver` chain falls back to system fonts.
    ///
    /// We never access `Bundle.module` because the SwiftPM-synthesized
    /// `static let module` accessor triggers `fatalError` when the resource
    /// bundle is absent — which is always the case in a production `.app`.
    /// See the v0.1.53 crash report (2026-04-11).
    static func fontResourceURLs() -> [URL] {
        var discovered = Set<URL>()

        for directory in candidateDirectories() {
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

    private static func candidateDirectories() -> [URL] {
        // Production `.app` ships fonts in `Contents/Resources/Fonts/` via
        // `build-app.sh` step 6d. `Bundle.main.resourceURL` resolves to
        // that directory.
        //
        // In SwiftPM dev/test contexts (`swift run`, `swift test`),
        // `Bundle.main` points to the test runner or raw executable, which
        // does not have a `Fonts/` subdirectory. Font registration is a
        // no-op in that context — system-installed fonts or Menlo serve as
        // fallback via the `FontFallbackResolver` chain.
        //
        // We intentionally do NOT access `Bundle.module` here. The
        // SwiftPM-synthesized accessor triggers `fatalError` inside
        // `dispatch_once` when the resource bundle is absent — which is
        // always the case in a production `.app` that does not ship the
        // SwiftPM resource bundle. See the v0.1.53 crash report
        // (2026-04-11). Keep this minimal: main bundle only.
        //
        // Earlier iterations walked `Bundle.allBundles` and
        // `Bundle.allFrameworks` with ancestor walks (200+ bundles ×
        // ~10 levels × 3 CF ops each), hanging xctest processes for
        // minutes. See `feedback_bundle_allframeworks_loop.md`.
        var discovered = Set<URL>()

        if let mainResourceURL = Bundle.main.resourceURL {
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
