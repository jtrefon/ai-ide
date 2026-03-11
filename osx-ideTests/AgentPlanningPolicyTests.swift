import XCTest
@testable import osx_ide

final class AgentPlanningPolicyTests: XCTestCase {
    private var policy: AgentPlanningPolicy!

    override func setUp() {
        super.setUp()
        policy = AgentPlanningPolicy()
    }

    override func tearDown() {
        policy = nil
        super.tearDown()
    }

    func testPlanningMode_skipsPlanningForSimpleInformationalAgentRequest() {
        let result = policy.planningMode(
            userInput: "what about typescript migration, is that finished, complete?",
            mode: .agent,
            availableToolsCount: 0
        )

        XCTAssertEqual(result, .skipPlanning)
    }

    func testPlanningMode_skipsPlanningWhenNoToolsAreAvailable() {
        let result = policy.planningMode(
            userInput: "fix the dashboard layout",
            mode: .agent,
            availableToolsCount: 0
        )

        XCTAssertEqual(result, .skipPlanning)
    }

    func testPlanningMode_requiresPlanningForClearlyComplexAgentRequest() {
        let result = policy.planningMode(
            userInput: "re-architect the agent execution flow across multiple files and then migrate the old framework step by step",
            mode: .agent,
            availableToolsCount: 4
        )

        XCTAssertEqual(result, .requirePlanning)
    }

    func testPlanningMode_skipsPlanningOutsideAgentMode() {
        let result = policy.planningMode(
            userInput: "re-architect the agent execution flow across multiple files",
            mode: .chat,
            availableToolsCount: 4
        )

        XCTAssertEqual(result, .skipPlanning)
    }
}
