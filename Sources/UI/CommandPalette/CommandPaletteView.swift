// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandPaletteView.swift - SwiftUI overlay for the command palette.

import SwiftUI
import Combine

// MARK: - Command Palette View Model

/// ViewModel driving the Command Palette overlay.
///
/// Manages the search query, filtered results, and keyboard navigation state.
/// Binds to a `CommandPaletteSearching` engine for search and execution.
///
/// - SeeAlso: `CommandPaletteView` (SwiftUI view)
/// - SeeAlso: `CommandPaletteSearching` (search engine protocol)
@MainActor
final class CommandPaletteViewModel: ObservableObject {

    // MARK: - Published State

    /// The current search query entered by the user.
    @Published var query: String = ""

    /// Whether the command palette overlay is visible.
    @Published var isVisible: Bool = false

    /// The index of the currently selected result (for keyboard navigation).
    @Published var selectedIndex: Int = 0

    // MARK: - Dependencies

    /// The search engine providing fuzzy matching and action execution.
    private let engine: CommandPaletteSearching

    /// Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Creates a ViewModel backed by the given search engine.
    ///
    /// - Parameter engine: The command palette engine for search and execution.
    init(engine: CommandPaletteSearching) {
        self.engine = engine
        observeQueryChanges()
    }

    // MARK: - Computed Properties

    /// The filtered list of actions matching the current query.
    ///
    /// When the query is empty, returns recent actions followed by all actions.
    var filteredActions: [CommandAction] {
        if query.isEmpty {
            let recents = engine.recentActions
            if !recents.isEmpty {
                // Show recents first, then all actions excluding duplicates.
                let recentIds = Set(recents.map { $0.id })
                let remaining = engine.allActions.filter { !recentIds.contains($0.id) }
                return recents + remaining
            }
            return engine.allActions
        }
        return engine.search(query: query)
    }

    // MARK: - Actions

    /// Toggles the visibility of the command palette.
    ///
    /// Resets the query and selection when opening.
    func toggle() {
        isVisible.toggle()
        if isVisible {
            query = ""
            selectedIndex = 0
        }
    }

    /// Dismisses the command palette.
    func dismiss() {
        isVisible = false
        query = ""
        selectedIndex = 0
    }

    /// Executes the currently selected action and dismisses the palette.
    func executeSelected() {
        let actions = filteredActions
        guard selectedIndex >= 0, selectedIndex < actions.count else { return }

        let action = actions[selectedIndex]
        engine.execute(action)
        dismiss()
    }

    /// Moves the selection up by one row.
    func moveSelectionUp() {
        let count = filteredActions.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex - 1 + count) % count
    }

    /// Moves the selection down by one row.
    func moveSelectionDown() {
        let count = filteredActions.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + 1) % count
    }

    // MARK: - Private

    /// Resets the selected index to 0 whenever the query changes.
    private func observeQueryChanges() {
        $query
            .dropFirst()
            .sink { [weak self] _ in
                self?.selectedIndex = 0
            }
            .store(in: &cancellables)
    }
}

// MARK: - Command Palette View

/// A floating overlay that provides quick access to all registered commands.
///
/// ## Layout
///
/// ```
/// +-- Command Palette ---------------------------+
/// | [Search field with autofocus]                 |
/// |-----------------------------------------------|
/// | [Tabs]   New Tab                     Cmd+T    |
/// | [Tabs]   Close Tab                   Cmd+W    |
/// | [Splits] Split Vertical              Cmd+D    |
/// | [Theme]  Toggle Theme                         |
/// | ...                                           |
/// +-----------------------------------------------+
/// ```
///
/// ## Behavior
///
/// - Toggle: Cmd+Shift+P.
/// - Up/Down arrows: navigate results.
/// - Enter: execute selected action.
/// - Esc: dismiss.
/// - Search is fuzzy: "sv" matches "Split Vertical".
///
/// ## Design
///
/// - Centered overlay with max width 500pt.
/// - Max height 400pt with scrollable results.
/// - Vibrancy background for native macOS feel.
/// - Matched characters highlighted (future enhancement).
///
/// - SeeAlso: `CommandPaletteViewModel` (state management)
/// - SeeAlso: `CommandPaletteRowView` (individual result row)
struct CommandPaletteView: View {

    /// The ViewModel driving this view.
    @ObservedObject var viewModel: CommandPaletteViewModel

    /// Focus state for the search text field.
    @FocusState private var isSearchFocused: Bool

    /// Maximum width of the palette overlay.
    private static let maxWidth: CGFloat = 500

    /// Maximum height of the palette overlay.
    private static let maxHeight: CGFloat = 400

    // MARK: - Body

    var body: some View {
        if viewModel.isVisible {
            ZStack {
                // Dimmed background that dismisses on click.
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { viewModel.dismiss() }

                // Palette overlay.
                paletteContent
                    .frame(maxWidth: Self.maxWidth)
                    .frame(maxHeight: Self.maxHeight)
                    .background(
                        ZStack {
                            // Solid Catppuccin Surface0 as reliable fallback.
                            Color(nsColor: CocxyColors.surface0)
                            // Vibrancy on top for native macOS feel.
                            VisualEffectBackground(
                                material: .popover,
                                blendingMode: .behindWindow
                            )
                        }
                    )
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 14)
                    .padding(.top, 80)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Command Palette")
        }
    }

    // MARK: - Palette Content

    private var paletteContent: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultsList
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            TextField("Type a command...", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isSearchFocused)
                .onSubmit { viewModel.executeSelected() }
                .onKeyPress(.upArrow) {
                    viewModel.moveSelectionUp()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    viewModel.moveSelectionDown()
                    return .handled
                }
                .onKeyPress(.escape) {
                    viewModel.dismiss()
                    return .handled
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear { isSearchFocused = true }
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if viewModel.filteredActions.isEmpty && !viewModel.query.isEmpty {
                        Text("No commands found")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    ForEach(Array(viewModel.filteredActions.enumerated()), id: \.element.id) { index, action in
                        CommandPaletteRowView(
                            action: action,
                            isSelected: index == viewModel.selectedIndex,
                            query: viewModel.query
                        )
                        .id(action.id)
                        .onTapGesture {
                            viewModel.selectedIndex = index
                            viewModel.executeSelected()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: viewModel.selectedIndex) {
                let actions = viewModel.filteredActions
                guard viewModel.selectedIndex >= 0,
                      viewModel.selectedIndex < actions.count else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(actions[viewModel.selectedIndex].id, anchor: .center)
                }
            }
        }
    }
}
