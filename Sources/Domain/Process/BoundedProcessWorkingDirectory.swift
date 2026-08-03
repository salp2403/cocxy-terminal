// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BoundedProcessWorkingDirectory.swift - Path or descriptor-bound process cwd.

import Darwin
import Foundation

struct BoundedProcessWorkingDirectory: Sendable {
    private enum Storage: Sendable {
        case path
        case descriptor(Int32)
    }

    let displayURL: URL
    private let storage: Storage

    static func path(_ url: URL) -> BoundedProcessWorkingDirectory {
        BoundedProcessWorkingDirectory(displayURL: url, storage: .path)
    }

    static func descriptor(
        displayURL: URL,
        rawValue: Int32
    ) -> BoundedProcessWorkingDirectory {
        BoundedProcessWorkingDirectory(
            displayURL: displayURL,
            storage: .descriptor(rawValue)
        )
    }

    var isValid: Bool {
        guard displayURL.isFileURL,
              displayURL.path.hasPrefix("/"),
              !displayURL.path.utf8.contains(0) else {
            return false
        }
        guard case .descriptor(let descriptor) = storage else { return true }
        var metadata = stat()
        return descriptor > STDERR_FILENO
            && fcntl(descriptor, F_GETFD) >= 0
            && fstat(descriptor, &metadata) == 0
            && metadata.st_mode & S_IFMT == S_IFDIR
    }

    func addSpawnFileAction(
        _ actions: inout posix_spawn_file_actions_t?
    ) throws {
        let result: Int32
        switch storage {
        case .path:
            result = displayURL.path.withCString { path in
                if #available(macOS 26.0, *) {
                    posix_spawn_file_actions_addchdir(&actions, path)
                } else {
                    posix_spawn_file_actions_addchdir_np(&actions, path)
                }
            }
        case .descriptor(let descriptor):
            if #available(macOS 26.0, *) {
                result = posix_spawn_file_actions_addfchdir(&actions, descriptor)
            } else {
                result = posix_spawn_file_actions_addfchdir_np(&actions, descriptor)
            }
        }
        guard result == 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "configure process working directory",
                code: result
            )
        }
    }
}
