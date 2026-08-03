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
    let targetTabID: TabID
    let destination: ProjectFanOutDestination

    init(projectID: ProjectID, targetTabID: TabID, destination: ProjectFanOutDestination) {
        self.id = UUID()
        self.projectID = projectID
        self.targetTabID = targetTabID
        self.destination = destination
    }
}

@MainActor
final class ProjectFanOutCoordinator: ObservableObject {
    static let maximumPendingRequests = 64
    @Published private(set) var requests: [ProjectFanOutRequest] = []

    func presentLaunch(
        projectID: ProjectID,
        targetTabID: TabID,
        draft: TaskRunRecycleDraft? = nil
    ) {
        enqueue(ProjectFanOutRequest(
            projectID: projectID,
            targetTabID: targetTabID,
            destination: .launch(draft)
        ))
    }

    func presentComparison(projectID: ProjectID, targetTabID: TabID, runID: String) {
        enqueue(ProjectFanOutRequest(
            projectID: projectID,
            targetTabID: targetTabID,
            destination: .comparison(runID: runID)
        ))
    }

    func consume(for projectID: ProjectID, targetTabID: TabID) -> ProjectFanOutDestination? {
        guard let request = requests.first(where: {
            $0.projectID == projectID && $0.targetTabID == targetTabID
        }) else { return nil }
        return consume(request, for: projectID, targetTabID: targetTabID)
    }

    func consume(
        _ deliveredRequest: ProjectFanOutRequest,
        for projectID: ProjectID,
        targetTabID: TabID
    ) -> ProjectFanOutDestination? {
        guard deliveredRequest.projectID == projectID,
              deliveredRequest.targetTabID == targetTabID,
              let index = requests.firstIndex(where: { $0.id == deliveredRequest.id }) else {
            return nil
        }
        requests.remove(at: index)
        return deliveredRequest.destination
    }

    private func enqueue(_ request: ProjectFanOutRequest) {
        requests.append(request)
        if requests.count > Self.maximumPendingRequests {
            requests.removeFirst(requests.count - Self.maximumPendingRequests)
        }
    }
}
