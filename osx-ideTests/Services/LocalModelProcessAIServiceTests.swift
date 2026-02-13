import XCTest

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

    private actor SpyGenerator: LocalModelProcessAIService.LocalModelGenerating {
        private(set) var lastModelDirectory: URL?
        private(set) var lastPrompt: String?
        private(set) var lastRunId: String?
        private(set) var lastContextLength: Int?
        private(set) var lastConversationId: String?

        func generate(modelDirectory: URL, prompt: String, runId: String?, contextLength: Int, conversationId: String?) async throws -> String {
            lastModelDirectory = modelDirectory
            lastPrompt = prompt
            lastRunId = runId
            lastContextLength = contextLength
            lastConversationId = conversationId
            return "local-response"
        }

        func snapshot() -> (URL?, String?, String?, Int?, String?) {
            (lastModelDirectory, lastPrompt, lastRunId, lastContextLength, lastConversationId)
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

        let (capturedDirectory, capturedPrompt, capturedRunId, capturedContextLength, _) = await generator.snapshot()
        XCTAssertEqual(capturedDirectory, modelDirectory)
        XCTAssertEqual(capturedRunId, runId)
        XCTAssertEqual(capturedContextLength, LocalModelFileStore.contextLength(for: model))

        let prompt = try XCTUnwrap(capturedPrompt)
        XCTAssertTrue(prompt.contains("System:"))
        XCTAssertTrue(prompt.contains("Context:\nRepo context"))
        XCTAssertTrue(prompt.contains("User: Implement feature"))
        XCTAssertTrue(prompt.contains("CURRENT MODE: AGENT"))
        XCTAssertTrue(prompt.contains("<ide_reasoning>"))
        XCTAssertTrue(prompt.hasSuffix("Assistant:"))
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
            reasoningEnabled: true
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

        let (_, capturedPrompt, _, _, _) = await generator.snapshot()
        let prompt = try XCTUnwrap(capturedPrompt)
        XCTAssertTrue(prompt.contains("System: CUSTOM_SYSTEM_PROMPT"))
    }
}
