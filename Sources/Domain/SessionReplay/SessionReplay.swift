// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionReplay.swift - Local session recording metadata and search.

import Foundation

struct SessionReplayRecording: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var surfaceID: SurfaceID
    var createdAt: Date
    var updatedAt: Date
    var durationNs: UInt64
    var byteCount: Int
    var castRelativePath: String
    var bookmarks: [SessionReplayBookmark]

    init(
        id: UUID = UUID(),
        title: String,
        surfaceID: SurfaceID,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        durationNs: UInt64 = 0,
        byteCount: Int = 0,
        castRelativePath: String? = nil,
        bookmarks: [SessionReplayBookmark] = []
    ) {
        self.id = id
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmedTitle.isEmpty ? "Untitled Recording" : trimmedTitle
        self.surfaceID = surfaceID
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.durationNs = durationNs
        self.byteCount = max(0, byteCount)
        self.castRelativePath = castRelativePath ?? "\(id.uuidString)/session.cast"
        self.bookmarks = bookmarks.sorted()
    }
}

struct SessionReplayBookmark: Codable, Identifiable, Comparable, Equatable, Sendable {
    let id: UUID
    let recordingID: UUID
    let offsetNs: UInt64
    let label: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        recordingID: UUID,
        offsetNs: UInt64,
        label: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.recordingID = recordingID
        self.offsetNs = offsetNs
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = trimmedLabel.isEmpty ? "Bookmark" : trimmedLabel
        self.createdAt = createdAt
    }

    static func < (lhs: SessionReplayBookmark, rhs: SessionReplayBookmark) -> Bool {
        if lhs.offsetNs == rhs.offsetNs {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.offsetNs < rhs.offsetNs
    }
}

struct SessionReplayPreparedRecording: Equatable, Sendable {
    let recording: SessionReplayRecording
    let castURL: URL
    let metadataURL: URL
}

struct SessionReplaySearchMatch: Equatable, Sendable {
    let recordingID: UUID
    let offsetNs: UInt64
    let snippet: String
}

enum SessionReplayStoreError: Error, Equatable, LocalizedError {
    case recordingNotFound(UUID)
    case invalidRecordingPath(String)
    case castFileMissing(UUID)

    var errorDescription: String? {
        switch self {
        case .recordingNotFound(let id):
            return "Session replay recording was not found: \(id.uuidString)"
        case .invalidRecordingPath(let path):
            return "Session replay recording path is invalid: \(path)"
        case .castFileMissing(let id):
            return "Session replay cast file is missing: \(id.uuidString)"
        }
    }
}

struct SessionReplayStore {
    let rootDirectory: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL = SessionReplayStore.defaultRootDirectory(),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.fileManager = fileManager
    }

    static func defaultRootDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Cocxy", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    func prepareRecording(
        title: String,
        surfaceID: SurfaceID,
        createdAt: Date = Date()
    ) throws -> SessionReplayPreparedRecording {
        try ensureRootDirectory()

        let recording = SessionReplayRecording(
            title: title,
            surfaceID: surfaceID,
            createdAt: createdAt
        )
        let directory = directoryURL(for: recording.id)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let metadataURL = metadataURL(for: recording.id)
        try save(recording)
        return SessionReplayPreparedRecording(
            recording: recording,
            castURL: castURL(for: recording),
            metadataURL: metadataURL
        )
    }

    func finishRecording(
        id: UUID,
        durationNs: UInt64,
        byteCount: Int,
        updatedAt: Date = Date()
    ) throws {
        var recording = try loadRecording(id: id)
        recording.durationNs = durationNs
        recording.byteCount = max(0, byteCount)
        recording.updatedAt = updatedAt
        try save(recording)

        let castURL = try castURL(forRecordingID: id)
        if fileManager.fileExists(atPath: castURL.path) {
            try setPrivateFilePermissions(at: castURL)
        }
    }

    func listRecordings() throws -> [SessionReplayRecording] {
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return [] }
        let entries = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return entries.compactMap { directory in
            let metadata = directory.appendingPathComponent("metadata.json", isDirectory: false)
            guard fileManager.fileExists(atPath: metadata.path) else { return nil }
            return try? loadRecording(from: metadata)
        }
        .sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func bookmarks(for recordingID: UUID) throws -> [SessionReplayBookmark] {
        try loadRecording(id: recordingID).bookmarks.sorted()
    }

    func recording(id recordingID: UUID) throws -> SessionReplayRecording {
        try loadRecording(id: recordingID)
    }

    func castFileURL(for recordingID: UUID) throws -> URL {
        try castURL(forRecordingID: recordingID)
    }

    @discardableResult
    func addBookmark(
        recordingID: UUID,
        offsetNs: UInt64,
        label: String,
        createdAt: Date = Date()
    ) throws -> SessionReplayBookmark {
        var recording = try loadRecording(id: recordingID)
        let clampedOffset = min(offsetNs, recording.durationNs)
        let bookmark = SessionReplayBookmark(
            recordingID: recordingID,
            offsetNs: clampedOffset,
            label: label,
            createdAt: createdAt
        )
        recording.bookmarks.append(bookmark)
        recording.bookmarks.sort()
        recording.updatedAt = createdAt
        try save(recording)
        return bookmark
    }

    func search(recordingID: UUID, query: String) throws -> [SessionReplaySearchMatch] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let castURL = try castURL(forRecordingID: recordingID)
        guard fileManager.fileExists(atPath: castURL.path) else {
            throw SessionReplayStoreError.castFileMissing(recordingID)
        }

        let contents = try String(contentsOf: castURL, encoding: .utf8)
        return SessionReplayCastSearch.matches(
            in: contents,
            recordingID: recordingID,
            query: trimmedQuery
        )
    }

    func exportCast(recordingID: UUID, to destinationURL: URL) throws {
        let sourceURL = try castURL(forRecordingID: recordingID)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw SessionReplayStoreError.castFileMissing(recordingID)
        }

        let parent = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        try setPrivateFilePermissions(at: destinationURL)
    }

    func deleteRecording(id: UUID) throws {
        let directory = directoryURL(for: id)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw SessionReplayStoreError.recordingNotFound(id)
        }
        try fileManager.removeItem(at: directory)
    }

    private func loadRecording(id: UUID) throws -> SessionReplayRecording {
        let url = metadataURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SessionReplayStoreError.recordingNotFound(id)
        }
        return try loadRecording(from: url)
    }

    private func loadRecording(from url: URL) throws -> SessionReplayRecording {
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(SessionReplayRecording.self, from: data)
    }

    private func save(_ recording: SessionReplayRecording) throws {
        let data = try Self.encoder.encode(recording)
        let url = metadataURL(for: recording.id)
        try data.write(to: url, options: [.atomic])
        try setPrivateFilePermissions(at: url)
    }

    private func castURL(for recording: SessionReplayRecording) -> URL {
        rootDirectory.appendingPathComponent(recording.castRelativePath, isDirectory: false)
            .standardizedFileURL
    }

    private func castURL(forRecordingID recordingID: UUID) throws -> URL {
        let recording = try loadRecording(id: recordingID)
        let url = castURL(for: recording)
        guard url.path.hasPrefix(rootDirectory.path + "/") else {
            throw SessionReplayStoreError.invalidRecordingPath(recording.castRelativePath)
        }
        return url
    }

    private func metadataURL(for recordingID: UUID) -> URL {
        directoryURL(for: recordingID)
            .appendingPathComponent("metadata.json", isDirectory: false)
    }

    private func directoryURL(for recordingID: UUID) -> URL {
        rootDirectory
            .appendingPathComponent(recordingID.uuidString, isDirectory: true)
            .standardizedFileURL
    }

    private func ensureRootDirectory() throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: rootDirectory.path
        )
    }

    private func setPrivateFilePermissions(at url: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum SessionReplayCastSearch {
    static func matches(
        in castContents: String,
        recordingID: UUID,
        query: String
    ) -> [SessionReplaySearchMatch] {
        let foldedQuery = query.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )

        return castContents.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = String(rawLine)
            guard line.first == "[",
                  let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  event.count >= 3,
                  let seconds = event[0] as? Double,
                  let stream = event[1] as? String,
                  stream == "o",
                  let text = event[2] as? String else {
                return nil
            }

            let normalizedText = text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            let foldedText = normalizedText.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard foldedText.contains(foldedQuery),
                  let offsetNs = nanosecondOffset(from: seconds) else {
                return nil
            }

            return SessionReplaySearchMatch(
                recordingID: recordingID,
                offsetNs: offsetNs,
                snippet: normalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private static func nanosecondOffset(from seconds: Double) -> UInt64? {
        guard seconds.isFinite else { return nil }
        let maxSeconds = Double(UInt64.max) / 1_000_000_000
        guard seconds <= maxSeconds else { return nil }
        return UInt64(max(0, seconds) * 1_000_000_000)
    }
}
