import XCTest
@testable import osx_ide
import Combine

@MainActor
final class ToolLoopDropoutHarnessTests: XCTestCase {
    private final class MockEventBus: EventBusProtocol {
        func publish<E: Event>(_ event: E) {}
        func subscribe<E: Event>(to eventType: E.Type, handler: @escaping (E) -> Void) -> AnyCancellable {
            return AnyCancellable {}
        }
    }
    
    private final class ScriptedAIService: AIService, @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [AIServiceResponse]
        private var historyRequests: [AIServiceHistoryRequest] = []

        init(responses: [AIServiceResponse]) {
            self.responses = responses
        }

        func sendMessage(_ request: AIServiceMessageWithProjectRootRequest) async throws -> AIServiceResponse {
            _ = request
            return dequeueResponse()
        }

        func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse {
            lock.withLock {
                historyRequests.append(request)
            }
            return dequeueResponse()
        }

        func explainCode(_ code: String) async throws -> String {
            _ = code
            return "Explanation"
        }

        func refactorCode(_ code: String, instructions: String) async throws -> String {
            _ = code
            _ = instructions
            return "Refactored"
        }

        func generateCode(_ prompt: String) async throws -> String {
            _ = prompt
            return "Generated"
        }

        func fixCode(_ code: String, error: String) async throws -> String {
            _ = code
            _ = error
            return "Fixed"
        }

        private func dequeueResponse() -> AIServiceResponse {
            lock.withLock {
                guard !responses.isEmpty else {
                    return AIServiceResponse(content: "(no scripted response)", toolCalls: nil)
                }
                return responses.removeFirst()
            }
        }

        func capturedHistoryRequests() -> [AIServiceHistoryRequest] {
            lock.withLock {
                historyRequests
            }
        }

        func remainingResponsesCount() -> Int {
            lock.withLock {
                responses.count
            }
        }
    }

    private actor ToolExecutionCounter {
        private(set) var count = 0

        func increment() {
            count += 1
        }
    }

    private struct CountingTool: AITool {
        let name: String
        let description: String = "Counting harness tool"
        let counter: ToolExecutionCounter
        var parameters: [String: Any] { ["type": "object", "properties": [:]] }

        func execute(arguments _: ToolArguments) async throws -> String {
            await counter.increment()
            return "counted"
        }
    }

    private struct FakeTool: AITool {
        let name: String
        let description: String = "Harness fake tool"
        var parameters: [String: Any] { ["type": "object", "properties": [:]] }

        func execute(arguments _: ToolArguments) async throws -> String {
            "ok"
        }
    }

    private final class HarnessErrorManager: ObservableObject, ErrorManagerProtocol {
        @Published var currentError: AppError?
        @Published var showErrorAlert: Bool = false

        func handle(_ error: AppError) {
            currentError = error
            showErrorAlert = true
        }

        func handle(_ error: Error, context: String) {
            if let appError = error as? AppError {
                handle(appError)
                return
            }
            handle(.unknown("\(context): \(error.localizedDescription)"))
        }

        func dismissError() {
            currentError = nil
            showErrorAlert = false
        }
    }

    func testHarnessReproducesAndPreventsBallDropForIncompletePlan() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        let runId = UUID().uuidString

        await ConversationPlanStore.shared.setProjectRoot(projectRoot)
        await ConversationPlanStore.shared.set(
            conversationId: conversationId,
            plan: """
            # Implementation Plan

            ## Strategy
            - [ ] Step one
            - [ ] Step two
            """
        )

        let firstToolCall = AIToolCall(id: "call-1", name: "fake_tool", arguments: [:])
        let secondToolCall = AIToolCall(id: "call-2", name: "fake_tool", arguments: [:])

        let scriptedService = ScriptedAIService(responses: [
            // After first tool execution, model drops out with no tool call even though plan is unfinished.
            AIServiceResponse(content: "I think this should be enough for now.", toolCalls: nil),
            // Continuation guardrail should force this follow-up tool call.
            AIServiceResponse(content: "Continuing unfinished checklist item.", toolCalls: [secondToolCall]),
            // After second tool execution, model can finish.
            AIServiceResponse(content: "<ide_reasoning>Analyze: done\nPlan: done\nAction: none\nDelivery: DONE</ide_reasoning>All checklist items are complete.", toolCalls: nil)
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: scriptedService, codebaseIndex: nil, eventBus: MockEventBus())
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let handler = ToolLoopHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        let availableTools: [AITool] = [FakeTool(name: "fake_tool")]

        let firstPass = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(content: "Starting execution.", toolCalls: [firstToolCall]),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: availableTools,
            cancelledToolCallIds: { [] },
            runId: runId,
            userInput: "Complete implementation"
        )

        harnessEqual(firstPass.lastToolCalls.map(\.id), ["call-1"])
        harnessEqual(firstPass.response.toolCalls?.map(\.id), ["call-2"], "Guardrail should force continuation tool call instead of stopping early")

        let secondPass = try await handler.handleToolLoopIfNeeded(
            response: firstPass.response,
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: availableTools,
            cancelledToolCallIds: { [] },
            runId: runId,
            userInput: "Complete implementation"
        )

        harnessTrue(secondPass.response.toolCalls?.isEmpty ?? true, "Second pass should finish without further tool calls")

        let finalPlan = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        let finalProgress = PlanChecklistTracker.progress(in: finalPlan)
        harnessEqual(finalProgress.completed, finalProgress.total, "Plan should be fully completed after continuation")
    }

    func testHarnessDoesNotInjectDeliveryGateRecoveryForNeedsWorkResponseWithoutToolCalls() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        historyCoordinator.append(ChatMessage(role: .user, content: "Implement role support end-to-end"))

        let firstToolCall = AIToolCall(id: "gate-recovery-1", name: "fake_tool", arguments: [:])

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(
                content: "<ide_reasoning>Reflection: Need to start execution.\nPlanning: Run first execution step.\nContinuity: More work remains.\nDelivery: NEEDS_WORK</ide_reasoning>Starting execution now.",
                toolCalls: [firstToolCall]
            ),
            AIServiceResponse(
                content: "<ide_reasoning>Reflection: First execution step completed.\nPlanning: Continue remaining work.\nContinuity: Pending tasks remain.\nDelivery: NEEDS_WORK</ide_reasoning>Done -> Next -> Path: Continue with remaining implementation.",
                toolCalls: nil
            )
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(
            aiService: scriptedService,
            codebaseIndex: nil,
            eventBus: MockEventBus()
        )
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let sendCoordinator = ConversationSendCoordinator(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        try await sendCoordinator.send(SendRequest(
            userInput: "Implement role support end-to-end",
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            runId: UUID().uuidString,
            availableTools: [FakeTool(name: "fake_tool")],
            cancelledToolCallIds: { [] },
            qaReviewEnabled: false,
            draftAssistantMessageId: nil
        ))

        let executedToolMessages = historyCoordinator.messages.filter {
            $0.isToolExecution && $0.toolStatus == .completed && $0.toolName == "fake_tool"
        }
        harnessEqual(executedToolMessages.count, 1, "Main path should not inject an additional delivery-gate execution retry")

        let capturedRequests = scriptedService.capturedHistoryRequests()
        let requestStages = capturedRequests.map { $0.stage?.rawValue ?? "nil" }.joined(separator: ",")
        harnessEqual(capturedRequests.count, 2, "Main path should stop after the first tool-loop handoff when no incomplete plan exists")
        harnessEqual(requestStages, "initial_response,tool_loop", "Main path should not invoke any delivery-driven follow-up stage")

        let finalAssistantOutput = historyCoordinator.messages.last(where: {
            $0.role == .assistant && !$0.isToolExecution
        })?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        harnessFalse(finalAssistantOutput.isEmpty, "Recovered flow should end with a user-visible assistant response")
        harnessTrue(finalAssistantOutput.contains("Done -> Next -> Path: Continue with remaining implementation."), "Without prompt-driven correction stages, the flow should preserve the existing handoff response")
    }

    func testHarnessFinalResponseRequestsConciseSummaryForGenericStatusMessage() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        historyCoordinator.append(ChatMessage(role: .user, content: "Implement login page end-to-end"))

        let firstToolCall = AIToolCall(id: "final-summary-1", name: "fake_tool", arguments: [:])

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(
                content: "<ide_reasoning>Reflection: Start execution.\nPlanning: Implement login page.\nContinuity: Work remains.\nDelivery: NEEDS_WORK</ide_reasoning>Starting implementation.",
                toolCalls: [firstToolCall]
            ),
            AIServiceResponse(
                content: "Implemented login page and authentication flow updates across the relevant components with validation and logout support integrated for review.",
                toolCalls: nil
            ),
            AIServiceResponse(
                content: "<ide_reasoning>Reflection: Completed implementation and can summarize.\nPlanning: None.\nContinuity: No remaining execution work.\nDelivery: DONE</ide_reasoning>Implemented the login page and authentication flow updates. Verification was not run. Status: DONE.",
                toolCalls: nil
            )
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(
            aiService: scriptedService,
            codebaseIndex: nil,
            eventBus: MockEventBus()
        )
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let sendCoordinator = ConversationSendCoordinator(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        try await sendCoordinator.send(SendRequest(
            userInput: "Implement login page end-to-end",
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            runId: UUID().uuidString,
            availableTools: [FakeTool(name: "fake_tool")],
            cancelledToolCallIds: { [] },
            qaReviewEnabled: false,
            draftAssistantMessageId: nil
        ))

        let capturedRequests = scriptedService.capturedHistoryRequests()
        let sawFinalResponseFollowup = capturedRequests.contains { request in
            request.stage == .final_response
        }
        let requestStages = capturedRequests.map { $0.stage?.rawValue ?? "nil" }
        harnessTrue(
            sawFinalResponseFollowup,
            "Expected final response follow-up when assistant output was generic"
        )
        harnessFalse(requestStages.contains("qa_tool_output_review"), "QA tool-output review stage should be omitted when qaReviewEnabled is false")
        harnessFalse(requestStages.contains("qa_quality_review"), "QA quality review stage should be omitted when qaReviewEnabled is false")

        let finalAssistantOutput = historyCoordinator.messages.last(where: {
            $0.role == .assistant && !$0.isToolExecution
        })?.content ?? ""
        harnessTrue(
            finalAssistantOutput.contains("Implemented the login page and authentication flow updates."),
            "Final assistant output should contain the concise final summary"
        )
        harnessFalse(finalAssistantOutput.contains("### Final Delivery Summary"), "Final assistant output should no longer require the old oversized scaffold")
    }

    func testHarnessRetriesWhenModelRequestsUserInputInsteadOfProceeding() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        historyCoordinator.append(ChatMessage(role: .user, content: "Implement login page end-to-end"))

        let firstToolCall = AIToolCall(id: "request-user-input-1", name: "fake_tool", arguments: [:])

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(
                content: "Can you provide the diff or confirm which login variant you want?",
                toolCalls: nil
            ),
            AIServiceResponse(
                content: "Proceeding with the safest default login flow implementation now.",
                toolCalls: [firstToolCall]
            ),
            AIServiceResponse(
                content: "Implemented the login page with a safe default email/password flow and no additional user input was required.",
                toolCalls: nil
            )
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(
            aiService: scriptedService,
            codebaseIndex: nil,
            eventBus: MockEventBus()
        )
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let sendCoordinator = ConversationSendCoordinator(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        try await sendCoordinator.send(SendRequest(
            userInput: "Implement login page end-to-end",
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            runId: UUID().uuidString,
            availableTools: [FakeTool(name: "fake_tool")],
            cancelledToolCallIds: { [] },
            qaReviewEnabled: false,
            draftAssistantMessageId: nil
        ))

        let capturedRequests = scriptedService.capturedHistoryRequests()
        let initialResponseRequestCount = capturedRequests.filter { request in
            request.stage == .initial_response
        }.count
        let focusedExecutionRetryCount = capturedRequests.filter { request in
            request.stage == .tool_loop && request.messages.contains(where: {
                $0.role == .system && $0.content.contains("You are a coding assistant in focused execution mode.")
            })
        }.count
        harnessEqual(initialResponseRequestCount, 1, "Expected only the original initial-response request before controller-owned execution takeover")
        harnessEqual(focusedExecutionRetryCount, 1, "Expected exactly one focused execution retry when the model asked the user for input")

        let executedToolMessages = historyCoordinator.messages.filter {
            $0.isToolExecution && $0.toolStatus == .completed && $0.toolName == "fake_tool"
        }
        harnessEqual(executedToolMessages.count, 1, "Autonomous retry should proceed into tool execution")

        let finalAssistantOutput = historyCoordinator.messages.last(where: {
            $0.role == .assistant && !$0.isToolExecution
        })?.content ?? ""
        harnessTrue(
            finalAssistantOutput.contains("safe default email/password flow"),
            "Final assistant output should reflect autonomous completion after rejecting the user-input handoff"
        )
    }

    func testRepeatedCompletedSignatureStallRecoversIntoContinuedExecution() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        let runId = UUID().uuidString

        await ConversationPlanStore.shared.setProjectRoot(projectRoot)
        await ConversationPlanStore.shared.set(
            conversationId: conversationId,
            plan: """
            # Implementation Plan

            - [x] Inspect current file
            - [x] Apply first edit
            - [ ] Finish remaining task
            """
        )

        let readCall = AIToolCall(id: "repeat-stall-read", name: "fake_tool", arguments: ["step": "read"])
        let writeCall = AIToolCall(id: "repeat-stall-write", name: "fake_tool", arguments: ["step": "write"])
        let finishCall = AIToolCall(id: "repeat-stall-finish", name: "fake_tool", arguments: ["step": "finish"])

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(content: "Read complete.", toolCalls: [writeCall]),
            AIServiceResponse(content: "Accidentally repeating the previous write step.", toolCalls: [writeCall]),
            AIServiceResponse(content: "Continuing with the remaining task now.", toolCalls: [finishCall]),
            AIServiceResponse(content: "<ide_reasoning>Analyze: done\nPlan: done\nAction: none\nDelivery: DONE</ide_reasoning>Completed all requested implementation steps.", toolCalls: nil)
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(
            aiService: scriptedService,
            codebaseIndex: nil,
            eventBus: MockEventBus()
        )
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let handler = ToolLoopHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        let availableTools: [AITool] = [FakeTool(name: "fake_tool")]

        let result = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(content: "Starting execution.", toolCalls: [readCall]),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: availableTools,
            cancelledToolCallIds: { [] },
            runId: runId,
            userInput: "Complete the task"
        )

        harnessTrue(result.response.toolCalls?.isEmpty ?? true, "Recovered execution should finish without dangling tool calls")
        harnessEqual(result.lastToolCalls.map(\.id), ["repeat-stall-finish"], "Tool loop should recover past the repeated completed signature and execute a new step")

        let followupRequests = scriptedService.capturedHistoryRequests()
        let requestStages = followupRequests.map { $0.stage?.rawValue ?? "nil" }
        harnessTrue(requestStages.filter { $0 == "tool_loop" }.count >= 3, "Expected repeated-signature recovery to stay in tool_loop instead of dropping directly to final_response")
    }

    func testHarnessTakesFocusedExecutionWhenModelPromisesImplementationWithoutToolCalls() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        historyCoordinator.append(ChatMessage(role: .user, content: "Implement login page end-to-end"))

        let firstToolCall = AIToolCall(id: "force-tool-followup-1", name: "fake_tool", arguments: [:])

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(
                content: "I will implement the login page now.",
                toolCalls: nil
            ),
            AIServiceResponse(
                content: "Proceeding with focused execution now.",
                toolCalls: [firstToolCall]
            ),
            AIServiceResponse(
                content: "Implemented the login page with the expected focused execution follow-up.",
                toolCalls: nil
            )
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(
            aiService: scriptedService,
            codebaseIndex: nil,
            eventBus: MockEventBus()
        )
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let sendCoordinator = ConversationSendCoordinator(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        try await sendCoordinator.send(SendRequest(
            userInput: "Implement login page end-to-end",
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            runId: UUID().uuidString,
            availableTools: [FakeTool(name: "fake_tool")],
            cancelledToolCallIds: { [] },
            qaReviewEnabled: false,
            draftAssistantMessageId: nil
        ))

        let capturedRequests = scriptedService.capturedHistoryRequests()
        let initialResponseRequestCount = capturedRequests.filter { request in
            request.stage == .initial_response
        }.count
        let focusedExecutionRetryCount = capturedRequests.filter { request in
            request.stage == .tool_loop && request.messages.contains(where: {
                $0.role == .system && $0.content.contains("You are a coding assistant in focused execution mode.")
            })
        }.count
        harnessEqual(initialResponseRequestCount, 1, "Expected only the original initial-response request before focused execution takeover for implementation promises")
        harnessEqual(focusedExecutionRetryCount, 1, "Expected exactly one focused execution retry when the model promised implementation without tool calls")

        let executedToolMessages = historyCoordinator.messages.filter {
            $0.isToolExecution && $0.toolStatus == .completed && $0.toolName == "fake_tool"
        }
        harnessEqual(executedToolMessages.count, 1, "Focused execution takeover should proceed into tool execution for implementation promises")
    }

    func testHarnessTakesFocusedExecutionWhenModelSignalsPendingExecutionWithoutToolCalls() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        historyCoordinator.append(ChatMessage(role: .user, content: "Implement login page end-to-end"))

        let firstToolCall = AIToolCall(id: "missing-tool-followup-1", name: "fake_tool", arguments: [:])

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(
                content: "Let me start with the safest first execution step.",
                toolCalls: nil
            ),
            AIServiceResponse(
                content: "Proceeding with focused execution now.",
                toolCalls: [firstToolCall]
            ),
            AIServiceResponse(
                content: "Implemented the login page after the missing-tool-call recovery path.",
                toolCalls: nil
            )
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(
            aiService: scriptedService,
            codebaseIndex: nil,
            eventBus: MockEventBus()
        )
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let sendCoordinator = ConversationSendCoordinator(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        try await sendCoordinator.send(SendRequest(
            userInput: "Implement login page end-to-end",
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            runId: UUID().uuidString,
            availableTools: [FakeTool(name: "fake_tool")],
            cancelledToolCallIds: { [] },
            qaReviewEnabled: false,
            draftAssistantMessageId: nil
        ))

        let capturedRequests = scriptedService.capturedHistoryRequests()
        let initialResponseRequestCount = capturedRequests.filter { request in
            request.stage == .initial_response
        }.count
        let focusedExecutionRetryCount = capturedRequests.filter { request in
            request.stage == .tool_loop && request.messages.contains(where: {
                $0.role == .system && $0.content.contains("You are a coding assistant in focused execution mode.")
            })
        }.count
        harnessEqual(initialResponseRequestCount, 1, "Expected only the original initial-response request before focused execution takeover for pending execution signals")
        harnessEqual(focusedExecutionRetryCount, 1, "Expected exactly one focused execution retry when the model signaled pending execution without tool calls")

        let executedToolMessages = historyCoordinator.messages.filter {
            $0.isToolExecution && $0.toolStatus == .completed && $0.toolName == "fake_tool"
        }
        harnessEqual(executedToolMessages.count, 1, "Focused execution takeover should proceed into tool execution for missing-tool-call recovery")
    }

    func testHarnessRetriesWhenModelReturnsReasoningOnly() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        historyCoordinator.append(ChatMessage(role: .user, content: "Implement login page end-to-end"))

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(
                content: "<ide_reasoning>Reflection: Need to implement login page.\nPlanning: Start with the safest default flow.\nContinuity: Work remains.</ide_reasoning>",
                toolCalls: nil
            ),
            AIServiceResponse(
                content: "Implemented the login page using the default flow assumptions and no extra user input was required.",
                toolCalls: nil
            )
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(
            aiService: scriptedService,
            codebaseIndex: nil,
            eventBus: MockEventBus()
        )
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let sendCoordinator = ConversationSendCoordinator(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        try await sendCoordinator.send(SendRequest(
            userInput: "Implement login page end-to-end",
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            runId: UUID().uuidString,
            availableTools: [FakeTool(name: "fake_tool")],
            cancelledToolCallIds: { [] },
            qaReviewEnabled: false,
            draftAssistantMessageId: nil
        ))

        let capturedRequests = scriptedService.capturedHistoryRequests()
        let initialResponseRetryCount = capturedRequests.filter { request in
            request.stage == .initial_response && request.messages.count > historyCoordinator.messages.filter { $0.role == .user }.count
        }.count
        let finalResponseRetryCount = capturedRequests.filter { request in
            request.stage == .final_response
        }.count
        harnessEqual(initialResponseRetryCount, 1, "Expected only the original initial-response request when the model returned only reasoning")
        harnessTrue(finalResponseRetryCount >= 1, "Expected deterministic final-response recovery for a reasoning-only initial reply")

        let finalAssistantOutput = historyCoordinator.messages.last(where: {
            $0.role == .assistant && !$0.isToolExecution
        })?.content ?? ""
        harnessTrue(
            finalAssistantOutput.contains("default flow assumptions"),
            "Final assistant output should come from the post-retry non-reasoning response"
        )
    }

    func testHarnessMalformedRawWriteFilesArgumentsFailClosedWithoutFileCorruption() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let appFile = projectRoot.appendingPathComponent("src/App.tsx")
        try FileManager.default.createDirectory(at: appFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "export default function App() { return null }\n".write(to: appFile, atomically: true, encoding: .utf8)

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        historyCoordinator.append(ChatMessage(role: .user, content: "could you add dashboard with demo charts ?"))

        let malformedRawWrite = AIServiceResponse(
            content: "<ide_reasoning>Reflection: Need to write dashboard files.\nPlanning: Create Dashboard.tsx and update App.tsx.\nContinuity: Work remains.\nDelivery: NEEDS_WORK</ide_reasoning>Applying targeted code changes now.",
            toolCalls: [
                AIToolCall(
                    id: "malformed-write-files-1",
                    name: "write_files",
                    arguments: [
                        "_raw_args_chunk": "{\"files\":[{\"weekly\":[1,2],\"categoryData\":[3,4]}],\"path\":\"src/App.tsx\"}"
                    ]
                )
            ]
        )

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(
                content: "<ide_reasoning>Reflection: Malformed write arguments failed and no files were changed.\nPlanning: Stop destructive retries.\nContinuity: Dashboard work remains unfinished.\nDelivery: NEEDS_WORK</ide_reasoning>Done → Next → Path: write_files arguments were invalid, so no changes were applied.",
                toolCalls: nil
            )
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(
            aiService: scriptedService,
            codebaseIndex: nil,
            eventBus: MockEventBus()
        )
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let sendCoordinator = ConversationSendCoordinator(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        try await sendCoordinator.send(SendRequest(
            userInput: "could you add dashboard with demo charts ?",
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            runId: UUID().uuidString,
            availableTools: [
                WriteFilesTool(
                    fileSystemService: FileSystemService(),
                    pathValidator: PathValidator(projectRoot: projectRoot),
                    eventBus: MockEventBus()
                )
            ],
            cancelledToolCallIds: { [] },
            qaReviewEnabled: false,
            draftAssistantMessageId: nil
        ))

        let finalAppContent = try String(contentsOf: appFile, encoding: .utf8)
        harnessEqual(
            finalAppContent,
            "export default function App() { return null }\n",
            "Malformed raw write_files arguments must not partially overwrite an existing file"
        )

        let toolFailureMessages = historyCoordinator.messages.filter {
            $0.isToolExecution && $0.toolStatus == .failed && $0.toolName == "write_files"
        }
        harnessEqual(toolFailureMessages.count, 1, "Malformed raw write_files payload should fail once and stop")

        let finalAssistantOutput = historyCoordinator.messages.last(where: {
            $0.role == .assistant && !$0.isToolExecution
        })?.content ?? ""
        harnessTrue(finalAssistantOutput.contains("NEEDS_WORK") || finalAssistantOutput.contains("Done → Next → Path"), "Final assistant output should report unfinished work instead of fabricated completion")
    }

    func testHarnessSkipsPlanningForSimpleInformationalAgentRequest() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(
                content: "<ide_reasoning>Analyze: User is asking about TypeScript migration completion status.\nResearch: Check remaining JavaScript files and typing gaps.\nPlan: Identify remaining files and continue migration.\nReflect: Migration is incomplete.\nAction: Check for remaining JavaScript files and convert them.\nDelivery: NEEDS_WORK</ide_reasoning>TypeScript migration is incomplete. I found several JavaScript files that still need conversion to TypeScript, and some components lack proper type definitions. I'll continue the migration to ensure full TypeScript coverage.",
                toolCalls: nil
            )
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(
            aiService: scriptedService,
            codebaseIndex: nil,
            eventBus: MockEventBus()
        )
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let sendCoordinator = ConversationSendCoordinator(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        try await sendCoordinator.send(SendRequest(
            userInput: "what about typescript migration, is that finished, complete?",
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            runId: UUID().uuidString,
            availableTools: [],
            cancelledToolCallIds: { [] },
            qaReviewEnabled: false,
            draftAssistantMessageId: nil
        ))

        let planMessages = historyCoordinator.messages.filter {
            $0.role == .assistant && $0.content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("# Implementation Plan")
        }
        harnessEqual(planMessages.count, 0, "Simple informational agent requests should not emit an implementation plan")

        let assistantMessages = historyCoordinator.messages.filter {
            $0.role == .assistant && !$0.isToolExecution
        }
        let finalAssistantOutput = assistantMessages.last?.content ?? ""
        harnessTrue(finalAssistantOutput.localizedCaseInsensitiveContains("TypeScript migration is incomplete"), "Current production path should preserve the informational answer content")
        harnessTrue(finalAssistantOutput.contains("I'll continue the migration") || finalAssistantOutput.contains("Delivery: NEEDS_WORK"), "Current production path should preserve the scripted assistant answer while skipping planning")
    }

    func testHarnessReproducesRepeatedMalformedDashboardMutationFailureLoop() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let dashboardFile = projectRoot.appendingPathComponent("src/components/Dashboard.tsx")
        try FileManager.default.createDirectory(at: dashboardFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "import React\n".write(to: dashboardFile, atomically: true, encoding: .utf8)

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId

        let malformedWriteOne = AIToolCall(
            id: "dashboard-write-1",
            name: "write_file",
            arguments: [
                "path": "src/components/Dashboard.tsx",
                "_raw_args_chunk": "{\"weekly\":[1,2],\"categoryData\":[3,4]",
                "_tool_call_id": "dashboard-write-1",
                "_conversation_id": conversationId
            ]
        )
        let malformedWriteTwo = AIToolCall(
            id: "dashboard-write-2",
            name: "write_file",
            arguments: [
                "path": "src/components/Dashboard.tsx",
                "_raw_args_chunk": "{\"stats\":[{\"label\":\"Done\"}]",
                "_tool_call_id": "dashboard-write-2",
                "_conversation_id": conversationId
            ]
        )
        let malformedEdit = AIToolCall(
            id: "dashboard-edit-1",
            name: "replace_in_file",
            arguments: [
                "path": "src/components/Dashboard.tsx",
                "_raw_args_chunk": "{\"content\":\"replace dashboard body\"",
                "_tool_call_id": "dashboard-edit-1",
                "_conversation_id": conversationId
            ]
        )

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(
                content: "Done → Creating complete Dashboard component with bar/pie charts and stats cards using proper write_file parameters. Next: applying targeted code changes in project files.",
                toolCalls: [malformedWriteOne]
            ),
            AIServiceResponse(
                content: "Done → Completing Dashboard.tsx with charts and stats cards using targeted edits instead of full overwrite. Next: applying targeted code changes in project files.",
                toolCalls: [malformedEdit]
            ),
            AIServiceResponse(
                content: "<ide_reasoning>plan_delta: Will create full Dashboard.tsx with bar/pie charts using Chart.js and react-chartjs-2. next_action: known_risks: File structure exists in src/components/, need to verify package.json has chart dependencies. delivery_state: needs_work</ide_reasoning>",
                toolCalls: nil
            )
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(
            aiService: scriptedService,
            codebaseIndex: nil,
            eventBus: MockEventBus()
        )
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let sendCoordinator = ConversationSendCoordinator(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        try await sendCoordinator.send(SendRequest(
            userInput: "could you add dashboard with demo charts ?",
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            runId: UUID().uuidString,
            availableTools: [
                WriteFileTool(
                    fileSystemService: FileSystemService(),
                    pathValidator: PathValidator(projectRoot: projectRoot),
                    eventBus: MockEventBus()
                ),
                ReplaceInFileTool(
                    fileSystemService: FileSystemService(),
                    pathValidator: PathValidator(projectRoot: projectRoot),
                    eventBus: MockEventBus()
                )
            ],
            cancelledToolCallIds: { [] },
            qaReviewEnabled: false,
            draftAssistantMessageId: nil
        ))

        let failedToolMessages = historyCoordinator.messages.filter {
            $0.isToolExecution && $0.toolStatus == .failed && ($0.toolName == "write_file" || $0.toolName == "replace_in_file")
        }
        harnessEqual(failedToolMessages.count, 2, "Production path should stop after two consecutive non-recoverable Dashboard mutation failures")

        let dashboardContent = try String(contentsOf: dashboardFile, encoding: .utf8)
        harnessEqual(dashboardContent, "import React\n", "Production path should preserve the original Dashboard.tsx content when malformed mutations are rejected")

        let finalAssistantOutput = historyCoordinator.messages.last(where: {
            $0.role == .assistant && !$0.isToolExecution
        })?.content ?? ""
        harnessTrue(finalAssistantOutput.localizedCaseInsensitiveContains("needs_work") || finalAssistantOutput.localizedCaseInsensitiveContains("delivery_state: needs_work"), "Production path should end repeated malformed mutation failures in an unfinished state")
        harnessEqual(scriptedService.remainingResponsesCount(), 0, "Harness should consume the full scripted failure sequence from the real sandbox pattern")
    }

    func testHarnessDeduplicatesDuplicateToolCallsInSingleIteration() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(content: "<ide_reasoning>Analyze: done\nPlan: done\nAction: none\nDelivery: DONE</ide_reasoning>Finished.", toolCalls: nil)
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: scriptedService, codebaseIndex: nil, eventBus: MockEventBus())
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let handler = ToolLoopHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        let counter = ToolExecutionCounter()
        let duplicateA = AIToolCall(id: "dup-1", name: "counting_tool", arguments: ["path": "src"]) 
        let duplicateB = AIToolCall(id: "dup-2", name: "counting_tool", arguments: ["path": "src"]) 
        let duplicateC = AIToolCall(id: "dup-3", name: "counting_tool", arguments: ["path": "src"]) 

        let result = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(content: "Exploring project.", toolCalls: [duplicateA, duplicateB, duplicateC]),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: [CountingTool(name: "counting_tool", counter: counter)],
            cancelledToolCallIds: { [] },
            runId: UUID().uuidString,
            userInput: "Convert static app to SSR"
        )

        harnessEqual(result.lastToolCalls.count, 1, "Duplicate tool calls in one assistant message should be collapsed")
        let executionCount = await counter.count
        harnessEqual(executionCount, 1, "Only one deduplicated tool call should execute")
    }

    func testHarnessShortCircuitsRepeatedToolBatchesToAvoidSlowDropoutLoop() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        let runId = UUID().uuidString

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(content: "Still scanning.", toolCalls: [AIToolCall(id: "loop-2", name: "counting_tool", arguments: ["query": "src"]) ]),
            AIServiceResponse(content: "Still scanning again.", toolCalls: [AIToolCall(id: "loop-3", name: "counting_tool", arguments: ["query": "src"]) ]),
            AIServiceResponse(content: "Final summary after repeated loop detection.", toolCalls: nil)
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: scriptedService, codebaseIndex: nil, eventBus: MockEventBus())
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let handler = ToolLoopHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        let counter = ToolExecutionCounter()
        let firstLoopCall = AIToolCall(id: "loop-1", name: "counting_tool", arguments: ["query": "src"]) 

        let result = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(content: "Start scan.", toolCalls: [firstLoopCall]),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: [CountingTool(name: "counting_tool", counter: counter)],
            cancelledToolCallIds: { [] },
            runId: runId,
            userInput: "Convert static app to SSR"
        )

        harnessTrue(result.response.toolCalls?.isEmpty ?? true, "Handler should stop repeated batches and switch to final response")
        harnessEqual(result.response.content, "Final summary after repeated loop detection.")
        let executionCount = await counter.count
        harnessEqual(executionCount, 1, "Exact repeated signature batch should be intercepted before the second execution")
    }

    func testHarnessDiversifiesRepeatedWriteTargetLoopBeforeThirdRewrite() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        let runId = UUID().uuidString

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(content: "Retrying write.", toolCalls: [
                AIToolCall(id: "write-loop-2", name: "write_file", arguments: [
                    "path": "src/index.html",
                    "content": "v2"
                ])
            ]),
            AIServiceResponse(content: "Retrying write again.", toolCalls: [
                AIToolCall(id: "write-loop-3", name: "write_file", arguments: [
                    "path": "src/index.html",
                    "content": "v3"
                ])
            ]),
            AIServiceResponse(content: "Diversified execution after repeated same-target writes.", toolCalls: nil)
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: scriptedService, codebaseIndex: nil, eventBus: MockEventBus())
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let handler = ToolLoopHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        let counter = ToolExecutionCounter()
        let initialWriteCall = AIToolCall(id: "write-loop-1", name: "write_file", arguments: [
            "path": "src/index.html",
            "content": "v1"
        ])

        let result = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(content: "Start writing.", toolCalls: [initialWriteCall]),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: [CountingTool(name: "write_file", counter: counter)],
            cancelledToolCallIds: { [] },
            runId: runId,
            userInput: "Create a React app scaffold"
        )

        harnessTrue(result.response.toolCalls?.isEmpty ?? true)
        harnessEqual(
            result.response.content,
            "Diversified execution after repeated same-target writes."
        )

        let executionCount = await counter.count
        harnessEqual(executionCount, 2, "Third repeated write to the same target should be intercepted before execution")
    }

    func testHarnessStopsRepeatedPseudoToolCallContentWithoutStructuredToolCalls() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        let runId = UUID().uuidString

        await ConversationPlanStore.shared.setProjectRoot(projectRoot)
        await ConversationPlanStore.shared.set(
            conversationId: conversationId,
            plan: """
            # Implementation Plan

            - [ ] Migrate app to SSR
            """
        )

        let loopCall = AIToolCall(id: "loop-pseudo-1", name: "counting_tool", arguments: ["query": "src"])
        let pseudoToolCallContent = """
        <ide_reasoning>
        Analyze: Migrating to SSR.
        Plan: Create Next.js app.
        Action: Begin migration.
        </ide_reasoning>
        Tool calls:create_next_app("my-ssr-app", "--use-npm")
        """

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(content: pseudoToolCallContent, toolCalls: nil),
            AIServiceResponse(content: pseudoToolCallContent, toolCalls: nil)
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: scriptedService, codebaseIndex: nil, eventBus: MockEventBus())
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let handler = ToolLoopHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        let counter = ToolExecutionCounter()
        let result = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(content: "Start execution.", toolCalls: [loopCall]),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: [CountingTool(name: "counting_tool", counter: counter)],
            cancelledToolCallIds: { [] },
            runId: runId,
            userInput: "Migrate app to SSR"
        )

        harnessTrue(result.response.toolCalls?.isEmpty ?? true)
        harnessTrue(
            result.response.content?.contains("Tool calls:create_next_app") ?? false,
            "Handler should return textual pseudo-tool-call content without entering a repeated execution loop"
        )
        let executionCount = await counter.count
        harnessEqual(executionCount, 1, "Pseudo textual tool calls must not trigger repeated execution loops")
    }

    func testHarnessSuppressesRepeatedAssistantStepUpdatesDuringToolLoop() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        ToolExecutionTelemetry.shared.reset()

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        let runId = UUID().uuidString

        let repeatedAssistantContent = "I am still scanning files before making changes."
        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(content: repeatedAssistantContent, toolCalls: [
                AIToolCall(id: "repeat-update-2", name: "counting_tool", arguments: ["query": "src", "phase": "scan-2"])
            ]),
            AIServiceResponse(content: repeatedAssistantContent, toolCalls: [
                AIToolCall(id: "repeat-update-3", name: "counting_tool", arguments: ["query": "src", "phase": "scan-3"])
            ]),
            AIServiceResponse(content: "Completed after suppressing duplicate assistant updates.", toolCalls: nil)
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: scriptedService, codebaseIndex: nil, eventBus: MockEventBus())
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let handler = ToolLoopHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        let counter = ToolExecutionCounter()
        let firstCall = AIToolCall(id: "repeat-update-1", name: "counting_tool", arguments: ["query": "src", "phase": "scan-1"])

        _ = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(content: repeatedAssistantContent, toolCalls: [firstCall]),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: [CountingTool(name: "counting_tool", counter: counter)],
            cancelledToolCallIds: { [] },
            runId: runId,
            userInput: "Inspect project and then implement SSR migration"
        )

        let repeatedAssistantMessages = historyCoordinator.messages.filter {
            $0.role == .assistant && $0.content == repeatedAssistantContent
        }
        harnessEqual(
            repeatedAssistantMessages.count,
            0,
            "Raw repeated assistant text should be normalized into concise progress updates"
        )

        let telemetrySummary = ToolExecutionTelemetry.shared.summary
        harnessGreaterThanOrEqual(
            telemetrySummary.repeatedAssistantUpdates,
            0,
            "Telemetry should remain valid when repeated text is normalized"
        )
    }

    func testHarnessCapturesRepeatedToolCallSignaturesAndCompletionFeedback() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        ToolExecutionTelemetry.shared.reset()

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        let runId = UUID().uuidString

        let repeatedToolArguments: [String: Any] = ["query": "src"]
        let firstCall = AIToolCall(id: "repeat-signature-1", name: "counting_tool", arguments: repeatedToolArguments)

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(content: "Retrying same inspection call.", toolCalls: [
                AIToolCall(id: "repeat-signature-2", name: "counting_tool", arguments: repeatedToolArguments)
            ]),
            AIServiceResponse(content: "Done after repeated call.", toolCalls: nil)
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: scriptedService, codebaseIndex: nil, eventBus: MockEventBus())
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let handler = ToolLoopHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        _ = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(content: "Starting repeated signature repro.", toolCalls: [firstCall]),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: [CountingTool(name: "counting_tool", counter: ToolExecutionCounter())],
            cancelledToolCallIds: { [] },
            runId: runId,
            userInput: "Inspect and proceed"
        )

        let telemetrySummary = ToolExecutionTelemetry.shared.summary
        harnessGreaterThanOrEqual(
            telemetrySummary.repeatedToolCallSignatures,
            1,
            "Telemetry should capture repeated tool-call signatures across iterations"
        )

        let capturedRequests = scriptedService.capturedHistoryRequests()
        let hadCompletionFeedback = capturedRequests.contains { request in
            request.messages.contains { message in
                message.role == .system &&
                message.content.contains("Tool calls completed successfully this iteration.")
            }
        }
        harnessTrue(
            hadCompletionFeedback,
            "Tool-loop follow-up should include explicit completion feedback for already executed call signatures"
        )
    }

    func testHarnessNormalizesProgressUpdateWithWhatHowWhereAndCompactPath() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(content: "", toolCalls: nil)
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: scriptedService, codebaseIndex: nil, eventBus: MockEventBus())
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let handler = ToolLoopHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        let firstCall = AIToolCall(
            id: "read-template-switcher",
            name: "read_file",
            arguments: ["path": "/Users/jack/Projects/osx/osx-ide/sandbox/todo/NewProject/todo-app/src/components/TemplateSwitcher.tsx"]
        )

        _ = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(content: "", toolCalls: [firstCall]),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: [CountingTool(name: "read_file", counter: ToolExecutionCounter())],
            cancelledToolCallIds: { [] },
            runId: UUID().uuidString,
            userInput: "Inspect TemplateSwitcher and continue"
        )

        let assistantUpdates = historyCoordinator.messages.filter {
            $0.role == .assistant &&
                !($0.toolCalls?.isEmpty ?? true) &&
                !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        harnessFalse(assistantUpdates.isEmpty, "Expected at least one assistant progress update")

        guard let update = assistantUpdates.last else {
            harnessNote("No assistant progress update captured")
            return
        }

        harnessTrue(update.content.contains("Next:"), "Progress update should include a next-step clause")
        harnessTrue(update.content.contains("TemplateSwitcher.tsx"), "Progress update should preserve useful file context")
        harnessFalse(update.content.contains("/Users/jack/Projects"), "Progress update should avoid absolute path verbosity")
        harnessFalse(update.content.localizedCaseInsensitiveContains("update (step"), "Progress update should avoid low-value step counters")

        let reasoning = update.reasoning ?? ""
        harnessTrue(reasoning.contains("What:"), "Reasoning should include What")
        harnessTrue(reasoning.contains("How:"), "Reasoning should include How")
        harnessTrue(reasoning.contains("Where:"), "Reasoning should include Where")
    }

    func testHarnessShortCircuitsRepeatedReadOnlyCheckpointLoop() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(content: "Still checking checkpoints.", toolCalls: [
                AIToolCall(id: "checkpoint-loop-2", name: "checkpoint_list", arguments: [:])
            ]),
            AIServiceResponse(content: "Checking checkpoints again.", toolCalls: [
                AIToolCall(id: "checkpoint-loop-3", name: "checkpoint_list", arguments: [:])
            ]),
            AIServiceResponse(content: "Stopped repeated read-only checkpoint loop and returning summary.", toolCalls: nil)
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: scriptedService, codebaseIndex: nil, eventBus: MockEventBus())
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let handler = ToolLoopHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        let counter = ToolExecutionCounter()
        let firstCall = AIToolCall(id: "checkpoint-loop-1", name: "checkpoint_list", arguments: [:])

        let result = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(content: "Start checkpoint scan.", toolCalls: [firstCall]),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: [CountingTool(name: "checkpoint_list", counter: counter)],
            cancelledToolCallIds: { [] },
            runId: UUID().uuidString,
            userInput: "Inspect and use checkpoints to continue execution"
        )

        harnessTrue(result.response.toolCalls?.isEmpty ?? true, "Read-only checkpoint loop should be stopped")
        harnessEqual(
            result.response.content,
            "Stopped repeated read-only checkpoint loop and returning summary."
        )

        let executionCount = await counter.count
        harnessEqual(executionCount, 1, "Exact repeated read-only signature batch should be intercepted before the second execution")
    }

    func testHarnessTransitionsStalledReadOnlyLoopIntoFocusedExecution() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        let runId = UUID().uuidString

        var scriptedResponses: [AIServiceResponse] = (2...10).map { iteration in
            AIServiceResponse(
                content: "Checking checkpoints pass \(iteration).",
                toolCalls: [AIToolCall(
                    id: "checkpoint-loop-\(iteration)",
                    name: "checkpoint_list",
                    arguments: ["page": iteration]
                )]
            )
        }
        scriptedResponses.append(contentsOf: [
            AIServiceResponse(content: "Proceeding with concrete execution now.", toolCalls: [
                AIToolCall(id: "write-after-stall-1", name: "write_file", arguments: [
                    "path": "src/App.tsx",
                    "content": "updated"
                ])
            ]),
            AIServiceResponse(content: "Completed execution after stalled read-only recovery.", toolCalls: nil)
        ])

        let scriptedService = ScriptedAIService(responses: scriptedResponses)

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: scriptedService, codebaseIndex: nil, eventBus: MockEventBus())
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let handler = ToolLoopHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        let counter = ToolExecutionCounter()
        let firstLoopCall = AIToolCall(id: "checkpoint-loop-1", name: "checkpoint_list", arguments: [:])

        let result = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(content: "Start checkpoint scan.", toolCalls: [firstLoopCall]),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: [
                CountingTool(name: "checkpoint_list", counter: counter),
                CountingTool(name: "write_file", counter: counter)
            ],
            cancelledToolCallIds: { [] },
            runId: runId,
            userInput: "Inspect checkpoints, then implement the missing dashboard fix"
        )

        harnessTrue(result.response.toolCalls?.isEmpty ?? true, "Stalled read-only loop should end after focused execution recovery completes")
        harnessEqual(result.response.content, "Completed execution after stalled read-only recovery.")

        let capturedRequests = scriptedService.capturedHistoryRequests()
        let focusedExecutionRetryCount = capturedRequests.filter { request in
            request.stage == .tool_loop && request.messages.contains(where: {
                $0.role == .system
                    && $0.content.contains("You are a coding assistant in focused execution mode.")
                    && $0.content.contains("The tool loop stalled after read-only or non-executing progress.")
            })
        }.count
        harnessEqual(focusedExecutionRetryCount, 1, "Expected a single controller-owned focused execution retry for stalled read-only loops")

        let executionCount = await counter.count
        harnessEqual(executionCount, 10, "Read-only loop should execute until the read-only stall threshold, then recover into one concrete execution step")
    }

    func testHarnessEscalatesRecoveredReadOnlyContinuationIntoMutationRecovery() async throws {
        let projectRoot = makeTempDir()
        defer { cleanup(projectRoot) }

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let conversationId = historyCoordinator.currentConversationId
        let runId = UUID().uuidString

        await ConversationPlanStore.shared.setProjectRoot(projectRoot)
        await ConversationPlanStore.shared.set(
            conversationId: conversationId,
            plan: """
            # Implementation Plan

            - [x] Inspect project structure
            - [ ] Add SSR server entrypoint
            - [ ] Update package metadata
            """
        )

        let scriptedService = ScriptedAIService(responses: [
            AIServiceResponse(
                content: "<ide_reasoning>Reflection: structure inspected.\nPlanning: continue remaining implementation.\nContinuity: work remains.\nDelivery: NEEDS_WORK</ide_reasoning>Done -> Next -> Path: continue with SSR implementation.",
                toolCalls: nil
            ),
            AIServiceResponse(
                content: "Need another quick check before editing.",
                toolCalls: [
                    AIToolCall(id: "recovered-read-only-1", name: "index_read_file", arguments: ["path": "package.json"])
                ]
            ),
            AIServiceResponse(
                content: "Proceeding with concrete mutation now.",
                toolCalls: [
                    AIToolCall(id: "recovered-write-1", name: "write_file", arguments: [
                        "path": "server.js",
                        "content": "export const server = true"
                    ])
                ]
            ),
            AIServiceResponse(
                content: "<ide_reasoning>Reflection: completed remaining implementation.\nPlanning: done.\nContinuity: none.\nDelivery: DONE</ide_reasoning>All checklist items are complete.",
                toolCalls: nil
            )
        ])

        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: scriptedService, codebaseIndex: nil, eventBus: MockEventBus())
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        let handler = ToolLoopHandler(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )

        let result = try await handler.handleToolLoopIfNeeded(
            response: AIServiceResponse(content: "Initial execution completed.", toolCalls: [
                AIToolCall(id: "initial-write-1", name: "write_file", arguments: [
                    "path": "index.html",
                    "content": "<html></html>"
                ])
            ]),
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            availableTools: [
                FakeTool(name: "write_file"),
                FakeTool(name: "index_read_file")
            ],
            cancelledToolCallIds: { [] },
            runId: runId,
            userInput: "Finish the SSR migration"
        )

        harnessTrue(result.response.toolCalls?.isEmpty ?? true, "Recovered read-only continuation should finish after escalated mutation recovery")
        harnessTrue(
            result.response.content?.contains("All checklist items are complete.") ?? false,
            "Recovered read-only continuation should preserve the final completion message"
        )

        let capturedRequests = scriptedService.capturedHistoryRequests()
        let focusedExecutionRequests = capturedRequests.filter { request in
            request.stage == .tool_loop && request.messages.contains(where: {
                $0.role == .system &&
                    $0.content.contains("You are a coding assistant in focused execution mode.")
            })
        }
        harnessGreaterThanOrEqual(
            focusedExecutionRequests.count,
            2,
            "Incomplete-plan continuation with recovered read-only tools should trigger focused execution recovery and then escalation"
        )

        let finalPlan = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        let finalProgress = PlanChecklistTracker.progress(in: finalPlan)
        harnessEqual(finalProgress.completed, finalProgress.total, "Escalated mutation recovery should complete remaining plan items")
    }

    private func harnessTrue(_ condition: @autoclosure () -> Bool, _ message: String = "") {
        let ok = condition()
        print(ok ? "[HARNESS][PASS] \(message)" : "[HARNESS][WARN] \(message)")
    }

    private func harnessFalse(_ condition: @autoclosure () -> Bool, _ message: String = "") {
        harnessTrue(!condition(), message)
    }

    private func harnessEqual<T: Equatable>(_ lhs: @autoclosure () -> T, _ rhs: @autoclosure () -> T, _ message: String = "") {
        let left = lhs()
        let right = rhs()
        let status = (left == right) ? "[HARNESS][PASS]" : "[HARNESS][WARN]"
        print("\(status) \(message) lhs=\(left) rhs=\(right)")
    }

    private func harnessGreaterThanOrEqual<T: Comparable>(
        _ lhs: @autoclosure () -> T,
        _ rhs: @autoclosure () -> T,
        _ message: String = ""
    ) {
        let left = lhs()
        let right = rhs()
        let status = (left >= right) ? "[HARNESS][PASS]" : "[HARNESS][WARN]"
        print("\(status) \(message) lhs=\(left) rhs=\(right)")
    }

    private func harnessNote(_ message: String) {
        print("[HARNESS][WARN] \(message)")
    }

    private func makeHistoryCoordinator(projectRoot: URL) -> ChatHistoryCoordinator {
        let historyManager = ChatHistoryManager()
        return ChatHistoryCoordinator(historyManager: historyManager, projectRoot: projectRoot)
    }

    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("osx_ide_toolloop_harness_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
