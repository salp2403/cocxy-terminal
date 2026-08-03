// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectErrorPresentation.swift - Safe localized project error presentation.

import Foundation

enum ProjectErrorPresentationContext {
    case projectAction
    case metadataWarning
    case teamLaunch
    case worktreeOpen
    case fanOut
    case codeReview
}

extension AppLocalizer {
    func projectErrorMessage(
        for error: Error,
        context: ProjectErrorPresentationContext
    ) -> String {
        if let failure = error as? ProjectHomeActionFailure {
            return projectHomeActionFailureMessage(failure)
        }
        if let cloneError = error as? ProjectCloneError {
            return projectCloneErrorMessage(cloneError)
        }
        if let activationError = error as? ProjectActivationError {
            return projectActivationErrorMessage(activationError)
        }
        if let executionError = error as? TaskRunExecutionError,
           executionError == .featureDisabled {
            return string(
                "worktree.featureDisabled",
                fallback: "Enable worktrees in the global or project configuration to use this action."
            )
        }

        switch context {
        case .metadataWarning:
            return string(
                "project.metadata.warning.message",
                fallback: "The project opened, but its recent-project metadata could not be saved."
            )
        case .teamLaunch:
            return projectHomeActionFailureMessage(.teamLaunchFailed)
        case .worktreeOpen:
            return projectHomeActionFailureMessage(.worktreeOpenFailed)
        case .codeReview:
            return string(
                "projectHome.error.codeReviewOpenFailed",
                fallback: "Code Review could not be opened."
            )
        case .projectAction, .fanOut:
            return string(
                "project.error.message",
                fallback: "The project action could not be completed."
            )
        }
    }

    private func projectHomeActionFailureMessage(_ failure: ProjectHomeActionFailure) -> String {
        switch failure {
        case .servicesUnavailable:
            return string(
                "projectHome.error.servicesUnavailable",
                fallback: "Project services are temporarily unavailable."
            )
        case .providerUnavailable:
            return string(
                "projectHome.error.providerUnavailable",
                fallback: "The selected local agent provider is unavailable."
            )
        case .projectSessionChanged:
            return string(
                "projectHome.error.sessionChanged",
                fallback: "The project session changed before the action started."
            )
        case .teamAlreadyRunning:
            return string(
                "projectHome.error.teamAlreadyRunning",
                fallback: "A team with this name is already running."
            )
        case .teamLaunchFailed:
            return string(
                "projectHome.error.teamLaunchFailed",
                fallback: "The team could not be launched."
            )
        case .worktreeOpenFailed:
            return string(
                "projectHome.error.worktreeOpenFailed",
                fallback: "The worktree could not be opened."
            )
        }
    }

    private func projectActivationErrorMessage(_ error: ProjectActivationError) -> String {
        switch error {
        case .unavailable(let path):
            return formattedProjectString(
                "project.activation.folderUnavailable",
                fallback: "The project folder is unavailable: %@",
                path
            )
        case .noWindow:
            return string(
                "project.activation.windowUnavailable",
                fallback: "Cocxy could not create a window for this project."
            )
        case .projectHomeUnavailable:
            return string(
                "project.activation.homeUnavailable",
                fallback: "Cocxy could not open Project Home in a readable pane."
            )
        }
    }

    private func projectCloneErrorMessage(_ error: ProjectCloneError) -> String {
        switch error {
        case .invalidRemote:
            return string(
                "project.clone.error.invalidRemote",
                fallback: "Enter a valid HTTPS or SSH Git URL."
            )
        case .embeddedCredentials:
            return string(
                "project.clone.error.embeddedCredentials",
                fallback: "The Git URL cannot contain credentials, a query, or a fragment."
            )
        case .unsupportedScheme:
            return string(
                "project.clone.error.unsupportedScheme",
                fallback: "Only HTTPS and SSH Git URLs are supported."
            )
        case .invalidParent(let path):
            return formattedProjectString(
                "project.clone.error.invalidParent",
                fallback: "The clone destination is not an existing folder: %@",
                path
            )
        case .symbolicLinkRejected(let path):
            return formattedProjectString(
                "project.clone.error.symbolicLinkRejected",
                fallback: "The clone destination cannot be a symbolic link: %@",
                path
            )
        case .invalidProjectName:
            return string(
                "project.clone.error.invalidProjectName",
                fallback: "The Git URL does not contain a valid project name."
            )
        case .destinationExists(let path):
            return formattedProjectString(
                "project.clone.error.destinationExists",
                fallback: "A file or folder already exists at %@.",
                path
            )
        case .cloneFailed(let exitCode, _):
            return formattedProjectString(
                "project.clone.error.failed",
                fallback: "Git could not clone the repository (exit %d).",
                exitCode
            )
        case .clonedRepositoryMissing(let path):
            return formattedProjectString(
                "project.clone.error.repositoryMissing",
                fallback: "Git finished without creating a repository at %@.",
                path
            )
        case .destinationChanged(let path):
            return formattedProjectString(
                "project.clone.error.destinationChanged",
                fallback: "The clone destination changed before it could be registered: %@.",
                path
            )
        case .cleanupUnverified(let path):
            return formattedProjectString(
                "project.clone.error.cleanupUnverified",
                fallback: "Clone cleanup could not be verified safely at %@. Review the folder before trying again.",
                path
            )
        }
    }

    private func formattedProjectString(
        _ key: String,
        fallback: String,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: string(key, fallback: fallback),
            locale: locale,
            arguments: arguments
        )
    }
}
