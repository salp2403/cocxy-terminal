// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskQueueSocketAuthority.swift - Exact queue mutation authorization metadata.

import Foundation

enum TaskQueueSocketAuthority {
    static func details(
        operation: String,
        params: [String: String]
    ) -> [String: String]? {
        guard operation == "enqueue" || operation == "cancel",
              let rawTaskID = params["task-id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTaskID.isEmpty else {
            return nil
        }
        let taskID = AgentPipelineStep.normalizedID(rawTaskID)
        guard !taskID.isEmpty, taskID.utf8.count <= TaskQueueItem.maximumIDBytes else {
            return nil
        }
        var details = [
            "operation": operation,
            "task-id": taskID,
        ]
        if operation == "enqueue" {
            details["trigger"] = params["trigger"] ?? "manual"
        }
        return details
    }
}
