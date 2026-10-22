// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserContentView+Hosting.swift - Direction-aware SwiftUI host creation.

import AppKit
import SwiftUI

@MainActor
extension BrowserContentView {
    func makeDirectionalHostingView<Content: View>(
        rootView: Content
    ) -> NSHostingView<Content> {
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.userInterfaceLayoutDirection = userInterfaceLayoutDirection
        return hostingView
    }
}
