// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorCoordinator+Models.swift - App-scoped mobile mirror state.

import Foundation
import os.log

enum MobileMirrorServiceState: Equatable {
    case stopped
    case starting
    case offering
    case awaitingConfirmation
    case active
    case denied
    case unavailable(MobileMirrorStatusMessage)
    case failed(MobileMirrorStatusMessage)
}

/// Panel status copy kept as a catalog key so it follows later language changes.
struct MobileMirrorStatusMessage: Equatable, Sendable {
    let key: String
    let fallback: String

    init(key: String, fallback: String) {
        self.key = key
        self.fallback = fallback
    }

    init(_ entry: (key: String, fallback: String)) {
        self.init(key: entry.key, fallback: entry.fallback)
    }

    func text(using localizer: AppLocalizer) -> String {
        localizer.string(key, fallback: fallback)
    }

    static let auditUnavailable = Self(
        key: "mobile.mirror.audit.unavailable",
        fallback: "The local audit log is unavailable."
    )
    static let unavailable = Self(
        key: "mobile.mirror.error.unavailable",
        fallback: "Mobile mirror is unavailable."
    )
}

extension MobileMirrorCoordinator {
    static let logger = Logger(subsystem: "dev.cocxy.terminal", category: "MobileMirror")

    struct OwnedStream {
        let bridge: CocxyCoreBridge
        let surfaceID: SurfaceID
        let port: UInt16
        let token: String
    }

    /// The raw error can name local paths and hosts, so it only reaches the private log.
    func statusMessage(for error: any Error) -> MobileMirrorStatusMessage {
        Self.logger.error(
            "Mobile mirror stopped: \(String(describing: error), privacy: .private)"
        )
        switch error {
        case let relayError as MobileMirrorLocalRelayError:
            return MobileMirrorStatusMessage(relayError.localizationEntry)
        case let tunnelError as MobileMirrorTunnelError:
            return MobileMirrorStatusMessage(tunnelError.localizationEntry)
        case let mirrorError as MobileMirrorError:
            return MobileMirrorStatusMessage(mirrorError.localizationEntry)
        case is RelayAuditLogError:
            return .auditUnavailable
        default:
            return .unavailable
        }
    }
}
