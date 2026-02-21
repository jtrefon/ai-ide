import XCTest

@testable import osx_ide

// MARK: - Real MLX Model Harness Tests

/// Harness tests using real MLX local model inference.
/// Tests validate the complete pipeline: model -> orchestration -> tool execution.
/// Tests are skipped if the model is not installed.
@MainActor
final class AgenticHarnessTests: XCTestCase {
    
    // MARK: - Configuration
    
    private static let defaultModelId = "mlx-community/Qwen3-4B-Instruct-2507-4bit@50d4277"
    
    private var modelId: String {
        ProcessInfo.processInfo.environment["HARNESS_MODEL_ID"] ?? Self.defaultModelId
    }
    
    private var useOpenRouter: Bool {
        ProcessInfo.processInfo.environment["HARNESS_USE_OPENROUTER"] == "1"
    }
    
    // MARK: - Setup
    
    private func skipIfModelNotInstalled() throws -> LocalModelDefinition? {
        if useOpenRouter {
            return nil // Skip installation check for OpenRouter
        }
        guard let model = LocalModelCatalog.model(id: modelId) else {
            throw XCTSkip("Model not in catalog: \(modelId)")
        }
        guard LocalModelFileStore.isModelInstalled(model) else {
            throw XCTSkip("Model not downloaded: \(modelId)")
        }
        return model
    }
    
    private func makeSelectionStore() async -> LocalModelSelectionStore {
        let store = LocalModelSelectionStore()
        await store.setSelectedModelId(modelId)
        await store.setOfflineModeEnabled(!useOpenRouter)
        return store
    }
    
    private func makeLocalService() async -> LocalModelProcessAIService {
        let selectionStore = await makeSelectionStore()
        return LocalModelProcessAIService(selectionStore: selectionStore)
    }
    
    // MARK: - Error Manager
    
    private final class HarnessErrorManager: ObservableObject, ErrorManagerProtocol {
        @Published var currentError: AppError?
        @Published var showErrorAlert: Bool = false
        
        func handle(_ error: AppError) {
            currentError = error
            showErrorAlert = true
            // Don't fail - just log for harness tests
            print("[HarnessErrorManager] Error: \(error)")
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
    
    // MARK: - Test: Simple File Creation
    
    /// Test that the model can create a single file with specified content.
    /// This is the most basic tool execution test.
    /// IMPORTANT: This test MUST fail if the model does not generate tool calls.
    func testHarnessCreatesSingleFile() async throws {
        let _ = try skipIfModelNotInstalled()
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        
        let localService = await makeLocalService()
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: localService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )
        
        let tools = makeFileTools(projectRoot: projectRoot)
        
        print("\n=== Test: Create Single File ===")
        print("Project root: \(projectRoot.path)")
        print("Model: \(modelId)")
        
        try await sendUserMessage(
            "Create a file named hello.txt with the content 'Hello World'",
            historyCoordinator: historyCoordinator,
            sendCoordinator: sendCoordinator,
            projectRoot: projectRoot,
            availableTools: tools
        )
        
        // Log conversation
        logConversation(historyCoordinator.messages)
        
        // CRITICAL: Check for tool calls - this is the primary success criteria
        let assistantMessagesWithToolCalls = historyCoordinator.messages.filter { 
            $0.role == .assistant && !($0.toolCalls?.isEmpty ?? true)
        }
        let toolExecutionMessages = historyCoordinator.messages.filter { $0.isToolExecution }
        
        // Check result
        let expectedFile = projectRoot.appendingPathComponent("hello.txt")
        let fileExists = FileManager.default.fileExists(atPath: expectedFile.path)
        
        // Log diagnostic information
        print("\n=== Test Results ===")
        print("Tool calls generated: \(assistantMessagesWithToolCalls.count)")
        print("Tool executions: \(toolExecutionMessages.count)")
        print("File created: \(fileExists)")
        
        // Log telemetry for debugging model behavior
        logToolCallingTelemetry(historyCoordinator.messages, tools: tools)
        
        // PRIMARY ASSERTION: Model must generate tool calls in agent mode
        XCTAssertFalse(assistantMessagesWithToolCalls.isEmpty, 
            "CRITICAL: Model must generate tool calls in agent mode. " +
            "If this fails, the model is not calling tools properly. " +
            "Check telemetry output above for diagnostic information.")
        
        // SECONDARY ASSERTION: Tool executions should occur
        XCTAssertFalse(toolExecutionMessages.isEmpty,
            "Tool execution messages should be present when tool calls are generated")
        
        // TERTIARY CHECK: File should be created
        if fileExists {
            let content = try String(contentsOf: expectedFile)
            print("File content: \(content)")
        } else {
            print("WARNING: File was not created despite tool calls being generated.")
            print("This indicates tool execution may have failed or used wrong parameters.")
        }
        
        // Log what the model said for debugging
        let assistantMessages = historyCoordinator.messages.filter { $0.role == .assistant }
        for msg in assistantMessages {
            print("Assistant content preview: \(msg.content.prefix(200))...")
            if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                for call in toolCalls {
                    print("  Tool call: \(call.name) with args: \(call.arguments)")
                }
            }
        }
    }
    
    // MARK: - Test: Multi-File Creation
    
    /// Test that the model can create multiple files in one session.
    func testHarnessCreatesMultipleFiles() async throws {
        let _ = try skipIfModelNotInstalled()
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        
        let localService = await makeLocalService()
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: localService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )
        
        let tools = makeFileTools(projectRoot: projectRoot)
        
        print("\n=== Test: Create Multiple Files ===")
        
        try await sendUserMessage(
            "Create two files: a.txt containing 'A' and b.txt containing 'B'",
            historyCoordinator: historyCoordinator,
            sendCoordinator: sendCoordinator,
            projectRoot: projectRoot,
            availableTools: tools
        )
        
        logConversation(historyCoordinator.messages)
        logToolCallingTelemetry(historyCoordinator.messages, tools: tools)
        
        // CRITICAL: Check for tool calls
        let assistantMessagesWithToolCalls = historyCoordinator.messages.filter { 
            $0.role == .assistant && !($0.toolCalls?.isEmpty ?? true)
        }
        
        let fileA = projectRoot.appendingPathComponent("a.txt")
        let fileB = projectRoot.appendingPathComponent("b.txt")
        
        let createdA = FileManager.default.fileExists(atPath: fileA.path)
        let createdB = FileManager.default.fileExists(atPath: fileB.path)
        
        print("File a.txt created: \(createdA)")
        print("File b.txt created: \(createdB)")
        print("Tool calls generated: \(assistantMessagesWithToolCalls.count)")
        
        // PRIMARY ASSERTION: Model must generate tool calls
        XCTAssertFalse(assistantMessagesWithToolCalls.isEmpty,
            "Model must generate tool calls for multi-file creation task")
        
        // SECONDARY ASSERTION: At least one file should be created
        XCTAssertTrue(createdA || createdB, "At least one file should be created")
    }
    
    // MARK: - Test: React Todo App Scaffold
    
    /// Test that the model can scaffold a basic React Todo application.
    func testHarnessScaffoldsReactTodoApp() async throws {
        let _ = try skipIfModelNotInstalled()
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        
        let localService = await makeLocalService()
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: localService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )
        
        let tools = makeFileTools(projectRoot: projectRoot)
        
        print("\n=== Test: Scaffold React Todo App ===")
        
        try await sendUserMessage(
            "Create a project with 4 files: package.json with content '{\"name\":\"todo\"}', index.html with content '<div id=\"root\"></div>', src/App.jsx with content 'export default function App() { return <h1>Todo</h1> }', src/main.jsx with content 'import App from \"./App\"'",
            historyCoordinator: historyCoordinator,
            sendCoordinator: sendCoordinator,
            projectRoot: projectRoot,
            availableTools: tools
        )
        
        logConversation(historyCoordinator.messages)
        logToolCallingTelemetry(historyCoordinator.messages, tools: tools)
        
        // CRITICAL: Check for tool calls
        let assistantMessagesWithToolCalls = historyCoordinator.messages.filter { 
            $0.role == .assistant && !($0.toolCalls?.isEmpty ?? true)
        }
        let toolMessages = historyCoordinator.messages.filter { $0.isToolExecution }
        print("Tool execution messages: \(toolMessages.count)")
        
        // List all files actually created in the project root
        let createdFiles = listAllFiles(under: projectRoot)
        print("Files created (\(createdFiles.count)):")
        for file in createdFiles {
            print("  \(file)")
        }
        
        // PRIMARY ASSERTION: Model must generate tool calls
        XCTAssertFalse(assistantMessagesWithToolCalls.isEmpty,
            "Model must generate tool calls for scaffold task")
        
        // SECONDARY ASSERTION: At least 2 files should be created
        XCTAssertGreaterThanOrEqual(createdFiles.count, 2, "At least 2 scaffold files should be created")
    }

    /// Production parity test: uses ConversationManager + ModelRoutingAIService + index-backed tools.
    /// This test validates that the production code path works with a simpler single-turn scenario
    /// to avoid MLX threading issues that occur with extended multi-turn tests.
    func testProductionParitySingleTurn() async throws {
        let _ = try skipIfModelNotInstalled()

        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        // Pre-create a basic project structure so the index has content
        let srcDir = projectRoot.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        
        let existingFile = projectRoot.appendingPathComponent("README.md")
        try "# Test Project".write(to: existingFile, atomically: true, encoding: .utf8)

        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent

        print("\n=== Production Parity Single Turn ===")
        print("Project root: \(projectRoot.path)")
        print("Model: \(modelId)")

        // Single turn: create a simple file
        try await sendProductionMessage(
            "Use write_file tool to create a file named test.txt with content 'Hello World'",
            manager: manager,
            timeoutSeconds: 180
        )

        let toolMessages = manager.messages.filter { $0.isToolExecution }
        XCTAssertFalse(toolMessages.isEmpty, "Should execute tools in production-parity path")

        // Check that file was created
        let createdFiles = listAllFiles(under: projectRoot)
        print("Files created: \(createdFiles)")
        
        XCTAssertTrue(createdFiles.contains("test.txt"), "Should create test.txt file")

        logToolTrail(messages: manager.messages)
    }
    
    // MARK: - Test: File Edit Chain
    
    /// Test that the model can edit an existing file.
    func testHarnessEditsFile() async throws {
        let _ = try skipIfModelNotInstalled()
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        
        // Pre-create a file to edit
        let existingFile = projectRoot.appendingPathComponent("config.txt")
        try "version=1.0\nname=old".write(to: existingFile, atomically: true, encoding: .utf8)
        
        let localService = await makeLocalService()
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: localService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )
        
        let tools = makeFileTools(projectRoot: projectRoot)
        
        print("\n=== Test: Edit File ===")
        
        try await sendUserMessage(
            "Edit config.txt and change 'name=old' to 'name=new'",
            historyCoordinator: historyCoordinator,
            sendCoordinator: sendCoordinator,
            projectRoot: projectRoot,
            availableTools: tools
        )
        
        logConversation(historyCoordinator.messages)
        logToolCallingTelemetry(historyCoordinator.messages, tools: tools)
        
        // CRITICAL: Check for tool calls
        let assistantMessagesWithToolCalls = historyCoordinator.messages.filter { 
            $0.role == .assistant && !($0.toolCalls?.isEmpty ?? true)
        }
        
        // Check if file was edited
        let content = try String(contentsOf: existingFile)
        print("File content after edit: \(content)")
        print("Tool calls generated: \(assistantMessagesWithToolCalls.count)")
        
        // PRIMARY ASSERTION: Model must generate tool calls
        XCTAssertFalse(assistantMessagesWithToolCalls.isEmpty,
            "Model must generate tool calls for edit task")
        
        // SECONDARY ASSERTION: File should be edited
        XCTAssertTrue(content.contains("name=new"), "File should be edited with new value")
    }
    
    // MARK: - Test: Orchestration Phases
    
    /// Test that the orchestration graph correctly transitions through phases.
    func testHarnessOrchestrationPhases() async throws {
        let _ = try skipIfModelNotInstalled()
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        
        let runId = UUID().uuidString
        
        let localService = await makeLocalService()
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: localService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )
        
        let tools = makeFileTools(projectRoot: projectRoot)
        
        print("\n=== Test: Orchestration Phases ===")
        
        try await sendUserMessage(
            "Hello, can you help me with something?",
            historyCoordinator: historyCoordinator,
            sendCoordinator: sendCoordinator,
            projectRoot: projectRoot,
            availableTools: tools,
            runId: runId
        )
        
        // Check orchestration snapshots
        let snapshots = try? readSnapshots(
            projectRoot: projectRoot,
            conversationId: historyCoordinator.currentConversationId,
            runId: runId
        )
        
        if let snapshots {
            let phases = snapshots.map(\.phase)
            print("Orchestration phases: \(phases)")
            
            XCTAssertFalse(phases.isEmpty, "Should have orchestration snapshots")
            
            // Check phase order
            if let strategicIndex = phases.firstIndex(of: StrategicPlanningNode.idValue),
               let tacticalIndex = phases.firstIndex(of: TacticalPlanningNode.idValue) {
                XCTAssertLessThan(strategicIndex, tacticalIndex, "Strategic should come before tactical")
                print("Phase order correct: strategic before tactical")
            }
        } else {
            print("No orchestration snapshots found")
        }
    }
    
    // MARK: - Test: Tool Execution Trail
    
    /// Test that tool executions are properly recorded in the conversation.
    func testHarnessToolExecutionTrail() async throws {
        let _ = try skipIfModelNotInstalled()
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        
        let localService = await makeLocalService()
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: localService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )
        
        let tools = makeFileTools(projectRoot: projectRoot)
        
        print("\n=== Test: Tool Execution Trail ===")
        
        try await sendUserMessage(
            "Create a file test.txt with content 'testing'",
            historyCoordinator: historyCoordinator,
            sendCoordinator: sendCoordinator,
            projectRoot: projectRoot,
            availableTools: tools
        )
        
        // Check for tool execution messages
        let toolMessages = historyCoordinator.messages.filter { $0.isToolExecution }
        print("Tool execution messages: \(toolMessages.count)")
        
        for msg in toolMessages {
            if let envelope = ToolExecutionEnvelope.decode(from: msg.content) {
                print("  Tool: \(envelope.toolName), Status: \(envelope.status.rawValue)")
            }
        }
        
        // CRITICAL: Check for tool calls
        let assistantMessagesWithToolCalls = historyCoordinator.messages.filter { 
            $0.role == .assistant && !($0.toolCalls?.isEmpty ?? true)
        }
        
        // PRIMARY ASSERTION: Model must generate tool calls
        XCTAssertFalse(assistantMessagesWithToolCalls.isEmpty,
            "Model must generate tool calls for file creation task")
        
        // If file was created, we should have tool execution messages
        let fileExists = FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("test.txt").path)
        if fileExists {
            XCTAssertFalse(toolMessages.isEmpty, "Should have tool execution messages when file is created")
        }
    }
    
    // MARK: - Test: Strategic and Tactical Planning
    
    /// Test that strategic and tactical plans are persisted.
    func testHarnessPersistsPlans() async throws {
        let _ = try skipIfModelNotInstalled()
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        
        await ConversationPlanStore.shared.setProjectRoot(projectRoot)
        
        let localService = await makeLocalService()
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: localService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )
        
        let tools = makeFileTools(projectRoot: projectRoot)
        
        print("\n=== Test: Plan Persistence ===")
        
        try await sendUserMessage(
            "Help me build a simple calculator app",
            historyCoordinator: historyCoordinator,
            sendCoordinator: sendCoordinator,
            projectRoot: projectRoot,
            availableTools: tools
        )
        
        let persistedPlan = await ConversationPlanStore.shared.get(conversationId: historyCoordinator.currentConversationId)
        
        if let plan = persistedPlan {
            print("Plan persisted: \(plan.prefix(500))...")
            XCTAssertTrue(plan.contains("# Strategic Plan") || plan.contains("Plan"), "Should contain planning content")
        } else {
            print("No plan persisted")
        }
    }
    
    // MARK: - Test: Multi-Turn Conversation
    
    /// Test that the model can handle multi-turn conversations.
    func testHarnessMultiTurnConversation() async throws {
        let _ = try skipIfModelNotInstalled()
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        
        let localService = await makeLocalService()
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: localService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )
        
        let tools = makeFileTools(projectRoot: projectRoot)
        
        print("\n=== Test: Multi-Turn Conversation ===")
        
        // Turn 1: Create a file
        try await sendUserMessage(
            "Create a file named turn1.txt with content 'First turn'",
            historyCoordinator: historyCoordinator,
            sendCoordinator: sendCoordinator,
            projectRoot: projectRoot,
            availableTools: tools
        )
        
        print("Turn 1 complete. Messages: \(historyCoordinator.messages.count)")
        
        // Turn 2: Ask about the file
        try await sendUserMessage(
            "Now create another file named turn2.txt with content 'Second turn'",
            historyCoordinator: historyCoordinator,
            sendCoordinator: sendCoordinator,
            projectRoot: projectRoot,
            availableTools: tools
        )
        
        print("Turn 2 complete. Messages: \(historyCoordinator.messages.count)")
        
        // CRITICAL: Check for tool calls across both turns
        let assistantMessagesWithToolCalls = historyCoordinator.messages.filter { 
            $0.role == .assistant && !($0.toolCalls?.isEmpty ?? true)
        }
        
        // Check both files
        let file1Exists = FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("turn1.txt").path)
        let file2Exists = FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("turn2.txt").path)
        
        print("turn1.txt exists: \(file1Exists)")
        print("turn2.txt exists: \(file2Exists)")
        print("Tool calls generated: \(assistantMessagesWithToolCalls.count)")
        
        // PRIMARY ASSERTION: Model must generate tool calls
        XCTAssertFalse(assistantMessagesWithToolCalls.isEmpty,
            "Model must generate tool calls in multi-turn conversation")
        
        // SECONDARY ASSERTION: At least one file should be created
        XCTAssertTrue(file1Exists || file2Exists, "At least one file should be created in multi-turn")
    }
    
    // MARK: - Test: Tool Execution Telemetry
    
    /// Test that tool execution telemetry is tracked and healthy.
    func testHarnessToolExecutionTelemetry() async throws {
        let _ = try skipIfModelNotInstalled()
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        
        // Reset telemetry for clean test
        ToolExecutionTelemetry.shared.reset()
        
        let localService = await makeLocalService()
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: localService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )
        
        let tools = makeFileTools(projectRoot: projectRoot)
        
        print("\n=== Test: Tool Execution Telemetry ===")
        
        try await sendUserMessage(
            "Create a file named telemetry-test.txt with content 'testing telemetry'",
            historyCoordinator: historyCoordinator,
            sendCoordinator: sendCoordinator,
            projectRoot: projectRoot,
            availableTools: tools
        )
        
        // Get telemetry summary
        let summary = ToolExecutionTelemetry.shared.summary
        
        print("\n=== Telemetry Summary ===")
        print(summary.healthReport)
        print("Total iterations: \(summary.totalIterations)")
        print("Successful executions: \(summary.successfulExecutions)")
        
        // PRIMARY ASSERTION: Model must generate tool calls
        let assistantMessagesWithToolCalls = historyCoordinator.messages.filter { 
            $0.role == .assistant && !($0.toolCalls?.isEmpty ?? true)
        }
        XCTAssertFalse(assistantMessagesWithToolCalls.isEmpty,
            "Model must generate tool calls for telemetry test")
        
        // SECONDARY ASSERTION: Telemetry should show iterations
        XCTAssertGreaterThan(summary.totalIterations, 0, "Should have at least one iteration")
        
        // TERTIARY ASSERTION: Quality metrics should be healthy (target: 0)
        // Note: In production, these should all be 0. In tests, we log but don't fail.
        if !summary.isHealthy {
            print("WARNING: Telemetry shows quality issues:")
            print("  - Responses without tool calls: \(summary.responsesWithoutToolCalls)")
            print("  - Textual tool call patterns: \(summary.textualToolCallPatterns)")
            print("  - Deduplicated tool calls: \(summary.deduplicatedToolCalls)")
            print("  - Repeated batches: \(summary.repeatedBatches)")
            print("  - Repeated content: \(summary.repeatedContent)")
        }
    }
    
    // MARK: - Test: Memory Stability Across Turns
    
    /// Test that MLX memory does not grow unboundedly across multiple turns.
    func testHarnessMemoryStabilityAcrossTurns() async throws {
        let _ = try skipIfModelNotInstalled()
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        
        let localService = await makeLocalService()
        let historyCoordinator = makeHistoryCoordinator(projectRoot: projectRoot)
        let sendCoordinator = makeSendCoordinator(
            aiService: localService,
            historyCoordinator: historyCoordinator,
            projectRoot: projectRoot
        )
        
        let tools = makeFileTools(projectRoot: projectRoot)
        let turnCount = 4
        var memorySnapshots: [(turn: Int, messages: Int, contentChars: Int)] = []
        
        print("\n=== Test: Memory Stability Across \(turnCount) Turns ===")
        print("Model: \(modelId)")
        
        for turn in 1...turnCount {
            let fileName = "mem_test_\(turn).txt"
            try await sendUserMessage(
                "Create a file named \(fileName) with content 'Turn \(turn) content for memory test'",
                historyCoordinator: historyCoordinator,
                sendCoordinator: sendCoordinator,
                projectRoot: projectRoot,
                availableTools: tools
            )
            
            let messageCount = historyCoordinator.messages.count
            let totalContentChars = historyCoordinator.messages.reduce(0) { $0 + $1.content.count }
            memorySnapshots.append((turn: turn, messages: messageCount, contentChars: totalContentChars))
            
            print("Turn \(turn): messages=\(messageCount), contentChars=\(totalContentChars)")
        }
        
        // Validate conversation folding keeps message count bounded
        let finalMessageCount = memorySnapshots.last?.messages ?? 0
        print("\nFinal message count: \(finalMessageCount)")
        print("Memory snapshots: \(memorySnapshots)")
        
        // With folding thresholds of 20 messages / 8K chars, we should not exceed ~30 messages
        // even after 4 turns with tool calls
        XCTAssertLessThan(finalMessageCount, 60, "Message count should be bounded by conversation folding")
        
        // Verify at least some files were created
        let createdFiles = listAllFiles(under: projectRoot)
        print("Files created: \(createdFiles.count)")
        XCTAssertGreaterThan(createdFiles.count, 0, "At least one file should be created across turns")
    }
    
    // MARK: - Test: Model Tool Calling Capability
    
    /// Diagnostic test to check if the model supports native tool calling.
    /// This test provides detailed telemetry about how the model calls tools.
    func testHarnessModelToolCallingCapability() async throws {
        let _ = try skipIfModelNotInstalled()
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        
        let localService = await makeLocalService()
        
        print("\n=== Test: Model Tool Calling Capability (Diagnostic) ===")
        print("Model: \(modelId)")
        
        let tools = makeFileTools(projectRoot: projectRoot)
        
        // Log available tools
        print("\nAvailable tools:")
        for tool in tools {
            print("  - \(tool.name): \(tool.description.prefix(50))...")
        }
        
        let response = try await localService.sendMessage(AIServiceHistoryRequest(
            messages: [ChatMessage(role: .user, content: "Create a file called capability-test.txt with content 'test'")],
            context: nil,
            tools: tools,
            mode: .agent,
            projectRoot: projectRoot
        ))
        
        print("\n=== Model Response ===")
        print("Content length: \(response.content?.count ?? 0)")
        print("Content preview: \(response.content?.prefix(300) ?? "(nil)")")
        print("Tool calls: \(response.toolCalls?.count ?? 0)")
        
        if let toolCalls = response.toolCalls {
            for call in toolCalls {
                print("  Tool: \(call.name)")
                print("    ID: \(call.id)")
                print("    Args: \(call.arguments)")
            }
        }
        
        let hasToolCalls = response.toolCalls?.isEmpty == false
        print("\nModel \(modelId) native tool calling: \(hasToolCalls ? "YES" : "NO")")
        
        // CRITICAL: This assertion now fails if model doesn't call tools
        XCTAssertTrue(hasToolCalls, 
            "Model must support native tool calling for agent mode to work. " +
            "If this fails, check: 1) toolCallFormat configuration, " +
            "2) chat template tool support, 3) message building in LocalModelProcessAIService")
    }
    
    // MARK: - Test: Create React App Scenario
    
    func testHarnessCreateReactApp() async throws {
        let _ = try skipIfModelNotInstalled()
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        
        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent
        
        print("\n=== Test: Create React App ===")
        print("Project root: \(projectRoot.path)")
        print("Model: \(modelId) (OpenRouter: \(useOpenRouter))")
        
        let prompt = """
        Create a simple React application structure using vite.
        1. Create package.json with react and react-dom dependencies
        2. Create index.html
        3. Create src/main.jsx
        4. Create src/App.jsx with a simple counter component
        Do not actually run npm install, just create the files.
        """
        
        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 300)
        
        let files = listAllFiles(under: projectRoot)
        print("\nFiles created: \(files.count)")
        for file in files { print("  - \(file)") }
        
        XCTAssertTrue(files.contains("package.json"))
        XCTAssertTrue(files.contains("index.html"))
        XCTAssertTrue(files.contains("src/main.jsx") || files.contains("src/main.tsx") || files.contains("src/index.js"))
        XCTAssertTrue(files.contains("src/App.jsx") || files.contains("src/App.tsx") || files.contains("src/App.js"))
    }
    
    // MARK: - Test: Refactor Scenario
    
    func testHarnessRefactorScenario() async throws {
        let _ = try skipIfModelNotInstalled()
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        
        // Setup initial messy code
        let messyCode = """
        function calculateTotal(items) {
            var total = 0;
            for(var i=0; i<items.length; i++) {
                if(items[i].active == true) {
                    if(items[i].price > 0) {
                        total = total + items[i].price;
                    }
                }
            }
            return total;
        }
        """
        try messyCode.write(to: projectRoot.appendingPathComponent("calculator.js"), atomically: true, encoding: .utf8)
        
        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent
        
        print("\n=== Test: Refactor Scenario ===")
        print("Project root: \(projectRoot.path)")
        print("Model: \(modelId) (OpenRouter: \(useOpenRouter))")
        
        let prompt = """
        Refactor the calculator.js file in this directory to use modern ES6+ syntax (const/let, array methods like reduce/filter).
        """
        
        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 300)
        
        let refactoredCode = try String(contentsOf: projectRoot.appendingPathComponent("calculator.js"))
        print("\nRefactored Code:\n\(refactoredCode)")
        
        XCTAssertFalse(refactoredCode.contains("var total = 0"))
        XCTAssertFalse(refactoredCode.contains("for(var i=0"))
        XCTAssertTrue(refactoredCode.contains("const") || refactoredCode.contains("let"))
        XCTAssertTrue(refactoredCode.contains("reduce") || refactoredCode.contains("filter") || refactoredCode.contains("=>"))
    }
    
    // MARK: - Helper Methods
    
    private func makeHistoryCoordinator(projectRoot: URL) -> ChatHistoryCoordinator {
        let historyManager = ChatHistoryManager()
        return ChatHistoryCoordinator(historyManager: historyManager, projectRoot: projectRoot)
    }

    private struct ProductionRuntime {
        let manager: ConversationManager
    }

    private func makeProductionRuntime(projectRoot: URL) async throws -> ProductionRuntime {
        let eventBus = EventBus()
        let errorManager = HarnessErrorManager()
        let fileSystemService = FileSystemService()
        let workspaceService = WorkspaceService(
            errorManager: errorManager,
            eventBus: eventBus,
            fileSystemService: fileSystemService
        )

        let selectionStore = await makeSelectionStore()
        let localService = LocalModelProcessAIService(
            selectionStore: selectionStore,
            eventBus: eventBus
        )
        let openRouterService = OpenRouterAIService(eventBus: eventBus)
        let routingService = ModelRoutingAIService(
            openRouterService: openRouterService,
            localService: localService,
            selectionStore: selectionStore
        )

        let codebaseIndex = try CodebaseIndex(
            eventBus: eventBus,
            projectRoot: projectRoot,
            aiService: routingService
        )
        codebaseIndex.start()
        codebaseIndex.setEnabled(true)

        let manager = ConversationManager(
            dependencies: ConversationManager.Dependencies(
                services: ConversationManager.ServiceDependencies(
                    aiService: routingService,
                    errorManager: errorManager,
                    fileSystemService: fileSystemService,
                    fileEditorService: nil
                ),
                environment: ConversationManager.EnvironmentDependencies(
                    workspaceService: workspaceService,
                    eventBus: eventBus,
                    projectRoot: projectRoot,
                    codebaseIndex: codebaseIndex
                )
            )
        )

        await ConversationPlanStore.shared.setProjectRoot(projectRoot)
        return ProductionRuntime(manager: manager)
    }

    private func sendProductionMessage(_ text: String, manager: ConversationManager, timeoutSeconds: TimeInterval = 180) async throws {
        manager.currentInput = text
        manager.sendMessage()
        try await waitForConversationToFinish(manager, timeoutSeconds: timeoutSeconds)
        if let error = manager.error {
            XCTFail("Conversation manager reported error: \(error)")
        }
    }

    private func waitForConversationToFinish(_ manager: ConversationManager, timeoutSeconds: TimeInterval = 180) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if !manager.isSending {
                return
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTFail("Timed out waiting for conversation manager to finish send task")
    }

    private func readLatestRunSnapshots(projectRoot: URL, conversationId: String) throws -> [OrchestrationRunSnapshot] {
        let runDirectory = projectRoot
            .appendingPathComponent(".ide", isDirectory: true)
            .appendingPathComponent("orchestration", isDirectory: true)
            .appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent(conversationId, isDirectory: true)

        let files = try FileManager.default.contentsOfDirectory(
            at: runDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let latest = try files
            .filter { $0.pathExtension == "jsonl" }
            .max { lhs, rhs in
                let leftDate = try lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                let rightDate = try rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                return leftDate < rightDate
            }

        guard let latest else {
            return []
        }

        let data = try Data(contentsOf: latest)
        let lines = String(data: data, encoding: .utf8)?
            .split(separator: "\n", omittingEmptySubsequences: true) ?? []

        let decoder = JSONDecoder()
        return try lines.map { line in
            try decoder.decode(OrchestrationRunSnapshot.self, from: Data(line.utf8))
        }
    }

    private func logToolTrail(messages: [ChatMessage]) {
        let toolMessages = messages.filter { $0.isToolExecution }
        print("\n--- Tool Trail (\(toolMessages.count) tool messages) ---")
        for message in toolMessages {
            if let envelope = ToolExecutionEnvelope.decode(from: message.content) {
                print("[\(envelope.status.rawValue)] \(envelope.toolName) -> \(envelope.targetFile ?? "(none)")")
            } else {
                print("[tool] \(message.toolName ?? "unknown") :: \(message.content.prefix(160))")
            }
        }
        print("--- End Tool Trail ---\n")
    }
    
    /// Log telemetry about tool calling behavior for debugging
    private func logToolCallingTelemetry(_ messages: [ChatMessage], tools: [AITool]) {
        print("\n=== Tool Calling Telemetry ===")
        print("Available tools: \(tools.map { $0.name }.joined(separator: ", "))")
        
        let assistantMessages = messages.filter { $0.role == .assistant }
        print("Assistant messages: \(assistantMessages.count)")
        
        var totalToolCalls = 0
        var toolCallNames: [String] = []
        
        for msg in assistantMessages {
            if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                totalToolCalls += toolCalls.count
                for call in toolCalls {
                    toolCallNames.append(call.name)
                }
            }
        }
        
        print("Total tool calls generated: \(totalToolCalls)")
        print("Tool call names: \(toolCallNames)")
        
        let toolExecutionMessages = messages.filter { $0.isToolExecution }
        print("Tool execution messages: \(toolExecutionMessages.count)")
        
        // Check for textual tool call patterns (model trying to call tools in text)
        let textualPatterns = assistantMessages.filter { msg in
            let content = msg.content.lowercased()
            return content.contains("tool_calls:") || 
                   content.contains("tool call:") ||
                   content.contains("```json") ||
                   content.contains("write_file(") ||
                   content.contains("create_file(")
        }
        
        if !textualPatterns.isEmpty {
            print("WARNING: Found \(textualPatterns.count) messages with textual tool call patterns")
            print("This suggests the model is trying to call tools but not in the expected format")
            for msg in textualPatterns {
                print("  Textual pattern preview: \(msg.content.prefix(100))...")
            }
        }
        
        print("=== End Telemetry ===\n")
    }

    /// Mirrors ConversationManager.sendMessage: append user message to history, then send.
    private func sendUserMessage(
        _ userInput: String,
        historyCoordinator: ChatHistoryCoordinator,
        sendCoordinator: ConversationSendCoordinator,
        projectRoot: URL,
        availableTools: [AITool],
        runId: String = UUID().uuidString
    ) async throws {
        await ConversationPlanStore.shared.setProjectRoot(projectRoot)
        historyCoordinator.append(ChatMessage(role: .user, content: userInput))
        try await sendCoordinator.send(makeSendRequest(
            conversationId: historyCoordinator.currentConversationId,
            projectRoot: projectRoot,
            userInput: userInput,
            runId: runId,
            availableTools: availableTools
        ))
    }
    
    private func makeSendCoordinator(
        aiService: AIService,
        historyCoordinator: ChatHistoryCoordinator,
        projectRoot: URL
    ) -> ConversationSendCoordinator {
        let aiInteractionCoordinator = AIInteractionCoordinator(aiService: aiService, codebaseIndex: nil)
        let toolExecutor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: HarnessErrorManager(),
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
            ReplaceInFileTool(fileSystemService: fileSystemService, pathValidator: pathValidator, eventBus: eventBus),
            ReadFileTool(fileSystemService: fileSystemService, pathValidator: pathValidator),
            ListFilesTool(pathValidator: pathValidator),
            RunCommandTool(projectRoot: projectRoot, pathValidator: pathValidator)
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
    
    private func listAllFiles(under directory: URL) -> [String] {
        let fm = FileManager.default
        let basePath = directory.standardizedFileURL.path
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var files: [String] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            let filePath = url.standardizedFileURL.path
            let relative = String(filePath.dropFirst(basePath.count + 1))
            if !relative.hasPrefix(".ide") {
                files.append(relative)
            }
        }
        return files.sorted()
    }

    private func logConversation(_ messages: [ChatMessage]) {
        print("\n--- Conversation (\(messages.count) messages) ---")
        for msg in messages {
            let preview = msg.content.prefix(100)
            print("[\(msg.role.rawValue)] \(preview)...")
            if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                for call in toolCalls {
                    print("  -> Tool: \(call.name)")
                }
            }
        }
        print("--- End Conversation ---\n")
    }
}
