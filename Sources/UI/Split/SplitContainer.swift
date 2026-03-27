// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SplitContainer.swift - Recursive split pane container.

import AppKit

// MARK: - Terminal View Provider

/// Closure type that provides an NSView for a given terminal UUID.
///
/// The caller is responsible for creating and caching terminal views.
/// The `SplitContainer` calls this to obtain the view for each leaf.
typealias TerminalViewProvider = (UUID) -> NSView

// MARK: - Split Container

/// NSView that renders a `SplitNode` tree recursively using NSSplitViews.
///
/// For each node in the tree:
/// - **Leaf:** Displays the terminal view provided by `terminalViewProvider`.
/// - **Split:** Creates an `NSSplitView` with two subviews (recursively).
///
/// The container observes divider drag events to update the split ratio
/// and supports programmatic updates via `updateNode(_:)`.
///
/// ## Usage
///
/// ```swift
/// let container = SplitContainer(
///     node: rootNode,
///     terminalViewProvider: { terminalID in
///         return myTerminalViewCache[terminalID] ?? createNewView(for: terminalID)
///     }
/// )
/// window.contentView = container
/// ```
///
/// ## Divider tracking
///
/// The container implements `NSSplitViewDelegate` to track divider position
/// changes. When the user drags a divider, the corresponding split node's
/// ratio is updated and reported via `onRatioChanged`.
///
/// - SeeAlso: `SplitNode` for the tree data structure.
/// - SeeAlso: `SplitManager` for the state management service.
@MainActor
final class SplitContainer: NSView {

    // MARK: - Properties

    /// The current split tree being rendered.
    private(set) var currentNode: SplitNode

    /// Provider that returns a terminal view for a given terminal UUID.
    private let terminalViewProvider: TerminalViewProvider

    /// Callback invoked when a divider drag changes a split's ratio.
    /// Parameters: (splitID: UUID, newRatio: CGFloat)
    var onRatioChanged: ((UUID, CGFloat) -> Void)?

    /// The leaf ID that currently has focus, if any.
    var focusedLeafID: UUID? {
        didSet {
            updateFocusIndicators()
        }
    }

    /// Cache of active split views keyed by their node ID.
    /// Used to avoid recreating the entire hierarchy on every update.
    private var splitViewCache: [UUID: NSSplitView] = [:]

    // MARK: - Initialization

    /// Creates a split container rendering the given node tree.
    ///
    /// - Parameters:
    ///   - node: The root split node to render.
    ///   - terminalViewProvider: Closure that provides a terminal view for each leaf.
    init(node: SplitNode, terminalViewProvider: @escaping TerminalViewProvider) {
        self.currentNode = node
        self.terminalViewProvider = terminalViewProvider
        super.init(frame: .zero)

        setAccessibilityRole(.splitGroup)
        setAccessibilityLabel("Terminal split panes")

        buildHierarchy(from: node)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SplitContainer does not support NSCoding")
    }

    // MARK: - Public API

    /// Updates the rendered tree to match the given node.
    ///
    /// This rebuilds the view hierarchy from scratch. For a future optimization,
    /// a diff algorithm could be used to minimize view churn.
    ///
    /// - Parameter node: The new root split node.
    func updateNode(_ node: SplitNode) {
        currentNode = node
        rebuildHierarchy()
    }

    // MARK: - Hierarchy Building

    /// Removes all subviews and rebuilds from the current node.
    private func rebuildHierarchy() {
        subviews.forEach { $0.removeFromSuperview() }
        splitViewCache.removeAll()
        buildHierarchy(from: currentNode)
    }

    /// Builds the view hierarchy from a SplitNode, filling this container.
    private func buildHierarchy(from node: SplitNode) {
        let contentView = createView(for: node)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Recursively creates the NSView for a SplitNode.
    ///
    /// - Parameter node: The node to render.
    /// - Returns: The NSView representing this node.
    private func createView(for node: SplitNode) -> NSView {
        switch node {
        case .leaf(let leafID, let terminalID):
            let wrapper = NSView()
            wrapper.wantsLayer = true
            wrapper.identifier = NSUserInterfaceItemIdentifier("leaf-\(leafID.uuidString)")

            // Accessibility: group role for each terminal pane.
            wrapper.setAccessibilityRole(.group)
            wrapper.setAccessibilityLabel("Terminal pane")

            let terminalView = terminalViewProvider(terminalID)
            terminalView.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(terminalView)
            NSLayoutConstraint.activate([
                terminalView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                terminalView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                terminalView.topAnchor.constraint(equalTo: wrapper.topAnchor),
                terminalView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            ])

            return wrapper

        case .split(let id, let direction, let first, let second, let ratio):
            let splitView = NSSplitView()
            splitView.translatesAutoresizingMaskIntoConstraints = false
            splitView.dividerStyle = .thin
            splitView.isVertical = (direction == .horizontal)
            splitView.identifier = NSUserInterfaceItemIdentifier(id.uuidString)

            let firstView = createView(for: first)
            let secondView = createView(for: second)

            firstView.translatesAutoresizingMaskIntoConstraints = false
            secondView.translatesAutoresizingMaskIntoConstraints = false

            splitView.addArrangedSubview(firstView)
            splitView.addArrangedSubview(secondView)

            // Store the ratio info for delegate use.
            splitViewCache[id] = splitView

            // Set up the delegate for ratio tracking.
            let delegateAdapter = SplitViewDelegateAdapter(
                splitID: id,
                ratio: ratio,
                onRatioChanged: { [weak self] splitID, newRatio in
                    self?.onRatioChanged?(splitID, newRatio)
                }
            )
            splitView.delegate = delegateAdapter
            // Retain the delegate adapter (NSSplitView.delegate is weak).
            objc_setAssociatedObject(
                splitView,
                &SplitViewDelegateAdapter.associatedKey,
                delegateAdapter,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )

            // Apply the initial ratio after layout.
            DispatchQueue.main.async { [weak splitView] in
                guard let splitView = splitView else { return }
                let totalSize = splitView.isVertical
                    ? splitView.bounds.width
                    : splitView.bounds.height
                let dividerThickness = splitView.dividerThickness
                let firstSize = (totalSize - dividerThickness) * ratio
                splitView.setPosition(firstSize, ofDividerAt: 0)
            }

            return splitView
        }
    }

    // MARK: - Focus Indicators

    /// The border width applied to the focused pane.
    static let focusBorderWidth: CGFloat = 2.0

    /// The accent color for the focused pane border.
    ///
    /// Uses the system accent color by default for consistency with macOS.
    static let focusBorderColor: NSColor = .controlAccentColor

    /// Updates visual focus indicators on leaf views.
    ///
    /// Iterates over all tracked leaf wrapper views and applies a colored
    /// border to the focused one, removing it from all others.
    private func updateFocusIndicators() {
        applyFocusBorder(to: self, node: currentNode)
    }

    /// Recursively applies focus border to the correct leaf wrapper.
    private func applyFocusBorder(to view: NSView, node: SplitNode) {
        switch node {
        case .leaf(let leafID, _):
            // Find the leaf wrapper view by tag and apply/remove border.
            let isFocused = (leafID == focusedLeafID)
            if let wrapperView = findLeafWrapper(withID: leafID, in: view) {
                wrapperView.wantsLayer = true
                if isFocused {
                    wrapperView.layer?.borderWidth = Self.focusBorderWidth
                    wrapperView.layer?.borderColor = Self.focusBorderColor.cgColor
                } else {
                    wrapperView.layer?.borderWidth = 0
                    wrapperView.layer?.borderColor = nil
                }
            }

        case .split(_, _, let first, let second, _):
            applyFocusBorder(to: view, node: first)
            applyFocusBorder(to: view, node: second)
        }
    }

    /// Finds a leaf wrapper view by the leaf's UUID identifier.
    private func findLeafWrapper(withID leafID: UUID, in view: NSView) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("leaf-\(leafID.uuidString)")
        if view.identifier == identifier {
            return view
        }
        for subview in view.subviews {
            if let found = findLeafWrapper(withID: leafID, in: subview) {
                return found
            }
        }
        return nil
    }
}

// MARK: - Split View Delegate Adapter

/// Adapter that bridges NSSplitViewDelegate callbacks to the SplitContainer.
///
/// Each NSSplitView in the hierarchy gets its own adapter instance that
/// tracks its split ID and reports ratio changes.
private final class SplitViewDelegateAdapter: NSObject, NSSplitViewDelegate {

    nonisolated(unsafe) static var associatedKey: UInt8 = 0

    let splitID: UUID
    private(set) var ratio: CGFloat
    let onRatioChanged: (UUID, CGFloat) -> Void

    init(splitID: UUID, ratio: CGFloat, onRatioChanged: @escaping (UUID, CGFloat) -> Void) {
        self.splitID = splitID
        self.ratio = ratio
        self.onRatioChanged = onRatioChanged
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? NSSplitView else { return }
        guard splitView.subviews.count == 2 else { return }

        let firstView = splitView.subviews[0]
        let totalSize = splitView.isVertical
            ? splitView.bounds.width
            : splitView.bounds.height

        guard totalSize > 0 else { return }

        let dividerThickness = splitView.dividerThickness
        let firstSize = splitView.isVertical
            ? firstView.frame.width
            : firstView.frame.height

        let newRatio = firstSize / (totalSize - dividerThickness)
        let clampedRatio = SplitNode.clampRatio(newRatio)

        if abs(clampedRatio - ratio) > 0.001 {
            ratio = clampedRatio
            onRatioChanged(splitID, clampedRatio)
        }
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        let totalSize = splitView.isVertical
            ? splitView.bounds.width
            : splitView.bounds.height
        return totalSize * SplitNode.minimumRatio
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        let totalSize = splitView.isVertical
            ? splitView.bounds.width
            : splitView.bounds.height
        return totalSize * SplitNode.maximumRatio
    }
}
