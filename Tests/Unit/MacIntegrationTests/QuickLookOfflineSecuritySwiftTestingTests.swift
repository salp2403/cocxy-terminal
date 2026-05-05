// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// QuickLookOfflineSecuritySwiftTestingTests.swift - Offline Quick Look security gates.

import Foundation
import Testing

@Suite("Quick Look offline security")
struct QuickLookOfflineSecuritySwiftTestingTests {
    @Test("Quick Look extension remains sandboxed without network entitlement")
    func quickLookExtensionOmitsNetworkEntitlement() throws {
        let root = repositoryRoot()
        let entitlementsURL = root.appendingPathComponent("QuickLook/CocxyQuickLook.entitlements")
        let data = try Data(contentsOf: entitlementsURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )

        #expect(plist["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(plist["com.apple.security.network.client"] == nil)
    }

    @Test("bundle verification enforces offline Quick Look entitlements")
    func bundleVerificationEnforcesOfflineQuickLookEntitlements() throws {
        let root = repositoryRoot()
        let verifyScript = try String(
            contentsOf: root.appendingPathComponent("scripts/verify-app-bundle.sh"),
            encoding: .utf8
        )
        let buildQuickLookScript = try String(
            contentsOf: root.appendingPathComponent("scripts/build-quicklook-extension.sh"),
            encoding: .utf8
        )

        #expect(verifyScript.contains("check_codesign_entitlement_absent"))
        #expect(verifyScript.contains("QuickLook offline network entitlement"))
        #expect(!verifyScript.contains("\"com.apple.security.network.client\" \"QuickLook network entitlement\""))
        #expect(buildQuickLookScript.contains("QuickLook network client entitlement must stay absent"))
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let package = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: package.path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
