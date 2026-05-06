// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraTweaksPanel.swift - Developer inspector for the Aurora redesign.
//
// The tweaks panel is the live playground for the redesign: engineers
// flip the active theme palette, force a specific `GlassRenderMode`
// override, and preview a representative component set without having
// to rebuild the app or poke at runtime defaults. It never touches
// production state — all it owns is a `@Binding` to an
// `AuroraTweaksState` value type, which any host can persist,
// serialise, or wire into a feature-flagged view tree.
//
// Keeping the panel here next to the design tokens means the view can
// share the rest of the Aurora palette / glass primitive / agent chip
// without importing the production chrome. That matches the
// "pure-design module" posture the rest of this folder follows.

import SwiftUI

extension Design {

    // MARK: - Tweaks state

    /// Observable snapshot of every tweak the inspector exposes.
    ///
    /// Modelled as a value type so SwiftUI diffs stay cheap and tests
    /// can compare states directly. The state carries no references to
    /// production managers; a host that wants to persist the inspector
    /// selection between launches can encode it manually — the panel
    /// itself is stateless beyond this struct.
    struct AuroraTweaksState: Equatable, Sendable {
        /// Active theme palette (drives tokens used across the chrome).
        var theme: ThemeIdentity
        /// Force a specific render mode regardless of the runtime
        /// accessibility signals. `nil` means "use the decision table
        /// inside `resolveGlassRenderMode(...)`".
        var renderModeOverride: GlassRenderMode?
        /// Whether the ambient backdrop animation should run. Turning
        /// the backdrop off is useful when demoing static layouts.
        var backdropEnabled: Bool

        init(
            theme: ThemeIdentity = .aurora,
            renderModeOverride: GlassRenderMode? = nil,
            backdropEnabled: Bool = true
        ) {
            self.theme = theme
            self.renderModeOverride = renderModeOverride
            self.backdropEnabled = backdropEnabled
        }

        /// Default state used by the demo harness — Aurora theme, no
        /// forced render mode, backdrop on.
        static let defaults: AuroraTweaksState = AuroraTweaksState()

        /// Pretty label for the render-mode override. Kept as a pure
        /// helper so tests can verify the copy without touching the
        /// SwiftUI layer.
        var renderModeLabel: String {
            guard let renderModeOverride else { return "Auto (decision table)" }
            switch renderModeOverride {
            case .liquid: return "Force liquid glass"
            case .visualEffect: return "Force visual effect fallback"
            case .opaque: return "Force opaque accessibility surface"
            }
        }

        func localizedRenderModeLabel(using localizer: AppLocalizer) -> String {
            guard let renderModeOverride else {
                return localizer.string(
                    "auroraTweaks.renderMode.autoLabel",
                    fallback: "Auto (decision table)"
                )
            }
            switch renderModeOverride {
            case .liquid:
                return localizer.string(
                    "auroraTweaks.renderMode.liquidLabel",
                    fallback: "Force liquid glass"
                )
            case .visualEffect:
                return localizer.string(
                    "auroraTweaks.renderMode.visualEffectLabel",
                    fallback: "Force visual effect fallback"
                )
            case .opaque:
                return localizer.string(
                    "auroraTweaks.renderMode.opaqueLabel",
                    fallback: "Force opaque accessibility surface"
                )
            }
        }
    }

    // MARK: - Tweaks panel view

    /// Developer inspector that drives an `AuroraTweaksState` binding
    /// and previews the live result. Used by the demo harness in
    /// previews; never mounted in the shipping chrome.
    ///
    /// Layout:
    ///
    ///     GlassSurface
    ///     └── VStack
    ///         ├── header ("Aurora inspector")
    ///         ├── theme picker (3 segmented buttons)
    ///         ├── render-mode picker (Auto / liquid / visualEffect / opaque)
    ///         ├── backdrop toggle
    ///         └── preview stack:
    ///             ├── AgentChipView (samples)
    ///             ├── AuroraPaletteRow (selected)
    ///             └── LocalBadgeView
    ///
    /// The preview pieces reuse the production-facing views so any
    /// regression in a chip / row / badge shows up here the moment the
    /// inspector is opened.
    struct AuroraTweaksPanel: View {

        @Binding var state: AuroraTweaksState
        var localizer: AppLocalizer

        @Environment(\.designThemePalette) private var palette

        public init(
            state: Binding<AuroraTweaksState>,
            localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
        ) {
            self._state = state
            self.localizer = localizer
        }

        public var body: some View {
            GlassSurface(cornerRadius: .large) {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    header
                    themePicker
                    renderModePicker
                    backdropToggle
                    Divider().opacity(0.4)
                    previewStack
                }
                .padding(Spacing.small)
            }
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
        }

        // MARK: - Pieces

        private var header: some View {
            HStack(spacing: Spacing.xSmall) {
                Text("AURORA")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(palette.textLow.resolvedColor())
                Text(Self.localizedInspectorTitle(using: localizer))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.textHigh.resolvedColor())
                Spacer()
            }
        }

        private var themePicker: some View {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                caption(Self.localizedThemePaletteTitle(using: localizer))
                HStack(spacing: Spacing.xxSmall) {
                    ForEach(ThemeIdentity.allCases, id: \.self) { theme in
                        pill(
                            label: theme.displayName,
                            isSelected: state.theme == theme
                        ) {
                            state.theme = theme
                        }
                    }
                }
            }
        }

        private var renderModePicker: some View {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                caption(Self.localizedRenderModeTitle(using: localizer))
                HStack(spacing: Spacing.xxSmall) {
                    pill(label: Self.localizedAutoPillTitle(using: localizer), isSelected: state.renderModeOverride == nil) {
                        state.renderModeOverride = nil
                    }
                    pill(label: Self.localizedLiquidPillTitle(using: localizer), isSelected: state.renderModeOverride == .liquid) {
                        state.renderModeOverride = .liquid
                    }
                    pill(label: Self.localizedVisualPillTitle(using: localizer), isSelected: state.renderModeOverride == .visualEffect) {
                        state.renderModeOverride = .visualEffect
                    }
                    pill(label: Self.localizedOpaquePillTitle(using: localizer), isSelected: state.renderModeOverride == .opaque) {
                        state.renderModeOverride = .opaque
                    }
                }
                Text(state.localizedRenderModeLabel(using: localizer))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.textLow.resolvedColor())
                    .padding(.top, 2)
            }
        }

        private var backdropToggle: some View {
            Toggle(isOn: $state.backdropEnabled) {
                Text(Self.localizedBackdropToggleTitle(using: localizer))
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.textHigh.resolvedColor())
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }

        private var previewStack: some View {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                caption(Self.localizedPreviewTitle(using: localizer))
                HStack(spacing: Spacing.xSmall) {
                    AgentChipView(agent: .claude, state: .working, size: 28)
                    AgentChipView(agent: .codex, state: .waiting, size: 28)
                    AgentChipView(agent: .gemini, state: .finished, size: 28)
                    AgentChipView(agent: .shell, state: .idle, size: 28)
                }
                AuroraPaletteRow(
                    action: Design.samplePaletteActions.first!,
                    isSelected: true
                )
                LocalBadgeView()
            }
        }

        // MARK: - Helpers

        private func caption(_ text: String) -> some View {
            Text(text.uppercased())
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .tracking(1.3)
                .foregroundStyle(palette.textLow.resolvedColor())
        }

        private func pill(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(
                        isSelected
                            ? palette.textHigh.resolvedColor()
                            : palette.textLow.resolvedColor()
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                isSelected
                                    ? palette.accent.withAlpha(0.15).resolvedColor()
                                    : palette.glassHighlight.resolvedColor()
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? palette.accent.withAlpha(0.45).resolvedColor()
                                    : Color.clear,
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)
        }

        static func localizedInspectorTitle(using localizer: AppLocalizer) -> String {
            localizer.string("auroraTweaks.inspector", fallback: "inspector")
        }

        static func localizedThemePaletteTitle(using localizer: AppLocalizer) -> String {
            localizer.string("auroraTweaks.themePalette", fallback: "Theme palette")
        }

        static func localizedRenderModeTitle(using localizer: AppLocalizer) -> String {
            localizer.string("auroraTweaks.renderMode", fallback: "Render mode override")
        }

        static func localizedAutoPillTitle(using localizer: AppLocalizer) -> String {
            localizer.string("auroraTweaks.pill.auto", fallback: "Auto")
        }

        static func localizedLiquidPillTitle(using localizer: AppLocalizer) -> String {
            localizer.string("auroraTweaks.pill.liquid", fallback: "Liquid")
        }

        static func localizedVisualPillTitle(using localizer: AppLocalizer) -> String {
            localizer.string("auroraTweaks.pill.visual", fallback: "Visual")
        }

        static func localizedOpaquePillTitle(using localizer: AppLocalizer) -> String {
            localizer.string("auroraTweaks.pill.opaque", fallback: "Opaque")
        }

        static func localizedBackdropToggleTitle(using localizer: AppLocalizer) -> String {
            localizer.string("auroraTweaks.backdrop", fallback: "Ambient backdrop animation")
        }

        static func localizedPreviewTitle(using localizer: AppLocalizer) -> String {
            localizer.string("auroraTweaks.preview", fallback: "Preview")
        }
    }
}
