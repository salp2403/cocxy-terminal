// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Pin the `NoteSearchEngineFactory` dispatch contract: every kind in
/// the closed enum produces a backend whose `kind` matches the request.
/// The compiler guarantees exhaustive coverage of the enum in the
/// factory's switch, but the explicit test surfaces that contract in
/// the suite output for reviewers.
@Suite("NoteSearchEngineFactory")
struct NoteSearchEngineFactorySwiftTestingTests {

    private func makeStore() -> (NoteStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "cocxy-search-factory-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        return (NoteStore(storageRoot: root, format: .markdown), root)
    }

    @Test("factory produces NoteSearchGrep for the .grep kind so the user-facing config picks the documented backend")
    func makeGrep() {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = NoteSearchEngineFactory.make(
            kind: .grep,
            store: store,
            storageRoot: root
        )

        #expect(engine.kind == .grep)
        #expect(engine is NoteSearchGrep)
    }

    @Test("factory produces NoteSearchFTS5 for the .fts5 kind so power users get the SQL-backed search")
    func makeFTS5() {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = NoteSearchEngineFactory.make(
            kind: .fts5,
            store: store,
            storageRoot: root
        )

        #expect(engine.kind == .fts5)
        #expect(engine is NoteSearchFTS5)
    }

    @Test("factory produces NoteSearchSpotlight for the .spotlight kind so users that opt into the system index get it")
    func makeSpotlight() {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = NoteSearchEngineFactory.make(
            kind: .spotlight,
            store: store,
            storageRoot: root
        )

        #expect(engine.kind == .spotlight)
        #expect(engine is NoteSearchSpotlight)
    }
}
