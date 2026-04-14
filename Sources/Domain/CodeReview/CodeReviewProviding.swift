// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewProviding.swift - ViewModel contract for the code review panel.

import Combine
import Foundation

@MainActor
protocol CodeReviewProviding: AnyObject, ObservableObject {
    var isVisible: Bool { get set }
    var currentDiffs: [FileDiff] { get }
    var selectedFilePath: String? { get set }
    var diffMode: DiffMode { get set }
    var isLoading: Bool { get }
    var activeSessionId: String? { get }
    var shouldAutoShow: Bool { get set }
    var pendingComments: [ReviewComment] { get }
    var pendingCommentCount: Int { get }

    func toggleVisibility()
    func refreshDiffs()
    func selectFile(_ path: String)
    func addComment(filePath: String, line: Int, body: String)
    func removeComment(id: UUID)
    func submitComments()
    func comments(for filePath: String) -> [ReviewComment]
    func comments(for filePath: String, line: Int) -> [ReviewComment]
    func commentCount(for filePath: String) -> Int
}
