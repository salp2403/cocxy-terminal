// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Mobile mirror surface routing")
struct MobileMirrorSurfaceRoutingSwiftTestingTests {
    @Test("primary and secondary surfaces retain independent exact routes")
    func splitSurfacesRetainIndependentRoutes() throws {
        let registry = MobileMirrorRouteRegistry()
        let sessionID = UUID().uuidString
        let primary = SurfaceID()
        let secondary = SurfaceID()
        let primaryRoute = MobileMirrorTerminalRoute(
            sessionID: sessionID,
            surfaceID: primary,
            port: 41_001,
            bearerToken: "primary-token"
        )
        let secondaryRoute = MobileMirrorTerminalRoute(
            sessionID: sessionID,
            surfaceID: secondary,
            port: 41_002,
            bearerToken: "secondary-token"
        )

        registry.replace(
            routes: [primaryRoute, secondaryRoute],
            preferredSurfaceID: secondary.rawValue.uuidString
        )

        #expect(registry.route(
            sessionID: sessionID,
            surfaceID: primary.rawValue.uuidString
        ) == primaryRoute)
        #expect(registry.route(
            sessionID: sessionID,
            surfaceID: secondary.rawValue.uuidString
        ) == secondaryRoute)
        #expect(registry.route(
            sessionID: UUID().uuidString,
            surfaceID: secondary.rawValue.uuidString
        ) == nil)
        #expect(registry.defaultRoute() == secondaryRoute)
        #expect(registry.surfaceIDs == Set([
            primary.rawValue.uuidString,
            secondary.rawValue.uuidString,
        ]))

        registry.replace(
            routes: [primaryRoute, secondaryRoute],
            preferredSurfaceID: nil
        )
        #expect(registry.defaultRoute() == primaryRoute)
    }

    @Test("wire snapshot keeps two surfaces from one tab distinguishable")
    func snapshotKeepsSplitSurfaceIdentity() throws {
        let sessionID = UUID().uuidString
        let primaryID = UUID().uuidString
        let secondaryID = UUID().uuidString
        let agents = [
            agent(sessionID: sessionID, surfaceID: primaryID, title: "Terminal 1"),
            agent(sessionID: sessionID, surfaceID: secondaryID, title: "Terminal 2"),
        ]
        let snapshot = MobileMirrorSnapshot(
            selectedSessionID: sessionID,
            selectedSurfaceID: secondaryID,
            projectCreationEnabled: false,
            projects: [],
            agents: agents,
            approvals: []
        )

        let decoded = try JSONDecoder().decode(
            MobileMirrorSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        #expect(decoded == snapshot)
        #expect(Set(decoded.agents.map(\.id)).count == 2)
        #expect(decoded.selectedSurfaceID == secondaryID)
    }

    private func agent(
        sessionID: String,
        surfaceID: String,
        title: String
    ) -> MobileMirrorAgentSnapshot {
        MobileMirrorAgentSnapshot(
            sessionID: sessionID,
            surfaceID: surfaceID,
            projectID: "project",
            title: title,
            name: nil,
            state: AgentState.idle.rawValue,
            stateLabel: "Idle",
            canRespond: false,
            terminalAvailable: true
        )
    }
}
