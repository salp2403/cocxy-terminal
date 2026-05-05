// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PRReviewResponseTemplate.swift - Reusable response templates for PR review comments.

import Foundation

enum PRReviewResponseTemplateID: String, CaseIterable, Sendable {
    case needsTests = "needs-tests"
    case narrowScope = "narrow-scope"
    case handleFailure = "handle-failure"
    case explainImpact = "explain-impact"
    case nit
}

struct PRReviewResponseTemplate: Identifiable, Equatable, Sendable {
    let id: PRReviewResponseTemplateID
    let titleKey: String
    let titleFallback: String
    let bodyKey: String
    let bodyFallback: String

    func title(using localizer: AppLocalizer) -> String {
        localizer.string(titleKey, fallback: titleFallback)
    }

    func body(using localizer: AppLocalizer) -> String {
        localizer.string(bodyKey, fallback: bodyFallback)
    }
}

enum PRReviewResponseTemplateCatalog {
    static let defaultTemplates: [PRReviewResponseTemplate] = [
        PRReviewResponseTemplate(
            id: .needsTests,
            titleKey: "codeReview.inlineComment.templates.needsTests.title",
            titleFallback: "Request tests",
            bodyKey: "codeReview.inlineComment.templates.needsTests.body",
            bodyFallback: "Please add focused coverage for this path, including the edge case this line changes."
        ),
        PRReviewResponseTemplate(
            id: .narrowScope,
            titleKey: "codeReview.inlineComment.templates.narrowScope.title",
            titleFallback: "Narrow scope",
            bodyKey: "codeReview.inlineComment.templates.narrowScope.body",
            bodyFallback: "Can we keep this change focused on the current behavior and avoid unrelated refactors?"
        ),
        PRReviewResponseTemplate(
            id: .handleFailure,
            titleKey: "codeReview.inlineComment.templates.handleFailure.title",
            titleFallback: "Handle failure",
            bodyKey: "codeReview.inlineComment.templates.handleFailure.body",
            bodyFallback: "Please handle the failure path here and surface a clear user-facing error."
        ),
        PRReviewResponseTemplate(
            id: .explainImpact,
            titleKey: "codeReview.inlineComment.templates.explainImpact.title",
            titleFallback: "Explain impact",
            bodyKey: "codeReview.inlineComment.templates.explainImpact.body",
            bodyFallback: "Please add a short note in the implementation or test that explains the user-visible impact."
        ),
        PRReviewResponseTemplate(
            id: .nit,
            titleKey: "codeReview.inlineComment.templates.nit.title",
            titleFallback: "Nit",
            bodyKey: "codeReview.inlineComment.templates.nit.body",
            bodyFallback: "Nit: please tighten the naming or formatting here before this lands."
        ),
    ]

    static func inserting(templateBody: String, into draft: String) -> String {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTemplate = templateBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTemplate.isEmpty else { return trimmedDraft }
        guard !trimmedDraft.isEmpty else { return trimmedTemplate }
        return "\(trimmedDraft)\n\n\(trimmedTemplate)"
    }
}
