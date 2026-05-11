// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RichInputRequest.swift - Terminal rich input request model.

import Foundation

struct TerminalRichInputRequest: Equatable, Sendable {
    let text: String
    let fileURLs: [URL]

    init(text: String = "", fileURLs: [URL] = []) {
        self.text = text
        self.fileURLs = fileURLs
    }
}
