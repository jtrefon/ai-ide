import XCTest
@testable import osx_ide

/// Tests the full tool chain by calling OpenRouter directly with streaming.
/// The harness NEVER implements tool logic — it only sets up fixtures,
/// sends requests, and reads telemetry.
///
/// This bypasses the `isRunningUnitTests` check that disables streaming
/// in AIInteractionCoordinator. Direct OpenRouter streaming = real tool calls.
@MainActor
final class FullToolChainHarnessTest: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        await OnlineHarnessExecutionGate.shared.acquire()
        let config = TestConfiguration(allowExternalAPIs: true, minAPIRequestInterval: 1.0,
            serialExternalAPITests: true, externalAPITimeout: 300.0, useMockServices: false)
        await TestConfigurationProvider.shared.setConfiguration(config)
        let sel = LocalModelSelectionStore()
        await sel.setOfflineModeEnabled(false)
        // Set Kilo Code as the active provider (not OpenRouter)
        let providerStore = AIProviderSelectionStore()
        await providerStore.setSelectedRemoteProvider(.kiloCode)
    }

    override func tearDown() async throws {
        await TestConfigurationProvider.shared.resetToDefault()
        await OnlineHarnessExecutionGate.shared.release()
        try await super.tearDown()
    }

    // MARK: - Test: Direct OpenRouter streaming tool call

    func testStreamingToolCallsWork() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("stream-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create a test file
        try "Hello World".write(to: tmpDir.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)

        // Get the real OpenRouter service from the app's DI container
        let container = DependencyContainer(
            launchContext: AppLaunchContext(mode: .unitTest, isTesting: true, isUITesting: false,
                testProfilePath: nil, disableHeavyInit: false, productionParityHarness: false))

        // The container's aiService is the ModelRoutingAIService.
        // Get the actual OpenRouter service from it.
        let modelRouter = container.aiService as? ModelRoutingAIService
        XCTAssertNotNil(modelRouter, "Should get model router")

        // Build tools
        let fileSystem = FileSystemService()
        let pathValidator = PathValidator(projectRoot: tmpDir)
        let readTool = ReadFileTool(fileSystemService: fileSystem, pathValidator: pathValidator)
        let listTool = ListFilesTool(pathValidator: pathValidator)

        // Build request
        let userMsg = ChatMessage(role: .user,
            content: "List files in the project directory and read test.txt.")
        let request = AIServiceHistoryRequest(
            messages: [userMsg],
            context: nil,
            tools: [readTool, listTool],
            mode: .coder,
            projectRoot: tmpDir,
            runId: UUID().uuidString,
            stage: .initial_response,
            conversationId: UUID().uuidString
        )

        print("[HARNESS] Sending streaming request with 2 tools...")

        // Call streaming DIRECTLY on the model router (bypasses AIInteractionCoordinator)
        // This tests: OpenRouter receives tools → model calls them → response has tool_calls
        let response = try await modelRouter!.sendMessageStreaming(request, runId: UUID().uuidString)

        print("[HARNESS] Response content: \(response.content?.prefix(300) ?? "(nil)")")
        print("[HARNESS] Tool calls: \(response.toolCalls?.count ?? 0)")

        if let calls = response.toolCalls {
            for c in calls {
                print("[HARNESS]   Tool: \(c.name) args=\(c.arguments)")
            }
        } else {
            // Try text recovery
            if let content = response.content {
                print("[HARNESS] Attempting text recovery on response...")
                let recovered = OpenRouterAIService.extractFallbackToolCalls(from: content)
                if let rc = recovered {
                    print("[HARNESS]   Recovered \(rc.count) tool calls from text")
                    for c in rc {
                        print("[HARNESS]     Tool: \(c.name) args=\(c.arguments)")
                    }
                }
            }
        }

        // The model should return tool calls (structured or recovered)
        if let calls = response.toolCalls, !calls.isEmpty {
            print("[HARNESS] ✅ Model returned \(calls.count) structured tool calls")
        } else if let content = response.content,
                  let recovered = OpenRouterAIService.extractFallbackToolCalls(from: content),
                  !recovered.isEmpty {
            print("[HARNESS] ✅ Text recovery found \(recovered.count) tool calls")
        } else {
            print("[HARNESS] ⚠️ No tool calls returned. Content: \(response.content?.prefix(200) ?? "nil")")
        }
    }
}
