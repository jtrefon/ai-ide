import XCTest

@testable import osx_ide

@MainActor
final class OrchestrationGraphRunnerTests: XCTestCase {
    private actor LogBox {
        private var lines: [String] = []

        func append(_ line: String) {
            lines.append(line)
        }

        func snapshot() -> [String] {
            lines
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

    @MainActor
    private struct AppendToLogNode: OrchestrationNode {
        let id: String
        let output: String
        let nextId: String?
        let log: LogBox

        func run(state: OrchestrationState) async throws -> OrchestrationState {
            await log.append(output)
            return OrchestrationState(
                request: state.request,
                response: state.response,
                lastToolResults: state.lastToolResults,
                branchExecution: state.branchExecution,
                transition: nextId.map { .next($0) } ?? .end
            )
        }
    }

    func testRunnerExecutesNodesDeterministicallyInOrder() async throws {
        let log = LogBox()

        let graph = OrchestrationGraph(
            entryNodeId: "a",
            nodes: [
                AppendToLogNode(id: "a", output: "A", nextId: "b", log: log),
                AppendToLogNode(id: "b", output: "B", nextId: "c", log: log),
                AppendToLogNode(id: "c", output: "C", nextId: nil, log: log)
            ]
        )

        let runner = OrchestrationGraphRunner(graph: graph, maxTransitions: 10)
        let state = try await runner.run(initialState: OrchestrationState(
            request: makeSendRequest(),
            transition: .next("a")
        ))

        _ = state
        let snapshot = await log.snapshot()
        XCTAssertEqual(snapshot, ["A", "B", "C"])
    }

    func testRunnerThrowsWhenExceedingMaxTransitions() async {
        let graph = OrchestrationGraph(
            entryNodeId: "loop",
            nodes: [
                LoopNode(id: "loop")
            ]
        )

        let runner = OrchestrationGraphRunner(graph: graph, maxTransitions: 3)

        do {
            _ = try await runner.run(initialState: OrchestrationState(
                request: makeSendRequest(),
                transition: .next("loop")
            ))
            XCTFail("Expected runner to throw")
        } catch {
            XCTAssertTrue(String(describing: error).localizedCaseInsensitiveContains("maxTransitions"))
        }
    }

    func testBranchReviewNodeAdvancesThroughRemainingBranchesThenFinishes() async throws {
        let branchExecution = OrchestrationState.BranchExecution(
            plan: "1. [ ] First\n2. [ ] Second",
            globalInvariants: ["Keep edits focused"],
            branches: [
                .init(id: "branch_1", title: "First", checklistItems: ["Inspect files"]),
                .init(id: "branch_2", title: "Second", checklistItems: ["Verify output"])
            ],
            activeBranchIndex: 0
        )

        let graph = OrchestrationGraph(
            entryNodeId: "branch_review",
            nodes: [
                BranchReviewNode(executionNodeId: "execute", finalNodeId: "final"),
                BranchStatePreservingNode(id: "execute", nextId: "branch_review"),
                BranchStatePreservingNode(id: "final", nextId: nil)
            ]
        )

        let runner = OrchestrationGraphRunner(graph: graph, maxTransitions: 10)
        let finalState = try await runner.run(initialState: OrchestrationState(
            request: makeSendRequest(),
            response: AIServiceResponse(content: "Done", toolCalls: nil),
            lastToolResults: [],
            branchExecution: branchExecution,
            transition: .next("branch_review")
        ))

        XCTAssertEqual(finalState.branchExecution?.activeBranchIndex, 1)
        XCTAssertEqual(finalState.transition.nextNodeId, nil)
    }

    func testBranchReviewNodeResumesExecutionForLastBranchWhenPlanRemainsIncomplete() async throws {
        let request = makeSendRequest(mode: .agent)
        let branchExecution = OrchestrationState.BranchExecution(
            plan: "1. [x] First\n2. [ ] Second",
            globalInvariants: ["Keep edits focused"],
            branches: [
                .init(id: "branch_1", title: "First", checklistItems: ["Inspect files"]),
                .init(id: "branch_2", title: "Second", checklistItems: ["Verify output"])
            ],
            activeBranchIndex: 1
        )

        await ConversationPlanStore.shared.setProjectRoot(request.projectRoot)
        await ConversationPlanStore.shared.set(
            conversationId: request.conversationId,
            plan: """
            # Implementation Plan

            - [x] First
            - [ ] Second
            """
        )

        let node = BranchReviewNode(executionNodeId: "execute", finalNodeId: "final")
        let nextState = try await node.run(state: OrchestrationState(
            request: request,
            response: AIServiceResponse(
                content: "<ide_reasoning>Delivery: NEEDS_WORK</ide_reasoning>Done -> Next -> Path: Continue with remaining implementation.",
                toolCalls: nil
            ),
            lastToolResults: [],
            branchExecution: branchExecution,
            transition: .next("branch_review")
        ))

        XCTAssertEqual(nextState.transition.nextNodeId, "execute")
        XCTAssertEqual(nextState.branchExecution?.activeBranchIndex, 1)

        await ConversationPlanStore.shared.set(conversationId: request.conversationId, plan: "")
    }

    @MainActor
    private struct LoopNode: OrchestrationNode {
        let id: String

        func run(state: OrchestrationState) async throws -> OrchestrationState {
            OrchestrationState(
                request: state.request,
                response: state.response,
                lastToolResults: state.lastToolResults,
                branchExecution: state.branchExecution,
                transition: .next(id)
            )
        }
    }

    @MainActor
    private struct BranchStatePreservingNode: OrchestrationNode {
        let id: String
        let nextId: String?

        func run(state: OrchestrationState) async throws -> OrchestrationState {
            OrchestrationState(
                request: state.request,
                response: state.response,
                lastToolResults: state.lastToolResults,
                branchExecution: state.branchExecution,
                transition: nextId.map { .next($0) } ?? .end
            )
        }
    }

    private func makeSendRequest(mode: AIMode = .chat) -> SendRequest {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        return SendRequest(
            userInput: "Hello",
            explicitContext: nil,
            mode: mode,
            projectRoot: projectRoot,
            conversationId: UUID().uuidString,
            runId: UUID().uuidString,
            availableTools: [NoopTool()],
            cancelledToolCallIds: { [] },
            qaReviewEnabled: false,
            draftAssistantMessageId: nil
        )
    }
}
