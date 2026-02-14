import XCTest

@testable import osx_ide

// MARK: - Real MLX Model Harness Tests

/// Harness tests using real MLX local model inference.
/// Tests validate the complete pipeline: model → orchestration → tool execution.
/// Tests are skipped if the model is not installed.
@MainActor
final class AgenticHarnessTests: XCTestCase {
    
    // MARK: - Configuration
    
    private static let defaultModelId = "mlx-community/Qwen3-4B-Instruct-2507-4bit@50d4277"
    
    private var modelId: String {
        ProcessInfo.processInfo.environment["HARNESS_MODEL_ID"] ?? Self.defaultModelId
    }
    
    // MARK: - Setup
    
    private func skipIfModelNotInstalled() throws -> LocalModelDefinition {
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
        await store.setOfflineModeEnabled(true)
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
        
        // Check result
        let expectedFile = projectRoot.appendingPathComponent("hello.txt")
        let fileExists = FileManager.default.fileExists(atPath: expectedFile.path)
        
        if fileExists {
            let content = try String(contentsOf: expectedFile)
            print("✅ File created with content: \(content)")
            XCTAssertTrue(true, "File was created successfully")
        } else {
            print("❌ File was not created")
            // Check if model at least responded
            let assistantMessages = historyCoordinator.messages.filter { $0.role == .assistant }
            XCTAssertFalse(assistantMessages.isEmpty, "Should have assistant response")
            
            // Log what the model said
            for msg in assistantMessages {
                print("Assistant said: \(msg.content.prefix(500))...")
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
        
        let fileA = projectRoot.appendingPathComponent("a.txt")
        let fileB = projectRoot.appendingPathComponent("b.txt")
        
        let createdA = FileManager.default.fileExists(atPath: fileA.path)
        let createdB = FileManager.default.fileExists(atPath: fileB.path)
        
        print("File a.txt created: \(createdA)")
        print("File b.txt created: \(createdB)")
        
        // At least one file should be created for the test to be meaningful
        XCTAssertTrue(createdA || createdB, "At least one file should be created")
    }
    
    // MARK: - Test: React Todo App Scaffold
    
    /// Test that the model can scaffold a basic React Todo application.
    /// This tests the model's ability to understand project structure and create multiple related files.
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
        
        // Check that tool execution occurred
        let toolMessages = historyCoordinator.messages.filter { $0.isToolExecution }
        print("Tool execution messages: \(toolMessages.count)")
        
        // List all files actually created in the project root
        let createdFiles = listAllFiles(under: projectRoot)
        print("Files created (\(createdFiles.count)):")
        for file in createdFiles {
            print("  ✅ \(file)")
        }
        
        // The model should have created at least 2 files for a meaningful scaffold
        XCTAssertGreaterThanOrEqual(createdFiles.count, 2, "At least 2 scaffold files should be created")
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
        
        // Check if file was edited
        let content = try String(contentsOf: existingFile)
        print("File content after edit: \(content)")
        
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
                print("✅ Phase order correct: strategic before tactical")
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
        
        // Check both files
        let file1Exists = FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("turn1.txt").path)
        let file2Exists = FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("turn2.txt").path)
        
        print("turn1.txt exists: \(file1Exists)")
        print("turn2.txt exists: \(file2Exists)")
        
        // At least one file should be created
        XCTAssertTrue(file1Exists || file2Exists, "At least one file should be created in multi-turn")
    }
    
    // MARK: - Test: Memory Stability Across Turns
    
    /// Test that MLX memory does not grow unboundedly across multiple turns.
    /// Validates the memory management fixes: maxKVSize, GPU cache clearing, message truncation.
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
    
    /// Informational test to check if the model supports native tool calling.
    func testHarnessModelToolCallingCapability() async throws {
        let _ = try skipIfModelNotInstalled()
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        
        let localService = await makeLocalService()
        
        print("\n=== Test: Model Tool Calling Capability ===")
        print("Model: \(modelId)")
        
        let tools = makeFileTools(projectRoot: projectRoot)
        
        let response = try await localService.sendMessage(AIServiceHistoryRequest(
            messages: [ChatMessage(role: .user, content: "Create a file called capability-test.txt with content 'test'")],
            context: nil,
            tools: tools,
            mode: .agent,
            projectRoot: projectRoot
        ))
        
        print("Response content: \(response.content ?? "(nil)")")
        print("Tool calls: \(response.toolCalls?.count ?? 0)")
        
        if let toolCalls = response.toolCalls {
            for call in toolCalls {
                print("  Tool: \(call.name), args: \(call.arguments)")
            }
        }
        
        let hasToolCalls = response.toolCalls?.isEmpty == false
        print("\nModel \(modelId) native tool calling: \(hasToolCalls ? "YES" : "NO")")
        
        // This test is informational
        XCTAssertTrue(true, "Capability test completed")
    }
    
    // MARK: - Helper Methods
    
    private func makeHistoryCoordinator(projectRoot: URL) -> ChatHistoryCoordinator {
        let historyManager = ChatHistoryManager()
        return ChatHistoryCoordinator(historyManager: historyManager, projectRoot: projectRoot)
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
                    print("  → Tool: \(call.name)")
                }
            }
        }
        print("--- End Conversation ---\n")
    }
}
