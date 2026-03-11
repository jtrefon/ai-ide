import XCTest
@testable import osx_ide

final class OpenRouterChatPreparationTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var settingsStore: OpenRouterSettingsStore!
    private let projectRoot = URL(fileURLWithPath: "/Users/jack/Projects/osx/osx-ide")

    override func setUp() {
        super.setUp()
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

    func testBuildChatPreparationCapturesFinalSystemMessagesAndTools() async throws {
        let service = OpenRouterAIService(
            settingsStore: settingsStore,
            client: OpenRouterAPIClient(),
            eventBus: EventBus()
        )

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

        let preparation = try await service.capturePreparationSnapshot(request: .init(
            messages: historyMessages,
            context: "Repo context block",
            tools: [tool],
            mode: .agent,
            projectRoot: projectRoot,
            runId: "run-1",
            stage: .initial_response
        ))

        XCTAssertEqual(preparation.model, "openrouter/test-model")
        XCTAssertEqual(preparation.toolChoice, "auto")
        XCTAssertEqual(preparation.nativeReasoning?.enabled, true)
        XCTAssertEqual(preparation.nativeReasoning?.effort, nil)
        XCTAssertEqual(preparation.nativeReasoning?.exclude, true)
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
        XCTAssertTrue(systemContent.contains("You are an expert AI software engineer assistant integrated into an IDE."))
        XCTAssertTrue(systemContent.contains("When tools are available, use real structured tool calls."))
        XCTAssertTrue(systemContent.contains("You are in Agent mode with full execution behavior."))
        XCTAssertTrue(systemContent.contains("Project Root: `/Users/jack/Projects/osx/osx-ide`"))
        XCTAssertFalse(systemContent.contains("Native model reasoning is allowed when it improves execution quality."))
        XCTAssertTrue(systemContent.contains("Do not emit pseudo-tool syntax"))
        XCTAssertFalse(systemContent.contains("<function"))
        XCTAssertFalse(systemContent.contains("tool calls:"))

        let toolDefinitions = try XCTUnwrap(preparation.toolDefinitions)
        XCTAssertEqual(toolDefinitions.count, 1)
        let definition = try XCTUnwrap(toolDefinitions.first)
        XCTAssertEqual(definition.type, "function")
        XCTAssertEqual(definition.function.name, "write_file")
        XCTAssertEqual(definition.function.description, "Write file content to disk")
        XCTAssertEqual(definition.function.parameterType, "object")
        XCTAssertEqual(definition.function.required, ["path", "content"])
    }

    func testBuildChatPreparationDoesNotInjectOptionalReasoningPromptDuringInitialResponse() async throws {
        let service = OpenRouterAIService(
            settingsStore: settingsStore,
            client: OpenRouterAPIClient(),
            eventBus: EventBus()
        )

        let preparation = try await service.capturePreparationSnapshot(request: .init(
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

private struct ChatPreparationSnapshot: Sendable {
    struct MessageSnapshot: Sendable {
        let role: String
        let content: String?
        let toolCallID: String?
    }

    struct ToolDefinitionSnapshot: Sendable {
        struct FunctionSnapshot: Sendable {
            let name: String
            let description: String
            let parameterType: String?
            let required: [String]
        }

        let type: String
        let function: FunctionSnapshot
    }

    let model: String
    let finalMessages: [MessageSnapshot]
    let toolDefinitions: [ToolDefinitionSnapshot]?
    let toolChoice: String?
    let nativeReasoning: NativeReasoningSnapshot?
}

private struct NativeReasoningSnapshot: Sendable {
    let enabled: Bool
    let effort: String?
    let exclude: Bool
}

private extension OpenRouterAIService {
    func capturePreparationSnapshot(
        request: OpenRouterChatHistoryInput
    ) throws -> ChatPreparationSnapshot {
        let preparation = try buildChatPreparation(request: request)
        let messageSnapshots = preparation.finalMessages.map { message in
            ChatPreparationSnapshot.MessageSnapshot(
                role: message.role,
                content: message.content,
                toolCallID: message.toolCallID
            )
        }
        let toolSnapshots = preparation.toolDefinitions?.compactMap { definition -> ChatPreparationSnapshot.ToolDefinitionSnapshot? in
            guard let type = definition["type"] as? String,
                  let function = definition["function"] as? [String: Any],
                  let name = function["name"] as? String,
                  let description = function["description"] as? String,
                  let parameters = function["parameters"] as? [String: Any] else {
                return nil
            }

            return ChatPreparationSnapshot.ToolDefinitionSnapshot(
                type: type,
                function: .init(
                    name: name,
                    description: description,
                    parameterType: parameters["type"] as? String,
                    required: parameters["required"] as? [String] ?? []
                )
            )
        }

        return ChatPreparationSnapshot(
            model: preparation.settings.model,
            finalMessages: messageSnapshots,
            toolDefinitions: toolSnapshots,
            toolChoice: preparation.toolChoice,
            nativeReasoning: preparation.nativeReasoningConfiguration.map {
                NativeReasoningSnapshot(
                    enabled: $0.enabled,
                    effort: $0.effort,
                    exclude: $0.exclude
                )
            }
        )
    }
}
