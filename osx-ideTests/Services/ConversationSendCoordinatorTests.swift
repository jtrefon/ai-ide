import XCTest

@testable import osx_ide

@MainActor
final class ConversationSendCoordinatorTests: XCTestCase {
    private final class SequenceAIService: AIService, @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [AIServiceResponse]

        init(responses: [AIServiceResponse]) {
            self.responses = responses
        }

        func sendMessage(
            _ request: AIServiceMessageWithProjectRootRequest
        ) async throws -> AIServiceResponse {
            _ = request
            return dequeueResponse()
        }

        func sendMessage(
            _ request: AIServiceHistoryRequest
        ) async throws -> AIServiceResponse {
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

    private struct FakeLocalModelFileStore: LocalModelProcessAIService.ModelFileStoring {
        let installedModelIds: Set<String>
        let modelDirectoryURL: URL

        func isModelInstalled(_ model: LocalModelDefinition) -> Bool {
            installedModelIds.contains(model.id)
        }

        func modelDirectory(modelId _: String) throws -> URL {
            modelDirectoryURL
        }
    }

    private struct FakeLocalModelGenerator: LocalModelProcessAIService.LocalModelGenerating {
        let output: String

        func generate(modelDirectory _: URL, prompt _: String, runId _: String?) async throws -> String {
            output
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

    func testSendExecutesToolLoopAndAppendsFinalAssistantMessage() async throws {
        let toolCallId = UUID().uuidString
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let toolCalls = [AIToolCall(id: toolCallId, name: "fake_tool", arguments: ["a": 1])]

        let aiService = makeSequenceAIService(toolCalls: toolCalls)
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: aiService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )

        try await sendCoordinator.send(makeSendRequest(
            conversationId: historyCoordinator.currentConversationId,
            projectRoot: projectRoot
        ))

        assertAssistantMessages(historyCoordinator: historyCoordinator)
        assertToolMessages(historyCoordinator: historyCoordinator, toolCallId: toolCallId)
    }

    func testSendRetriesWhenResponseContainsOnlyReasoning() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let aiService = SequenceAIService(responses: [
            AIServiceResponse(content: reasoningOnlyContent(), toolCalls: nil),
            AIServiceResponse(content: "Final answer", toolCalls: nil)
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
            availableTools: []
        ))

        XCTAssertTrue(
            historyCoordinator.messages.contains(where: { $0.role == .assistant && $0.content.contains("Final answer") })
        )
    }

    func testSendProvidesFallbackWhenResponseIsEmpty() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let aiService = SequenceAIService(responses: [
            AIServiceResponse(content: "", toolCalls: nil),
            AIServiceResponse(content: "", toolCalls: nil)
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
            availableTools: []
        ))
        
        XCTAssertTrue(
            historyCoordinator.messages.contains(where: { $0.role == .assistant && $0.content.contains("I wasn't able to generate a final response") })
        )
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

        let tools = makeFileTools(projectRoot: projectRoot)
        try await sendCoordinator.send(makeSendRequest(
            conversationId: historyCoordinator.currentConversationId,
            projectRoot: projectRoot,
            availableTools: tools
        ))

        let expectedURL = projectRoot.appendingPathComponent("harness/lifecycle.txt")
        let fileContent = try String(contentsOf: expectedURL, encoding: .utf8)
        XCTAssertEqual(fileContent, "two")

        assertToolMessages(historyCoordinator: historyCoordinator, toolCallId: writeCallId)
        assertToolMessages(historyCoordinator: historyCoordinator, toolCallId: replaceCallId)
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

        let tools = makeFileTools(projectRoot: projectRoot)
        try await sendCoordinator.send(makeSendRequest(
            conversationId: historyCoordinator.currentConversationId,
            projectRoot: projectRoot,
            availableTools: tools
        ))

        for path in reactTodoRequiredPaths() {
            let url = projectRoot.appendingPathComponent(path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Expected file not created: \(url.path)")
        }

        assertToolMessages(historyCoordinator: historyCoordinator, toolCallId: writeFilesCallId)
    }

    func testHarnessAgentGreetingInOfflineModeReturnsPlainText() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let userDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let settingsStore = SettingsStore(userDefaults: userDefaults)

        let selectedModelId = "qwen/Qwen3-4B-Instruct-2507@cdbee75"
        let setupSelectionStore = LocalModelSelectionStore(settingsStore: settingsStore)
        setupSelectionStore.setSelectedModelId(selectedModelId)
        setupSelectionStore.setOfflineModeEnabled(true)

        guard let selectedModel = LocalModelCatalog.model(id: selectedModelId) else {
            throw XCTSkip("Selected local model is not present in LocalModelCatalog: \(selectedModelId)")
        }
        guard LocalModelFileStore.isModelInstalled(selectedModel) else {
            throw XCTSkip("Local model not downloaded, skipping native inference harness test: \(selectedModelId)")
        }

        let localSelectionStore = LocalModelSelectionStore(settingsStore: settingsStore)
        let routingSelectionStore = LocalModelSelectionStore(settingsStore: settingsStore)

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

        // Provide at least one tool to match Agent mode reality.
        let tools = makeFileTools(projectRoot: projectRoot)
        try await sendCoordinator.send(makeSendRequest(
            conversationId: historyCoordinator.currentConversationId,
            projectRoot: projectRoot,
            availableTools: tools
        ))

        let assistantMessages = historyCoordinator.messages.filter { $0.role == .assistant }
        let assistantContent = assistantMessages.map(\.content).joined(separator: "\n")
        XCTAssertFalse(assistantContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func makeSequenceAIService(toolCalls: [AIToolCall]) -> SequenceAIService {
        let completeReasoningPrefix =
            "<ide_reasoning>Analyze: Details\nResearch: Details\nPlan: Details\n" +
            "Reflect: Details\nAction: Call fake_tool\nDelivery: DONE</ide_reasoning>"
        return SequenceAIService(responses: [
            AIServiceResponse(content: completeReasoningPrefix + "Call tool", toolCalls: toolCalls),
            AIServiceResponse(content: completeReasoningPrefix + "Final answer", toolCalls: nil)
        ])
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
            errorManager: AIToolExecutorNoopErrorManager(),
            projectRoot: projectRoot
        )
        let toolExecutionCoordinator = ToolExecutionCoordinator(toolExecutor: toolExecutor)
        return ConversationSendCoordinator(
            historyCoordinator: historyCoordinator,
            aiInteractionCoordinator: aiInteractionCoordinator,
            toolExecutionCoordinator: toolExecutionCoordinator
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

    private func makeSendRequest(
        conversationId: String,
        projectRoot: URL,
        availableTools: [AITool] = [FakeTool(name: "fake_tool", response: "ok")],
        qaReviewEnabled: Bool = false,
        draftAssistantMessageId: UUID? = nil
    ) -> SendRequest {
        SendRequest(
            userInput: "Hello",
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            runId: UUID().uuidString,
            availableTools: availableTools,
            cancelledToolCallIds: { [] },
            qaReviewEnabled: qaReviewEnabled,
            draftAssistantMessageId: draftAssistantMessageId
        )
    }

    private func reasoningOnlyContent() -> String {
        """
        <ide_reasoning>
        Analyze: Details
        Research: Details
        Plan: Details
        Reflect: Details
        </ide_reasoning>
        """
    }

    private func assertAssistantMessages(historyCoordinator: ChatHistoryCoordinator) {
        print("History coordinator messages: \(historyCoordinator.messages)")
        XCTAssertTrue(
            historyCoordinator.messages.contains(where: { $0.role == .assistant && $0.toolCalls?.isEmpty == false })
        )
        XCTAssertTrue(
            historyCoordinator.messages.contains(where: { $0.role == .assistant && ($0.content.contains("Done") || $0.content.contains("Final answer")) })
        )
    }

    private func assertToolMessages(historyCoordinator: ChatHistoryCoordinator, toolCallId: String) {
        let toolMessages = historyCoordinator.messages.filter {
            $0.role == .tool && $0.toolCallId == toolCallId
        }

        let observedToolMessages = historyCoordinator.messages
            .filter { $0.role == .tool }
            .map {
                "\($0.toolName ?? "nil"):" +
                    "\($0.toolStatus?.rawValue ?? "nil"):" +
                    "\($0.toolCallId ?? "nil")"
            }

        XCTAssertFalse(
            toolMessages.isEmpty,
            "Expected tool messages for toolCallId=\(toolCallId). " +
                "Observed tool messages: \(observedToolMessages)"
        )

        let observedToolStatuses = toolMessages.map {
            "\($0.toolName ?? "nil"):" +
                "\($0.toolStatus?.rawValue ?? "nil")"
        }

        XCTAssertTrue(
            toolMessages.contains(where: { $0.toolStatus == .completed }),
            "Expected at least one completed tool message for toolCallId=\(toolCallId). " +
                "Observed: \(observedToolStatuses)"
        )
    }
}
