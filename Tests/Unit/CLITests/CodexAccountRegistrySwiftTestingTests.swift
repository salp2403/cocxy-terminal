// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodexAccountRegistrySwiftTestingTests.swift - Codex account discovery coverage.

import Foundation
import Testing
import CocxyShared

@Suite("Codex account registry")
struct CodexAccountRegistrySwiftTestingTests {

    @Test("scanner extracts accounts from nested auth JSON")
    func extractsNestedAccounts() throws {
        let json = """
        {
          "profiles": [
            { "id": "acct_1", "email": "one@example.com", "name": "One" },
            { "nested": { "account_id": "acct_2", "account_email": "two@example.com" } }
          ]
        }
        """
        let accounts = CodexAccountScanner.accounts(inAuthJSONData: Data(json.utf8), sourcePath: "/tmp/auth.json")
        #expect(accounts.count == 2)
        #expect(accounts[0].id == "acct_1")
        #expect(accounts[0].displayName == "One")
        #expect(accounts[1].id == "acct_2")
        #expect(accounts[1].sourcePath == "/tmp/auth.json")
    }

    @Test("scanner returns empty for missing or malformed auth JSON")
    func malformedJSONReturnsEmpty() {
        #expect(CodexAccountScanner.accounts(inAuthJSONData: Data("not json".utf8)).isEmpty)
    }

    @Test("scanner deduplicates repeated account records")
    func deduplicatesAccounts() {
        let json = """
        {
          "a": { "id": "acct_1", "email": "same@example.com" },
          "b": { "id": "acct_1", "email": "same@example.com" }
        }
        """
        let accounts = CodexAccountScanner.accounts(inAuthJSONData: Data(json.utf8))
        #expect(accounts.count == 1)
    }

    @Test("scanner extracts the signed-in account from Codex id_token payloads without reading token values")
    func extractsAccountFromIDTokenPayload() throws {
        let idToken = try makeUnsignedJWT(payload: [
            "email": "signed-in@example.com",
            "name": "Signed In",
            "sub": "jwt_subject",
        ])
        let json = """
        {
          "tokens": {
            "account_id": "acct_real",
            "id_token": "\(idToken)"
          }
        }
        """

        let accounts = CodexAccountScanner.accounts(inAuthJSONData: Data(json.utf8), sourcePath: "/tmp/auth.json")

        #expect(accounts.count == 1)
        #expect(accounts[0].id == "acct_real")
        #expect(accounts[0].email == "signed-in@example.com")
        #expect(accounts[0].displayName == "Signed In")
        #expect(accounts[0].sourcePath == "/tmp/auth.json")
    }

    @Test("selection store round-trips atomically")
    func selectionStoreRoundTrips() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("selection.json")

        try CodexAccountSelectionStore.save(
            CodexAccountSelection(selectedAccountID: "acct_1"),
            to: url
        )

        #expect(CodexAccountSelectionStore.load(from: url).selectedAccountID == "acct_1")
    }

    @Test("default selection URL uses Cocxy app-support storage")
    func defaultSelectionURLUsesAppSupportStorage() {
        let root = URL(fileURLWithPath: "/tmp/app-support", isDirectory: true)

        let url = CodexAccountSelectionStore.defaultSelectionURL(applicationSupportDirectory: root)

        #expect(url.path == "/tmp/app-support/CocxyTerminal/codex-account-selection.json")
    }

    private func makeUnsignedJWT(payload: [String: String]) throws -> String {
        let header = try base64URL(JSONSerialization.data(withJSONObject: ["alg": "none"]))
        let body = try base64URL(JSONSerialization.data(withJSONObject: payload))
        return "\(header).\(body)."
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
