// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// QuickTerminalViewModel.swift - Presentation logic for the quick terminal.

import Foundation
import Combine

// MARK: - Quick Terminal View Model

/// Presentation logic for the quick terminal dropdown.
///
/// Manages the visibility state, position, height and working directory.
/// Does NOT import AppKit (per ADR-002). The view model is the single source
/// of truth for the quick terminal's logical state.
///
/// ## State flow
///
/// ```
/// User presses hotkey
///   -> QuickTerminalController.toggle()
///   -> QuickTerminalViewModel.toggle()
///   -> @Published isVisible changes
///   -> UI reacts via Combine
/// ```
///
/// ## Persistence
///
/// The view model can serialize its state to `QuickTerminalSessionState` via
/// `toState()` and restore from it via `restore(from:)`. This integrates with
/// the session save/restore system.
///
/// ## Clamping
///
/// The `heightPercent` is clamped to the valid range (0.2...0.9) when
/// serialized to state. This matches `QuickTerminalPanel.minimumPercent`
/// and `maximumPercent`.
///
/// - SeeAlso: ADR-002 (MVVM pattern)
/// - SeeAlso: `QuickTerminalSessionState` for the serializable counterpart.
/// - SeeAlso: `QuickTerminalController` for the AppKit lifecycle controller.
@MainActor
final class QuickTerminalViewModel: ObservableObject {

    // MARK: - Constants

    /// Minimum height/width percent (matches QuickTerminalPanel.minimumPercent).
    static let minimumPercent: Double = 0.2

    /// Maximum height/width percent (matches QuickTerminalPanel.maximumPercent).
    static let maximumPercent: Double = 0.9

    // MARK: - Published State

    /// Whether the quick terminal panel is currently visible.
    @Published var isVisible: Bool = false

    /// The screen edge from which the panel slides in.
    @Published var position: QuickTerminalPosition = .top

    /// The panel size as a fraction of the relevant screen dimension (0.2...0.9).
    @Published var heightPercent: Double = 0.4

    /// The working directory of the quick terminal session.
    @Published var workingDirectory: String = "~"

    // MARK: - Visibility Control

    /// Toggles the quick terminal: shows if hidden, hides if visible.
    func toggle() {
        isVisible.toggle()
    }

    /// Shows the quick terminal. No-op if already visible.
    func show() {
        if !isVisible {
            isVisible = true
        }
    }

    /// Hides the quick terminal. No-op if already hidden.
    func hide() {
        if isVisible {
            isVisible = false
        }
    }

    // MARK: - Persistence

    /// Captures the current state as a serializable snapshot.
    ///
    /// The `heightPercent` is clamped to the valid range before serializing.
    ///
    /// - Returns: A `QuickTerminalSessionState` reflecting the current state.
    func toState() -> QuickTerminalSessionState {
        let clampedHeight = clampedHeightPercent()

        return QuickTerminalSessionState(
            isVisible: isVisible,
            workingDirectory: workingDirectory,
            heightPercent: clampedHeight,
            position: position
        )
    }

    /// Restores state from a saved snapshot.
    ///
    /// All fields are updated to match the saved state. The `heightPercent`
    /// from the state is applied as-is (it was clamped when saved).
    ///
    /// - Parameter state: The saved state to restore from.
    func restore(from state: QuickTerminalSessionState) {
        isVisible = state.isVisible
        workingDirectory = state.workingDirectory
        heightPercent = state.heightPercent
        position = state.position
    }

    // MARK: - Private Helpers

    /// Returns the height percent clamped to the valid range.
    private func clampedHeightPercent() -> Double {
        min(Self.maximumPercent, max(Self.minimumPercent, heightPercent))
    }
}
