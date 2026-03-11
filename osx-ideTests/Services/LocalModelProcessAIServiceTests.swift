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

        func runtimeModelDirectory(for model: LocalModelDefinition) throws -> URL {
            _ = model
            return directory
        }
    }

    private final class SpyGenerator: LocalModelProcessAIService.LocalModelGenerating, @unchecked Sendable {
        struct CapturedMessage: Sendable {
            let role: String
            let content: String
        }

        private(set) var lastModelDirectory: URL?
        private(set) var lastCapturedMessages: [CapturedMessage]?
        private(set) var lastTools: [ToolSpec]?
        private(set) var lastToolCallFormat: ToolCallFormat?
        private(set) var lastRunId: String?
        private(set) var lastContextLength: Int?
        private(set) var lastMaxOutputTokens: Int?
        private(set) var lastConversationId: String?
        private(set) var lastImageCount: Int?
        private(set) var lastVideoCount: Int?
        private let response: AIServiceResponse

        init(response: AIServiceResponse = AIServiceResponse(content: "local-response", toolCalls: nil)) {
            self.response = response
        }

        func generate(modelDirectory: URL, userInput: sending UserInput, tools: [ToolSpec]?, toolCallFormat: ToolCallFormat?, runId: String?, contextLength: Int, maxOutputTokens: Int, conversationId: String?) async throws -> AIServiceResponse {
            lastModelDirectory = modelDirectory
            switch userInput.prompt {
            case .chat(let messages):
                lastCapturedMessages = messages.map { CapturedMessage(role: $0.role.rawValue, content: $0.content) }
            case .messages(let messages):
                lastCapturedMessages = messages.map {
                    CapturedMessage(
                        role: ($0["role"] as? String) ?? "unknown",
                        content: ($0["content"] as? String) ?? ""
                    )
                }
            case .text(let text):
                lastCapturedMessages = [CapturedMessage(role: "user", content: text)]
            }
            lastTools = tools
            lastToolCallFormat = toolCallFormat
            lastRunId = runId
            lastContextLength = contextLength
            lastMaxOutputTokens = maxOutputTokens
            lastConversationId = conversationId
            lastImageCount = userInput.images.count
            lastVideoCount = userInput.videos.count
            return response
        }

        func snapshot() -> (URL?, [CapturedMessage]?, [ToolSpec]?, ToolCallFormat?, String?, Int?, Int?, String?, Int?, Int?) {
            (lastModelDirectory, lastCapturedMessages, lastTools, lastToolCallFormat, lastRunId, lastContextLength, lastMaxOutputTokens, lastConversationId, lastImageCount, lastVideoCount)
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

        let (capturedDirectory, capturedMessages, capturedTools, capturedToolCallFormat, capturedRunId, capturedContextLength, capturedMaxOutputTokens, _, _, _) = generator.snapshot()
        XCTAssertEqual(capturedDirectory, modelDirectory)
        XCTAssertEqual(capturedRunId, runId)
        XCTAssertEqual(capturedContextLength, min(LocalModelFileStore.contextLength(for: model), 2048))
        XCTAssertEqual(capturedMaxOutputTokens, min(768, max(384, (capturedContextLength ?? 0) / 3)))
        
        // Verify tools were passed
        XCTAssertNotNil(capturedTools)
        XCTAssertEqual(capturedTools?.count, 1)
        let messages = try XCTUnwrap(capturedMessages)
        XCTAssertEqual(messages[0].role, "system")
        XCTAssertTrue(messages[0].content.contains("When tools are available"))
        XCTAssertFalse(messages[0].content.contains("<ide_reasoning>"))
        
        XCTAssertTrue(messages[0].content.contains("Project context:\nRepo context"))

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[1].role, "user")
        XCTAssertEqual(messages[1].content, "Implement feature")
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
            reasoningMode: .modelAndAgent,
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

        let (_, capturedMessages, _, _, _, _, _, _, _, _) = generator.snapshot()
        let messages = try XCTUnwrap(capturedMessages)
        XCTAssertEqual(messages[0].role, "system")
        XCTAssertTrue(messages[0].content.contains("CUSTOM_SYSTEM_PROMPT"))
    }

    func testSendMessageDoesNotInjectReasoningPromptDuringToolLoop() async throws {
        let selectedModelId = "mlx-community/Qwen3-4B-Instruct-2507-4bit@50d4277"
        let selectionStore = LocalModelSelectionStore()
        await selectionStore.setSelectedModelId(selectedModelId)

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

        _ = try await service.sendMessage(AIServiceHistoryRequest(
            messages: [ChatMessage(role: .user, content: "Create file")],
            context: nil,
            tools: [NoopTool(name: "write_file")],
            mode: .agent,
            projectRoot: modelDirectory,
            stage: .tool_loop
        ))

        let (_, capturedMessages, _, _, _, _, _, _, _, _) = generator.snapshot()
        let messages = try XCTUnwrap(capturedMessages)
        XCTAssertEqual(messages[0].role, "system")
        XCTAssertFalse(messages[0].content.contains("<ide_reasoning>"))
        XCTAssertFalse(messages[0].content.contains("Native model reasoning is allowed"))
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

    func testSendMessagePassesImageAttachmentsIntoUserInput() async throws {
        let selectedModelId = "mlx-community/Qwen3.5-4B-MLX-4bit@main"
        let selectionStore = LocalModelSelectionStore()
        await selectionStore.setSelectedModelId(selectedModelId)

        let modelDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileStore = FakeFileStore(installed: true, directory: modelDirectory)
        let generator = SpyGenerator()
        let settingsLoader = StubSettingsLoader(settings: .empty)
        let imageURL = modelDirectory.appendingPathComponent("sample.png")

        let service = LocalModelProcessAIService(
            selectionStore: selectionStore,
            fileStore: fileStore,
            generator: generator,
            settingsStore: settingsLoader,
            memoryPressureObserverFactory: { _ in nil }
        )

        _ = try await service.sendMessage(AIServiceHistoryRequest(
            messages: [
                ChatMessage(
                    role: .user,
                    content: "Describe this image",
                    mediaAttachments: [.init(kind: .image, url: imageURL)]
                )
            ],
            mediaAttachments: [.init(kind: .image, url: imageURL)],
            context: nil,
            tools: nil,
            mode: .chat,
            projectRoot: modelDirectory
        ))

        let (_, capturedMessages, _, _, _, _, _, _, imageCount, videoCount) = generator.snapshot()
        let messages = try XCTUnwrap(capturedMessages)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[1].role, "user")
        XCTAssertEqual(messages[1].content, "Describe this image")
        XCTAssertEqual(imageCount, 1)
        XCTAssertEqual(videoCount, 0)
    }

    func testSendMessagePreservesTextualToolLikeOutputWhenUsingSpyGenerator() async throws {
        let selectedModelId = "mlx-community/Qwen3-4B-Instruct-2507-4bit@50d4277"
        let selectionStore = LocalModelSelectionStore()
        await selectionStore.setSelectedModelId(selectedModelId)

        let modelDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileStore = FakeFileStore(installed: true, directory: modelDirectory)
        let textualToolLikeOutput = """
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
        let generator = SpyGenerator(response: AIServiceResponse(content: textualToolLikeOutput, toolCalls: nil))
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

        XCTAssertEqual(response.content, textualToolLikeOutput)
        XCTAssertNil(response.toolCalls)
    }

    func testFallbackParserRecoversJSONCodeBlockToolCall() {
        let textualToolLikeOutput = """
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

        let toolCalls = LocalModelProcessAIService.NativeMLXGenerator.extractFallbackToolCalls(
            from: textualToolLikeOutput,
            toolsWereProvided: true,
            structuredToolCallsWereDetected: false,
            toolCallFormat: .json
        )

        XCTAssertEqual(toolCalls?.count, 1)
        XCTAssertEqual(toolCalls?.first?.name, "write_file")
        XCTAssertEqual(toolCalls?.first?.arguments["path"] as? String, "Sources/App.swift")
        XCTAssertEqual(toolCalls?.first?.arguments["content"] as? String, "print(1)")
    }

    func testSendMessagePreservesWrappedJSONToolCallOutputWhenUsingSpyGenerator() async throws {
        let selectedModelId = "mlx-community/Qwen3.5-4B-MLX-4bit@main"
        let selectionStore = LocalModelSelectionStore()
        await selectionStore.setSelectedModelId(selectedModelId)

        let modelDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileStore = FakeFileStore(installed: true, directory: modelDirectory)
        let wrappedJSONOutput = #"{"tool_calls":[{"name":"write_file","arguments":{"path":"Sources/App.swift","content":"print(1)"}}]}"#
        let generator = SpyGenerator(response: AIServiceResponse(content: wrappedJSONOutput, toolCalls: nil))
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

        XCTAssertEqual(response.content, wrappedJSONOutput)
        XCTAssertNil(response.toolCalls)
    }

    func testFallbackParserDoesNotRecoverWrappedXMLToolCallForJSONFormat() {
        let wrappedXMLOutput = """
        <tool_call>
        <function=write_file>
        <parameter=path>
        Sources/App.swift
        </parameter>
        <parameter=content>
        print(1)
        </parameter>
        </function>
        </tool_call>
        """

        let toolCalls = LocalModelProcessAIService.NativeMLXGenerator.extractFallbackToolCalls(
            from: wrappedXMLOutput,
            toolsWereProvided: true,
            structuredToolCallsWereDetected: false,
            toolCallFormat: .json
        )

        XCTAssertNil(toolCalls)
    }
}
