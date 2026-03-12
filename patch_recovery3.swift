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

        if await shouldPreserveNoToolHandoffWithoutIncompletePlan(
            content: currentContent,
            conversationId: conversationId
        ) {
            return currentResponse
        }

        let shouldRecoverExecution =
"""

if content.contains(target) {
    content = content.replacingOccurrences(of: target, with: replacement)
    try content.write(toFile: path, atomically: true, encoding: .utf8)
    print("Patched successfully")
} else {
    print("Not found")
}
