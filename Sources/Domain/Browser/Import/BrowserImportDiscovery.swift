// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserImportDiscovery.swift - Dynamic browser and source-profile discovery.

import Foundation

extension BrowserImportSource {
    func discoveredLocations(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [BrowserImportLocation] {
        if isChromiumBased {
            return BrowserImportDiscovery.chromiumLocations(
                source: self,
                homeDirectory: homeDirectory,
                fileManager: fileManager
            )
        }
        switch self {
        case .firefox, .firefoxDeveloperEdition, .firefoxNightly,
             .librewolf, .waterfox, .floorp, .zen:
            return BrowserImportDiscovery.firefoxLocations(
                source: self,
                homeDirectory: homeDirectory,
                fileManager: fileManager
            )
        case .safari:
            return BrowserImportDiscovery.safariLocations(
                source: self,
                homeDirectory: homeDirectory,
                fileManager: fileManager
            )
        case .orion:
            return BrowserImportDiscovery.orionLocations(
                source: self,
                homeDirectory: homeDirectory,
                fileManager: fileManager
            )
        case .chrome, .chromeCanary, .chromium,
             .edge, .edgeBeta, .edgeDev,
             .brave, .braveBeta, .braveNightly,
             .opera, .operaGX,
             .vivaldi, .vivaldiSnapshot,
             .arc, .arcBeta:
            return []
        }
    }
}

enum BrowserImportDiscovery {
    private enum FirefoxInstallChannel {
        case stable
        case developerEdition
        case nightly
        case unknown
    }

    private struct ChromiumProfileMetadata {
        let displayName: String
        let lastUsed: Bool
    }

    private struct INIProfile {
        var name: String?
        var path: String?
        var isRelative = true
        var isDefault = false
    }

    static func chromiumLocations(
        source: BrowserImportSource,
        homeDirectory: URL,
        fileManager: FileManager
    ) -> [BrowserImportLocation] {
        let root = chromiumRoot(source: source, homeDirectory: homeDirectory)
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        if source == .opera || source == .operaGX {
            guard containsImportableFile(in: root, fileManager: fileManager) else { return [] }
            return [chromiumLocation(source: source, profileDirectory: root, displayName: "Default", fileManager: fileManager)]
        }

        let metadata = chromiumProfileMetadata(root: root)
        var directoryNames = Set(metadata.keys)
        if let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for child in children {
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                      containsImportableFile(in: child, fileManager: fileManager) else { continue }
                directoryNames.insert(child.lastPathComponent)
            }
        }

        return directoryNames.compactMap { identifier -> BrowserImportLocation? in
            let directory = root.appendingPathComponent(identifier, isDirectory: true)
            guard containsImportableFile(in: directory, fileManager: fileManager) else { return nil }
            let displayName = metadata[identifier]?.displayName ?? identifier
            return chromiumLocation(
                source: source,
                profileDirectory: directory,
                displayName: displayName,
                fileManager: fileManager
            )
        }.sorted { lhs, rhs in
            let lhsLastUsed = metadata[lhs.profileIdentifier]?.lastUsed == true
            let rhsLastUsed = metadata[rhs.profileIdentifier]?.lastUsed == true
            if lhsLastUsed != rhsLastUsed { return lhsLastUsed }
            if lhs.profileIdentifier == "Default" { return true }
            if rhs.profileIdentifier == "Default" { return false }
            return lhs.profileName.localizedCaseInsensitiveCompare(rhs.profileName) == .orderedAscending
        }
    }

    static func firefoxLocations(
        source: BrowserImportSource,
        homeDirectory: URL,
        fileManager: FileManager
    ) -> [BrowserImportLocation] {
        for base in firefoxBaseCandidates(source: source, homeDirectory: homeDirectory)
            where fileManager.fileExists(atPath: base.path) {
            let profilesFromINI = parseFirefoxProfiles(base: base)
            var resolved: [(location: BrowserImportLocation, isDefault: Bool)] = []
            var seenPaths = Set<String>()

            for profile in profilesFromINI {
                guard let rawPath = profile.path, !rawPath.isEmpty else { continue }
                let directory = profile.isRelative
                    ? base.appendingPathComponent(rawPath, isDirectory: true)
                    : URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath, isDirectory: true)
                let canonical = directory.resolvingSymlinksInPath().standardizedFileURL
                guard containsFirefoxImportableFile(in: canonical, fileManager: fileManager),
                      firefoxProfile(canonical, matches: source),
                      seenPaths.insert(canonical.path).inserted else { continue }
                resolved.append((
                    firefoxLocation(
                        source: source,
                        profileDirectory: canonical,
                        displayName: profile.name ?? canonical.lastPathComponent
                    ),
                    profile.isDefault
                ))
            }

            let profilesDirectory = base.appendingPathComponent("Profiles", isDirectory: true)
            if let children = try? fileManager.contentsOfDirectory(
                at: profilesDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for child in children {
                    let canonical = child.resolvingSymlinksInPath().standardizedFileURL
                    guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                          containsFirefoxImportableFile(in: canonical, fileManager: fileManager),
                          firefoxProfile(canonical, matches: source),
                          seenPaths.insert(canonical.path).inserted else { continue }
                    resolved.append((
                        firefoxLocation(
                            source: source,
                            profileDirectory: canonical,
                            displayName: canonical.lastPathComponent
                        ),
                        false
                    ))
                }
            }

            if !resolved.isEmpty {
                return resolved.sorted { lhs, rhs in
                    if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
                    return lhs.location.profileName.localizedCaseInsensitiveCompare(
                        rhs.location.profileName
                    ) == .orderedAscending
                }.map(\.location)
            }
        }
        return []
    }

    static func safariLocations(
        source: BrowserImportSource,
        homeDirectory: URL,
        fileManager: FileManager
    ) -> [BrowserImportLocation] {
        let history = homeDirectory.appendingPathComponent("Library/Safari/History.db")
        let bookmarks = homeDirectory.appendingPathComponent("Library/Safari/Bookmarks.plist")
        let cookieCandidates = [
            homeDirectory.appendingPathComponent(
                "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
            ),
            homeDirectory.appendingPathComponent("Library/Cookies/Cookies.binarycookies"),
        ]
        let cookies = firstExisting(cookieCandidates, fileManager: fileManager) ?? cookieCandidates[0]
        guard [history, bookmarks, cookies].contains(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return []
        }
        return [BrowserImportLocation(
            source: source,
            profileName: "Safari",
            profileIdentifier: "default",
            historyPath: history,
            cookiesPath: cookies,
            bookmarksPath: bookmarks
        )]
    }

    static func orionLocations(
        source: BrowserImportSource,
        homeDirectory: URL,
        fileManager: FileManager
    ) -> [BrowserImportLocation] {
        let root = homeDirectory.appendingPathComponent("Library/Application Support/Orion", isDirectory: true)
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        var candidates = [root, root.appendingPathComponent("Default", isDirectory: true)]
        let profilesRoot = root.appendingPathComponent("Profiles", isDirectory: true)
        if let children = try? fileManager.contentsOfDirectory(
            at: profilesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            candidates.append(contentsOf: children.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            })
        }

        var seen = Set<String>()
        return candidates.compactMap { directory -> BrowserImportLocation? in
            let canonical = directory.resolvingSymlinksInPath().standardizedFileURL
            guard seen.insert(canonical.path).inserted else { return nil }
            let historyCandidates = [
                canonical.appendingPathComponent("History.db"),
                canonical.appendingPathComponent("History"),
            ]
            let cookieCandidates = [
                canonical.appendingPathComponent("Cookies.binarycookies"),
                canonical.appendingPathComponent("Network/Cookies"),
                canonical.appendingPathComponent("Cookies"),
            ]
            let bookmarkCandidates = [
                canonical.appendingPathComponent("Bookmarks.plist"),
                canonical.appendingPathComponent("Bookmarks"),
            ]
            guard (historyCandidates + cookieCandidates + bookmarkCandidates).contains(where: {
                fileManager.fileExists(atPath: $0.path)
            }) else { return nil }
            return BrowserImportLocation(
                source: source,
                profileName: canonical == root ? "Default" : canonical.lastPathComponent,
                profileIdentifier: canonical == root ? "default" : canonical.lastPathComponent,
                historyPath: firstExisting(historyCandidates, fileManager: fileManager) ?? historyCandidates[0],
                cookiesPath: firstExisting(cookieCandidates, fileManager: fileManager) ?? cookieCandidates[0],
                bookmarksPath: firstExisting(bookmarkCandidates, fileManager: fileManager) ?? bookmarkCandidates[0]
            )
        }.sorted {
            if $0.profileIdentifier == "default" { return true }
            if $1.profileIdentifier == "default" { return false }
            return $0.profileName.localizedCaseInsensitiveCompare($1.profileName) == .orderedAscending
        }
    }

    private static func chromiumRoot(source: BrowserImportSource, homeDirectory: URL) -> URL {
        let support = homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
        let component: String
        switch source {
        case .chrome: component = "Google/Chrome"
        case .chromeCanary: component = "Google/Chrome Canary"
        case .chromium: component = "Chromium"
        case .edge: component = "Microsoft Edge"
        case .edgeBeta: component = "Microsoft Edge Beta"
        case .edgeDev: component = "Microsoft Edge Dev"
        case .brave: component = "BraveSoftware/Brave-Browser"
        case .braveBeta: component = "BraveSoftware/Brave-Browser-Beta"
        case .braveNightly: component = "BraveSoftware/Brave-Browser-Nightly"
        case .opera: component = "com.operasoftware.Opera"
        case .operaGX: component = "com.operasoftware.OperaGX"
        case .vivaldi: component = "Vivaldi"
        case .vivaldiSnapshot: component = "Vivaldi Snapshot"
        case .arc: component = "Arc/User Data"
        case .arcBeta: component = "Arc Beta/User Data"
        case .firefox, .firefoxDeveloperEdition, .firefoxNightly,
             .librewolf, .waterfox, .floorp, .zen, .safari, .orion:
            component = ""
        }
        return support.appendingPathComponent(component, isDirectory: true)
    }

    private static func firefoxBaseCandidates(
        source: BrowserImportSource,
        homeDirectory: URL
    ) -> [URL] {
        let support = homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
        let components: [String]
        switch source {
        case .firefox, .firefoxDeveloperEdition, .firefoxNightly:
            components = ["Firefox"]
        case .librewolf:
            components = ["LibreWolf"]
        case .waterfox:
            components = ["Waterfox"]
        case .floorp:
            components = ["Floorp"]
        case .zen:
            components = ["zen", "Zen"]
        default:
            components = []
        }
        return components.map { support.appendingPathComponent($0, isDirectory: true) }
    }

    private static func chromiumProfileMetadata(root: URL) -> [String: ChromiumProfileMetadata] {
        let localState = root.appendingPathComponent("Local State")
        guard let data = try? BrowserImportFileReader.readData(from: localState, maximumByteCount: 16 * 1_024 * 1_024),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any] else { return [:] }
        let lastUsed = profile["last_used"] as? String
        let infoCache = profile["info_cache"] as? [String: Any] ?? [:]
        return infoCache.reduce(into: [:]) { result, item in
            guard !item.key.contains("/") && item.key != "." && item.key != ".." else { return }
            let fields = item.value as? [String: Any]
            let name = (fields?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            result[item.key] = ChromiumProfileMetadata(
                displayName: name.flatMap { $0.isEmpty ? nil : $0 } ?? item.key,
                lastUsed: item.key == lastUsed
            )
        }
    }

    private static func parseFirefoxProfiles(base: URL) -> [INIProfile] {
        let url = base.appendingPathComponent("profiles.ini")
        guard let data = try? BrowserImportFileReader.readData(from: url, maximumByteCount: 2 * 1_024 * 1_024),
              let text = String(data: data, encoding: .utf8) else { return [] }

        var profiles: [INIProfile] = []
        var current: INIProfile?
        var currentIsProfile = false
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix(";") && !line.hasPrefix("#") else { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                if currentIsProfile, let current { profiles.append(current) }
                let section = String(line.dropFirst().dropLast())
                currentIsProfile = section.lowercased().hasPrefix("profile")
                current = currentIsProfile ? INIProfile() : nil
                continue
            }
            guard currentIsProfile,
                  let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            switch key {
            case "name": current?.name = value
            case "path": current?.path = value
            case "isrelative": current?.isRelative = value != "0"
            case "default": current?.isDefault = value == "1"
            default: break
            }
        }
        if currentIsProfile, let current { profiles.append(current) }
        return profiles
    }

    private static func firefoxProfile(
        _ profileDirectory: URL,
        matches source: BrowserImportSource
    ) -> Bool {
        switch source {
        case .firefox:
            let channel = firefoxInstallChannel(profileDirectory: profileDirectory)
            return channel == .stable || channel == .unknown
        case .firefoxDeveloperEdition:
            return firefoxInstallChannel(profileDirectory: profileDirectory) == .developerEdition
        case .firefoxNightly:
            return firefoxInstallChannel(profileDirectory: profileDirectory) == .nightly
        default:
            return true
        }
    }

    private static func firefoxInstallChannel(profileDirectory: URL) -> FirefoxInstallChannel {
        let compatibility = profileDirectory.appendingPathComponent("compatibility.ini")
        guard let data = try? BrowserImportFileReader.readData(
            from: compatibility,
            maximumByteCount: 256 * 1_024
        ), let text = String(data: data, encoding: .utf8) else {
            return .unknown
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard key == "lastappdir" || key == "lastplatformdir" else { continue }
            let path = String(line[line.index(after: separator)...])
            let components = URL(fileURLWithPath: path).pathComponents.map { $0.lowercased() }
            if components.contains("firefox developer edition.app") {
                return .developerEdition
            }
            if components.contains("firefox nightly.app") {
                return .nightly
            }
            if components.contains("firefox.app") {
                return .stable
            }
        }
        return .unknown
    }

    private static func chromiumLocation(
        source: BrowserImportSource,
        profileDirectory: URL,
        displayName: String,
        fileManager: FileManager
    ) -> BrowserImportLocation {
        let cookieCandidates = [
            profileDirectory.appendingPathComponent("Network/Cookies"),
            profileDirectory.appendingPathComponent("Cookies"),
        ]
        return BrowserImportLocation(
            source: source,
            profileName: displayName,
            profileIdentifier: profileDirectory.lastPathComponent,
            historyPath: profileDirectory.appendingPathComponent("History"),
            cookiesPath: firstExisting(cookieCandidates, fileManager: fileManager) ?? cookieCandidates[0],
            bookmarksPath: profileDirectory.appendingPathComponent("Bookmarks")
        )
    }

    private static func firefoxLocation(
        source: BrowserImportSource,
        profileDirectory: URL,
        displayName: String
    ) -> BrowserImportLocation {
        let places = profileDirectory.appendingPathComponent("places.sqlite")
        return BrowserImportLocation(
            source: source,
            profileName: displayName,
            profileIdentifier: profileDirectory.lastPathComponent,
            historyPath: places,
            cookiesPath: profileDirectory.appendingPathComponent("cookies.sqlite"),
            bookmarksPath: places
        )
    }

    private static func containsImportableFile(in directory: URL, fileManager: FileManager) -> Bool {
        [
            directory.appendingPathComponent("History"),
            directory.appendingPathComponent("Network/Cookies"),
            directory.appendingPathComponent("Cookies"),
            directory.appendingPathComponent("Bookmarks"),
        ].contains { fileManager.fileExists(atPath: $0.path) }
    }

    private static func containsFirefoxImportableFile(in directory: URL, fileManager: FileManager) -> Bool {
        ["places.sqlite", "cookies.sqlite"].contains {
            fileManager.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    private static func firstExisting(_ urls: [URL], fileManager: FileManager) -> URL? {
        urls.first { fileManager.fileExists(atPath: $0.path) }
    }
}
