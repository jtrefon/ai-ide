import XCTest

@testable import osx_ide

@MainActor
final class AgenticHarnessTests: XCTestCase {
    // MARK: - Performance Testing Support
    
    /// Run a performance-measured local inference test
    /// Returns metrics for analysis
    func runPerformanceTest(
        testId: String,
        modelId: String,
        projectRoot: URL,
        userInput: String,
        expectedMinTokens: Int = 10,
        maxDuration: TimeInterval = 60.0
    ) async throws -> InferencePerformanceMetrics? {
        guard let model = LocalModelCatalog.model(id: modelId) else {
            throw XCTSkip("Model not in catalog: \(modelId)")
        }
        guard LocalModelFileStore.isModelInstalled(model) else {
            throw XCTSkip("Model not downloaded: \(modelId)")
        }
        
        let selectionStore = LocalModelSelectionStore()
        await selectionStore.setSelectedModelId(modelId)
        await selectionStore.setOfflineModeEnabled(true)
        
        let localService = LocalModelProcessAIService(selectionStore: selectionStore)
        
        var timer = InferenceTimer()
        var outputTokenCount = 0
        var firstTokenRecorded = false
        
        // Create a mock streaming event bus to count tokens
        let eventBus = EventBus()
        let cancellable = eventBus.subscribe(to: LocalModelStreamingChunkEvent.self) { event in
            if !firstTokenRecorded {
                timer.recordFirstToken()
                firstTokenRecorded = true
            }
            outputTokenCount += event.chunk.split(separator: " ").count
        }
        
        let response = try await localService.sendMessage(AIServiceHistoryRequest(
            messages: [ChatMessage(role: .user, content: userInput)],
            context: nil,
            tools: nil,
            mode: .chat,
            projectRoot: projectRoot
        ))
        
        cancellable.cancel()
        
        // Estimate token counts (rough approximation)
        let promptTokens = userInput.split(separator: " ").count
        let outputTokens = max(outputTokenCount, response.content?.split(separator: " ").count ?? 0)
        
        let metrics = timer.finalize(
            testId: testId,
            modelId: modelId,
            turn: 1,
            promptTokens: promptTokens,
            outputTokens: outputTokens
        )
        
        // Log metrics
        print(metrics.summary)
        
        // Record for aggregation
        await InferenceMetricsCollector.shared.recordMetrics(metrics)
        
        // Basic assertions
        XCTAssertNotNil(response.content)
        XCTAssertGreaterThan(outputTokens, expectedMinTokens, "Output should have at least \(expectedMinTokens) tokens")
        XCTAssertLessThan(metrics.totalDuration, maxDuration, "Inference should complete within \(maxDuration)s")
        
        return metrics
    }
    
    // MARK: - Existing Tests
    @MainActor
    private final class NoopErrorManager: ObservableObject, ErrorManagerProtocol {
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

            let message: String
            if context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                message = error.localizedDescription
            } else {
                message = "\(context): \(error.localizedDescription)"
            }
            handle(.unknown(message))
        }

        func dismissError() {
            currentError = nil
            showErrorAlert = false
        }
    }

    private final class SequenceAIService: AIService, @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [AIServiceResponse]

        init(responses: [AIServiceResponse]) {
            self.responses = responses
        }

        func sendMessage(_ request: AIServiceMessageWithProjectRootRequest) async throws -> AIServiceResponse {
            _ = request
            return dequeueResponse()
        }

        func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse {
            _ = request
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
            lock.lock()
            defer { lock.unlock() }
            guard !responses.isEmpty else {
                return AIServiceResponse(content: "(no more responses)", toolCalls: nil)
            }
            return responses.removeFirst()
        }
    }

    private struct FakeTool: AITool, @unchecked Sendable {
        let name: String
        let description: String = "fake"
        var parameters: [String: Any] { ["type": "object", "properties": [:]] }

        let response: String

        func execute(arguments _: ToolArguments) async throws -> String {
            response
        }
    }

    func testHarnessOrchestrationLifecycleCreatesAndEditsFile() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let writeCallId = UUID().uuidString
        let replaceCallId = UUID().uuidString

        let toolCalls = [
            AIToolCall(id: writeCallId, name: "write_file", arguments: [
                "path": "harness/lifecycle.txt",
                "content": "one"
            ]),
            AIToolCall(id: replaceCallId, name: "replace_in_file", arguments: [
                "path": "harness/lifecycle.txt",
                "old_text": "one",
                "new_text": "two"
            ])
        ]

        let aiService = SequenceAIService(responses: [
            AIServiceResponse(content: "Call tools", toolCalls: toolCalls),
            AIServiceResponse(content: "Done", toolCalls: nil)
        ])

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: aiService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )

        try await sendCoordinator.send(makeSendRequest(
            conversationId: historyCoordinator.currentConversationId,
            projectRoot: projectRoot,
            availableTools: makeFileTools(projectRoot: projectRoot)
        ))

        let expectedURL = projectRoot.appendingPathComponent("harness/lifecycle.txt")
        let fileContent = try String(contentsOf: expectedURL, encoding: .utf8)
        XCTAssertEqual(fileContent, "two")
    }

    func testHarnessAgentFlowEmitsPlanningUpdatesAndToolExecutionTrail() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let runId = UUID().uuidString
        let toolCallId = UUID().uuidString
        let toolCalls = [
            AIToolCall(id: toolCallId, name: "write_file", arguments: [
                "path": "harness/planning.txt",
                "content": "planned"
            ])
        ]

        let aiService = SequenceAIService(responses: [
            AIServiceResponse(content: "Call tools", toolCalls: toolCalls),
            AIServiceResponse(content: "Done", toolCalls: nil)
        ])

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: aiService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )

        try await sendCoordinator.send(makeSendRequest(
            conversationId: historyCoordinator.currentConversationId,
            projectRoot: projectRoot,
            runId: runId,
            availableTools: makeFileTools(projectRoot: projectRoot)
        ))

        let assistantMessages = historyCoordinator.messages.filter { $0.role == .assistant }
        let assistantText = assistantMessages.map(\.content).joined(separator: "\n")
        XCTAssertTrue(assistantText.contains("Progress update: strategic plan prepared."))
        XCTAssertTrue(assistantText.contains("Progress update: tactical execution plan prepared."))
        XCTAssertTrue(assistantText.contains("# Strategic Plan"))
        XCTAssertTrue(assistantText.contains("## Tactical Plan"))

        let toolExecutionMessages = historyCoordinator.messages.filter { $0.isToolExecution }
        XCTAssertTrue(toolExecutionMessages.contains { $0.toolName == "write_file" })
        let writeMessage = try XCTUnwrap(toolExecutionMessages.last(where: { $0.toolName == "write_file" }))
        let envelope = try XCTUnwrap(ToolExecutionEnvelope.decode(from: writeMessage.content))
        XCTAssertEqual(envelope.toolName, "write_file")
        XCTAssertEqual(envelope.status, .completed)
        XCTAssertNotNil(envelope.preview)
        XCTAssertTrue(envelope.preview?.contains("Write file") == true)
        XCTAssertTrue(envelope.preview?.contains("harness/planning.txt") == true)

        let snapshots = try readSnapshots(
            projectRoot: projectRoot,
            conversationId: historyCoordinator.currentConversationId,
            runId: runId
        )
        let phases = snapshots.map(\.phase)
        XCTAssertTrue(phases.contains(StrategicPlanningNode.idValue))
        XCTAssertTrue(phases.contains(TacticalPlanningNode.idValue))
        XCTAssertTrue(phases.contains("tool_loop"))
    }

    func testHarnessReactTodoAppCreatesViteScaffoldFiles() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let writeFilesCallId = UUID().uuidString
        let toolCalls = [makeReactTodoWriteFilesCall(id: writeFilesCallId)]

        let aiService = SequenceAIService(responses: [
            AIServiceResponse(content: "Scaffold", toolCalls: toolCalls),
            AIServiceResponse(content: "Done", toolCalls: nil)
        ])

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: aiService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )

        try await sendCoordinator.send(makeSendRequest(
            conversationId: historyCoordinator.currentConversationId,
            projectRoot: projectRoot,
            availableTools: makeFileTools(projectRoot: projectRoot)
        ))

        for path in reactTodoRequiredPaths() {
            let url = projectRoot.appendingPathComponent(path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Expected file not created: \(url.path)")
        }
    }

    func testHarnessAgentFlowPersistsStrategicAndTacticalPlan() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        await ConversationPlanStore.shared.setProjectRoot(projectRoot)

        let aiService = SequenceAIService(responses: [
            AIServiceResponse(content: "Done", toolCalls: nil)
        ])

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: aiService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )

        try await sendCoordinator.send(makeSendRequest(
            conversationId: historyCoordinator.currentConversationId,
            projectRoot: projectRoot,
            availableTools: makeFileTools(projectRoot: projectRoot)
        ))

        let persistedPlan = await ConversationPlanStore.shared.get(conversationId: historyCoordinator.currentConversationId)
        let plan = try XCTUnwrap(persistedPlan)
        XCTAssertTrue(plan.contains("# Strategic Plan"))
        XCTAssertTrue(plan.contains("## Tactical Plan"))
    }

    func testHarnessOrchestrationSnapshotsIncludePlanningPhases() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let runId = UUID().uuidString
        let aiService = SequenceAIService(responses: [
            AIServiceResponse(content: "Done", toolCalls: nil)
        ])

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: aiService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )

        try await sendCoordinator.send(makeSendRequest(
            conversationId: historyCoordinator.currentConversationId,
            projectRoot: projectRoot,
            runId: runId,
            availableTools: makeFileTools(projectRoot: projectRoot)
        ))

        let snapshots = try readSnapshots(
            projectRoot: projectRoot,
            conversationId: historyCoordinator.currentConversationId,
            runId: runId
        )
        let phases = snapshots.map(\.phase)

        let strategicIndex = try XCTUnwrap(phases.firstIndex(of: StrategicPlanningNode.idValue))
        let tacticalIndex = try XCTUnwrap(phases.firstIndex(of: TacticalPlanningNode.idValue))
        XCTAssertLessThan(strategicIndex, tacticalIndex)
    }

    func testHarnessAgentGreetingInOfflineModeReturnsPlainText() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let selectedModelId = "mlx-community/Qwen3-4B-Instruct-2507-4bit@50d4277"
        let setupSelectionStore = LocalModelSelectionStore()
        await setupSelectionStore.setSelectedModelId(selectedModelId)
        await setupSelectionStore.setOfflineModeEnabled(true)

        guard let selectedModel = LocalModelCatalog.model(id: selectedModelId) else {
            throw XCTSkip("Selected local model is not present in LocalModelCatalog: \(selectedModelId)")
        }
        guard LocalModelFileStore.isModelInstalled(selectedModel) else {
            throw XCTSkip("Local model not downloaded, skipping native inference harness test: \(selectedModelId)")
        }

        let localSelectionStore = setupSelectionStore
        let routingSelectionStore = setupSelectionStore

        let localService = LocalModelProcessAIService(selectionStore: localSelectionStore)
        let openRouterService = SequenceAIService(responses: [
            AIServiceResponse(content: "Hello from remote", toolCalls: nil)
        ])

        let routingService = ModelRoutingAIService(
            openRouterService: openRouterService,
            localService: localService,
            selectionStore: routingSelectionStore
        )

        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: routingService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )

        try await sendCoordinator.send(makeSendRequest(
            conversationId: historyCoordinator.currentConversationId,
            projectRoot: projectRoot,
            availableTools: makeFileTools(projectRoot: projectRoot)
        ))

        let assistantMessages = historyCoordinator.messages.filter { $0.role == .assistant }
        let assistantContent = assistantMessages.map(\.content).joined(separator: "\n")
        XCTAssertFalse(assistantContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func makeHistoryCoordinator(projectRoot: URL) -> ChatHistoryCoordinator {
        let historyManager = ChatHistoryManager()
        let historyCoordinator = ChatHistoryCoordinator(historyManager: historyManager, projectRoot: projectRoot)
        historyCoordinator.append(ChatMessage(role: .user, content: "Hello"))
        return historyCoordinator
    }

    private func makeSendCoordinator(
        aiService: AIService,
        historyCoordinator: ChatHistoryCoordinator,
        projectRoot: URL
    ) -> ConversationSendCoordinator {
        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: aiService, codebaseIndex: nil)
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: NoopErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        return ConversationSendCoordinator(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
        )
    }

    private func makeSendRequest(
        conversationId: String,
        projectRoot: URL,
        userInput: String = "Hello",
        runId: String = UUID().uuidString,
        availableTools: [AITool]
    ) -> SendRequest {
        SendRequest(
            userInput: userInput,
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            runId: runId,
            availableTools: availableTools,
            cancelledToolCallIds: { [] },
            qaReviewEnabled: false,
            draftAssistantMessageId: nil
        )
    }

    private func makeFileTools(projectRoot: URL) -> [AITool] {
        let fileSystemService = FileSystemService()
        let eventBus = EventBus()
        let pathValidator = PathValidator(projectRoot: projectRoot)
        return [
            WriteFileTool(fileSystemService: fileSystemService, pathValidator: pathValidator, eventBus: eventBus),
            WriteFilesTool(fileSystemService: fileSystemService, pathValidator: pathValidator, eventBus: eventBus),
            ReplaceInFileTool(fileSystemService: fileSystemService, pathValidator: pathValidator, eventBus: eventBus)
        ]
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

    private func reactTodoRequiredPaths() -> [String] {
        [
            "harness/react-todo/package.json",
            "harness/react-todo/index.html",
            "harness/react-todo/src/main.jsx",
            "harness/react-todo/src/App.jsx"
        ]
    }

    private func makeReactTodoWriteFilesCall(id: String) -> AIToolCall {
        let files: [[String: Any]] = [
            [
                "path": "harness/react-todo/package.json",
                "content": "{\n  \"name\": \"react-todo\"\n}"
            ],
            [
                "path": "harness/react-todo/index.html",
                "content": "<!doctype html><html><body><div id=\"root\"></div></body></html>"
            ],
            [
                "path": "harness/react-todo/src/main.jsx",
                "content": "import React from 'react'\nimport ReactDOM from 'react-dom/client'\nimport App from './App.jsx'\nReactDOM.createRoot(document.getElementById('root')).render(<App />)\n"
            ],
            [
                "path": "harness/react-todo/src/App.jsx",
                "content": "export default function App(){return <h1>Todo</h1>}\n"
            ]
        ]

        return AIToolCall(id: id, name: "write_files", arguments: ["files": files])
    }
    
    // MARK: - Performance Tests
    
    /// Test local inference performance with the Qwen 4-bit model
    /// Measures time-to-first-token and tokens-per-second
    func testLocalInferencePerformance() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        
        let modelId = "mlx-community/Qwen3-4B-Instruct-2507-4bit@50d4277"
        
        let metrics = try await runPerformanceTest(
            testId: "local-inference-baseline",
            modelId: modelId,
            projectRoot: projectRoot,
            userInput: "Write a short greeting message in one sentence.",
            expectedMinTokens: 5,
            maxDuration: 30.0
        )
        
        // Log performance baseline
        if let metrics = metrics {
            print("Performance baseline recorded:")
            print("  Time to first token: \(String(format: "%.2f", metrics.timeToFirstToken))s")
            print("  Tokens per second: \(String(format: "%.1f", metrics.tokensPerSecond))")
            print("  Total duration: \(String(format: "%.2f", metrics.totalDuration))s")
        }
    }
    
    /// Test multi-turn conversation performance to measure KV cache effectiveness
    func testLocalInferenceMultiTurnPerformance() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        
        let modelId = "mlx-community/Qwen3-4B-Instruct-2507-4bit@50d4277"
        
        guard let model = LocalModelCatalog.model(id: modelId) else {
            throw XCTSkip("Model not in catalog: \(modelId)")
        }
        guard LocalModelFileStore.isModelInstalled(model) else {
            throw XCTSkip("Model not downloaded: \(modelId)")
        }
        
        let selectionStore = LocalModelSelectionStore()
        await selectionStore.setSelectedModelId(modelId)
        await selectionStore.setOfflineModeEnabled(true)
        
        let localService = LocalModelProcessAIService(selectionStore: selectionStore)
        
        // First turn
        var timer1 = InferenceTimer()
        var outputTokens1 = 0
        var firstToken1 = false
        
        let eventBus = EventBus()
        let cancellable1 = eventBus.subscribe(to: LocalModelStreamingChunkEvent.self) { event in
            if !firstToken1 {
                timer1.recordFirstToken()
                firstToken1 = true
            }
            outputTokens1 += event.chunk.split(separator: " ").count
        }
        
        _ = try await localService.sendMessage(AIServiceHistoryRequest(
            messages: [ChatMessage(role: .user, content: "My name is Alice.")],
            context: nil,
            tools: nil,
            mode: .chat,
            projectRoot: projectRoot
        ))
        cancellable1.cancel()
        
        let metrics1 = timer1.finalize(
            testId: "multi-turn-1",
            modelId: modelId,
            turn: 1,
            promptTokens: 4,
            outputTokens: outputTokens1
        )
        
        // Second turn (should benefit from KV cache if model stays loaded)
        var timer2 = InferenceTimer()
        var outputTokens2 = 0
        var firstToken2 = false
        
        let cancellable2 = eventBus.subscribe(to: LocalModelStreamingChunkEvent.self) { event in
            if !firstToken2 {
                timer2.recordFirstToken()
                firstToken2 = true
            }
            outputTokens2 += event.chunk.split(separator: " ").count
        }
        
        _ = try await localService.sendMessage(AIServiceHistoryRequest(
            messages: [
                ChatMessage(role: .user, content: "My name is Alice."),
                ChatMessage(role: .assistant, content: "Hello Alice!"),
                ChatMessage(role: .user, content: "What is my name?")
            ],
            context: nil,
            tools: nil,
            mode: .chat,
            projectRoot: projectRoot
        ))
        cancellable2.cancel()
        
        let metrics2 = timer2.finalize(
            testId: "multi-turn-2",
            modelId: modelId,
            turn: 2,
            promptTokens: 10,
            outputTokens: outputTokens2
        )
        
        // Record both for comparison
        await InferenceMetricsCollector.shared.recordMetrics(metrics1)
        await InferenceMetricsCollector.shared.recordMetrics(metrics2)
        
        print("Multi-turn performance comparison:")
        print("  Turn 1 - TTFT: \(String(format: "%.2f", metrics1.timeToFirstToken))s, TPS: \(String(format: "%.1f", metrics1.tokensPerSecond))")
        print("  Turn 2 - TTFT: \(String(format: "%.2f", metrics2.timeToFirstToken))s, TPS: \(String(format: "%.1f", metrics2.tokensPerSecond))")
        
        // Second turn should not be significantly slower (model should remain loaded)
        // Allow 50% tolerance for variance
        if metrics1.timeToFirstToken == 0 {
            XCTAssertLessThanOrEqual(metrics2.timeToFirstToken, 0,
                                     "Second turn TTFT should not be significantly worse than first turn")
        } else {
            XCTAssertLessThan(metrics2.timeToFirstToken, metrics1.timeToFirstToken * 1.5,
                              "Second turn TTFT should not be significantly worse than first turn")
        }
    }
}
