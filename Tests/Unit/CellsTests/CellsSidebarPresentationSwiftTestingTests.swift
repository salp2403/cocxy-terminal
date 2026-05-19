// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CellsSidebarPresentationSwiftTestingTests.swift - Cells UI presentation contracts.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Cells sidebar presentation")
struct CellsSidebarPresentationSwiftTestingTests {
    @Test("sidebar presentation sorts cells and never exposes redacted metadata")
    func sidebarPresentationSortsCellsAndRedactsMetadata() {
        let dockerID = UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!
        let flyID = UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!
        let cells = [
            Cell(
                id: flyID,
                name: "Fly Lab",
                provider: .fly,
                status: .running,
                metadata: [
                    "app": "cocxy-lab",
                    "region": "iad",
                    "token": "secret-token",
                ]
            ),
            Cell(
                id: dockerID,
                name: "Local Swift",
                provider: .docker,
                status: .stopped,
                metadata: [
                    "image": "swift:6.0",
                    "containerID": "container-123",
                ]
            ),
        ]

        let presentation = CellsSidebarPresentation(cells: cells)

        #expect(presentation.runningCount == 1)
        #expect(presentation.rows.map(\.id) == [flyID.uuidString, dockerID.uuidString])
        #expect(presentation.rows[0].metadataSummary == "app: cocxy-lab  region: iad")
        #expect(!presentation.rows[0].metadataSummary.contains("secret-token"))
        #expect(!presentation.rows[0].metadataSummary.contains("token"))
        #expect(presentation.rows[1].metadataSummary == "containerID: container-123  image: swift:6.0")
    }

    @Test("cell rows expose concise VoiceOver labels")
    func cellRowsExposeConciseAccessibilityLabels() {
        let cellID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let presentation = CellsSidebarPresentation(cells: [
            Cell(
                id: cellID,
                name: "Remote Lab",
                provider: .ssh,
                status: .running,
                metadata: ["host": "example.test", "user": "deploy"]
            ),
        ])

        let row = presentation.rows[0]

        #expect(row.title == "Remote Lab")
        #expect(row.subtitle == "ssh, running")
        #expect(row.accessibilityLabel == "Remote Lab, ssh cell, running, host: example.test  user: deploy")
    }
}
