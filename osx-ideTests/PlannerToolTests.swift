import XCTest

@testable import osx_ide

final class PlannerToolTests: XCTestCase {

    func testUpdateReplacesExistingPlanInsteadOfAppending() async throws {
        let store = ConversationPlanStore.shared
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        await store.setProjectRoot(tempDir)

        let tool = PlannerTool()
        let conversationId = "planner-update-replace"
        let originalPlan = """
        # Implementation Plan

        - [ ] Step one
        - [ ] Step two
        """
        let updatedPlan = """
        # Implementation Plan

        - [x] Step one
        - [ ] Step two
        """

        _ = try await tool.execute(arguments: ToolArguments([
            "action": "set",
            "plan": originalPlan,
            "_conversation_id": conversationId
        ]))

        let result = try await tool.execute(arguments: ToolArguments([
            "action": "update",
            "plan": updatedPlan,
            "_conversation_id": conversationId
        ]))

        let storedPlan = await store.get(conversationId: conversationId)

        XCTAssertEqual(result, updatedPlan)
        XCTAssertEqual(storedPlan, updatedPlan)
        XCTAssertFalse(storedPlan?.contains("- [ ] Step one\n- [ ] Step two\n\n# Implementation Plan") ?? false)

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testUpdateWithSamePlanDoesNotDuplicateContent() async throws {
        let store = ConversationPlanStore.shared
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        await store.setProjectRoot(tempDir)

        let tool = PlannerTool()
        let conversationId = "planner-update-same"
        let plan = """
        # Implementation Plan

        - [ ] Step one
        - [ ] Step two
        """

        _ = try await tool.execute(arguments: ToolArguments([
            "action": "set",
            "plan": plan,
            "_conversation_id": conversationId
        ]))

        let result = try await tool.execute(arguments: ToolArguments([
            "action": "update",
            "plan": plan,
            "_conversation_id": conversationId
        ]))

        let storedPlan = await store.get(conversationId: conversationId)

        XCTAssertEqual(result, plan)
        XCTAssertEqual(storedPlan, plan)
        XCTAssertEqual(storedPlan?.components(separatedBy: "# Implementation Plan").count, 2)

        try? FileManager.default.removeItem(at: tempDir)
    }
}
