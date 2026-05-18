// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CellModels.swift - Local-first Cocxy Cells domain models.

import Foundation

enum CellProviderKind: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case docker
    case ssh
    case e2b
    case fly
    case aws
    case gcp
    case azure
    case selfHosted = "self-hosted"

    static var localFirstCases: [CellProviderKind] {
        [.docker, .ssh, .selfHosted, .e2b, .fly, .aws, .gcp, .azure]
    }
}

enum CellStatus: String, Codable, Equatable, Sendable {
    case creating
    case running
    case stopped
    case failed
    case destroyed
}

struct Cell: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var provider: CellProviderKind
    var status: CellStatus
    var createdAt: Date
    var updatedAt: Date
    var metadata: [String: String]

    init(
        id: UUID = UUID(),
        name: String,
        provider: CellProviderKind,
        status: CellStatus = .creating,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }

    var safeMetadata: [String: String] {
        CellMetadataRedactor.redacted(metadata)
    }
}

enum CellLeasePurpose: String, Codable, Equatable, Sendable {
    case attachPTY = "attach-pty"
    case exec
    case logs
}

struct CellLease: Codable, Equatable, Sendable {
    let id: UUID
    let cellID: UUID
    let purpose: CellLeasePurpose
    let issuedAt: Date
    let expiresAt: Date
    let signature: Data
}

enum CellAuditAction: String, Codable, Equatable, Sendable {
    case create
    case exec
    case attach
    case destroy
    case status
    case logs
}

struct CellAuditEvent: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let cellID: UUID
    let action: CellAuditAction
    let actor: String
    let metadata: [String: String]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        cellID: UUID,
        action: CellAuditAction,
        actor: String,
        metadata: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.cellID = cellID
        self.action = action
        self.actor = actor
        self.metadata = CellMetadataRedactor.redacted(metadata)
        self.createdAt = createdAt
    }
}

enum CellMetadataRedactor {
    static let redactedValue = "[redacted]"

    private static let sensitiveKeys: Set<String> = [
        "api_key",
        "apikey",
        "authorization",
        "credential",
        "identity",
        "identity_file",
        "password",
        "private_key",
        "secret",
        "token",
    ]

    static func redacted(_ metadata: [String: String]) -> [String: String] {
        metadata.mapValues { $0 }.reduce(into: [:]) { result, pair in
            let normalized = pair.key
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
                .lowercased()
            result[pair.key] = sensitiveKeys.contains(normalized)
                ? redactedValue
                : pair.value
        }
    }
}
