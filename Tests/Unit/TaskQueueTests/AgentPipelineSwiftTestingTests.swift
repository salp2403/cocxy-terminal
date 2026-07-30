// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Agent pipeline")
struct AgentPipelineSwiftTestingTests {
    @Test("validates and batches a dependency DAG deterministically")
    func validatesAndBatchesDependencyDAG() throws {
        let pipeline = try AgentPipeline(
            id: "Release Review",
            steps: [
                AgentPipelineStep(id: "scan", provider: .codex, prompt: "Scan"),
                AgentPipelineStep(id: "test", provider: .claudeCode, prompt: "Test"),
                AgentPipelineStep(
                    id: "summarize",
                    provider: .gemini,
                    prompt: "Summarize",
                    dependsOn: ["scan", "test", "scan"]
                ),
            ]
        )

        #expect(pipeline.id == "release-review")
        #expect(pipeline.steps[2].dependsOn == ["scan", "test"])
        #expect(try pipeline.topologicalBatches().map { $0.map(\.id) } == [
            ["scan", "test"],
            ["summarize"],
        ])
    }

    @Test("rejects unknown dependencies and cycles during decoding")
    func rejectsInvalidDependenciesDuringDecoding() throws {
        #expect(throws: AgentPipelineError.unknownDependency(
            stepID: "ship",
            dependencyID: "missing"
        )) {
            _ = try AgentPipeline(
                id: "invalid",
                steps: [
                    AgentPipelineStep(
                        id: "ship",
                        provider: .codex,
                        prompt: "Ship",
                        dependsOn: ["missing"]
                    ),
                ]
            )
        }

        let cycleJSON = Data("""
        {
          "id": "cycle",
          "steps": [
            {"id":"a","provider":"codex","prompt":"A","dependsOn":["b"]},
            {"id":"b","provider":"claude-code","prompt":"B","dependsOn":["a"]}
          ]
        }
        """.utf8)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(AgentPipeline.self, from: cycleJSON)
        }
    }

    @Test("executes independent steps in parallel before their dependent")
    func executesDAGWithBoundedParallelism() async throws {
        let probe = PipelineConcurrencyProbe()
        let pipeline = try AgentPipeline(
            id: "parallel",
            steps: [
                AgentPipelineStep(id: "a", provider: .codex, prompt: "A"),
                AgentPipelineStep(id: "b", provider: .claudeCode, prompt: "B"),
                AgentPipelineStep(
                    id: "c",
                    provider: .gemini,
                    prompt: "C",
                    dependsOn: ["a", "b"]
                ),
            ]
        )
        let executor = try AgentPipelineExecutor(maximumConcurrency: 2)

        let summary = await executor.execute(pipeline) { step in
            await probe.started(step.id)
            try await Task.sleep(for: .milliseconds(25))
            await probe.finished(step.id)
            return AgentPipelineStepExecutionOutput(summary: "done-\(step.id)")
        }

        #expect(summary.status == .succeeded)
        #expect(summary.stepResults.map(\.stepID) == ["a", "b", "c"])
        #expect(summary.stepResults.map(\.output) == ["done-a", "done-b", "done-c"])
        #expect(await probe.maximumActive == 2)
        #expect(await probe.didStart("c", afterFinishing: ["a", "b"]))
    }

    @Test("failed dependencies are skipped while independent branches finish")
    func failureSkipsOnlyDependentBranch() async throws {
        struct ExpectedFailure: Error {}
        let pipeline = try AgentPipeline(
            id: "partial",
            steps: [
                AgentPipelineStep(id: "fail", provider: .codex, prompt: "Fail"),
                AgentPipelineStep(id: "independent", provider: .gemini, prompt: "Continue"),
                AgentPipelineStep(
                    id: "blocked",
                    provider: .claudeCode,
                    prompt: "Blocked",
                    dependsOn: ["fail"]
                ),
            ]
        )
        let executor = try AgentPipelineExecutor(maximumConcurrency: 2)

        let summary = await executor.execute(pipeline) { step in
            if step.id == "fail" { throw ExpectedFailure() }
            return AgentPipelineStepExecutionOutput(summary: step.id)
        }

        #expect(summary.status == .failed)
        #expect(summary.stepResults.first(where: { $0.stepID == "fail" })?.status == .failed)
        #expect(summary.stepResults.first(where: { $0.stepID == "independent" })?.status == .succeeded)
        #expect(summary.stepResults.first(where: { $0.stepID == "blocked" })?.status == .skipped)
    }

    @Test("starts newly unblocked work without waiting for an unrelated branch")
    func startsNewlyUnblockedWorkImmediately() async throws {
        let probe = PipelineConcurrencyProbe()
        let pipeline = try AgentPipeline(
            id: "dynamic",
            steps: [
                AgentPipelineStep(id: "fast", provider: .codex, prompt: "Fast"),
                AgentPipelineStep(id: "slow", provider: .claudeCode, prompt: "Slow"),
                AgentPipelineStep(
                    id: "dependent",
                    provider: .gemini,
                    prompt: "Dependent",
                    dependsOn: ["fast"]
                ),
            ]
        )
        let executor = try AgentPipelineExecutor(maximumConcurrency: 2)

        let summary = await executor.execute(pipeline) { step in
            await probe.started(step.id)
            try await Task.sleep(for: step.id == "slow" ? .milliseconds(80) : .milliseconds(10))
            await probe.finished(step.id)
            return AgentPipelineStepExecutionOutput()
        }

        #expect(summary.status == .succeeded)
        #expect(await probe.didStart("dependent", beforeFinishing: "slow"))
    }

    @Test("pipeline JSON round-trips without becoming a WorkflowStep")
    func pipelineJSONRoundTrip() throws {
        let pipeline = try AgentPipeline(
            id: "review",
            name: "Review",
            steps: [
                AgentPipelineStep(
                    id: "audit",
                    provider: .codex,
                    prompt: "Audit",
                    worktree: "review-worktree"
                ),
            ]
        )
        let encoded = try JSONEncoder().encode(pipeline)
        let decoded = try JSONDecoder().decode(AgentPipeline.self, from: encoded)

        #expect(decoded == pipeline)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("command"))
    }
}

private actor PipelineConcurrencyProbe {
    private var active = 0
    private(set) var maximumActive = 0
    private var sequence: [String] = []

    func started(_ id: String) {
        active += 1
        maximumActive = max(maximumActive, active)
        sequence.append("start:\(id)")
    }

    func finished(_ id: String) {
        sequence.append("finish:\(id)")
        active -= 1
    }

    func didStart(_ id: String, afterFinishing dependencies: [String]) -> Bool {
        guard let startIndex = sequence.firstIndex(of: "start:\(id)") else { return false }
        return dependencies.allSatisfy { dependency in
            guard let finishIndex = sequence.firstIndex(of: "finish:\(dependency)") else {
                return false
            }
            return finishIndex < startIndex
        }
    }

    func didStart(_ id: String, beforeFinishing otherID: String) -> Bool {
        guard let startIndex = sequence.firstIndex(of: "start:\(id)"),
              let finishIndex = sequence.firstIndex(of: "finish:\(otherID)") else {
            return false
        }
        return startIndex < finishIndex
    }
}
