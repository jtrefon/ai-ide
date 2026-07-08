import XCTest
@testable import osx_ide

final class OpenRouterChatPreparationTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var settingsStore: OpenRouterSettingsStore!
    private let projectRoot = URL(fileURLWithPath: "/Users/jack/Projects/osx/osx-ide")

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set("max", forKey: "AI.ReasoningIntensity")
        defaultsSuiteName = "OpenRouterChatPreparationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        let backingStore = SettingsStore(userDefaults: defaults)
        settingsStore = OpenRouterSettingsStore(settingsStore: backingStore)
        settingsStore.save(OpenRouterSettings(
            apiKey: "test-key",
            model: "openrouter/test-model",
            baseURL: OpenRouterSettings.empty.baseURL,
            systemPrompt: "",
            reasoningMode: .modelAndAgent,
            toolPromptMode: .concise,
            ragEnabledDuringToolLoop: true
        ))
    }

    override func tearDown() {
        if let defaultsSuiteName {
            let defaults = UserDefaults(suiteName: defaultsSuiteName)
            defaults?.removePersistentDomain(forName: defaultsSuiteName)
        }
        settingsStore = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    private func makeService() -> OpenAICompatibleChatService {
        let eventBus = EventBus()
        let client = OpenRouterAPIClient()
        let config = OpenRouterProviderConfig()
        let usageTracker = UsageTracker(client: client, eventBus: eventBus)
        guard let store = settingsStore else { fatalError("settingsStore not set up") }
        return OpenAICompatibleChatService(
            client: client,
            config: config,
            usageTracker: usageTracker,
            eventBus: eventBus,
            settingsStoreProvider: { store }
        )
    }

    func testBuildChatPreparationCapturesFinalSystemMessagesAndTools() async throws {
        let service = makeService()

        let historyMessages = [
            OpenRouterChatMessage(role: "user", content: "Read test.txt and write output.txt"),
            OpenRouterChatMessage(role: "assistant", content: "I will inspect the file and update it."),
            OpenRouterChatMessage(role: "tool", content: "Hello World", toolCallID: "tool-call-1")
        ]

        let tool = NoopTool(
            name: "write_file",
            description: "Write file content to disk",
            parameters: [
                "type": "object",
                "properties": [
                    "path": ["type": "string"],
                    "content": ["type": "string"]
                ],
                "required": ["path", "content"]
            ]
        )

        let preparation = try await service.buildChatPreparation(request: .init(
            messages: historyMessages,
            context: "Repo context block",
            tools: [tool],
            mode: .agent,
            projectRoot: projectRoot,
            runId: "run-1",
            stage: .initial_response
        ))

        XCTAssertEqual(preparation.settings.model, "openrouter/test-model")
        XCTAssertEqual(preparation.toolChoice, "auto")
        XCTAssertEqual(preparation.nativeReasoningConfiguration?.enabled, true)
        XCTAssertEqual(preparation.nativeReasoningConfiguration?.effort, "high")
        XCTAssertEqual(preparation.nativeReasoningConfiguration?.exclude, true)
        XCTAssertEqual(preparation.finalMessages.count, 5)
        XCTAssertEqual(preparation.finalMessages[0].role, "system")
        XCTAssertEqual(preparation.finalMessages[1].role, "user")
        XCTAssertEqual(preparation.finalMessages[1].content, "Context:\nRepo context block")
        XCTAssertEqual(preparation.finalMessages[2].role, "user")
        XCTAssertEqual(preparation.finalMessages[2].content, "Read test.txt and write output.txt")
        XCTAssertEqual(preparation.finalMessages[3].role, "assistant")
        XCTAssertEqual(preparation.finalMessages[4].role, "tool")
        XCTAssertEqual(preparation.finalMessages[4].toolCallID, "tool-call-1")

        let systemContent = try XCTUnwrap(preparation.finalMessages.first?.content)
        XCTAssertTrue(systemContent.contains("Project Root: `/Users/jack/Projects/osx/osx-ide`"), "System prompt should contain project root")

        let toolDefinitions = try XCTUnwrap(preparation.toolDefinitions)
        XCTAssertEqual(toolDefinitions.count, 1)
        guard let definition = toolDefinitions.first,
              let function = definition["function"] as? [String: Any],
              let name = function["name"] as? String,
              let description = function["description"] as? String else {
            XCTFail("Missing tool definition structure"); return
        }
        XCTAssertEqual(definition["type"] as? String, "function")
        XCTAssertEqual(name, "write_file")
        XCTAssertEqual(description, "Write file content to disk")
    }

    func testBuildChatPreparationDoesNotInjectOptionalReasoningPromptDuringInitialResponse() async throws {
        let service = makeService()

        let preparation = try await service.buildChatPreparation(request: .init(
            messages: [OpenRouterChatMessage(role: "user", content: "Implement feature")],
            context: nil,
            tools: [NoopTool(name: "write_file", description: "Write file content to disk", parameters: ["type": "object"])],
            mode: .agent,
            projectRoot: projectRoot,
            runId: "run-2",
            stage: .initial_response
        ))

        let systemContent = try XCTUnwrap(preparation.finalMessages.first?.content)
        XCTAssertFalse(systemContent.contains("Reasoning is optional. Use it only when it improves execution quality."))
        XCTAssertFalse(systemContent.contains("Wrap reasoning in <ide_reasoning>...</ide_reasoning>"))
    }
}

private struct NoopTool: AITool, @unchecked Sendable {
    let name: String
    let description: String
    let parameters: [String: Any]

    func execute(arguments: ToolArguments) async throws -> String {
        "ok"
    }
}
