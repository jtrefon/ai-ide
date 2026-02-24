import XCTest
@testable import osx_ide

@MainActor
final class ConversationPolicyTests: XCTestCase {

    private let policy = ConversationPolicy()

    private func makeTool(name: String) -> StubTool {
        StubTool(name: name)
    }

    private var allTools: [AITool] {
        [
            makeTool(name: "index_find_files"),
            makeTool(name: "index_list_files"),
            makeTool(name: "index_search_text"),
            makeTool(name: "index_read_file"),
            makeTool(name: "index_search_symbols"),
            makeTool(name: "read_file"),
            makeTool(name: "list_files"),
            makeTool(name: "conversation_fold"),
            makeTool(name: "write_file"),
            makeTool(name: "replace_in_file"),
            makeTool(name: "run_command")
        ]
    }

    private let expectedReadOnly: Set<String> = [
        "index_find_files",
        "index_list_files",
        "index_search_text",
        "index_read_file",
        "index_search_symbols",
        "read_file",
        "list_files",
        "conversation_fold"
    ]

    // MARK: - Chat mode

    func testChatModeReturnsNoToolsRegardlessOfStage() {
        let stages: [AIRequestStage?] = [nil, .initial_response, .tool_loop, .delivery_gate, .final_response, .qa_tool_output_review, .qa_quality_review]
        for stage in stages {
            let result = policy.allowedTools(for: stage, mode: .chat, from: allTools)
            XCTAssertTrue(result.isEmpty, "Chat mode should return no tools for stage=\(String(describing: stage))")
        }
    }

    // MARK: - Agent mode: full tool access stages

    func testAgentModeNilStageReturnsAllTools() {
        let result = policy.allowedTools(for: nil, mode: .agent, from: allTools)
        XCTAssertEqual(result.count, allTools.count)
    }

    func testAgentModeInitialResponseReturnsNoTools() {
        let result = policy.allowedTools(for: .initial_response, mode: .agent, from: allTools)
        XCTAssertTrue(result.isEmpty, "initial_response should return no tools to save context")
    }

    func testAgentModeToolLoopReturnsAllTools() {
        let result = policy.allowedTools(for: .tool_loop, mode: .agent, from: allTools)
        XCTAssertEqual(result.count, allTools.count)
    }

    func testAgentModeDeliveryGateReturnsAllTools() {
        let result = policy.allowedTools(for: .delivery_gate, mode: .agent, from: allTools)
        XCTAssertEqual(result.count, allTools.count)
    }

    func testAgentModeFinalResponseReturnsAllTools() {
        let result = policy.allowedTools(for: .final_response, mode: .agent, from: allTools)
        XCTAssertEqual(result.count, allTools.count)
    }

    // MARK: - Agent mode: QA stages (read-only)

    // MARK: - Agent mode: planning stages (read-only)

    func testAgentModeStrategicPlanningReturnsReadOnlyTools() {
        let result = policy.allowedTools(for: .strategic_planning, mode: .agent, from: allTools)
        let names = Set(result.map(\.name))
        XCTAssertEqual(names, expectedReadOnly)
    }

    func testAgentModeTacticalPlanningReturnsReadOnlyTools() {
        let result = policy.allowedTools(for: .tactical_planning, mode: .agent, from: allTools)
        let names = Set(result.map(\.name))
        XCTAssertEqual(names, expectedReadOnly)
    }

    func testAgentModeQAToolOutputReviewReturnsReadOnlyTools() {
        let result = policy.allowedTools(for: .qa_tool_output_review, mode: .agent, from: allTools)
        let names = Set(result.map(\.name))
        XCTAssertEqual(names, expectedReadOnly)
    }

    func testAgentModeQAQualityReviewReturnsReadOnlyTools() {
        let result = policy.allowedTools(for: .qa_quality_review, mode: .agent, from: allTools)
        let names = Set(result.map(\.name))
        XCTAssertEqual(names, expectedReadOnly)
    }

    func testAgentModeReadOnlyStageExcludesWriteTools() {
        let result = policy.allowedTools(for: .qa_tool_output_review, mode: .agent, from: allTools)
        let names = result.map(\.name)
        XCTAssertFalse(names.contains("write_file"))
        XCTAssertFalse(names.contains("replace_in_file"))
        XCTAssertFalse(names.contains("run_command"))
    }

    // MARK: - Edge cases

    func testEmptyToolListReturnsEmpty() {
        let result = policy.allowedTools(for: .tool_loop, mode: .agent, from: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testQAStageWithNoReadOnlyToolsReturnsEmpty() {
        let writeOnly: [AITool] = [makeTool(name: "write_file"), makeTool(name: "run_command")]
        let result = policy.allowedTools(for: .qa_tool_output_review, mode: .agent, from: writeOnly)
        XCTAssertTrue(result.isEmpty)
    }
}

private struct StubTool: AITool {
    let name: String
    let description: String = "stub"

    var parameters: [String: Any] {
        ["type": "object", "properties": [:]]
    }

    func execute(arguments _: ToolArguments) async throws -> String {
        "ok"
    }
}
