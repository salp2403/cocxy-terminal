// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubPanePanelWidthSwiftTestingTests.swift - Tests the MainWindowController
// static helpers that manage the pane's preferred width persistence.
// Mirrors the `feedback_preferred_vs_effective_width` pattern used by
// the Code Review panel so both docked panels behave identically.

import Testing
import Foundation
@testable import CocxyTerminal

@Suite("GitHubPanePanelWidth", .serialized)
@MainActor
struct GitHubPanePanelWidthSwiftTestingTests {

    // MARK: - Helpers

    /// Runs a block with an isolated UserDefaults key so the test can
    /// seed a specific persisted width without bleeding into the
    /// user's real preferences.
    private func withIsolatedWidthPreference(_ body: () -> Void) {
        let key = MainWindowController.gitHubPanePanelWidthDefaultsKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.removeObject(forKey: key)
        body()
    }

    // MARK: - Clamp contract

    @Test("clampStoredGitHubPanePanelWidth respects the absolute bounds")
    func clampStoredGitHubPanePanelWidth_respectsAbsoluteBounds() {
        #expect(
            MainWindowController.clampStoredGitHubPanePanelWidth(100)
                == GitHubPaneView.minimumPanelWidth
        )
        #expect(
            MainWindowController.clampStoredGitHubPanePanelWidth(9999)
                == GitHubPaneView.maximumPanelWidth
        )
        let middle = (GitHubPaneView.minimumPanelWidth + GitHubPaneView.maximumPanelWidth) / 2
        #expect(
            MainWindowController.clampStoredGitHubPanePanelWidth(middle) == middle
        )
    }

    // MARK: - Defaults load / store

    @Test("loadStoredGitHubPanePanelWidth returns default when nothing persisted")
    func loadStoredGitHubPanePanelWidth_returnsDefaultWhenAbsent() {
        withIsolatedWidthPreference {
            #expect(
                MainWindowController.loadStoredGitHubPanePanelWidth()
                    == GitHubPaneView.defaultPanelWidth
            )
        }
    }

    @Test("loadStoredGitHubPanePanelWidth clamps corrupted stored values")
    func loadStoredGitHubPanePanelWidth_clampsCorruptedValues() {
        withIsolatedWidthPreference {
            UserDefaults.standard.set(
                9999,
                forKey: MainWindowController.gitHubPanePanelWidthDefaultsKey
            )
            #expect(
                MainWindowController.loadStoredGitHubPanePanelWidth()
                    == GitHubPaneView.maximumPanelWidth
            )

            UserDefaults.standard.set(
                50,
                forKey: MainWindowController.gitHubPanePanelWidthDefaultsKey
            )
            #expect(
                MainWindowController.loadStoredGitHubPanePanelWidth()
                    == GitHubPaneView.minimumPanelWidth
            )
        }
    }

    @Test("storeGitHubPanePanelWidth persists the given value verbatim")
    func storeGitHubPanePanelWidth_persistsVerbatim() {
        withIsolatedWidthPreference {
            MainWindowController.storeGitHubPanePanelWidth(512)
            let raw = UserDefaults.standard.double(
                forKey: MainWindowController.gitHubPanePanelWidthDefaultsKey
            )
            #expect(raw == 512)
        }
    }
}
