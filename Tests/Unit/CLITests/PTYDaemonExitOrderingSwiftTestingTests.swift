// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyDaemonLib

@Suite("PTY daemon exit ordering")
struct PTYDaemonExitOrderingSwiftTestingTests {
    @Test("authoritative waitpid success wins before an unknown tracker exit")
    func authoritativeWaitResultWinsUnknownTrackerExit() {
        var firstReportedExitCode: Int??
        var callbackOrder: [String] = []
        func reportOnce(_ exitCode: Int?) {
            guard firstReportedExitCode == nil else { return }
            firstReportedExitCode = .some(exitCode)
        }

        let didExit = PTYDaemonSurface.completePTYExitPoll(
            didExit: true,
            exitCode: 0,
            emitProcessExit: { exitCode in
                callbackOrder.append("waitpid")
                reportOnce(exitCode)
            },
            pollTrackedProcesses: {
                callbackOrder.append("tracker")
                reportOnce(nil)
            }
        )

        #expect(didExit == true)
        #expect(callbackOrder == ["waitpid", "tracker"])
        #expect(firstReportedExitCode == .some(.some(0)))
    }
}
