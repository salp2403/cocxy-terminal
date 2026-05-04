// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// OnboardingFlowView.swift - Guided first-run setup for local Cocxy features.

import SwiftUI

struct OnboardingFlowView: View {
    let onComplete: (OnboardingSelection) -> Void
    let onSkip: () -> Void
    private let localizer: AppLocalizer

    @State private var theme = CocxyConfig.defaults.appearance.theme
    @State private var agentAutoMode = CocxyConfig.defaults.agent.autoMode
    @State private var lspEnabled = CocxyConfig.defaults.lsp.enabled
    @State private var createTabConfig = true
    @State private var createPrimerSkill = true
    @State private var createFirstWorkflow = true
    @State private var isVisible = false

    private let themes = [
        "catppuccin-mocha",
        "catppuccin-latte",
        "one-dark",
        "solarized-dark",
        "solarized-light",
    ]

    init(
        onComplete: @escaping (OnboardingSelection) -> Void,
        onSkip: @escaping () -> Void,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.onComplete = onComplete
        self.onSkip = onSkip
        self.localizer = localizer
    }

    var body: some View {
        ZStack {
            Color.black.opacity(isVisible ? 0.35 : 0.0)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.25), value: isVisible)

            VStack(alignment: .leading, spacing: 18) {
                header
                controls
                footer
            }
            .frame(width: 560)
            .padding(24)
            .background {
                Design.GlassSurface(cornerRadius: .large) {
                    Color.clear
                }
            }
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
            .scaleEffect(isVisible ? 1.0 : 0.96)
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isVisible)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("onboarding.accessibilityLabel", fallback: "Cocxy onboarding"))
        .onAppear { isVisible = true }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.blue))
                .frame(width: 38, height: 38)
                .background(CocxyColors.swiftUI(CocxyColors.blue).opacity(0.14))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(localized("onboarding.title", fallback: "Cocxy Setup"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(CocxyColors.swiftUI(CocxyColors.text))
                Text(localized("onboarding.subtitle", fallback: "Choose local defaults for this Mac"))
                    .font(.system(size: 13))
                    .foregroundColor(CocxyColors.swiftUI(CocxyColors.subtext0))
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(localized("onboarding.theme", fallback: "Theme"), selection: $theme) {
                ForEach(themes, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)

            Toggle(localized("onboarding.enableLanguageServers", fallback: "Enable language servers"), isOn: $lspEnabled)
            Toggle(localized("onboarding.agentAutoMode", fallback: "Agent auto mode"), isOn: $agentAutoMode)
            Toggle(localized("onboarding.createStarterTabConfig", fallback: "Create starter tab config"), isOn: $createTabConfig)
            Toggle(localized("onboarding.createPrimerSkill", fallback: "Create primer skill"), isOn: $createPrimerSkill)
            Toggle(localized("onboarding.createFirstWorkflow", fallback: "Create first workflow"), isOn: $createFirstWorkflow)
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 13))
        .foregroundColor(CocxyColors.swiftUI(CocxyColors.text))
    }

    private var footer: some View {
        HStack {
            Button(localized("onboarding.skip", fallback: "Skip")) {
                onSkip()
            }
            .buttonStyle(.plain)
            .foregroundColor(CocxyColors.swiftUI(CocxyColors.subtext0))

            Spacer()

            Button(localized("onboarding.apply", fallback: "Apply")) {
                onComplete(selection)
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(CocxyColors.swiftUI(CocxyColors.crust))
            .padding(.horizontal, 24)
            .padding(.vertical, 9)
            .background(CocxyColors.swiftUI(CocxyColors.blue))
            .cornerRadius(8)
        }
    }

    private var selection: OnboardingSelection {
        OnboardingSelection(
            theme: theme,
            agentAutoMode: agentAutoMode,
            lspEnabled: lspEnabled,
            createTabConfig: createTabConfig,
            createPrimerSkill: createPrimerSkill,
            createFirstWorkflow: createFirstWorkflow
        )
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}
