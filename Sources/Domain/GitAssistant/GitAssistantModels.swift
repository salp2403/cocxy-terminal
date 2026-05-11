// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitAssistantModels.swift - Value types returned by Git Assistant.

import Foundation

struct GitAssistantCommitMessageDraft: Sendable, Equatable {
    let subject: String
    let body: String
}

struct GitAssistantPullRequestDraft: Sendable, Equatable {
    let title: String
    let body: String
}

struct GitAssistantReleaseNotesDraft: Sendable, Equatable {
    let markdown: String
}

struct GitAssistantCommit: Sendable, Equatable, Identifiable {
    let hash: String
    let subject: String

    var id: String { hash }
}
