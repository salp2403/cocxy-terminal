// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CreatePullRequestSheet.swift - Multi-step pull-request creation wizard.

import SwiftUI

struct CreatePullRequestSheet: View {
    let defaultBaseBranch: String?
    var onCancel: () -> Void
    var onCreate: (PullRequestCreateRequest) -> Void
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .english)

    @State private var step: Step = .title
    @State private var title = ""
    @State private var bodyText = ""
    @State private var reviewers = ""
    @State private var baseBranch = ""
    @State private var draft = false

    enum Step: Int, CaseIterable, Identifiable {
        case title
        case body
        case reviewers
        case confirm

        var id: Int { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localizer.string("github.createPR.title", fallback: "Create Pull Request"))
                .font(.system(size: 15, weight: .semibold))

            Picker("", selection: $step) {
                Text("Title").tag(Step.title)
                Text("Body").tag(Step.body)
                Text("Reviewers").tag(Step.reviewers)
                Text("Confirm").tag(Step.confirm)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            stepContent

            HStack {
                Spacer()
                Button(localizer.string("common.cancel", fallback: "Cancel"), action: onCancel)
                Button(localizer.string("common.back", fallback: "Back")) {
                    step = Step(rawValue: max(0, step.rawValue - 1)) ?? .title
                }
                .disabled(step == .title)
                Button(step == .confirm ? localizer.string("github.createPR.create", fallback: "Create") : localizer.string("common.next", fallback: "Next")) {
                    if step == .confirm {
                        onCreate(request)
                    } else {
                        step = Step(rawValue: min(Step.confirm.rawValue, step.rawValue + 1)) ?? .confirm
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdvance)
            }
        }
        .onAppear {
            if baseBranch.isEmpty {
                baseBranch = defaultBaseBranch ?? "main"
            }
        }
        .padding(18)
        .frame(width: 480)
    }

    static func reviewerList(from raw: String) -> [String] {
        raw
            .split { $0 == "," || $0 == "\n" || $0 == " " }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var request: PullRequestCreateRequest {
        PullRequestCreateRequest(
            title: title,
            body: bodyText.isEmpty ? nil : bodyText,
            baseBranch: baseBranch.isEmpty ? defaultBaseBranch : baseBranch,
            reviewers: Self.reviewerList(from: reviewers),
            draft: draft
        )
    }

    private var canAdvance: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .title:
            VStack(alignment: .leading, spacing: 8) {
                TextField(localizer.string("github.createPR.titleField", fallback: "Title"), text: $title)
                    .textFieldStyle(.roundedBorder)
                TextField(localizer.string("github.createPR.base", fallback: "Base branch"), text: $baseBranch)
                    .textFieldStyle(.roundedBorder)
                Toggle(localizer.string("github.createPR.draft", fallback: "Draft"), isOn: $draft)
            }
        case .body:
            TextEditor(text: $bodyText)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 180)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
        case .reviewers:
            TextField(
                localizer.string("github.createPR.reviewers", fallback: "Reviewers"),
                text: $reviewers
            )
            .textFieldStyle(.roundedBorder)
        case .confirm:
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(bodyText.isEmpty ? localizer.string("github.createPR.noBody", fallback: "No body") : bodyText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(6)
                Text("base: \(request.baseBranch ?? "main")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                if !request.reviewers.isEmpty {
                    Text("reviewers: \(request.reviewers.joined(separator: ", "))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
