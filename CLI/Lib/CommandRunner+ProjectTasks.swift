// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandRunner+ProjectTasks.swift - Project-aware task socket requests.

import Foundation

extension CommandRunner {
    func taskRunListRequest(id: String, project: String?) -> CLISocketRequest {
        let currentDirectory = FileManager.default.currentDirectoryPath
        let params = project.map {
            ["project": Self.absoluteCLIPath($0, relativeTo: currentDirectory)]
        }
        return CLISocketRequest(id: id, command: "task-run-list", params: params)
    }

    func taskEnqueueRequest(
        id: String,
        options: TaskEnqueueCLIOptions
    ) -> CLISocketRequest {
        let currentDirectory = FileManager.default.currentDirectoryPath
        var params = options.socketParams
        params["cwd"] = Self.absoluteCLIPath(
            options.worktree ?? currentDirectory,
            relativeTo: currentDirectory
        )
        if let pipelinePath = options.pipelinePath {
            params["input"] = Self.absoluteCLIPath(
                pipelinePath,
                relativeTo: currentDirectory
            )
        }
        if let project = options.project {
            params["project"] = Self.absoluteCLIPath(
                project,
                relativeTo: currentDirectory
            )
        }
        return CLISocketRequest(id: id, command: "task-enqueue", params: params)
    }
}
