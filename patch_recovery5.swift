import Foundation

let path = "/Users/jack/Projects/osx/osx-ide/osx-ide/Services/ConversationFlow/ToolLoopHandler.swift"
var content = try String(contentsOfFile: path, encoding: .utf8)

let target = """
        let planMarkdown = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        let planProgress = PlanChecklistTracker.progress(in: planMarkdown)
        guard planProgress.total == 0 else { return currentResponse }

        let shouldRecoverExecution =
"""

let replacement = """
        let planMarkdown = await ConversationPlanStore.shared.get(conversationId: conversationId) ?? ""
        let planProgress = PlanChecklistTracker.progress(in: planMarkdown)
        guard planProgress.total == 0 else { return currentResponse }

        let shouldPreserve = await shouldPreserveNoToolHandoffWithoutIncompletePlan(
            content: currentContent,
            conversationId: conversationId
        )
        guard !shouldPreserve else { return currentResponse }

        let shouldRecoverExecution =
"""

if let range = content.range(of: target) {
    content.replaceSubrange(range, with: replacement)
    
    // Also patch shouldPreserveNoToolHandoffWithoutIncompletePlan
    let preserveTarget = """
        let planProgress = PlanChecklistTracker.progress(in: planMarkdown)
        guard planProgress.total > 0 else { return false }
        return !planProgress.isComplete
"""
    let preserveReplacement = """
        let planProgress = PlanChecklistTracker.progress(in: planMarkdown)
        guard planProgress.total > 0 else { return true }
        return !planProgress.isComplete
"""
    content = content.replacingOccurrences(of: preserveTarget, with: preserveReplacement)
    
    try content.write(toFile: path, atomically: true, encoding: .utf8)
    print("Patched successfully")
} else {
    print("Not found")
}
