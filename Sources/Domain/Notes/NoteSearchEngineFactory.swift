// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NoteSearchEngineFactory.swift - Selects the search backend by
// `NoteSearchEngineKind` and wires its dependencies.

import Foundation

/// Centralises the mapping from a `NoteSearchEngineKind` value to a
/// fully-wired `NoteSearching` instance.
///
/// Keeping the selection in one place means the rest of the code base
/// (the view model, the test suite, the wiring in `MainWindowController`)
/// never has to switch over the enum directly. Adding a new backend is
/// a matter of:
///
///   1. Adding the case to `NoteSearchEngineKind`.
///   2. Implementing the protocol in a new file.
///   3. Extending the `switch` here.
///
/// The compiler flags any missed branch automatically because the enum
/// is closed.
enum NoteSearchEngineFactory {

    /// Builds a fresh engine for the supplied `kind`. The store and
    /// storage root are injected because the engines are stateless —
    /// tests can recreate a backend per assertion without lifecycle
    /// bookkeeping.
    static func make(
        kind: NoteSearchEngineKind,
        store: NoteStore,
        storageRoot: URL
    ) -> any NoteSearching {
        switch kind {
        case .grep:
            return NoteSearchGrep(store: store)
        case .fts5:
            return NoteSearchFTS5(store: store)
        case .spotlight:
            return NoteSearchSpotlight(store: store, storageRoot: storageRoot)
        }
    }
}
