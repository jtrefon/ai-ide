import Foundation

let path = "/Users/jack/Projects/osx/osx-ide/osx-ide/Services/ConversationFlow/ToolLoopHandler.swift"
var content = try String(contentsOfFile: path, encoding: .utf8)

let target1 = """
        let planMarkdown = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        let planProgress = PlanChecklistTracker.progress(in: planMarkdown)
        guard planProgress.total == 0 else { return currentResponse }

        let shouldRecoverExecution =
"""

let replacement1 = """
        let planMarkdown = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        let planProgress = PlanChecklistTracker.progress(in: planMarkdown)
        guard planProgress.total == 0 else { return currentResponse }

        if await shouldPreserveNoToolHandoffWithoutIncompletePlan(
            content: currentContent,
            conversationId: conversationId
        ) {
            return currentResponse
        }

        let shouldRecoverExecution =
"""

if content.contains(target1) {
    content = content.replacingOccurrences(of: target1, with: replacement1)
    print("Patched requestExecutionRecoveryForUnfinishedResponseWithoutPlan")
}

let target2 = """
    private func shouldPreserveNoToolHandoffWithoutIncompletePlan(
        content: String,
        conversationId: String
    ) async -> Bool {
        guard isPureContinuationOrRecoverySummary(content) else { return false }

        let planMarkdown = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        let planProgress = PlanChecklistTracker.progress(in: planMarkdown)
        guard planProgress.total > 0 else { return false }
        return !planProgress.isComplete
    }
"""

let replacement2 = """
    private func shouldPreserveNoToolHandoffWithoutIncompletePlan(
        content: String,
        conversationId: String
    ) async -> Bool {
        guard isPureContinuationOrRecoverySummary(content) else { return false }

        let planMarkdown = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        let planProgress = PlanChecklistTracker.progress(in: planMarkdown)
        guard planProgress.total > 0 else { return true }
        return !planProgress.isComplete
    }
"""

if content.contains(target2) {
    content = content.replacingOccurrences(of: target2, with: replacement2)
    print("Patched shouldPreserveNoToolHandoffWithoutIncompletePlan")
}

try content.write(toFile: path, atomically: true, encoding: .utf8)
