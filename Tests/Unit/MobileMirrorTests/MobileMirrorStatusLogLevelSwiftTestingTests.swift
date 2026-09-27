// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import OSLog
import Testing
@testable import CocxyTerminal

@Suite("Mobile mirror status log level")
struct MobileMirrorStatusLogLevelSwiftTestingTests {
    @Test("expected pairing conditions log below error level and faults stay errors")
    func statusLogLevelsFollowSeverity() {
        #expect(MobileMirrorCoordinator.statusLogLevel(for: MobileMirrorTunnelError.noConnectedTarget) == .default)
        #expect(MobileMirrorCoordinator.statusLogLevel(for: MobileMirrorLocalRelayError.noPrivateNetwork) == .default)
        #expect(MobileMirrorCoordinator.statusLogLevel(for: MobileMirrorError.pairingExpired) == .default)
        #expect(MobileMirrorCoordinator.statusLogLevel(for: MobileMirrorError.pairingDenied) == .default)
        #expect(MobileMirrorCoordinator.statusLogLevel(for: MobileMirrorLocalRelayError.listenerUnavailable) == .error)
        #expect(MobileMirrorCoordinator.statusLogLevel(for: CancellationError()) == .error)
    }
}
