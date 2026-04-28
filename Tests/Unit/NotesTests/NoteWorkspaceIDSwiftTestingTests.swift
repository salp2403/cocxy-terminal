// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Pin the `NoteWorkspaceID` contract: deterministic + stable +
/// filesystem-safe + privacy-preserving. The hash width and lowercase
/// hexadecimal output matter because the file layout depends on a
/// fixed-shape identifier — any drift here would orphan existing
/// notes when a user upgrades.
@Suite("NoteWorkspaceID")
struct NoteWorkspaceIDSwiftTestingTests {

    @Test("rawValue is exactly the documented ID length so file paths stay aligned across upgrades")
    func rawValueLengthIsPinned() {
        let id = NoteWorkspaceID(workspaceRoot: URL(fileURLWithPath: "/Users/sample/projects/foo"))

        #expect(id.rawValue.count == NoteWorkspaceID.idLength)
        #expect(NoteWorkspaceID.idLength == 12)
    }

    @Test("identical workspace roots produce identical IDs so the resolver always returns to the same folder")
    func sameRootProducesSameID() {
        let a = NoteWorkspaceID(workspaceRoot: URL(fileURLWithPath: "/Users/sample/projects/foo"))
        let b = NoteWorkspaceID(workspaceRoot: URL(fileURLWithPath: "/Users/sample/projects/foo"))

        #expect(a == b)
        #expect(a.rawValue == b.rawValue)
    }

    @Test("different roots produce different IDs so two repos never share a notes folder")
    func differentRootsProduceDifferentIDs() {
        let a = NoteWorkspaceID(workspaceRoot: URL(fileURLWithPath: "/Users/sample/projects/foo"))
        let b = NoteWorkspaceID(workspaceRoot: URL(fileURLWithPath: "/Users/sample/projects/bar"))

        #expect(a != b)
    }

    @Test("trailing slashes do not change the ID so a normalised root collapses onto the canonical one")
    func trailingSlashesAreNormalised() {
        let withSlash = NoteWorkspaceID(workspaceRoot: URL(fileURLWithPath: "/Users/sample/projects/foo/"))
        let withoutSlash = NoteWorkspaceID(workspaceRoot: URL(fileURLWithPath: "/Users/sample/projects/foo"))

        #expect(withSlash == withoutSlash)
    }

    @Test("rawValue is lowercase hexadecimal so the result is filesystem-safe on every platform")
    func rawValueIsLowercaseHex() {
        let id = NoteWorkspaceID(workspaceRoot: URL(fileURLWithPath: "/Users/sample/projects/foo"))

        let allowed = Set("0123456789abcdef")
        for character in id.rawValue {
            #expect(allowed.contains(character), "unexpected character in workspace ID: \(character)")
        }
    }

    @Test("computeID matches the value-type initializer so callers can hash without instantiating")
    func computeIDMatchesInitializer() {
        let url = URL(fileURLWithPath: "/Users/sample/projects/foo")

        let computed = NoteWorkspaceID.computeID(from: url)
        let viaInit = NoteWorkspaceID(workspaceRoot: url)

        #expect(computed == viaInit.rawValue)
    }

    @Test("rawValue init re-hydrates a value without re-hashing so persisted IDs round-trip cleanly")
    func rawValueInitRoundTrips() {
        let original = NoteWorkspaceID(workspaceRoot: URL(fileURLWithPath: "/Users/sample/projects/foo"))

        let rehydrated = NoteWorkspaceID(rawValue: original.rawValue)

        #expect(original == rehydrated)
    }

    @Test("Codable round-trip preserves the raw value so persistence formats stay stable")
    func codableRoundTripPreservesValue() throws {
        let original = NoteWorkspaceID(workspaceRoot: URL(fileURLWithPath: "/Users/sample/projects/foo"))

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NoteWorkspaceID.self, from: encoded)

        #expect(original == decoded)
    }
}
