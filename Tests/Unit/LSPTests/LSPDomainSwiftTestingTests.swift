// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPDomainSwiftTestingTests.swift - Native LSP domain foundation tests.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("LSP JSON-RPC framing")
struct LSPFramingSwiftTestingTests {
    @Test("encodes and decodes a request frame")
    func encodesAndDecodesRequestFrame() throws {
        let message = LSPMessage.request(
            id: .int(1),
            method: "initialize",
            params: .object([
                "processId": .number(42),
                "rootUri": .string("file:///tmp/cocxy"),
            ])
        )

        let frame = try LSPFraming.encode(message)
        let frameText = String(decoding: frame, as: UTF8.self)

        #expect(frameText.hasPrefix("Content-Length: "))
        #expect(frameText.contains("\r\n\r\n"))
        #expect(try LSPFraming.decodeMessages(from: frame) == [message])
    }

    @Test("content length is counted in utf8 bytes")
    func contentLengthCountsUTF8Bytes() throws {
        let message = LSPMessage.notification(
            method: "window/logMessage",
            params: .object(["message": .string("á😀")])
        )

        let frame = try LSPFraming.encode(message)
        let header = String(decoding: frame.prefix { $0 != 13 }, as: UTF8.self)
        let declaredLength = try #require(Int(header.replacingOccurrences(of: "Content-Length: ", with: "")))
        let separator = Data("\r\n\r\n".utf8)
        let separatorRange = try #require(frame.range(of: separator))
        let bodyLength = frame.count - separatorRange.upperBound

        #expect(declaredLength == bodyLength)
        #expect(try LSPFraming.decodeMessages(from: frame) == [message])
    }

    @Test("decodes multiple adjacent frames")
    func decodesMultipleAdjacentFrames() throws {
        let first = LSPMessage.notification(method: "initialized", params: .object([:]))
        let second = LSPMessage.response(id: .int(2), result: .object(["ok": .bool(true)]), error: nil)
        let combined = try LSPFraming.encode(first) + LSPFraming.encode(second)

        #expect(try LSPFraming.decodeMessages(from: combined) == [first, second])
    }
}

@Suite("LSP language registry")
struct LSPLanguageRegistrySwiftTestingTests {
    @Test("default registry covers the phase B target languages")
    func defaultsCoverTargetLanguages() throws {
        let registry = LSPLanguageRegistry.defaults
        let targetIDs = Set([
            "swift", "rust", "typescript", "python", "go", "kotlin",
            "java", "c", "cpp", "javascript", "ruby", "php", "bash",
        ])

        #expect(Set(registry.languageIDs).isSuperset(of: targetIDs))
        #expect(registry.server(forFileURL: URL(fileURLWithPath: "/tmp/main.swift"))?.languageID == "swift")
        #expect(registry.server(forFileURL: URL(fileURLWithPath: "/tmp/main.cpp"))?.languageID == "cpp")
        #expect(registry.server(forFileURL: URL(fileURLWithPath: "/tmp/app.js"))?.languageID == "javascript")
    }

    @Test("install suggestions never enable automatic installation")
    func suggestionsNeverAutoInstall() throws {
        let registry = LSPLanguageRegistry.defaults
        let rust = try #require(registry.server(forLanguageID: "rust"))
        let swift = try #require(registry.server(forLanguageID: "swift"))

        #expect(rust.allowsAutomaticInstall == false)
        #expect(rust.installSuggestion.command == "brew install rust-analyzer")
        #expect(swift.allowsAutomaticInstall == false)
        #expect(swift.installSuggestion.command == nil)
        #expect(swift.installSuggestion.message.contains("Xcode"))
    }

    @Test("PHP registry avoids candidates with mismatched default arguments")
    func phpRegistryAvoidsMismatchedArguments() throws {
        let php = try #require(LSPLanguageRegistry.defaults.server(forLanguageID: "php"))

        #expect(php.executableNames == ["intelephense"])
        #expect(php.arguments == ["--stdio"])
        #expect(php.installSuggestion.command == nil)
    }
}

@Suite("LSP server discovery")
struct LSPServerDiscoverySwiftTestingTests {
    @Test("configured path has priority over PATH lookup")
    func configuredPathHasPriority() throws {
        let registry = LSPLanguageRegistry.defaults
        let rust = try #require(registry.server(forLanguageID: "rust"))
        let discovery = LSPServerDiscovery(
            executableResolver: { executable in
                executable == "rust-analyzer" ? "/opt/homebrew/bin/rust-analyzer" : nil
            },
            homebrewDetector: { true }
        )

        let result = discovery.resolve(
            rust,
            configuredExecutablePath: "/Users/dev/bin/custom-rust-analyzer"
        )

        #expect(result == .available(path: "/Users/dev/bin/custom-rust-analyzer", source: .configuredPath))
    }

    @Test("PATH lookup is used when no explicit path exists")
    func pathLookupWhenNoExplicitPathExists() throws {
        let registry = LSPLanguageRegistry.defaults
        let go = try #require(registry.server(forLanguageID: "go"))
        let discovery = LSPServerDiscovery(
            executableResolver: { executable in
                executable == "gopls" ? "/opt/homebrew/bin/gopls" : nil
            },
            homebrewDetector: { true }
        )

        #expect(discovery.resolve(go) == .available(path: "/opt/homebrew/bin/gopls", source: .pathLookup))
    }

    @Test("missing server returns guidance without auto-installing")
    func missingServerReturnsGuidance() throws {
        let registry = LSPLanguageRegistry.defaults
        let python = try #require(registry.server(forLanguageID: "python"))
        let discovery = LSPServerDiscovery(
            executableResolver: { _ in nil },
            homebrewDetector: { true }
        )

        let result = discovery.resolve(python)

        guard case let .missing(suggestion) = result else {
            Issue.record("Expected missing server result")
            return
        }

        #expect(suggestion.command == "brew install pyright")
        #expect(suggestion.allowsAutomaticInstall == false)
        #expect(suggestion.message.contains("pyright"))
    }
}

@Suite("LSP manager privacy gates")
struct LSPManagerSwiftTestingTests {
    @Test("manager is disabled by default for every language")
    func managerDisabledByDefault() {
        let configuration = LSPManager.Configuration.defaults
        let manager = LSPManager(
            registry: .defaults,
            configuration: configuration,
            discovery: LSPServerDiscovery(executableResolver: { _ in nil }, homebrewDetector: { false })
        )

        #expect(configuration.enabledLanguageIDs.isEmpty)
        #expect(manager.planClient(forFileURL: URL(fileURLWithPath: "/tmp/main.swift")).status == .disabled)
    }

    @Test("language opt-in allows discovery to run")
    func languageOptInAllowsDiscovery() {
        let manager = LSPManager(
            registry: .defaults,
            configuration: .init(enabledLanguageIDs: ["go"]),
            discovery: LSPServerDiscovery(
                executableResolver: { executable in executable == "gopls" ? "/opt/homebrew/bin/gopls" : nil },
                homebrewDetector: { true }
            )
        )

        let plan = manager.planClient(forFileURL: URL(fileURLWithPath: "/tmp/main.go"))

        #expect(plan.languageID == "go")
        #expect(plan.status == .ready(path: "/opt/homebrew/bin/gopls"))
    }
}

@Suite("LSP process privacy")
struct LSPProcessPrivacySwiftTestingTests {
    @Test("sanitized environment removes secret-like keys")
    func sanitizedEnvironmentRemovesSecrets() {
        let sanitized = LSPProcessEnvironment.sanitized(from: [
            "PATH": "/opt/homebrew/bin:/usr/bin",
            "HOME": "/Users/dev",
            "TMPDIR": "/tmp",
            "JAVA_HOME": "/Library/Java/JavaVirtualMachines/current",
            "GOPATH": "/Users/dev/go",
            "AWS_SECRET_ACCESS_KEY": "secret",
            "GITHUB_TOKEN": "secret",
            "PROJECT_API_PASSWORD": "secret",
        ])

        #expect(sanitized["PATH"] == "/opt/homebrew/bin:/usr/bin")
        #expect(sanitized["HOME"] == "/Users/dev")
        #expect(sanitized["TMPDIR"] == "/tmp")
        #expect(sanitized["JAVA_HOME"] == "/Library/Java/JavaVirtualMachines/current")
        #expect(sanitized["GOPATH"] == "/Users/dev/go")
        #expect(sanitized["AWS_SECRET_ACCESS_KEY"] == nil)
        #expect(sanitized["GITHUB_TOKEN"] == nil)
        #expect(sanitized["PROJECT_API_PASSWORD"] == nil)
    }
}
