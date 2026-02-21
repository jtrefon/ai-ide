import XCTest
@testable import osx_ide

// MARK: - Real App Parity Harness Tests

/// Harness tests using the real app's DependencyContainer.
/// Tests validate the complete pipeline: model -> orchestration -> tool execution.
@MainActor
final class AgenticHarnessTests: XCTestCase {
    
    // MARK: - Helper Methods
    
    private var modelId: String {
        ProcessInfo.processInfo.environment["HARNESS_MODEL_ID"] ?? "mlx-community/Qwen3-4B-Instruct-2507-4bit@50d4277"
    }

    private struct ProductionRuntime {
        let container: DependencyContainer
        let manager: ConversationManager
    }

    private func makeProductionRuntime(projectRoot: URL) async throws -> ProductionRuntime {
        // Initialize the app's real DependencyContainer in testing mode
        let container = DependencyContainer(isTesting: true)
        
        guard let manager = container.conversationManager as? ConversationManager else {
            throw NSError(domain: "AgenticHarnessTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "ConversationManager is not the expected concrete type"])
        }
        
        // Emulate what the app does when a project is selected
        container.workspaceService.currentDirectory = projectRoot
        container.projectCoordinator.configureProject(root: projectRoot)
        
        // Wait for setup
        try await Task.sleep(nanoseconds: 500_000_000)

        return ProductionRuntime(container: container, manager: manager)
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

    // MARK: - Test: Create React App Scenario
    
    func testHarnessCreateReactApp() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        
        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent
        
        print("\n=== Test: Create React App ===")
        print("Project root: \(projectRoot.path)")
        
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
    }

    // MARK: - Test: React Todo to SSR Refactor Scenario
    
    func testHarnessReactTodoToSSRRefactor() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        
        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent
        
        print("\n=== Test: React Todo -> SSR Refactor ===")
        print("Project root: \(projectRoot.path)")
        
        // Phase 1: Build the Todo App
        let buildPrompt = """
        Create a simple React Todo application structure using vite.
        1. Create package.json with react and react-dom dependencies
        2. Create index.html
        3. Create src/main.jsx
        4. Create src/App.jsx with a functional todo list (add, toggle, delete).
        Do not actually run npm install, just create the files using your tools.
        """
        
        print("--- Phase 1: Building React Todo App ---")
        try await sendProductionMessage(buildPrompt, manager: manager, timeoutSeconds: 300)
        
        var files = listAllFiles(under: projectRoot)
        print("\nFiles created after Phase 1: \(files.count)")
        for file in files { print("  - \(file)") }
        
        XCTAssertTrue(files.contains("package.json"))
        XCTAssertTrue(files.contains("index.html"))
        XCTAssertTrue(files.contains("src/App.jsx") || files.contains("src/App.tsx") || files.contains("src/App.js"))
        
        // Phase 2: Refactor to SSR
        let refactorPrompt = """
        Now refactor this application into a Server-Side Rendered (SSR) setup using a simple Express server.
        1. Add express to package.json
        2. Create a server.js file at the root that serves the React app using ReactDOMServer.renderToString
        3. Modify index.html and src/main.jsx to support hydration
        Do not run npm install, just implement the file changes using your tools.
        """
        
        print("\n--- Phase 2: Refactoring to SSR ---")
        try await sendProductionMessage(refactorPrompt, manager: manager, timeoutSeconds: 400)
        
        files = listAllFiles(under: projectRoot)
        print("\nFiles created/modified after Phase 2: \(files.count)")
        for file in files { print("  - \(file)") }
        
        XCTAssertTrue(files.contains("server.js") || files.contains("server/index.js"), "Should have created a server entry point")
        
        let serverPath = files.contains("server.js") ? "server.js" : "server/index.js"
        let serverCode = try String(contentsOf: projectRoot.appendingPathComponent(serverPath))
        
        XCTAssertTrue(serverCode.contains("express"), "Server code should use express")
        XCTAssertTrue(serverCode.contains("renderToString") || serverCode.contains("renderToPipeableStream"), "Server code should use SSR rendering methods")
    }
}
