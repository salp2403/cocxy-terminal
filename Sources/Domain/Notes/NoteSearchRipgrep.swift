// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NoteSearchRipgrep.swift - Notes search backend backed by bundled ripgrep.

import Foundation

struct NoteSearchRipgrep: NoteSearching {

    let kind: NoteSearchEngineKind = .ripgrep

    let store: NoteStore
    let executableURL: URL?
    let fallback: NoteSearchGrep

    init(
        store: NoteStore,
        executableURL: URL? = BundledRipgrepExecutable.resolve(
            developmentRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ),
        fallback: NoteSearchGrep? = nil
    ) {
        self.store = store
        self.executableURL = executableURL
        self.fallback = fallback ?? NoteSearchGrep(store: store)
    }

    func search(
        query: String,
        in workspaceID: NoteWorkspaceID
    ) async throws -> [NoteSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let executableURL else {
            return try await fallback.search(query: query, in: workspaceID)
        }

        let directory = await store.directoryURL(for: workspaceID)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }

        let run = try? Self.runRipgrep(
            executableURL: executableURL,
            query: trimmed,
            directory: directory
        )
        guard let run else {
            return try await fallback.search(query: query, in: workspaceID)
        }
        if run.exitCode == 1 { return [] }
        guard run.exitCode == 0 else {
            return try await fallback.search(query: query, in: workspaceID)
        }

        return try await buildResults(
            from: run.output,
            query: trimmed,
            workspaceID: workspaceID
        )
    }

    private func buildResults(
        from output: Data,
        query: String,
        workspaceID: NoteWorkspaceID
    ) async throws -> [NoteSearchResult] {
        let hits = Self.parseMatches(from: output)
        guard !hits.isEmpty else { return [] }

        var aggregated: [UUID: AggregatedHit] = [:]
        for hit in hits {
            guard let id = Self.noteID(from: hit.path) else { continue }
            var current = aggregated[id] ?? AggregatedHit(count: 0, preview: hit.preview)
            current.count += max(1, hit.matchCount)
            if current.preview.isEmpty {
                current.preview = hit.preview
            }
            aggregated[id] = current
        }

        var results: [NoteSearchResult] = []
        for (noteID, hit) in aggregated {
            guard let note = try await store.note(id: noteID, in: workspaceID) else { continue }
            let preview = hit.preview.isEmpty
                ? NoteSearchGrep.makePreview(body: note.body, needle: query, window: 80)
                : hit.preview
            results.append(
                NoteSearchResult(
                    noteID: noteID,
                    title: Note.deriveTitle(from: note.body),
                    preview: preview,
                    score: NoteSearchGrep.normaliseScore(occurrences: hit.count)
                )
            )
        }

        return results.sorted {
            if $0.score == $1.score { return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            return $0.score > $1.score
        }
    }

    static func runRipgrep(
        executableURL: URL,
        query: String,
        directory: URL
    ) throws -> RipgrepRun {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "--json",
            "--ignore-case",
            "--fixed-strings",
            "--glob",
            "*.md",
            "--",
            query,
            directory.path,
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
        return RipgrepRun(exitCode: process.terminationStatus, output: output)
    }

    static func parseMatches(from data: Data) -> [RipgrepMatch] {
        guard let raw = String(data: data, encoding: .utf8), !raw.isEmpty else { return [] }
        let decoder = JSONDecoder()
        return raw.split(whereSeparator: \.isNewline).compactMap { line -> RipgrepMatch? in
            guard let lineData = String(line).data(using: .utf8),
                  let event = try? decoder.decode(RipgrepJSONEvent.self, from: lineData),
                  event.type == "match",
                  let path = event.data?.path?.text,
                  let line = event.data?.lines?.text else {
                return nil
            }
            let cleanLine = line.trimmingCharacters(in: .newlines)
            return RipgrepMatch(
                path: path,
                preview: cleanLine,
                matchCount: event.data?.submatches?.count ?? 1
            )
        }
    }

    static func noteID(from path: String) -> UUID? {
        UUID(uuidString: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
    }
}

extension NoteSearchRipgrep {
    struct RipgrepRun: Sendable, Equatable {
        let exitCode: Int32
        let output: Data
    }

    struct RipgrepMatch: Sendable, Equatable {
        let path: String
        let preview: String
        let matchCount: Int
    }

    struct AggregatedHit: Sendable, Equatable {
        var count: Int
        var preview: String
    }
}

private struct RipgrepJSONEvent: Decodable {
    let type: String
    let data: RipgrepJSONData?
}

private struct RipgrepJSONData: Decodable {
    let path: RipgrepJSONText?
    let lines: RipgrepJSONText?
    let submatches: [RipgrepJSONSubmatch]?
}

private struct RipgrepJSONText: Decodable {
    let text: String?
}

private struct RipgrepJSONSubmatch: Decodable {}
