// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectFanOutCoordinator.swift - App-wide routing into an embedded project flow.

import Foundation

enum ProjectFanOutDestination: Equatable, Sendable {
    case launch(TaskRunRecycleDraft?)
    case comparison(runID: String)
}

struct ProjectFanOutRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let projectID: ProjectID
    let destination: ProjectFanOutDestination

    init(projectID: ProjectID, destination: ProjectFanOutDestination) {
        self.id = UUID()
        self.projectID = projectID
        self.destination = destination
    }
}

@MainActor
final class ProjectFanOutCoordinator: ObservableObject {
    @Published private(set) var request: ProjectFanOutRequest?

    func presentLaunch(projectID: ProjectID, draft: TaskRunRecycleDraft? = nil) {
        request = ProjectFanOutRequest(projectID: projectID, destination: .launch(draft))
    }

    func presentComparison(projectID: ProjectID, runID: String) {
        request = ProjectFanOutRequest(
            projectID: projectID,
            destination: .comparison(runID: runID)
        )
    }

    func consume(for projectID: ProjectID) -> ProjectFanOutDestination? {
        guard let request, request.projectID == projectID else { return nil }
        self.request = nil
        return request.destination
    }
}
