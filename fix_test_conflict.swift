import Foundation

let path = "/Users/jack/Projects/osx/osx-ide/osx-ide/Services/ConversationFlow/ToolLoopHandler.swift"
var content = try String(contentsOfFile: path, encoding: .utf8)

let targetShouldPreserve = """
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

let replacementShouldPreserve = """
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

if content.contains(targetShouldPreserve) {
    content = content.replacingOccurrences(of: targetShouldPreserve, with: replacementShouldPreserve)
    print("Patched shouldPreserveNoToolHandoffWithoutIncompletePlan")
}

let targetRecovery = """
        let planMarkdown = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        let planProgress = PlanChecklistTracker.progress(in: planMarkdown)
        guard planProgress.total == 0 else { return currentResponse }

        let shouldRecoverExecution =
"""

let replacementRecovery = """
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

if content.contains(targetRecovery) {
    content = content.replacingOccurrences(of: targetRecovery, with: replacementRecovery)
    print("Patched requestExecutionRecoveryForUnfinishedResponseWithoutPlan")
}

try content.write(toFile: path, atomically: true, encoding: .utf8)
