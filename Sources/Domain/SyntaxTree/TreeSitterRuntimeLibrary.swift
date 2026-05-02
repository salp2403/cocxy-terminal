// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TreeSitterRuntimeLibrary.swift - Local Tree-sitter core dylib symbol provider.

import Darwin
import Foundation

final class TreeSitterRuntimeLibrary {
    typealias FileExists = (URL) -> Bool
    typealias OpenLibrary = (URL) -> UnsafeMutableRawPointer?
    typealias LookupSymbol = (UnsafeMutableRawPointer, String) -> UnsafeMutableRawPointer?
    typealias CloseLibrary = (UnsafeMutableRawPointer) -> Void

    static let defaultResourceCandidates = [
        "TreeSitter/libtree-sitter.dylib",
        "Grammars/libtree-sitter.dylib",
    ]

    private let handle: UnsafeMutableRawPointer
    private let lookupSymbolImpl: LookupSymbol
    private let closeLibrary: CloseLibrary
    private var isClosed = false

    init(
        handle: UnsafeMutableRawPointer,
        lookupSymbol: @escaping LookupSymbol = TreeSitterRuntimeLibrary.defaultLookupSymbol,
        closeLibrary: @escaping CloseLibrary = TreeSitterRuntimeLibrary.defaultCloseLibrary
    ) {
        self.handle = handle
        self.lookupSymbolImpl = lookupSymbol
        self.closeLibrary = closeLibrary
    }

    deinit {
        close()
    }

    static func bundled(
        bundleResourceURL: URL?,
        resourceCandidates: [String] = defaultResourceCandidates,
        fileExists: @escaping FileExists = { FileManager.default.fileExists(atPath: $0.path) },
        openLibrary: @escaping OpenLibrary = TreeSitterRuntimeLibrary.defaultOpenLibrary,
        lookupSymbol: @escaping LookupSymbol = TreeSitterRuntimeLibrary.defaultLookupSymbol,
        closeLibrary: @escaping CloseLibrary = TreeSitterRuntimeLibrary.defaultCloseLibrary
    ) -> TreeSitterRuntimeLibrary? {
        guard let bundleResourceURL else { return nil }

        for resource in resourceCandidates {
            guard let url = bundledURL(resource: resource, bundleResourceURL: bundleResourceURL),
                  fileExists(url),
                  let handle = openLibrary(url) else {
                continue
            }
            return TreeSitterRuntimeLibrary(
                handle: handle,
                lookupSymbol: lookupSymbol,
                closeLibrary: closeLibrary
            )
        }
        return nil
    }

    func lookupSymbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard !isClosed else { return nil }
        return lookupSymbolImpl(handle, name)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        closeLibrary(handle)
    }

    private static func bundledURL(resource: String, bundleResourceURL: URL) -> URL? {
        let cleanResource = resource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanResource.isEmpty else { return nil }

        let baseURL = bundleResourceURL.standardizedFileURL
        let candidateURL = baseURL
            .appendingPathComponent(cleanResource, isDirectory: false)
            .standardizedFileURL
        let basePath = baseURL.path.hasSuffix("/") ? baseURL.path : baseURL.path + "/"
        guard candidateURL.path.hasPrefix(basePath) else {
            return nil
        }
        return candidateURL
    }

    static func defaultOpenLibrary(_ url: URL) -> UnsafeMutableRawPointer? {
        dlopen(url.path, RTLD_NOW | RTLD_LOCAL)
    }

    static func defaultLookupSymbol(
        handle: UnsafeMutableRawPointer,
        name: String
    ) -> UnsafeMutableRawPointer? {
        dlsym(handle, name)
    }

    static func defaultCloseLibrary(_ handle: UnsafeMutableRawPointer) {
        dlclose(handle)
    }
}

struct TreeSitterSymbolProvider {
    typealias LookupSymbol = (String) -> UnsafeMutableRawPointer?

    var lookupSymbol: LookupSymbol
    var retainedObjects: [AnyObject]

    init(
        lookupSymbol: @escaping LookupSymbol,
        retainedObjects: [AnyObject] = []
    ) {
        self.lookupSymbol = lookupSymbol
        self.retainedObjects = retainedObjects
    }

    static func bundledOrProcess(
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        resourceCandidates: [String] = TreeSitterRuntimeLibrary.defaultResourceCandidates,
        fileExists: @escaping TreeSitterRuntimeLibrary.FileExists = { FileManager.default.fileExists(atPath: $0.path) },
        openLibrary: @escaping TreeSitterRuntimeLibrary.OpenLibrary = TreeSitterRuntimeLibrary.defaultOpenLibrary,
        lookupLibrarySymbol: @escaping TreeSitterRuntimeLibrary.LookupSymbol = TreeSitterRuntimeLibrary.defaultLookupSymbol,
        closeLibrary: @escaping TreeSitterRuntimeLibrary.CloseLibrary = TreeSitterRuntimeLibrary.defaultCloseLibrary,
        lookupProcessSymbol: @escaping LookupSymbol = TreeSitterRuntimeAdapter.defaultLookupSymbol
    ) -> TreeSitterSymbolProvider {
        if let library = TreeSitterRuntimeLibrary.bundled(
            bundleResourceURL: bundleResourceURL,
            resourceCandidates: resourceCandidates,
            fileExists: fileExists,
            openLibrary: openLibrary,
            lookupSymbol: lookupLibrarySymbol,
            closeLibrary: closeLibrary
        ) {
            return TreeSitterSymbolProvider(
                lookupSymbol: { [library] name in library.lookupSymbol(name) },
                retainedObjects: [library]
            )
        }

        return TreeSitterSymbolProvider(lookupSymbol: lookupProcessSymbol)
    }
}
