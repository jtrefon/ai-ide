import XCTest

@testable import osx_ide

final class PlanToolTests: XCTestCase {
    var tempDir: URL!
    var store: ConversationPlanStore!
    var tool: PlanTool!
    let conversationId = "plan-test-conv"

    override func setUp() async throws {
        try await super.setUp()
        tool = PlanTool()
        store = ConversationPlanStore.shared
        await store.reset()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        await store.setProjectRoot(tempDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        await store.reset()
        try await super.tearDown()
    }

    // MARK: - init

    func testInitCreatesEmptyPlanAndReturnsResearchPrompt() async throws {
        let result = try await tool.execute(arguments: ToolArguments([
            "action": "init",
            "_conversation_id": conversationId
        ]))

        XCTAssertTrue(result.contains("status: success"))
        XCTAssertTrue(result.contains("phase: researching"))

        let plan = await store.getPlan(conversationId: conversationId)
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.items.count, 0)
    }

    func testInitStoresPlanInConversationPlanStore() async throws {
        _ = try await tool.execute(arguments: ToolArguments([
            "action": "init",
            "_conversation_id": conversationId
        ]))

        let plan = await store.getPlan(conversationId: conversationId)
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.goal, "Task planning session")
        XCTAssertEqual(plan?.domain, .implementation)
        XCTAssertEqual(plan?.mode, .coder)
    }

    // MARK: - finishTask during research (transition to execution)

    func testFinishTaskDuringResearchParsesMultiLineSummary() async throws {
        // Start with init
        _ = try await tool.execute(arguments: ToolArguments([
            "action": "init",
            "_conversation_id": conversationId
        ]))

        // Finish research with multi-line summary
        let result = try await tool.execute(arguments: ToolArguments([
            "action": "finishTask",
            "summary": "Task 1: Implement feature X\nTask 2: Write tests\nTask 3: Update docs",
            "_conversation_id": conversationId
        ]))

        XCTAssertTrue(result.contains("status: success"))
        XCTAssertTrue(result.contains("phase: executing"))
        XCTAssertTrue(result.contains("progress: \"0/3\""))

        let plan = await store.getPlan(conversationId: conversationId)
        XCTAssertEqual(plan?.items.count, 3)
        XCTAssertEqual(plan?.items[0].status, .active)
        XCTAssertEqual(plan?.items[1].status, .pending)
        XCTAssertEqual(plan?.items[2].status, .pending)
    }

    func testFinishTaskDuringResearchWithSingleLineSummary() async throws {
        _ = try await tool.execute(arguments: ToolArguments([
            "action": "init",
            "_conversation_id": conversationId
        ]))

        let result = try await tool.execute(arguments: ToolArguments([
            "action": "finishTask",
            "summary": "Just one task",
            "_conversation_id": conversationId
        ]))

        XCTAssertTrue(result.contains("phase: executing"))

        let plan = await store.getPlan(conversationId: conversationId)
        XCTAssertEqual(plan?.items.count, 1)
        XCTAssertEqual(plan?.items[0].description, "Just one task")
    }

    func testFinishTaskStripsNumberingFromLines() async throws {
        _ = try await tool.execute(arguments: ToolArguments([
            "action": "init",
            "_conversation_id": conversationId
        ]))

        _ = try await tool.execute(arguments: ToolArguments([
            "action": "finishTask",
            "summary": "1. First task\n2. Second task\n3) Third task",
            "_conversation_id": conversationId
        ]))

        let plan = await store.getPlan(conversationId: conversationId)
        XCTAssertEqual(plan?.items[0].description, "First task")
        XCTAssertEqual(plan?.items[1].description, "Second task")
        XCTAssertEqual(plan?.items[2].description, "Third task")
    }

    // MARK: - finishTask during execution

    func testFinishTaskCompletesCurrentAndAdvancesToNext() async throws {
        // Set up: init + research → execution with 3 tasks
        try await setupPlanWithTasks(items: 3)

        // Complete task 1
        let result1 = try await tool.execute(arguments: ToolArguments([
            "action": "finishTask",
            "summary": "Done with task 1",
            "_conversation_id": conversationId
        ]))

        XCTAssertTrue(result1.contains("phase: executing"))
        XCTAssertTrue(result1.contains("progress: \"1/3\""))

        var plan = await store.getPlan(conversationId: conversationId)
        XCTAssertEqual(plan?.items[0].status, .completed)
        XCTAssertEqual(plan?.items[0].summary, "Done with task 1")
        XCTAssertEqual(plan?.items[1].status, .active)

        // Complete task 2
        let result2 = try await tool.execute(arguments: ToolArguments([
            "action": "finishTask",
            "summary": "Done with task 2",
            "_conversation_id": conversationId
        ]))

        XCTAssertTrue(result2.contains("progress: \"2/3\""))

        plan = await store.getPlan(conversationId: conversationId)
        XCTAssertEqual(plan?.items[1].status, .completed)
        XCTAssertEqual(plan?.items[2].status, .active)
    }

    func testFinishTaskOnLastTaskReturnsAllDone() async throws {
        try await setupPlanWithTasks(items: 2)

        // Complete task 1
        _ = try await tool.execute(arguments: ToolArguments([
            "action": "finishTask",
            "summary": "Task 1 done",
            "_conversation_id": conversationId
        ]))

        // Complete task 2 (last)
        let result = try await tool.execute(arguments: ToolArguments([
            "action": "finishTask",
            "summary": "Task 2 done",
            "_conversation_id": conversationId
        ]))

        XCTAssertTrue(result.contains("all_done: true"))
        XCTAssertTrue(result.contains("progress: \"2/2\""))

        let plan = await store.getPlan(conversationId: conversationId)
        XCTAssertEqual(plan?.items[0].status, .completed)
        XCTAssertEqual(plan?.items[1].status, .completed)
        XCTAssertTrue(plan?.isComplete ?? false)
    }

    // MARK: - raiseQuestion

    func testRaiseQuestionReturnsQuestionStatus() async throws {
        let result = try await tool.execute(arguments: ToolArguments([
            "action": "raiseQuestion",
            "question": "Which approach should I use?",
            "_conversation_id": conversationId
        ]))

        XCTAssertTrue(result.contains("status: question"))
        XCTAssertTrue(result.contains("Which approach should I use?"))
    }

    func testRaiseQuestionWithoutQuestionReturnsError() async throws {
        let result = try await tool.execute(arguments: ToolArguments([
            "action": "raiseQuestion",
            "_conversation_id": conversationId
        ]))

        XCTAssertTrue(result.contains("status: error"))
        XCTAssertTrue(result.contains("MISSING_QUESTION"))
    }

    // MARK: - breakOutCantContinue

    func testBreakOutCantContinueAbortsPlan() async throws {
        try await setupPlanWithTasks(items: 3)

        let result = try await tool.execute(arguments: ToolArguments([
            "action": "breakOutCantContinue",
            "summary": "Missing required library",
            "blocker_reason": "Core library X is not available for this platform",
            "_conversation_id": conversationId
        ]))

        XCTAssertTrue(result.contains("status: blocked"))
        XCTAssertTrue(result.contains("Missing required library"))

        let plan = await store.getPlan(conversationId: conversationId)
        XCTAssertTrue(plan?.items.allSatisfy { $0.status == .blocked } ?? false)
    }

    func testBreakOutCantContinueWithoutSummaryReturnsError() async throws {
        let result = try await tool.execute(arguments: ToolArguments([
            "action": "breakOutCantContinue",
            "blocker_reason": "Something broke",
            "_conversation_id": conversationId
        ]))

        XCTAssertTrue(result.contains("status: error"))
        XCTAssertTrue(result.contains("MISSING_SUMMARY"))
    }

    func testBreakOutCantContinueWithoutBlockerReasonReturnsError() async throws {
        let result = try await tool.execute(arguments: ToolArguments([
            "action": "breakOutCantContinue",
            "summary": "Cannot proceed",
            "_conversation_id": conversationId
        ]))

        XCTAssertTrue(result.contains("status: error"))
        XCTAssertTrue(result.contains("MISSING_BLOCKER_REASON"))
    }

    // MARK: - Error cases

    func testInvalidActionReturnsError() async throws {
        let result = try await tool.execute(arguments: ToolArguments([
            "action": "invalidAction",
            "_conversation_id": conversationId
        ]))

        XCTAssertTrue(result.contains("status: error"))
        XCTAssertTrue(result.contains("INVALID_ACTION"))
    }

    func testFinishTaskWithoutSummaryReturnsError() async throws {
        let result = try await tool.execute(arguments: ToolArguments([
            "action": "finishTask",
            "_conversation_id": conversationId
        ]))

        XCTAssertTrue(result.contains("status: error"))
        XCTAssertTrue(result.contains("MISSING_SUMMARY"))
    }

    func testFinishTaskWithoutConversationIdReturnsGuidance() async throws {
        let result = try await tool.execute(arguments: ToolArguments([
            "action": "finishTask",
            "summary": "Some task"
        ]))

        XCTAssertTrue(result.contains("Call plan"))
        XCTAssertTrue(result.contains("init"))
    }

    func testFinishTaskWithoutExistingPlanReturnsGuidance() async throws {
        let result = try await tool.execute(arguments: ToolArguments([
            "action": "finishTask",
            "summary": "Some task",
            "_conversation_id": "nonexistent-conv"
        ]))

        XCTAssertTrue(result.contains("No plan found"))
        XCTAssertTrue(result.contains("init"))
    }

    // MARK: - Helpers

    private func setupPlanWithTasks(items count: Int) async throws {
        _ = try await tool.execute(arguments: ToolArguments([
            "action": "init",
            "_conversation_id": conversationId
        ]))

        let lines = (1...count).map { "Task \($0)" }.joined(separator: "\n")
        _ = try await tool.execute(arguments: ToolArguments([
            "action": "finishTask",
            "summary": lines,
            "_conversation_id": conversationId
        ]))
    }
}
