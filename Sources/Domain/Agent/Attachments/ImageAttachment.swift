// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ImageAttachment.swift - Local Agent Mode image attachment metadata.

import Foundation

struct AgentImageAttachment: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let mimeType: String
    let filePath: String
    let byteCount: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let createdAt: Date

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    init(
        id: String = UUID().uuidString,
        displayName: String,
        mimeType: String,
        filePath: String,
        byteCount: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.mimeType = mimeType
        self.filePath = filePath
        self.byteCount = max(0, byteCount)
        self.pixelWidth = max(0, pixelWidth)
        self.pixelHeight = max(0, pixelHeight)
        self.createdAt = createdAt
    }
}
