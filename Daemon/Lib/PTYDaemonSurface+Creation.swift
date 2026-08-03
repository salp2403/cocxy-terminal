// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonSurface+Creation.swift - Validated daemon surface construction.

import CocxyCoreKit
import CocxyShared
import Darwin
import Foundation

extension PTYDaemonSurface {
    static func create(
        payload: [String: String],
        writer: PTYDaemonLineWriter
    ) throws -> PTYDaemonSurface {
        let dimensions = try validatedDimensions(payload: payload)
        let rows = dimensions.rows
        let columns = dimensions.columns
        let shell = payload.nonEmpty("command")
            ?? ProcessInfo.processInfo.environment["SHELL"]
            ?? "/bin/zsh"
        let workingDirectory = payload.nonEmpty("workingDirectory")
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workingDirectory, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw PTYDaemonSurfaceError.invalidPayload(
                "surface_create requires an existing workingDirectory"
            )
        }
        let workingDirectoryDescriptor = try verifiedWorkingDirectoryDescriptor(
            path: workingDirectory,
            payload: payload
        )
        defer {
            if let workingDirectoryDescriptor {
                Darwin.close(workingDirectoryDescriptor)
            }
        }

        guard let terminal = cocxycore_terminal_create(rows, columns) else {
            throw PTYDaemonSurfaceError.creationFailed("terminal allocation failed")
        }

        let fontConfiguration = try validatedFontConfiguration(payload: payload)
        guard applyFontConfiguration(fontConfiguration, to: terminal) else {
            cocxycore_terminal_destroy(terminal)
            throw PTYDaemonSurfaceError.creationFailed("terminal font configuration failed")
        }
        guard cocxycore_terminal_enable_scrollback(terminal, 10_000),
              cocxycore_terminal_enable_semantic(terminal, semanticBlockCapacity) else {
            cocxycore_terminal_destroy(terminal)
            throw PTYDaemonSurfaceError.creationFailed("terminal history configuration failed")
        }

        guard let pty = spawnPTY(
            rows: rows,
            columns: columns,
            shell: shell,
            workingDirectory: workingDirectory,
            workingDirectoryDescriptor: workingDirectoryDescriptor
        ) else {
            cocxycore_terminal_destroy(terminal)
            throw PTYDaemonSurfaceError.creationFailed("PTY spawn failed")
        }

        guard cocxycore_terminal_attach_pty(terminal, pty) else {
            cocxycore_pty_destroy(pty)
            cocxycore_terminal_destroy(terminal)
            throw PTYDaemonSurfaceError.creationFailed("PTY attach failed")
        }

        _ = cocxycore_terminal_enable_process_tracking(terminal, cocxycore_pty_child_pid(pty), 256)

        let surface = PTYDaemonSurface(
            surfaceID: UUID().uuidString,
            terminal: terminal,
            pty: pty,
            writer: writer
        )
        surface.registerCallbacks()
        return surface
    }

    private static func verifiedWorkingDirectoryDescriptor(
        path: String,
        payload: [String: String]
    ) throws -> Int32? {
        let rawDevice = payload.nonEmpty("workingDirectoryDevice")
        let rawInode = payload.nonEmpty("workingDirectoryInode")
        let rawFileType = payload.nonEmpty("workingDirectoryFileType")
        guard rawDevice != nil || rawInode != nil || rawFileType != nil else { return nil }
        guard let rawDevice,
              let rawInode,
              let rawFileType,
              let expectedDevice = UInt64(rawDevice),
              let expectedInode = UInt64(rawInode),
              let expectedFileType = UInt32(rawFileType) else {
            throw PTYDaemonSurfaceError.invalidPayload(
                "surface_create requires a complete working directory identity"
            )
        }
        let descriptor = path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw PTYDaemonSurfaceError.invalidPayload(
                "surface_create could not open the verified working directory"
            )
        }
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              UInt64(truncatingIfNeeded: metadata.st_dev) == expectedDevice,
              UInt64(truncatingIfNeeded: metadata.st_ino) == expectedInode,
              UInt32(metadata.st_mode & mode_t(S_IFMT)) == expectedFileType,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
            Darwin.close(descriptor)
            throw PTYDaemonSurfaceError.invalidPayload(
                "surface_create working directory identity changed"
            )
        }
        return descriptor
    }
}
