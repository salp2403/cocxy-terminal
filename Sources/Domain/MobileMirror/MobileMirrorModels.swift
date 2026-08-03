// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorModels.swift - Wire contracts for the local mobile mirror.

import Foundation

struct MobileMirrorProjectSnapshot: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let isPinned: Bool
    let accent: String?
}

enum MobileMirrorTerminalControl {
    static let maximumPasteUTF8Bytes = 1 * 1_024 * 1_024
    static let supportedKeys: Set<String> = [
        "backspace", "down", "enter", "escape", "left", "right", "tab", "up",
    ]
}

struct MobileMirrorAgentSnapshot: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(sessionID):\(surfaceID)" }

    let sessionID: String
    let surfaceID: String
    let projectID: String
    let title: String
    let name: String?
    let state: String
    let stateLabel: String
    let canRespond: Bool
    let terminalAvailable: Bool

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case surfaceID
        case projectID
        case title
        case name
        case state
        case stateLabel
        case canRespond
        case terminalAvailable
    }

    init(
        sessionID: String,
        surfaceID: String,
        projectID: String,
        title: String,
        name: String?,
        state: String,
        stateLabel: String,
        canRespond: Bool,
        terminalAvailable: Bool
    ) {
        self.sessionID = sessionID
        self.surfaceID = surfaceID
        self.projectID = projectID
        self.title = title
        self.name = name
        self.state = state
        self.stateLabel = stateLabel
        self.canRespond = canRespond
        self.terminalAvailable = terminalAvailable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        surfaceID = try container.decodeIfPresent(String.self, forKey: .surfaceID) ?? sessionID
        projectID = try container.decode(String.self, forKey: .projectID)
        title = try container.decode(String.self, forKey: .title)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        state = try container.decode(String.self, forKey: .state)
        stateLabel = try container.decode(String.self, forKey: .stateLabel)
        canRespond = try container.decode(Bool.self, forKey: .canRespond)
        terminalAvailable = try container.decode(Bool.self, forKey: .terminalAvailable)
    }
}

struct MobileMirrorApprovalSnapshot: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let sessionID: String
    let title: String
    let body: String
    let requiresResponse: Bool
}

struct MobileMirrorSnapshot: Codable, Equatable, Sendable {
    let selectedSessionID: String?
    let selectedSurfaceID: String?
    let projectCreationEnabled: Bool
    let projects: [MobileMirrorProjectSnapshot]
    let agents: [MobileMirrorAgentSnapshot]
    let approvals: [MobileMirrorApprovalSnapshot]

    private enum CodingKeys: String, CodingKey {
        case selectedSessionID
        case selectedSurfaceID
        case projectCreationEnabled
        case projects
        case agents
        case approvals
    }

    init(
        selectedSessionID: String?,
        selectedSurfaceID: String? = nil,
        projectCreationEnabled: Bool,
        projects: [MobileMirrorProjectSnapshot],
        agents: [MobileMirrorAgentSnapshot],
        approvals: [MobileMirrorApprovalSnapshot]
    ) {
        self.selectedSessionID = selectedSessionID
        self.selectedSurfaceID = selectedSurfaceID
        self.projectCreationEnabled = projectCreationEnabled
        self.projects = projects
        self.agents = agents
        self.approvals = approvals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedSessionID = try container.decodeIfPresent(String.self, forKey: .selectedSessionID)
        selectedSurfaceID = try container.decodeIfPresent(String.self, forKey: .selectedSurfaceID)
        projectCreationEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .projectCreationEnabled
        ) ?? false
        projects = try container.decodeIfPresent(
            [MobileMirrorProjectSnapshot].self,
            forKey: .projects
        ) ?? []
        agents = try container.decodeIfPresent(
            [MobileMirrorAgentSnapshot].self,
            forKey: .agents
        ) ?? []
        approvals = try container.decodeIfPresent(
            [MobileMirrorApprovalSnapshot].self,
            forKey: .approvals
        ) ?? []
    }

    static let empty = MobileMirrorSnapshot(
        selectedSessionID: nil,
        selectedSurfaceID: nil,
        projectCreationEnabled: false,
        projects: [],
        agents: [],
        approvals: []
    )
}

struct MobileMirrorBootstrap: Codable, Equatable, Sendable {
    let snapshot: MobileMirrorSnapshot
    let actionSecret: String
}

struct MobileMirrorActionResponse: Codable, Equatable, Sendable {
    let ok: Bool
    let error: String?
    let snapshot: MobileMirrorSnapshot?

    static func success(snapshot: MobileMirrorSnapshot?) -> Self {
        Self(ok: true, error: nil, snapshot: snapshot)
    }

    static func failure(_ message: String) -> Self {
        Self(ok: false, error: message, snapshot: nil)
    }
}

struct MobileMirrorTerminalModifiers: Codable, Equatable, Sendable {
    let shift: Bool
    let alt: Bool
    let ctrl: Bool

    init(shift: Bool = false, alt: Bool = false, ctrl: Bool = false) {
        self.shift = shift
        self.alt = alt
        self.ctrl = ctrl
    }
}

struct MobileMirrorAction: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case terminalControl = "terminal-control"
        case selectSession = "select-session"
        case agentRespond = "agent-respond"
        case approvalApprove = "approval-approve"
        case approvalReject = "approval-reject"
        case projectCreate = "project-create"
    }

    let kind: Kind
    let sessionID: String?
    let surfaceID: String?
    let controlType: String?
    let key: String?
    let text: String?
    let mouseAction: String?
    let row: Int?
    let col: Int?
    let button: Int?
    let scrollDelta: Int?
    let shift: Bool
    let alt: Bool
    let ctrl: Bool
    let approvalID: String?
    let name: String?

    private enum CodingKeys: String, CodingKey {
        case kind
        case sessionID
        case surfaceID
        case controlType
        case key
        case text
        case mouseAction
        case row
        case col
        case button
        case scrollDelta
        case shift
        case alt
        case ctrl
        case approvalID
        case name
    }

    init(
        kind: Kind,
        sessionID: String? = nil,
        surfaceID: String? = nil,
        controlType: String? = nil,
        key: String? = nil,
        text: String? = nil,
        mouseAction: String? = nil,
        row: Int? = nil,
        col: Int? = nil,
        button: Int? = nil,
        scrollDelta: Int? = nil,
        shift: Bool = false,
        alt: Bool = false,
        ctrl: Bool = false,
        approvalID: String? = nil,
        name: String? = nil
    ) {
        self.kind = kind
        self.sessionID = sessionID
        self.surfaceID = surfaceID
        self.controlType = controlType
        self.key = key
        self.text = text
        self.mouseAction = mouseAction
        self.row = row
        self.col = col
        self.button = button
        self.scrollDelta = scrollDelta
        self.shift = shift
        self.alt = alt
        self.ctrl = ctrl
        self.approvalID = approvalID
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        surfaceID = try container.decodeIfPresent(String.self, forKey: .surfaceID)
        controlType = try container.decodeIfPresent(String.self, forKey: .controlType)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        mouseAction = try container.decodeIfPresent(String.self, forKey: .mouseAction)
        row = try container.decodeIfPresent(Int.self, forKey: .row)
        col = try container.decodeIfPresent(Int.self, forKey: .col)
        button = try container.decodeIfPresent(Int.self, forKey: .button)
        scrollDelta = try container.decodeIfPresent(Int.self, forKey: .scrollDelta)
        shift = try container.decodeIfPresent(Bool.self, forKey: .shift) ?? false
        alt = try container.decodeIfPresent(Bool.self, forKey: .alt) ?? false
        ctrl = try container.decodeIfPresent(Bool.self, forKey: .ctrl) ?? false
        approvalID = try container.decodeIfPresent(String.self, forKey: .approvalID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }

    func validate() throws {
        switch kind {
        case .terminalControl:
            try validateTerminalControl()
        case .selectSession:
            guard let sessionID, UUID(uuidString: sessionID) != nil,
                  let surfaceID, UUID(uuidString: surfaceID) != nil else {
                throw MobileMirrorError.invalidAction
            }
            guard controlType == nil, key == nil, text == nil, mouseAction == nil,
                  row == nil, col == nil, button == nil, scrollDelta == nil,
                  !shift, !alt, !ctrl, approvalID == nil, name == nil else {
                throw MobileMirrorError.invalidAction
            }
        case .agentRespond:
            guard let sessionID, UUID(uuidString: sessionID) != nil,
                  let surfaceID, UUID(uuidString: surfaceID) != nil,
                  let text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.utf8.count <= 8_192,
                  controlType == nil, key == nil, mouseAction == nil,
                  row == nil, col == nil, button == nil, scrollDelta == nil,
                  !shift, !alt, !ctrl, approvalID == nil, name == nil else {
                throw MobileMirrorError.invalidAction
            }
        case .approvalApprove, .approvalReject:
            guard let approvalID, approvalID.utf8.count <= 256,
                  !approvalID.isEmpty,
                  text?.utf8.count ?? 0 <= 8_192,
                  actionAllowsApprovalText,
                  sessionID == nil, surfaceID == nil,
                  controlType == nil, key == nil, mouseAction == nil,
                  row == nil, col == nil, button == nil, scrollDelta == nil,
                  !shift, !alt, !ctrl, name == nil else {
                throw MobileMirrorError.invalidAction
            }
        case .projectCreate:
            guard let name,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  name.utf8.count <= 160,
                  sessionID == nil, surfaceID == nil,
                  controlType == nil, key == nil, text == nil,
                  mouseAction == nil, row == nil, col == nil, button == nil,
                  scrollDelta == nil, !shift, !alt, !ctrl, approvalID == nil else {
                throw MobileMirrorError.invalidAction
            }
        }
    }

    private var actionAllowsApprovalText: Bool {
        kind == .approvalApprove || text == nil
    }

    private func validateTerminalControl() throws {
        guard let sessionID, UUID(uuidString: sessionID) != nil,
              let surfaceID, UUID(uuidString: surfaceID) != nil,
              approvalID == nil, name == nil else {
            throw MobileMirrorError.invalidAction
        }
        switch controlType {
        case "key":
            guard (key == nil) != (text == nil),
                  mouseAction == nil, row == nil, col == nil, button == nil,
                  scrollDelta == nil,
                  key?.utf8.count ?? 0 <= 32,
                  (key.map {
                      MobileMirrorTerminalControl.supportedKeys.contains($0.lowercased())
                  } ?? true),
                  text?.utf8.count ?? 0 <= 8_192 else {
                throw MobileMirrorError.invalidAction
            }
        case "paste":
            guard key == nil, mouseAction == nil,
                  row == nil, col == nil, button == nil, scrollDelta == nil,
                  let text, !text.isEmpty,
                  text.utf8.count <= MobileMirrorTerminalControl.maximumPasteUTF8Bytes,
                  !shift, !alt, !ctrl else {
                throw MobileMirrorError.invalidAction
            }
        case "viewport-scroll":
            guard key == nil, text == nil, mouseAction == nil,
                  row == nil, col == nil, button == nil,
                  let scrollDelta, scrollDelta != 0, (-64...64).contains(scrollDelta),
                  !shift, !alt, !ctrl else {
                throw MobileMirrorError.invalidAction
            }
        default:
            throw MobileMirrorError.invalidAction
        }
    }
}

enum MobileMirrorError: Error, Equatable, Sendable, LocalizedError {
    case unavailable
    case noPrivateNetwork
    case invalidPairingToken
    case pairingExpired
    case pairingPending
    case pairingDenied
    case sessionExpired
    case invalidSignature
    case replayDetected
    case invalidAction
    case targetUnavailable
    case authorizationDenied
    case projectCreationUnavailable
    case invalidProjectName
    case projectAlreadyExists
    case projectCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Mobile mirror is unavailable."
        case .noPrivateNetwork: return "No private local network is available."
        case .invalidPairingToken: return "The pairing code is invalid."
        case .pairingExpired: return "The pairing code has expired."
        case .pairingPending: return "Pairing is awaiting confirmation on the Mac."
        case .pairingDenied: return "Pairing was denied on the Mac."
        case .sessionExpired: return "The paired session has expired or was revoked."
        case .invalidSignature: return "The signed mobile action is invalid."
        case .replayDetected: return "The mobile action was already used."
        case .invalidAction: return "The mobile action is invalid."
        case .targetUnavailable: return "The requested local target is unavailable."
        case .authorizationDenied: return "The action was not approved on the Mac."
        case .projectCreationUnavailable: return "Choose a project folder on the Mac first."
        case .invalidProjectName: return "The project name is invalid."
        case .projectAlreadyExists: return "A file or folder already uses that project name."
        case .projectCreationFailed(let message): return "Project creation failed: \(message)"
        }
    }
}
