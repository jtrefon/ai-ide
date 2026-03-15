import XCTest
import Combine

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

    private actor StubPlanStore: ConversationPlanStoring {
        private var plans: [String: String]

        init(plans: [String: String] = [:]) {
            self.plans = plans
        }

        func get(conversationId: String) -> String? {
            plans[conversationId]
        }

        func set(conversationId: String, plan: String) {
            plans[conversationId] = plan
        }
    }

    private struct StubBranchExecutionContinuationDecider: BranchExecutionContinuationDeciding {
        let shouldResume: Bool

        func shouldResumeExecution(
            from state: OrchestrationState,
            branchExecution: OrchestrationState.BranchExecution
        ) async -> Bool {
            _ = state
            _ = branchExecution
            return shouldResume
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
            return state.transitioning(to: nextId)
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
                content: "Reflection: Remaining work\nPlanning: Continue\nContinuity: NEEDS_WORK\n\nDone -> Next -> Path: Continue with remaining implementation.",
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

    func testBranchReviewNodeUsesInjectedContinuationDecider() async throws {
        let branchExecution = OrchestrationState.BranchExecution(
            plan: "1. [x] First",
            globalInvariants: [],
            branches: [
                .init(id: "branch_1", title: "First", checklistItems: ["Inspect files"])
            ],
            activeBranchIndex: 0
        )

        let node = BranchReviewNode(
            executionNodeId: "execute",
            finalNodeId: "final",
            continuationDecider: StubBranchExecutionContinuationDecider(shouldResume: true)
        )
        let nextState = try await node.run(state: OrchestrationState(
            request: makeSendRequest(mode: .agent),
            response: AIServiceResponse(content: "Done", toolCalls: nil),
            lastToolResults: [],
            branchExecution: branchExecution,
            transition: .next("branch_review")
        ))

        XCTAssertEqual(nextState.transition.nextNodeId, "execute")
        XCTAssertEqual(nextState.branchExecution?.activeBranchIndex, 0)
    }

    func testBranchExecutionContinuationDeciderDoesNotResumeIntermediateHandoffWithoutToolResults() async throws {
        let request = makeSendRequest(mode: .agent)
        let branchExecution = OrchestrationState.BranchExecution(
            plan: "1. [x] First",
            globalInvariants: [],
            branches: [
                .init(id: "branch_1", title: "First", checklistItems: ["Inspect files"])
            ],
            activeBranchIndex: 0
        )
        let decider = BranchExecutionContinuationDecider(planStore: StubPlanStore())

        let shouldResume = await decider.shouldResumeExecution(
            from: OrchestrationState(
                request: request,
                response: AIServiceResponse(
                    content: "Done -> Next -> Path: Continue with remaining implementation.",
                    toolCalls: nil
                ),
                lastToolResults: [],
                branchExecution: branchExecution,
                transition: .next("branch_review")
            ),
            branchExecution: branchExecution
        )

        XCTAssertFalse(shouldResume)
    }

    func testBranchExecutionContinuationDeciderResumesForIncompletePlanAfterToolLoopEvenIfResponseIsHandoffText() async throws {
        let request = makeSendRequest(mode: .agent, userInput: "Implement remaining work")
        let branchExecution = OrchestrationState.BranchExecution(
            plan: "1. [x] First\n2. [ ] Second",
            globalInvariants: [],
            branches: [
                .init(id: "branch_1", title: "Second", checklistItems: ["Finish implementation"])
            ],
            activeBranchIndex: 0
        )
        let decider = BranchExecutionContinuationDecider(planStore: StubPlanStore(plans: [
            request.conversationId: """
            # Implementation Plan

            - [x] First
            - [ ] Second
            """
        ]))

        let shouldResume = await decider.shouldResumeExecution(
            from: OrchestrationState(
                request: request,
                response: AIServiceResponse(
                    content: "Done -> Next -> Path: Continue with remaining implementation.",
                    toolCalls: nil
                ),
                lastToolResults: [
                    ChatMessage(
                        role: .tool,
                        content: "ok",
                        tool: ChatMessageToolContext(
                            toolName: "write_file",
                            toolStatus: .completed,
                            target: ToolInvocationTarget(toolCallId: "tool-1")
                        )
                    )
                ],
                branchExecution: branchExecution,
                transition: .next("branch_review")
            ),
            branchExecution: branchExecution
        )

        XCTAssertTrue(shouldResume)
    }

    func testBranchExecutionContinuationDeciderResumesWhenToolCallsRemainOnLastBranch() async throws {
        let request = makeSendRequest(mode: .agent, userInput: "Implement remaining work")
        let branchExecution = OrchestrationState.BranchExecution(
            plan: "1. [x] First\n2. [ ] Second",
            globalInvariants: [],
            branches: [
                .init(id: "branch_1", title: "Second", checklistItems: ["Finish implementation"])
            ],
            activeBranchIndex: 0
        )
        let decider = BranchExecutionContinuationDecider(planStore: StubPlanStore(plans: [
            request.conversationId: """
            # Implementation Plan

            - [x] First
            - [ ] Second
            """
        ]))

        let shouldResume = await decider.shouldResumeExecution(
            from: OrchestrationState(
                request: request,
                response: AIServiceResponse(
                    content: "Proceeding now.",
                    toolCalls: [AIToolCall(id: "tool-1", name: "write_file", arguments: ["path": "foo.txt", "content": "x"])]
                ),
                lastToolResults: [],
                branchExecution: branchExecution,
                transition: .next("branch_review")
            ),
            branchExecution: branchExecution
        )

        XCTAssertTrue(shouldResume)
    }

    func testExecutionSignalBuilderCapturesIncompletePlanAndExecutionFollowupSignals() async throws {
        let request = makeSendRequest(mode: .agent, userInput: "Implement remaining work")
        let builder = OrchestrationExecutionSignalBuilder(planStore: StubPlanStore(plans: [
            request.conversationId: """
            # Implementation Plan

            - [x] First
            - [ ] Second
            """
        ]))

        let state = OrchestrationState(
            request: request,
            response: AIServiceResponse(
                content: "<ide_reasoning>Reflection: one\nPlanning: continue\nContinuity: pending\nDelivery: NEEDS_WORK</ide_reasoning>Done -> Next -> Path: Continue with remaining implementation.",
                toolCalls: nil
            ),
            lastToolResults: [
                ChatMessage(
                    role: .tool,
                    content: "ok",
                    tool: ChatMessageToolContext(
                        toolName: "write_file",
                        toolStatus: .completed,
                        target: ToolInvocationTarget(toolCallId: "tool-1")
                    )
                )
            ],
            transition: .next("branch_review")
        )

        let signals = await builder.build(for: state)

        XCTAssertTrue(signals.hasToolResults)
        XCTAssertTrue(signals.hasIncompletePlan)
        XCTAssertEqual(
            signals.deliveryState,
            OrchestrationState.ExecutionSignals.DeliveryState.needsWork
        )
        XCTAssertTrue(signals.indicatesUnfinishedExecution)
    }

    func testBranchExecutionContinuationDeciderUsesPrecomputedExecutionSignals() async throws {
        let request = makeSendRequest(mode: .agent, userInput: "Implement remaining work")
        let branchExecution = OrchestrationState.BranchExecution(
            plan: "1. [x] First\n2. [ ] Second",
            globalInvariants: [],
            branches: [
                .init(id: "branch_1", title: "Second", checklistItems: ["Finish implementation"])
            ],
            activeBranchIndex: 0
        )
        let decider = BranchExecutionContinuationDecider(planStore: StubPlanStore())

        let signals = OrchestrationState.ExecutionSignals(
            hasToolCalls: false,
            hasToolResults: true,
            deliveryState: OrchestrationState.ExecutionSignals.DeliveryState.needsWork,
            planProgress: .init(completed: 1, total: 2),
            missingClaimedArtifacts: false,
            shouldForceExecutionFollowup: false,
            shouldForceToolFollowup: false,
            indicatesUnfinishedExecution: false,
            isIntermediateExecutionHandoff: false,
            isSyntheticProgressArtifact: false
        )

        let shouldResume = await decider.shouldResumeExecution(
            from: OrchestrationState(
                request: request,
                response: AIServiceResponse(
                    content: "Looks fine.",
                    toolCalls: nil
                ),
                lastToolResults: [
                    ChatMessage(
                        role: .tool,
                        content: "ok",
                        tool: ChatMessageToolContext(
                            toolName: "write_file",
                            toolStatus: .completed,
                            target: ToolInvocationTarget(toolCallId: "tool-1")
                        )
                    )
                ],
                branchExecution: branchExecution,
                executionSignals: signals,
                transition: .next("branch_review")
            ),
            branchExecution: branchExecution
        )

        XCTAssertTrue(shouldResume)
    }

    func testConversationFlowGraphStartsAtDispatcherForSimpleAgentRequest() {
        let graph = ConversationFlowGraphFactory.makeGraph(
            request: makeSendRequest(mode: .agent),
            historyCoordinator: makeHistoryCoordinator(),
            aiInteractionCoordinator: makeAIInteractionCoordinator(),
            initialResponseHandler: makeInitialResponseHandler(),
            toolLoopHandler: makeToolLoopHandler(),
            finalResponseHandler: makeFinalResponseHandler(),
            qaReviewHandler: makeQAReviewHandler(),
            qaReviewEnabled: false
        )

        XCTAssertEqual(graph.entryNodeId, DispatcherNode.idValue)
    }

    func testConversationFlowGraphStartsAtDispatcherForComplexAgentRequest() {
        let graph = ConversationFlowGraphFactory.makeGraph(
            request: makeSendRequest(
                mode: .agent,
                userInput: "re-architect the agent execution flow across multiple files and then migrate the old framework step by step"
            ),
            historyCoordinator: makeHistoryCoordinator(),
            aiInteractionCoordinator: makeAIInteractionCoordinator(),
            initialResponseHandler: makeInitialResponseHandler(),
            toolLoopHandler: makeToolLoopHandler(),
            finalResponseHandler: makeFinalResponseHandler(),
            qaReviewHandler: makeQAReviewHandler(),
            qaReviewEnabled: false
        )

        XCTAssertEqual(graph.entryNodeId, DispatcherNode.idValue)
    }

    @MainActor
    private struct LoopNode: OrchestrationNode {
        let id: String

        func run(state: OrchestrationState) async throws -> OrchestrationState {
            state.transitioning(to: id)
        }
    }

    @MainActor
    private struct BranchStatePreservingNode: OrchestrationNode {
        let id: String
        let nextId: String?

        func run(state: OrchestrationState) async throws -> OrchestrationState {
            state.transitioning(to: nextId)
        }
    }

    private func makeSendRequest(mode: AIMode = .chat, userInput: String = "Hello") -> SendRequest {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        return SendRequest(
            userInput: userInput,
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

    private func makeHistoryCoordinator() -> ChatHistoryCoordinator {
        ChatHistoryCoordinator(
            historyManager: ChatHistoryManager(),
            projectRoot: FileManager.default.temporaryDirectory
        )
    }

    private func makeAIInteractionCoordinator() -> AIInteractionCoordinator {
        AIInteractionCoordinator(aiService: StubAIService(), codebaseIndex: nil, eventBus: MockEventBus())
    }

    private func makeInitialResponseHandler() -> InitialResponseHandler {
        InitialResponseHandler(
            aiInteractionCoordinator: makeAIInteractionCoordinator(),
            historyCoordinator: makeHistoryCoordinator()
        )
    }

    private func makeToolLoopHandler() -> ToolLoopHandler {
        ToolLoopHandler(
            historyCoordinator: makeHistoryCoordinator(),
            aiInteractionCoordinator: makeAIInteractionCoordinator(),
            toolExecutionCoordinator: ToolExecutionCoordinator(
                toolExecutor: AIToolExecutor(
                    fileSystemService: FileSystemService(),
                    errorManager: AIToolExecutorNoopErrorManager(),
                    projectRoot: FileManager.default.temporaryDirectory
                )
            )
        )
    }

    private func makeFinalResponseHandler() -> FinalResponseHandler {
        FinalResponseHandler(
            historyCoordinator: makeHistoryCoordinator(),
            aiInteractionCoordinator: makeAIInteractionCoordinator()
        )
    }

    private func makeQAReviewHandler() -> QAReviewHandler {
        QAReviewHandler(
            historyCoordinator: makeHistoryCoordinator(),
            aiInteractionCoordinator: makeAIInteractionCoordinator()
        )
    }

    private struct StubAIService: AIService {
        func sendMessage(_ request: AIServiceMessageWithProjectRootRequest) async throws -> AIServiceResponse {
            _ = request
            return AIServiceResponse(content: "ok", toolCalls: nil)
        }

        func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse {
            _ = request
            return AIServiceResponse(content: "ok", toolCalls: nil)
        }

        func explainCode(_ code: String) async throws -> String {
            _ = code
            return "ok"
        }

        func refactorCode(_ code: String, instructions: String) async throws -> String {
            _ = code
            _ = instructions
            return "ok"
        }

        func generateCode(_ prompt: String) async throws -> String {
            _ = prompt
            return "ok"
        }

        func fixCode(_ code: String, error: String) async throws -> String {
            _ = code
            _ = error
            return "ok"
        }
    }

    private final class MockEventBus: EventBusProtocol {
        func publish<E: Event>(_ event: E) {
            _ = event
        }

        func subscribe<E: Event>(to eventType: E.Type, handler: @escaping (E) -> Void) -> AnyCancellable {
            _ = eventType
            _ = handler
            return AnyCancellable {}
        }
    }
}
