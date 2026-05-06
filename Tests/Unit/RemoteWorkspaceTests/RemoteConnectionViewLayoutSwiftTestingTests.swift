// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteConnectionViewLayoutSwiftTestingTests.swift - Remote workspace panel layout contracts.

import Testing
import Foundation
@testable import CocxyTerminal

@Suite("Remote connection view layout")
struct RemoteConnectionViewLayoutSwiftTestingTests {
    @Test("sub-panel picker shows every destination inside the dock width")
    func subPanelPickerFitsAllDestinationsInsideDockWidth() {
        let columns = RemoteConnectionView.subPanelPickerColumnCount(for: RemoteConnectionView.panelWidth)
        let rows = Int(ceil(Double(RemoteConnectionViewModel.SubPanel.allCases.count) / Double(columns)))

        #expect(columns >= 4)
        #expect(rows <= 2)
    }

    @Test("sub-panel picker keeps a usable fallback on narrow widths")
    func subPanelPickerKeepsUsableFallbackOnNarrowWidths() {
        #expect(RemoteConnectionView.subPanelPickerColumnCount(for: 0) == 1)
        #expect(RemoteConnectionView.subPanelPickerColumnCount(for: 220) >= 2)
    }
}
