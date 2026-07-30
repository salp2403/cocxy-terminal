// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Dashboard file impact disclosure")
struct DashboardFileImpactDisclosureSwiftTestingTests {
    @Test("collapsed impacts show four and expansion exposes every retained impact")
    func disclosureShowsEveryImpact() {
        let impacts = (0..<8).map { index in
            FileImpact(path: "/tmp/file-\(index).swift", lastChangedAt: Date())
        }

        #expect(DashboardSessionRow.visibleFileImpacts(impacts, expanded: false).count == 4)
        #expect(DashboardSessionRow.visibleFileImpacts(impacts, expanded: true).count == 8)
    }
}
