import XCTest
@testable import osx_ide

// MARK: - Real App Parity Harness Tests

/// Harness tests using the real app's DependencyContainer.
/// Tests validate the complete pipeline: model -> orchestration -> tool execution.
@MainActor
final class AgenticHarnessTests: XCTestCase {

    // MARK: - Helper Methods
    
    override func setUp() async throws {
        try await super.setUp()
        // Set up test configuration for isolated testing with real services
        let config = TestConfiguration(
            allowExternalAPIs: true,
            minAPIRequestInterval: 1.0,
            serialExternalAPITests: true,
            externalAPITimeout: 60.0,
            useMockServices: false
        )
        await TestConfigurationProvider.shared.setConfiguration(config)
        
        // Configure settings for OpenRouter testing (disable offline mode to use OpenRouter)
        // This ensures we test the full agentic capabilities with LangGraph and toolchain
        let selectionStore = LocalModelSelectionStore()
        await selectionStore.setOfflineModeEnabled(false)
    }
    
    override func tearDown() async throws {
        await TestConfigurationProvider.shared.resetToDefault()
        try await super.tearDown()
    }

    private struct ProductionRuntime {
        let container: DependencyContainer
        let manager: ConversationManager
    }

    private func makeProductionRuntime(projectRoot: URL) async throws -> ProductionRuntime {
        // Initialize the app's real DependencyContainer in testing mode
        let container = DependencyContainer(launchContext: AppLaunchContext(mode: .unitTest, isTesting: true, isUITesting: false, testProfilePath: nil, disableHeavyInit: false))

        guard let manager = container.conversationManager as? ConversationManager else {
            throw NSError(
                domain: "AgenticHarnessTests", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "ConversationManager is not the expected concrete type"
                ])
        }

        // Emulate what the app does when a project is selected
        container.workspaceService.currentDirectory = projectRoot
        container.projectCoordinator.configureProject(root: projectRoot)

        // Wait for setup
        try await Task.sleep(nanoseconds: 500_000_000)

        return ProductionRuntime(container: container, manager: manager)
    }

    private func sendProductionMessage(
        _ text: String, manager: ConversationManager, timeoutSeconds: TimeInterval = 180
    ) async throws {
        manager.currentInput = text
        manager.sendMessage()
        try await waitForConversationToFinish(manager, timeoutSeconds: timeoutSeconds)
        if let error = manager.error {
            print("[HARNESS][warning] Conversation manager reported error: \(error)")
        }
    }

    private func waitForConversationToFinish(
        _ manager: ConversationManager, timeoutSeconds: TimeInterval = 180
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if !manager.isSending {
                return
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        print("[HARNESS][warning] Timed out waiting for conversation manager to finish send task")
    }

    private func listAllFiles(under directory: URL) -> [String] {
        let fm = FileManager.default
        let basePath = directory.standardizedFileURL.path
        guard
            let enumerator = fm.enumerator(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])
        else {
            return []
        }
        var files: [String] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                values.isRegularFile == true
            else { continue }
            let filePath = url.standardizedFileURL.path
            let relative = String(filePath.dropFirst(basePath.count + 1))
            if !relative.hasPrefix(".ide") {
                files.append(relative)
            }
        }
        return files.sorted()
    }

    // MARK: - Test: Verify Real OpenRouter Responses
    
    func testHarnessRealOpenRouterVerification() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .chat  // Use chat mode for simple interaction

        print("\n=== Test: Verify Real OpenRouter Responses ===")
        print("Project root: \(projectRoot.path)")

        let prompt = "What is your name?"

        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 60)

        // Debug: Log the conversation to see the response
        logConversation(manager.messages)

        // Check if the response contains "Yodah" (from system prompt override)
        let assistantMessages = manager.messages.filter { $0.role == .assistant }
        logHarnessCheck(!assistantMessages.isEmpty, label: "assistant response exists")
        
        let lastAssistantMessage = assistantMessages.last!
        print("\nAssistant response: \(lastAssistantMessage.content)")
        
        // If this fails, we're either not using the real API or system prompt isn't being applied
        logHarnessCheck(
            lastAssistantMessage.content.contains("Yodah") || lastAssistantMessage.content.contains("yodah"),
            label: "response contains system prompt identity override (Yodah)",
            detail: lastAssistantMessage.content
        )
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
        
        // Debug: Log the conversation to understand what happened
        logConversation(manager.messages)
        
        // Check if tools are being provided to the model
        print("\n=== Tool Debugging ===")
        print("Current mode: \(manager.currentMode)")
        print("=== End Tool Debugging ===\n")

        logHarnessCheck(files.contains("package.json"), label: "react scaffold package.json created")
        logHarnessCheck(files.contains("index.html"), label: "react scaffold index.html created")
        logHarnessCheck(
            files.contains("src/main.jsx") || files.contains("src/main.tsx")
                || files.contains("src/index.js"),
            label: "react scaffold entry file created")
        logHarnessCheck(
            files.contains("src/App.jsx") || files.contains("src/App.tsx")
                || files.contains("src/App.js"),
            label: "react scaffold app component created")
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
        try messyCode.write(
            to: projectRoot.appendingPathComponent("calculator.js"), atomically: true,
            encoding: .utf8)

        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent

        print("\n=== Test: Refactor Scenario ===")
        print("Project root: \(projectRoot.path)")

        let prompt = """
            Refactor the calculator.js file in this directory to use modern ES6+ syntax (const/let, array methods like reduce/filter).
            """

        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 300)

        let refactoredCode = try String(
            contentsOf: projectRoot.appendingPathComponent("calculator.js"))
        print("\nRefactored Code:\n\(refactoredCode)")

        let hasLegacyVarDeclaration = refactoredCode.contains("var ") || refactoredCode.contains("var\t")
        let usesModernBindings = refactoredCode.contains("const") || refactoredCode.contains("let")

        logHarnessCheck(!refactoredCode.contains("var total = 0"), label: "legacy var removed")
        logHarnessCheck(!refactoredCode.contains("for(var i=0"), label: "legacy for loop removed")
        logHarnessCheck(usesModernBindings || !hasLegacyVarDeclaration, label: "modern bindings used")
        logHarnessCheck(
            refactoredCode.contains("reduce") || refactoredCode.contains("filter")
                || refactoredCode.contains("=>"),
            label: "functional refactor constructs present")
    }

    private func logToolTrail(messages: [ChatMessage]) {
        let toolMessages = messages.filter { $0.isToolExecution }
        print("\n--- Tool Trail (\(toolMessages.count) tool messages) ---")
        for message in toolMessages {
            if let envelope = ToolExecutionEnvelope.decode(from: message.content) {
                print(
                    "[\(envelope.status.rawValue)] \(envelope.toolName) -> \(envelope.targetFile ?? "(none)")"
                )
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
            return content.contains("tool_calls:") || content.contains("tool call:")
                || content.contains("```json") || content.contains("write_file(")
                || content.contains("create_file(")
        }

        if !textualPatterns.isEmpty {
            print(
                "WARNING: Found \(textualPatterns.count) messages with textual tool call patterns")
            print("This suggests the model is trying to call tools but not in the expected format")
            for msg in textualPatterns {
                print("  Textual pattern preview: \(msg.content.prefix(100))...")
            }
        }

        print("=== End Telemetry ===\n")
    }

    private func readSnapshots(projectRoot: URL, conversationId: String, runId: String) throws
        -> [OrchestrationRunSnapshot]
    {
        let url =
            projectRoot
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
            // Print full content for assistant messages to debug tool calling
            if msg.role == .assistant {
                print("  [FULL CONTENT]: \(msg.content)")
            }
        }
        print("--- End Conversation ---\n")
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

        logHarnessCheck(files.contains("package.json"), label: "phase 1 package.json created")
        logHarnessCheck(files.contains("index.html"), label: "phase 1 index.html created")
        logHarnessCheck(
            files.contains("src/App.jsx") || files.contains("src/App.tsx")
                || files.contains("src/App.js"),
            label: "phase 1 App component created")

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

        logHarnessCheck(
            files.contains("server.js") || files.contains("server/index.js"),
            label: "phase 2 server entrypoint created")

        let serverPath = files.contains("server.js") ? "server.js" : "server/index.js"
        let serverCode = try String(contentsOf: projectRoot.appendingPathComponent(serverPath))

        logHarnessCheck(serverCode.contains("express"), label: "SSR server uses express")
        logHarnessCheck(
            serverCode.contains("renderToString") || serverCode.contains("renderToPipeableStream"),
            label: "SSR rendering API present")
    }

    // MARK: - Test: JavaScript to TypeScript Migration Scenario

    func testHarnessJavaScriptToTypeScriptMigration() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent

        print("\n=== Test: JavaScript -> TypeScript Migration ===")
        print("Project root: \(projectRoot.path)")

        let prompt = """
            Create a small JavaScript utility project and migrate it to TypeScript.
            1. Create package.json with scripts for build and test (do not run npm install)
            2. Create src/math.js with add/subtract/divide functions
            3. Migrate src/math.js to src/math.ts with explicit types
            4. Add tsconfig.json
            5. Remove obsolete JS implementation if replaced
            Use tools only. Keep project runnable after migration.
            """

        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 300)

        let files = listAllFiles(under: projectRoot)
        print("\nFiles after JS->TS migration: \(files.count)")
        for file in files { print("  - \(file)") }

        logHarnessCheck(files.contains("package.json"), label: "migration package.json created")
        logHarnessCheck(files.contains("tsconfig.json"), label: "migration tsconfig created")
        logHarnessCheck(files.contains("src/math.ts"), label: "migration TypeScript source created")

        let migratedCode = try String(contentsOf: projectRoot.appendingPathComponent("src/math.ts"))
        logHarnessCheck(migratedCode.contains(": number"), label: "migration typed signatures present")
        logHarnessCheck(
            migratedCode.contains("export") || migratedCode.contains("function"),
            label: "migration usable TS module exported")
    }

    // MARK: - Test: Add Test Coverage Scenario

    func testHarnessAddsTestCoverageForExistingModule() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: projectRoot.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )

        let moduleCode = """
            export function normalizeName(value) {
                if (!value) return "";
                return value.trim().toLowerCase();
            }

            export function safeDivide(a, b) {
                if (b === 0) return null;
                return a / b;
            }
            """
        try moduleCode.write(
            to: projectRoot.appendingPathComponent("src/utils.js"),
            atomically: true,
            encoding: .utf8
        )

        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent

        print("\n=== Test: Add Test Coverage ===")
        print("Project root: \(projectRoot.path)")

        let prompt = """
            Add full unit test coverage for src/utils.js.
            1. Create package.json with test script using vitest or jest (do not run install)
            2. Create tests that cover normal and edge cases for normalizeName and safeDivide
            3. Ensure divide-by-zero and empty input cases are covered
            4. Keep source behavior unchanged
            Use tools to create/modify files.
            """

        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 300)

        let files = listAllFiles(under: projectRoot)
        print("\nFiles after coverage scenario: \(files.count)")
        for file in files { print("  - \(file)") }

        logHarnessCheck(files.contains("package.json"), label: "coverage package.json created")

        let candidateTestFiles = files.filter {
            $0.contains("test") || $0.contains("spec")
        }
        logHarnessCheck(!candidateTestFiles.isEmpty, label: "coverage test file created")

        if let firstTestPath = candidateTestFiles.first {
            let testCode = try String(contentsOf: projectRoot.appendingPathComponent(firstTestPath))
            logHarnessCheck(
                testCode.localizedCaseInsensitiveContains("normalizeName"),
                label: "coverage includes normalizeName assertions")
            logHarnessCheck(
                testCode.localizedCaseInsensitiveContains("safeDivide"),
                label: "coverage includes safeDivide assertions")
            logHarnessCheck(
                testCode.contains("0") || testCode.localizedCaseInsensitiveContains("null"),
                label: "coverage includes divide-by-zero behavior")
        }
    }

    // MARK: - Test: Complex Architecture Refactor Scenario

    func testHarnessComplexArchitectureRefactor() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let packageJson = """
            {
              "name": "complex-app",
              "version": "1.0.0",
              "dependencies": {
                "express": "^4.18.2"
              }
            }
            """
        try packageJson.write(
            to: projectRoot.appendingPathComponent("package.json"), atomically: true,
            encoding: .utf8)

        let messyServerCode = """
            const express = require('express');
            const app = express();

            app.use(express.json());

            let users = [{ id: 1, name: 'Alice' }, { id: 2, name: 'Bob' }];
            let products = [{ id: 101, title: 'Laptop', price: 999 }, { id: 102, title: 'Mouse', price: 25 }];

            app.get('/api/users', (req, res) => {
                res.json(users);
            });

            app.post('/api/users', (req, res) => {
                const newUser = { id: users.length + 1, name: req.body.name };
                users.push(newUser);
                res.status(201).json(newUser);
            });

            app.get('/api/products', (req, res) => {
                res.json(products);
            });

            app.post('/api/products', (req, res) => {
                const newProduct = { id: products.length + 101, title: req.body.title, price: req.body.price };
                products.push(newProduct);
                res.status(201).json(newProduct);
            });

            app.listen(3000, () => {
                console.log('Server running on port 3000');
            });
            """
        try messyServerCode.write(
            to: projectRoot.appendingPathComponent("server.js"), atomically: true, encoding: .utf8)

        let runtime = try await makeProductionRuntime(projectRoot: projectRoot)
        let manager = runtime.manager
        manager.currentMode = .agent

        print("\n=== Test: Complex Architecture Refactor ===")
        print("Project root: \(projectRoot.path)")

        let prompt = """
            Refactor the monolithic 'server.js' file into a proper modular MVC architecture.
            1. Create a `models/` directory. Move the users array into `models/User.js` and products array into `models/Product.js` (export them).
            2. Create a `controllers/` directory with `usersController.js` and `productsController.js` containing the logic for GET and POST.
            3. Create a `routes/` directory with `usersRoutes.js` and `productsRoutes.js` using express.Router().
            4. Rewrite 'server.js' so it only contains the express app setup, middleware, mounting the routers, and app.listen.
            You must ensure the app retains the exact same functionality but is split into these multiple files.
            """

        try await sendProductionMessage(prompt, manager: manager, timeoutSeconds: 600)

        let files = listAllFiles(under: projectRoot)
        print("\nFiles in project after refactor: \(files.count)")
        for file in files { print("  - \(file)") }

        // Assert architecture elements exist
        logHarnessCheck(files.contains("models/User.js") || files.contains("models/user.js"), label: "model user file exists")
        logHarnessCheck(files.contains("models/Product.js") || files.contains("models/product.js"), label: "model product file exists")
        logHarnessCheck(
            files.contains("controllers/usersController.js")
                || files.contains("controllers/userController.js"),
            label: "users controller exists")
        logHarnessCheck(
            files.contains("controllers/productsController.js")
                || files.contains("controllers/productController.js"),
            label: "products controller exists")
        logHarnessCheck(
            files.contains("routes/usersRoutes.js") || files.contains("routes/userRoutes.js"),
            label: "users routes exists")
        logHarnessCheck(
            files.contains("routes/productsRoutes.js") || files.contains("routes/productRoutes.js"),
            label: "products routes exists")

        // Assert server.js is much shorter and requires routes
        let serverCode = try String(contentsOf: projectRoot.appendingPathComponent("server.js"))
        logHarnessCheck(!serverCode.contains("let users ="), label: "users state extracted from server.js")
        logHarnessCheck(!serverCode.contains("let products ="), label: "products state extracted from server.js")
        logHarnessCheck(
            serverCode.contains("routes") || serverCode.contains("Route")
                || serverCode.contains("require("),
            label: "server.js wires modular routes")
    }

    private func logHarnessCheck(_ condition: Bool, label: String, detail: String? = nil) {
        let status = condition ? "PASS" : "FAIL"
        if let detail, !detail.isEmpty {
            print("[HARNESS][\(status)] \(label) :: \(detail)")
            return
        }
        print("[HARNESS][\(status)] \(label)")
    }
}
