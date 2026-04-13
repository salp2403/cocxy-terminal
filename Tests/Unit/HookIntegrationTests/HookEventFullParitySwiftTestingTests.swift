// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Hook event full parity")
struct HookEventFullParitySwiftTestingTests {

    @Test("SessionStart decodes injected agent_type from flat hook payload")
    func sessionStartDecodesAgentType() throws {
        let json = """
        {
          "hook_event_name": "SessionStart",
          "session_id": "codex-thread-1",
          "cwd": "/tmp/project",
          "agent_type": "codex"
        }
        """

        let decoder = JSONDecoder()
        let event = try decoder.decode(HookEvent.self, from: Data(json.utf8))

        #expect(event.type == .sessionStart)
        #expect(event.sessionId == "codex-thread-1")

        guard case .sessionStart(let data) = event.data else {
            Issue.record("Expected sessionStart payload")
            return
        }

        #expect(data.agentType == "codex")
        #expect(data.workingDirectory == "/tmp/project")
    }
}
