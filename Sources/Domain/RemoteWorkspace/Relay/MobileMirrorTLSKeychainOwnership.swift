// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorTLSKeychainOwnership.swift - Relay key ownership across app and boot sessions.

import Darwin
import Foundation

enum MobileMirrorTLSKeychainOwnership {
    static let keyTagPrefix = "dev.cocxy.mobile.tls."

    enum Owner: Equatable {
        case session(bootIdentifier: String, processIdentifier: pid_t)
        case legacyProcess(processIdentifier: pid_t)
        case legacy
    }

    static func currentBootSessionIdentifier() -> String? {
        guard let identity = try? LaunchdBootIdentity.current(),
              let sessionUUID = identity.sessionUUID else {
            return nil
        }
        return sessionUUID
    }

    static func storageIdentifier(
        bootSessionIdentifier: String,
        ownerProcessIdentifier: pid_t,
        identityIdentifier: UUID
    ) -> String? {
        guard ownerProcessIdentifier > 0,
              let bootUUID = UUID(uuidString: bootSessionIdentifier) else {
            return nil
        }
        return [
            "v3",
            bootUUID.uuidString.lowercased(),
            String(ownerProcessIdentifier),
            identityIdentifier.uuidString.lowercased(),
        ].joined(separator: ".")
    }

    static func owner(from tag: String) -> Owner? {
        guard tag.hasPrefix(keyTagPrefix) else { return nil }
        let components = tag.dropFirst(keyTagPrefix.count).split(separator: ".")
        if components.count == 4,
           components[0] == "v3",
           let bootUUID = UUID(uuidString: String(components[1])),
           let processIdentifier = pid_t(components[2]),
           processIdentifier > 0,
           UUID(uuidString: String(components[3])) != nil {
            return .session(
                bootIdentifier: bootUUID.uuidString.lowercased(),
                processIdentifier: processIdentifier
            )
        }
        if components.count == 3,
           components[0] == "v2",
           let processIdentifier = pid_t(components[1]),
           processIdentifier > 0,
           UUID(uuidString: String(components[2])) != nil {
            return .legacyProcess(processIdentifier: processIdentifier)
        }
        if components.count == 1, UUID(uuidString: String(components[0])) != nil {
            return .legacy
        }
        return nil
    }

    static func shouldRemove(
        owner: Owner,
        currentBootSessionIdentifier: String?,
        processIsAlive: (pid_t) -> Bool
    ) -> Bool {
        switch owner {
        case let .session(bootIdentifier, processIdentifier):
            guard let currentBootSessionIdentifier else { return false }
            return bootIdentifier != currentBootSessionIdentifier.lowercased()
                || !processIsAlive(processIdentifier)
        case let .legacyProcess(processIdentifier):
            return !processIsAlive(processIdentifier)
        case .legacy:
            return true
        }
    }
}
