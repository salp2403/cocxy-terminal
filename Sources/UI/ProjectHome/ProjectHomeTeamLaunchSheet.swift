// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectHomeTeamLaunchSheet.swift - Real project-scoped team launch form.

import SwiftUI

struct ProjectHomeTeamLaunchSheet: View {
    let projectName: String
    let localizer: AppLocalizer
    let isLaunching: Bool
    let onCancel: () -> Void
    let onLaunch: (ProjectTeamLaunchRequest) -> Void

    @State private var teamName: String
    @State private var provider: AgentTeamProvider?
    @State private var teammates: String
    @State private var prompt = ""

    init(
        projectName: String,
        localizer: AppLocalizer,
        isLaunching: Bool,
        onCancel: @escaping () -> Void,
        onLaunch: @escaping (ProjectTeamLaunchRequest) -> Void
    ) {
        self.projectName = projectName
        self.localizer = localizer
        self.isLaunching = isLaunching
        self.onCancel = onCancel
        self.onLaunch = onLaunch
        _teamName = State(initialValue: AgentTeamConfig.slug("\(projectName)-team"))
        _provider = State(initialValue: AgentTeamProvider.allCases.first)
        _teammates = State(initialValue: localizer.string(
            "projectHome.team.defaultTeammates",
            fallback: "implementation, review"
        ))
    }

    private var request: ProjectTeamLaunchRequest? {
        try? ProjectTeamLaunchRequest.make(
            teamName: teamName,
            provider: provider,
            teammates: teammates,
            prompt: prompt
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localizer.string("projectHome.team.title", fallback: "Launch Team"))
                .font(.system(size: 17, weight: .semibold))

            Form {
                TextField(
                    localizer.string("projectHome.team.name", fallback: "Team name"),
                    text: $teamName
                )
                Picker(
                    localizer.string("projectHome.team.provider", fallback: "Provider"),
                    selection: $provider
                ) {
                    ForEach(AgentTeamProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(Optional(provider))
                    }
                }
                TextField(
                    localizer.string("projectHome.team.teammates", fallback: "Teammates"),
                    text: $teammates
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text(localizer.string("projectHome.team.task", fallback: "Task"))
                        .font(.system(size: 11, weight: .medium))
                    TextEditor(text: $prompt)
                        .font(.system(size: 12))
                        .frame(minHeight: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(localizer.string("common.cancel", fallback: "Cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button {
                    if let request { onLaunch(request) }
                } label: {
                    Label(
                        localizer.string("projectHome.team.launch", fallback: "Launch"),
                        systemImage: "person.3.fill"
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(request == nil || isLaunching)
            }
        }
        .padding(20)
        .frame(width: 500, height: 430)
    }
}
