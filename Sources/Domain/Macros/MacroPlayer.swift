// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MacroPlayer.swift - Deterministic macro replay planning.

import Foundation
import CocxyCommandSignatures

enum MacroPlayerError: Error, Equatable, Sendable {
    case emptyMacro(String)
    case invalidRepeatCount(Int)
    case signatureRequired(String)
    case untrustedSignature(String)
    case invalidSignature(String)
}

struct MacroPlaybackPlan: Equatable, Sendable {
    let macroID: String
    let events: [MacroEvent]
    let signatureStatus: MacroSignatureStatus

    init(
        macroID: String,
        events: [MacroEvent],
        signatureStatus: MacroSignatureStatus = .unsignedAllowed
    ) {
        self.macroID = macroID
        self.events = events
        self.signatureStatus = signatureStatus
    }
}

enum MacroSignatureStatus: Equatable, Sendable {
    case verified
    case unsignedAllowed
    case presentButUnverified
}

struct MacroSignaturePolicy: Sendable {
    let trustedAuthors: TrustedAuthorRegistry
    let requireSignedMacros: Bool

    init(
        trustedAuthors: TrustedAuthorRegistry = TrustedAuthorRegistry(),
        requireSignedMacros: Bool = false
    ) {
        self.trustedAuthors = trustedAuthors
        self.requireSignedMacros = requireSignedMacros
    }

    func validate(_ macro: TerminalMacro) throws -> MacroSignatureStatus {
        guard let artifact = macro.signature else {
            if requireSignedMacros {
                throw MacroPlayerError.signatureRequired(macro.id)
            }
            return .unsignedAllowed
        }

        guard let publicKey = trustedAuthors.publicKey(for: artifact.keyID) else {
            if requireSignedMacros {
                throw MacroPlayerError.untrustedSignature(macro.id)
            }
            return .presentButUnverified
        }

        let result = SignatureVerifier().verify(
            payload: try MacroSignaturePayload.data(for: macro),
            artifact: artifact,
            publicKey: publicKey
        )
        guard result == .valid else {
            throw MacroPlayerError.invalidSignature(macro.id)
        }
        return .verified
    }
}

enum MacroSignaturePayload {
    static func data(for macro: TerminalMacro) throws -> Data {
        let unsigned = TerminalMacro(
            id: macro.id,
            name: macro.name,
            events: macro.events,
            createdAt: macro.createdAt,
            updatedAt: macro.updatedAt,
            signature: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(unsigned)
    }
}

struct MacroPlayer: Sendable {
    let signaturePolicy: MacroSignaturePolicy

    init(signaturePolicy: MacroSignaturePolicy = MacroSignaturePolicy()) {
        self.signaturePolicy = signaturePolicy
    }

    func playback(
        _ macro: TerminalMacro,
        repeatCount: Int = 1
    ) throws -> MacroPlaybackPlan {
        guard repeatCount > 0 else {
            throw MacroPlayerError.invalidRepeatCount(repeatCount)
        }
        guard !macro.events.isEmpty else {
            throw MacroPlayerError.emptyMacro(macro.id)
        }
        let signatureStatus = try signaturePolicy.validate(macro)

        return MacroPlaybackPlan(
            macroID: macro.id,
            events: Array(repeating: macro.events, count: repeatCount).flatMap { $0 },
            signatureStatus: signatureStatus
        )
    }
}
