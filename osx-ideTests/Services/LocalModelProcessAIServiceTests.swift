import XCTest
import Tokenizers
@preconcurrency import MLXLMCommon

@testable import osx_ide

@MainActor
final class LocalModelProcessAIServiceTests: XCTestCase {
    private struct FakeFileStore: LocalModelProcessAIService.ModelFileStoring {
        let installed: Bool
        let directory: URL

        func isModelInstalled(_ model: LocalModelDefinition) -> Bool {
            _ = model
            return installed
        }

        func modelDirectory(modelId: String) throws -> URL {
            _ = modelId
            return directory
        }
    }

    private final class SpyGenerator: LocalModelProcessAIService.LocalModelGenerating, @unchecked Sendable {
        struct CapturedMessage: Sendable {
            let role: Chat.Message.Role
            let content: String
        }

        private(set) var lastModelDirectory: URL?
        private(set) var lastCapturedMessages: [CapturedMessage]?
        private(set) var lastTools: [ToolSpec]?
        private(set) var lastToolCallFormat: ToolCallFormat?
        private(set) var lastRunId: String?
        private(set) var lastContextLength: Int?
        private(set) var lastConversationId: String?
        private let response: AIServiceResponse

        init(response: AIServiceResponse = AIServiceResponse(content: "local-response", toolCalls: nil)) {
            self.response = response
        }

        func generate(modelDirectory: URL, messages: sending [Chat.Message], tools: [ToolSpec]?, toolCallFormat: ToolCallFormat?, runId: String?, contextLength: Int, conversationId: String?) async throws -> AIServiceResponse {
            lastModelDirectory = modelDirectory
            lastCapturedMessages = messages.map { CapturedMessage(role: $0.role, content: $0.content) }
            lastTools = tools
            lastToolCallFormat = toolCallFormat
            lastRunId = runId
            lastContextLength = contextLength
            lastConversationId = conversationId
            return response
        }

        func snapshot() -> (URL?, [CapturedMessage]?, [ToolSpec]?, ToolCallFormat?, String?, Int?, String?) {
            (lastModelDirectory, lastCapturedMessages, lastTools, lastToolCallFormat, lastRunId, lastContextLength, lastConversationId)
        }
    }

    private struct StubSettingsLoader: OpenRouterSettingsLoading {
        let settings: OpenRouterSettings

        func load(includeApiKey: Bool) -> OpenRouterSettings {
            _ = includeApiKey
            return settings
        }
    }

    private struct NoopTool: AITool {
        let name: String
        let description: String = "noop"

        var parameters: [String: Any] {
            ["type": "object", "properties": [:]]
        }

        func execute(arguments: ToolArguments) async throws -> String {
            _ = arguments
            return "ok"
        }
    }

    func testSendMessageBuildsPromptAndPassesContextLengthToGenerator() async throws {
        let selectedModelId = "mlx-community/Qwen3-4B-Instruct-2507-4bit@50d4277"
        let selectionStore = LocalModelSelectionStore()
        await selectionStore.setSelectedModelId(selectedModelId)

        guard let model = LocalModelCatalog.model(id: selectedModelId) else {
            XCTFail("Missing expected local model in catalog")
            return
        }

        let modelDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileStore = FakeFileStore(installed: true, directory: modelDirectory)
        let generator = SpyGenerator()
        let settingsLoader = StubSettingsLoader(settings: .empty)

        let service = LocalModelProcessAIService(
            selectionStore: selectionStore,
            fileStore: fileStore,
            generator: generator,
            settingsStore: settingsLoader,
            memoryPressureObserverFactory: { _ in nil }
        )

        let runId = UUID().uuidString
        let response = try await service.sendMessage(AIServiceHistoryRequest(
            messages: [ChatMessage(role: .user, content: "Implement feature")],
            context: "Repo context",
            tools: [NoopTool(name: "write_file")],
            mode: .agent,
            projectRoot: modelDirectory,
            runId: runId,
            stage: .initial_response
        ))

        XCTAssertEqual(response.content, "local-response")

        let (capturedDirectory, capturedMessages, capturedTools, capturedToolCallFormat, capturedRunId, capturedContextLength, _) = generator.snapshot()
        XCTAssertEqual(capturedDirectory, modelDirectory)
        XCTAssertEqual(capturedRunId, runId)
        XCTAssertEqual(capturedContextLength, LocalModelFileStore.contextLength(for: model))
        
        // Verify tools were passed
        XCTAssertNotNil(capturedTools)
        XCTAssertEqual(capturedTools?.count, 1)
        XCTAssertEqual((capturedTools?.first?["function"] as? [String: any Sendable])?["name"] as? String, "write_file")
        
        // Verify toolCallFormat is passed from model definition
        XCTAssertEqual(capturedToolCallFormat, .json)

        // Verify structured messages with proper roles
        let messages = try XCTUnwrap(capturedMessages)
        XCTAssertGreaterThanOrEqual(messages.count, 3) // system + context + user
        
        // First message should be system
        XCTAssertEqual(messages[0].role, .system)
        XCTAssertTrue(messages[0].content.contains("CURRENT MODE: AGENT"))
        XCTAssertTrue(messages[0].content.contains("<ide_reasoning>"))
        
        // Second message should be context
        XCTAssertEqual(messages[1].role, .system)
        XCTAssertTrue(messages[1].content.contains("Repo context"))
        
        // Last message should be user
        let lastMessage = messages.last!
        XCTAssertEqual(lastMessage.role, .user)
        XCTAssertEqual(lastMessage.content, "Implement feature")
    }

    func testSendMessagePrefersCustomSystemPromptFromSettings() async throws {
        let selectedModelId = "mlx-community/Qwen3-4B-Instruct-2507-4bit@50d4277"
        let selectionStore = LocalModelSelectionStore()
        await selectionStore.setSelectedModelId(selectedModelId)

        let modelDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileStore = FakeFileStore(installed: true, directory: modelDirectory)
        let generator = SpyGenerator()
        let settingsLoader = StubSettingsLoader(settings: OpenRouterSettings(
            apiKey: "",
            model: "",
            baseURL: OpenRouterSettings.empty.baseURL,
            systemPrompt: "CUSTOM_SYSTEM_PROMPT",
            reasoningEnabled: true,
            toolPromptMode: .fullStatic,
            ragEnabledDuringToolLoop: true
        ))

        let service = LocalModelProcessAIService(
            selectionStore: selectionStore,
            fileStore: fileStore,
            generator: generator,
            settingsStore: settingsLoader,
            memoryPressureObserverFactory: { _ in nil }
        )

        _ = try await service.sendMessage(AIServiceHistoryRequest(
            messages: [ChatMessage(role: .user, content: "Hello")],
            context: nil,
            tools: [NoopTool(name: "write_file")],
            mode: .agent,
            projectRoot: modelDirectory
        ))

        let (_, capturedMessages, _, _, _, _, _) = generator.snapshot()
        let messages = try XCTUnwrap(capturedMessages)
        XCTAssertEqual(messages[0].role, .system)
        XCTAssertTrue(messages[0].content.contains("CUSTOM_SYSTEM_PROMPT"))
    }

    func testSendMessageReturnsToolCallsFromGenerator() async throws {
        let selectedModelId = "mlx-community/Qwen3-4B-Instruct-2507-4bit@50d4277"
        let selectionStore = LocalModelSelectionStore()
        await selectionStore.setSelectedModelId(selectedModelId)

        let modelDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileStore = FakeFileStore(installed: true, directory: modelDirectory)
        let generator = SpyGenerator(response: AIServiceResponse(content: nil, toolCalls: [
            AIToolCall(id: "tool-call-1", name: "write_file", arguments: ["path": "foo.swift"])
        ]))
        let settingsLoader = StubSettingsLoader(settings: .empty)

        let service = LocalModelProcessAIService(
            selectionStore: selectionStore,
            fileStore: fileStore,
            generator: generator,
            settingsStore: settingsLoader,
            memoryPressureObserverFactory: { _ in nil }
        )

        let response = try await service.sendMessage(AIServiceHistoryRequest(
            messages: [ChatMessage(role: .user, content: "Create file")],
            context: nil,
            tools: [NoopTool(name: "write_file")],
            mode: .agent,
            projectRoot: modelDirectory
        ))

        XCTAssertNil(response.content)
        XCTAssertEqual(response.toolCalls?.count, 1)
        XCTAssertEqual(response.toolCalls?.first?.name, "write_file")
    }

    func testRecoverTextualToolCallsParsesToolCallsEnvelope() {
        let content = """
        ```json
        {
          "tool_calls": [
            {
              "id": "call_1",
              "type": "function",
              "function": {
                "name": "write_file",
                "arguments": {
                  "path": "Sources/App.swift",
                  "content": "print(1)"
                }
              }
            }
          ]
        }
        ```
        """

        let calls = LocalModelProcessAIService.NativeMLXGenerator.recoverTextualToolCalls(from: content)

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.id, "call_1")
        XCTAssertEqual(calls.first?.name, "write_file")
        XCTAssertEqual(calls.first?.arguments["path"] as? String, "Sources/App.swift")
    }

    func testRecoverTextualToolCallsReturnsEmptyForNonJsonText() {
        let content = "I'll update files now using tools."
        let calls = LocalModelProcessAIService.NativeMLXGenerator.recoverTextualToolCalls(from: content)
        XCTAssertTrue(calls.isEmpty)
    }
}
