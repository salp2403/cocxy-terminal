// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonProtocol.swift - Shared JSONL contract for the local PTY daemon.

import Foundation

public enum PTYDaemonProtocol {
    public static let helperName = "cocxyd"
    public static let protocolVersion = 1
    public static let jsonLinesCapability = "ipc-jsonl-v1"
    public static let terminalSurfaceCapability = "terminal-surface-v1"
    public static let terminalEngineCapability = "terminal-engine-v1"
    public static let terminalHostRendererCapability = "terminal-host-renderer-v1"
}

public struct PTYDaemonHello: Codable, Equatable, Sendable {
    public let version: String
    public let protocolVersion: Int
    public let pid: Int32?
    public let capabilities: [String]

    public init(
        version: String,
        protocolVersion: Int = PTYDaemonProtocol.protocolVersion,
        pid: Int32? = nil,
        capabilities: [String] = [PTYDaemonProtocol.jsonLinesCapability]
    ) {
        self.version = version
        self.protocolVersion = protocolVersion
        self.pid = pid
        self.capabilities = capabilities
    }

    public var supportsTerminalSurfaces: Bool {
        capabilities.contains(PTYDaemonProtocol.terminalSurfaceCapability)
    }

    public var supportsTerminalHostRenderer: Bool {
        capabilities.contains(PTYDaemonProtocol.terminalHostRendererCapability)
    }

    public var supportsTerminalEngineAdapter: Bool {
        supportsTerminalSurfaces &&
            capabilities.contains(PTYDaemonProtocol.terminalEngineCapability) &&
            supportsTerminalHostRenderer
    }
}

public struct PTYDaemonRequest: Codable, Equatable, Sendable {
    public enum Command: String, Codable, Sendable {
        case hello
        case shutdown
        case surfaceCreate = "surface_create"
        case surfaceAttach = "surface_attach"
        case surfaceWrite = "surface_write"
        case surfaceResize = "surface_resize"
        case surfaceClose = "surface_close"
        case surfaceFrameSubscribe = "surface_frame_subscribe"
        case surfaceSignal = "surface_signal"
        case surfaceKey = "surface_key"
        case surfacePreedit = "surface_preedit"
        case surfaceFocus = "surface_focus"
        case surfaceSearch = "surface_search"
        case surfaceScroll = "surface_scroll"
        case surfaceProcess = "surface_process"
    }

    public let id: String
    public let command: Command
    public let payload: [String: String]?

    public init(id: String, command: Command, payload: [String: String]? = nil) {
        self.id = id
        self.command = command
        self.payload = payload
    }
}

public struct PTYDaemonResponse: Codable, Equatable, Sendable {
    public let id: String
    public let ok: Bool
    public let hello: PTYDaemonHello?
    public let surfaceID: String?
    public let frame: PTYDaemonSurfaceFrame?
    public let searchResults: [PTYDaemonSearchResult]?
    public let process: PTYDaemonProcessRegistration?
    public let error: String?

    public init(
        id: String,
        ok: Bool,
        hello: PTYDaemonHello? = nil,
        surfaceID: String? = nil,
        frame: PTYDaemonSurfaceFrame? = nil,
        searchResults: [PTYDaemonSearchResult]? = nil,
        process: PTYDaemonProcessRegistration? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.ok = ok
        self.hello = hello
        self.surfaceID = surfaceID
        self.frame = frame
        self.searchResults = searchResults
        self.process = process
        self.error = error
    }
}

public struct PTYDaemonEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case surfaceOutput = "surface_output"
        case surfaceOSC = "surface_osc"
        case surfaceFrame = "surface_frame"
        case surfaceClosed = "surface_closed"
    }

    public let event: Kind
    public let surfaceID: String
    public let bytesBase64: String?
    public let osc: PTYDaemonOSCNotification?
    public let frame: PTYDaemonSurfaceFrame?
    public let error: String?

    public init(
        event: Kind,
        surfaceID: String,
        bytesBase64: String? = nil,
        osc: PTYDaemonOSCNotification? = nil,
        frame: PTYDaemonSurfaceFrame? = nil,
        error: String? = nil
    ) {
        self.event = event
        self.surfaceID = surfaceID
        self.bytesBase64 = bytesBase64
        self.osc = osc
        self.frame = frame
        self.error = error
    }
}

public struct PTYDaemonOSCNotification: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case titleChange = "title_change"
        case notification
        case shellPrompt = "shell_prompt"
        case commandStarted = "command_started"
        case commandFinished = "command_finished"
        case currentDirectory = "current_directory"
        case inlineImage = "inline_image"
        case processExited = "process_exited"
    }

    public let kind: Kind
    public let text: String?
    public let title: String?
    public let body: String?
    public let url: String?
    public let exitCode: Int?

    public init(
        kind: Kind,
        text: String? = nil,
        title: String? = nil,
        body: String? = nil,
        url: String? = nil,
        exitCode: Int? = nil
    ) {
        self.kind = kind
        self.text = text
        self.title = title
        self.body = body
        self.url = url
        self.exitCode = exitCode
    }
}

public struct PTYDaemonSurfaceFrame: Codable, Equatable, Sendable {
    public let surfaceID: String
    public let revision: UInt64
    public let timestamp: Double
    public let columns: UInt16
    public let rows: UInt16
    public let cells: [PTYDaemonGridCell]
    public let cursor: PTYDaemonCursor
    public let scrollbackTop: Int
    public let images: [PTYDaemonImageReference]

    public init(
        surfaceID: String,
        revision: UInt64,
        timestamp: Double,
        columns: UInt16,
        rows: UInt16,
        cells: [PTYDaemonGridCell],
        cursor: PTYDaemonCursor,
        scrollbackTop: Int = 0,
        images: [PTYDaemonImageReference] = []
    ) {
        self.surfaceID = surfaceID
        self.revision = revision
        self.timestamp = timestamp
        self.columns = columns
        self.rows = rows
        self.cells = cells
        self.cursor = cursor
        self.scrollbackTop = scrollbackTop
        self.images = images
    }
}

public struct PTYDaemonGridCell: Codable, Equatable, Sendable {
    public let row: UInt16
    public let column: UInt16
    public let glyph: UInt32
    public let foregroundRGBA: UInt32
    public let backgroundRGBA: UInt32
    public let attributes: UInt16

    public init(
        row: UInt16,
        column: UInt16,
        glyph: UInt32,
        foregroundRGBA: UInt32,
        backgroundRGBA: UInt32,
        attributes: UInt16 = 0
    ) {
        self.row = row
        self.column = column
        self.glyph = glyph
        self.foregroundRGBA = foregroundRGBA
        self.backgroundRGBA = backgroundRGBA
        self.attributes = attributes
    }
}

public struct PTYDaemonCursor: Codable, Equatable, Sendable {
    public let row: UInt16
    public let column: UInt16
    public let visible: Bool
    public let style: String

    public init(row: UInt16, column: UInt16, visible: Bool = true, style: String = "block") {
        self.row = row
        self.column = column
        self.visible = visible
        self.style = style
    }
}

public struct PTYDaemonImageReference: Codable, Equatable, Sendable {
    public let id: String
    public let row: UInt16
    public let column: UInt16
    public let width: UInt16
    public let height: UInt16

    public init(id: String, row: UInt16, column: UInt16, width: UInt16, height: UInt16) {
        self.id = id
        self.row = row
        self.column = column
        self.width = width
        self.height = height
    }
}

public struct PTYDaemonSearchResult: Codable, Equatable, Sendable {
    public let id: String
    public let lineNumber: Int
    public let column: Int
    public let matchText: String
    public let contextBefore: String?
    public let contextAfter: String?

    public init(
        id: String,
        lineNumber: Int,
        column: Int,
        matchText: String,
        contextBefore: String? = nil,
        contextAfter: String? = nil
    ) {
        self.id = id
        self.lineNumber = lineNumber
        self.column = column
        self.matchText = matchText
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
    }
}

public struct PTYDaemonProcessRegistration: Codable, Equatable, Sendable {
    public let shellPID: Int32
    public let ptyMasterFD: Int32
    public let startSeconds: UInt64?
    public let startMicroseconds: UInt64?

    public init(
        shellPID: Int32,
        ptyMasterFD: Int32,
        startSeconds: UInt64? = nil,
        startMicroseconds: UInt64? = nil
    ) {
        self.shellPID = shellPID
        self.ptyMasterFD = ptyMasterFD
        self.startSeconds = startSeconds
        self.startMicroseconds = startMicroseconds
    }
}

public enum PTYDaemonLineCodec {
    public enum CodecError: Error, Equatable {
        case missingNewline
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, fromLine data: Data) throws -> T {
        guard data.last == 0x0A else { throw CodecError.missingNewline }
        return try JSONDecoder().decode(type, from: data.dropLast())
    }
}
