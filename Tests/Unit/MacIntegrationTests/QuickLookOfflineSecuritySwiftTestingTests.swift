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

    @Test("Cocxy notebooks are declared as Quick Look previewable documents")
    func cocxyNotebooksAreQuickLookPreviewableDocuments() throws {
        let root = repositoryRoot()
        let appInfo = try plist(at: root.appendingPathComponent("Resources/Info.plist"))
        let quickLookInfo = try plist(at: root.appendingPathComponent("QuickLook/Info.plist"))
        let project = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        let verifyScript = try String(
            contentsOf: root.appendingPathComponent("scripts/verify-app-bundle.sh"),
            encoding: .utf8
        )

        let exportedTypes = try #require(appInfo["UTExportedTypeDeclarations"] as? [[String: Any]])
        let notebookType = try #require(exportedTypes.first {
            $0["UTTypeIdentifier"] as? String == "dev.cocxy.notebook"
        })
        #expect(notebookType["UTTypeConformsTo"] as? [String] == ["net.daringfireball.markdown"])
        #expect(notebookType["UTTypeTagSpecification"] as? [String: [String]] == [
            "public.filename-extension": ["cocxynb"],
            "public.mime-type": ["text/x-cocxy-notebook"],
        ])

        let documentTypes = try #require(appInfo["CFBundleDocumentTypes"] as? [[String: Any]])
        #expect(documentTypes.contains {
            ($0["LSItemContentTypes"] as? [String])?.contains("dev.cocxy.notebook") == true
        })

        let extensionAttributes = try #require(
            ((quickLookInfo["NSExtension"] as? [String: Any])?["NSExtensionAttributes"] as? [String: Any])
        )
        let supportedContentTypes = try #require(extensionAttributes["QLSupportedContentTypes"] as? [String])
        #expect(supportedContentTypes.contains("dev.cocxy.notebook"))
        #expect(project.contains("- dev.cocxy.notebook"))
        #expect(verifyScript.contains("QuickLook Cocxy notebook content type"))
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

    private func plist(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )
    }
}
