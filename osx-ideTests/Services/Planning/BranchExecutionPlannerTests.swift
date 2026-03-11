import XCTest
@testable import osx_ide

@MainActor
final class BranchExecutionPlannerTests: XCTestCase {
    func testMakeBranchExecutionBuildsSequentialBranchesFromTacticalPlan() {
        let tacticalPlan = """
        # Implementation Plan

        1. [ ] Analyze requirements and identify target files
           - [ ] Read relevant source files to understand structure
           - [ ] Identify dependencies and constraints
        2. [ ] Implement changes with minimal footprint
           - [ ] Apply focused edits to each target file
           - [ ] Ensure consistency across changes
        3. [ ] Verify and deliver
           - [ ] Confirm all changes are correct
           - [ ] Report completion status
        """

        let execution = BranchExecutionPlanner.makeBranchExecution(
            tacticalPlan: tacticalPlan,
            userInput: "Refactor the feature across multiple files"
        )

        XCTAssertNotNil(execution)
        XCTAssertEqual(execution?.branches.count, 3)
        XCTAssertEqual(execution?.activeBranchIndex, 0)
        XCTAssertEqual(execution?.branches.first?.title, "[ ] Analyze requirements and identify target files")
        XCTAssertEqual(
            execution?.branches.first?.checklistItems,
            [
                "Read relevant source files to understand structure",
                "Identify dependencies and constraints"
            ]
        )
        XCTAssertTrue(execution?.globalInvariants.contains("Primary objective: Refactor the feature across multiple files") == true)
    }

    func testMakeBranchExecutionReturnsNilWhenPlanHasNoNumberedSteps() {
        let execution = BranchExecutionPlanner.makeBranchExecution(
            tacticalPlan: "# Plan\n\nNo numbered steps here.",
            userInput: "Do something"
        )

        XCTAssertNil(execution)
    }
}
