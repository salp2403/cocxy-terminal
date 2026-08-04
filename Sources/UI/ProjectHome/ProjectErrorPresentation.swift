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
        if context == .fanOut {
            if let executionError = error as? TaskRunExecutionError {
                return taskRunExecutionErrorMessage(executionError)
            }
            if let worktreeError = error as? WorktreeServiceError {
                return worktreeServiceErrorMessage(worktreeError)
            }
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
        case .fanOut:
            let category = "\(String(describing: type(of: error))) [\((error as NSError).code)]"
            return formattedProjectString(
                "projectHome.fanOut.error.unknown",
                fallback: "The parallel task could not be completed. Technical category: %@",
                category
            )
        case .projectAction:
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
        case .verifiedSurfaceUnavailable:
            return string(
                "project.activation.verifiedSurfaceUnavailable",
                fallback: "Cocxy could not open a terminal in the verified project folder."
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

    private func taskRunExecutionErrorMessage(_ error: TaskRunExecutionError) -> String {
        switch error {
        case .targetUnavailable:
            return string(
                "projectHome.fanOut.error.targetUnavailable",
                fallback: "The task target is no longer available. Reopen Project Home and try again."
            )
        case .featureDisabled:
            return string(
                "worktree.featureDisabled",
                fallback: "Enable worktrees in the global or project configuration to use this action."
            )
        case .duplicateRun(let runID):
            return formattedProjectString(
                "projectHome.fanOut.error.duplicateRun",
                fallback: "A task run with this identifier is already active: %@",
                runID
            )
        case .launchFailed(_, let rollbackFailures) where !rollbackFailures.isEmpty:
            return formattedProjectString(
                "projectHome.fanOut.error.launchRollbackIncomplete",
                fallback: "The parallel task could not start, and %d cleanup operation(s) need attention.",
                Int32(clamping: rollbackFailures.count)
            )
        case .launchFailed:
            return string(
                "projectHome.fanOut.error.launchFailed",
                fallback: "The parallel task could not start. Verify the selected providers and worktree state, then try again."
            )
        case .promotionUnavailable(let reason):
            return formattedProjectString(
                "projectHome.fanOut.error.promotionUnavailable",
                fallback: "The promotion preview is no longer valid: %@",
                boundedFanOutDetail(reason)
            )
        case .cancelled:
            return string(
                "projectHome.fanOut.error.cancelled",
                fallback: "The parallel task was cancelled."
            )
        }
    }

    private func worktreeServiceErrorMessage(_ error: WorktreeServiceError) -> String {
        switch error {
        case .featureDisabled:
            return string(
                "worktree.featureDisabled",
                fallback: "Enable worktrees in the global or project configuration to use this action."
            )
        case .gitUnavailable:
            return string(
                "projectHome.fanOut.error.gitUnavailable",
                fallback: "Git is unavailable. Check your installation and PATH."
            )
        case .notAGitRepository(let path):
            return formattedProjectString(
                "projectHome.fanOut.error.notRepository",
                fallback: "The project is no longer a Git repository: %@",
                path
            )
        case .collisionAfterRetries(let attempts):
            return formattedProjectString(
                "projectHome.fanOut.error.worktreeCollision",
                fallback: "A unique worktree could not be created after %d attempts.",
                Int32(clamping: attempts)
            )
        case .gitCommandFailed(_, _, let exitCode):
            return formattedProjectString(
                "projectHome.fanOut.error.gitFailed",
                fallback: "Git could not complete the operation (exit %d). Review the repository state and try again.",
                exitCode
            )
        case .worktreeNotFound(let id):
            return formattedProjectString(
                "projectHome.fanOut.error.worktreeMissing",
                fallback: "The worktree is no longer available: %@",
                id
            )
        case .uncommittedChanges(let path, _):
            return formattedProjectString(
                "projectHome.fanOut.error.uncommittedChanges",
                fallback: "Commit or stash the changes in %@ before continuing.",
                path
            )
        case .originHasUncommittedChanges(let path, _):
            return formattedProjectString(
                "projectHome.fanOut.error.originDirty",
                fallback: "Commit or stash the changes in the project checkout before promotion: %@",
                path
            )
        case .baseRevisionChanged:
            return string(
                "projectHome.fanOut.error.baseChanged",
                fallback: "The project branch changed after the parallel task started. Refresh or restart the task."
            )
        case .manifestError:
            return string(
                "projectHome.fanOut.error.manifestUnavailable",
                fallback: "The worktree registry could not be updated safely."
            )
        }
    }

    private func boundedFanOutDetail(_ detail: String) -> String {
        let oneLine = detail
            .split(whereSeparator: { $0.isNewline })
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !oneLine.isEmpty else { return "state changed" }
        return String(oneLine.prefix(180))
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
