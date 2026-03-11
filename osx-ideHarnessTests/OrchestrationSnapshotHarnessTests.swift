import XCTest
@testable import osx_ide

@MainActor
final class OrchestrationSnapshotHarnessTests: XCTestCase {

    // MARK: - Per-transition snapshot writing

    func testRunnerWritesOneSnapshotPerTransition() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let conversationId = UUID().uuidString
        let runId = UUID().uuidString

        await OrchestrationRunStore.shared.setProjectRoot(projectRoot)

        let graph = OrchestrationGraph(
            entryNodeId: "a",
            nodes: [
                PassthroughNode(id: "a", nextId: "b"),
                PassthroughNode(id: "b", nextId: "c"),
                PassthroughNode(id: "c", nextId: nil)
            ]
        )

        let runner = OrchestrationGraphRunner(graph: graph, maxTransitions: 10)
        let request = makeSendRequest(conversationId: conversationId, runId: runId, projectRoot: projectRoot)
        _ = try await runner.run(initialState: OrchestrationState(
            request: request,
            transition: .next("a")
        ))

        let snapshotFileURL = projectRoot
            .appendingPathComponent(".ide", isDirectory: true)
            .appendingPathComponent("orchestration", isDirectory: true)
            .appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent(conversationId, isDirectory: true)
            .appendingPathComponent("\(runId).jsonl")

        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotFileURL.path), "Snapshot JSONL file should exist")

        let data = try Data(contentsOf: snapshotFileURL)
        let lines = String(data: data, encoding: .utf8)!
            .split(separator: "\n", omittingEmptySubsequences: true)

        XCTAssertEqual(lines.count, 3, "Should have exactly 3 snapshots (one per node transition)")

        let decoder = JSONDecoder()
        let snapshots = try lines.map { line in
            try decoder.decode(OrchestrationRunSnapshot.self, from: Data(line.utf8))
        }

        XCTAssertEqual(snapshots[0].phase, "a")
        XCTAssertEqual(snapshots[1].phase, "b")
        XCTAssertEqual(snapshots[2].phase, "c")

        XCTAssertEqual(snapshots[0].iteration, 1)
        XCTAssertEqual(snapshots[1].iteration, 2)
        XCTAssertEqual(snapshots[2].iteration, 3)

        for snapshot in snapshots {
            XCTAssertEqual(snapshot.runId, runId)
            XCTAssertEqual(snapshot.conversationId, conversationId)
        }
    }

    // MARK: - Phase order matches graph wiring

    func testSnapshotPhaseOrderMatchesGraphWiring() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let conversationId = UUID().uuidString
        let runId = UUID().uuidString

        await OrchestrationRunStore.shared.setProjectRoot(projectRoot)

        let graph = OrchestrationGraph(
            entryNodeId: "init",
            nodes: [
                PassthroughNode(id: "init", nextId: "process"),
                PassthroughNode(id: "process", nextId: "review"),
                PassthroughNode(id: "review", nextId: "deliver"),
                PassthroughNode(id: "deliver", nextId: nil)
            ]
        )

        let runner = OrchestrationGraphRunner(graph: graph, maxTransitions: 20)
        let request = makeSendRequest(conversationId: conversationId, runId: runId, projectRoot: projectRoot)
        _ = try await runner.run(initialState: OrchestrationState(
            request: request,
            transition: .next("init")
        ))

        let snapshots = try readSnapshots(projectRoot: projectRoot, conversationId: conversationId, runId: runId)
        let phases = snapshots.map(\.phase)
        XCTAssertEqual(phases, ["init", "process", "review", "deliver"])
    }

    // MARK: - maxTransitions enforcement

    func testRunnerThrowsOnMaxTransitionsExceeded() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        await OrchestrationRunStore.shared.setProjectRoot(projectRoot)

        let graph = OrchestrationGraph(
            entryNodeId: "loop",
            nodes: [
                PassthroughNode(id: "loop", nextId: "loop")
            ]
        )

        let runner = OrchestrationGraphRunner(graph: graph, maxTransitions: 5)
        let request = makeSendRequest(conversationId: UUID().uuidString, runId: UUID().uuidString, projectRoot: projectRoot)

        do {
            _ = try await runner.run(initialState: OrchestrationState(
                request: request,
                transition: .next("loop")
            ))
            XCTFail("Expected runner to throw when exceeding maxTransitions")
        } catch {
            let description = String(describing: error)
            XCTAssertTrue(description.localizedCaseInsensitiveContains("maxTransitions"), "Error should mention maxTransitions: \(description)")
        }
    }

    func testRunnerWritesSnapshotsUpToMaxTransitions() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let conversationId = UUID().uuidString
        let runId = UUID().uuidString

        await OrchestrationRunStore.shared.setProjectRoot(projectRoot)

        let graph = OrchestrationGraph(
            entryNodeId: "loop",
            nodes: [
                PassthroughNode(id: "loop", nextId: "loop")
            ]
        )

        let runner = OrchestrationGraphRunner(graph: graph, maxTransitions: 4)
        let request = makeSendRequest(conversationId: conversationId, runId: runId, projectRoot: projectRoot)

        _ = try? await runner.run(initialState: OrchestrationState(
            request: request,
            transition: .next("loop")
        ))

        let snapshots = try readSnapshots(projectRoot: projectRoot, conversationId: conversationId, runId: runId)
        XCTAssertEqual(snapshots.count, 4, "Should have written exactly maxTransitions snapshots before throwing")
    }

    // MARK: - Snapshot content validation

    func testSnapshotContainsUserInput() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let conversationId = UUID().uuidString
        let runId = UUID().uuidString

        await OrchestrationRunStore.shared.setProjectRoot(projectRoot)

        let graph = OrchestrationGraph(
            entryNodeId: "only",
            nodes: [
                PassthroughNode(id: "only", nextId: nil)
            ]
        )

        let runner = OrchestrationGraphRunner(graph: graph, maxTransitions: 10)
        let request = makeSendRequest(
            conversationId: conversationId,
            runId: runId,
            projectRoot: projectRoot,
            userInput: "Build a SwiftUI app"
        )
        _ = try await runner.run(initialState: OrchestrationState(
            request: request,
            transition: .next("only")
        ))

        let snapshots = try readSnapshots(projectRoot: projectRoot, conversationId: conversationId, runId: runId)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].userInput, "Build a SwiftUI app")
    }

    // MARK: - Helpers

    @MainActor
    private struct PassthroughNode: OrchestrationNode {
        let id: String
        let nextId: String?

        func run(state: OrchestrationState) async throws -> OrchestrationState {
            OrchestrationState(
                request: state.request,
                response: state.response,
                lastToolResults: state.lastToolResults,
                transition: nextId.map { .next($0) } ?? .end
            )
        }
    }

    private struct NoopTool: AITool {
        let name: String = "noop"
        let description: String = "noop"

        var parameters: [String: Any] {
            ["type": "object", "properties": [:]]
        }

        func execute(arguments _: ToolArguments) async throws -> String {
            "ok"
        }
    }

    private func makeSendRequest(
        conversationId: String,
        runId: String,
        projectRoot: URL,
        userInput: String = "Hello"
    ) -> SendRequest {
        SendRequest(
            userInput: userInput,
            explicitContext: nil,
            mode: .chat,
            projectRoot: projectRoot,
            conversationId: conversationId,
            runId: runId,
            availableTools: [NoopTool()],
            cancelledToolCallIds: { [] },
            qaReviewEnabled: false,
            draftAssistantMessageId: nil
        )
    }

    private func readSnapshots(projectRoot: URL, conversationId: String, runId: String) throws -> [OrchestrationRunSnapshot] {
        let url = projectRoot
            .appendingPathComponent(".ide", isDirectory: true)
            .appendingPathComponent("orchestration", isDirectory: true)
            .appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent(conversationId, isDirectory: true)
            .appendingPathComponent("\(runId).jsonl")

        let data = try Data(contentsOf: url)
        let lines = String(data: data, encoding: .utf8)!
            .split(separator: "\n", omittingEmptySubsequences: true)

        let decoder = JSONDecoder()
        return try lines.map { line in
            try decoder.decode(OrchestrationRunSnapshot.self, from: Data(line.utf8))
        }
    }

    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("osx_ide_snapshot_harness_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
