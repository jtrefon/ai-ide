import Foundation

let path = "/Users/jack/Projects/osx/osx-ide/osx-ide/Services/ConversationFlow/ToolLoopHandler.swift"
var content = try String(contentsOfFile: path, encoding: .utf8)

let target = """
        let shouldRecoverExecution =
            isSyntheticProgressArtifact(currentContent)
            || isPureContinuationOrRecoverySummary(currentContent)
            || ChatPromptBuilder.deliveryStatus(from: currentContent) == .needsWork
            || ChatPromptBuilder.shouldForceToolFollowup(content: currentContent)
            || ChatPromptBuilder.shouldForceExecutionFollowup(
                userInput: userInput,
                content: currentContent,
                hasToolCalls: false
            )
            || indicatesUnfinishedExecutionSummary(currentContent)
            || (
                requestLikelyRequiresMutation(userInput)
                && !hasObservedSuccessfulMutation
                && indicatesNoChangeConclusion(currentContent)
            )

        guard shouldRecoverExecution else { return currentResponse }
"""

let replacement = """
        let shouldRecoverExecution =
            isSyntheticProgressArtifact(currentContent)
            || ChatPromptBuilder.shouldForceToolFollowup(content: currentContent)
            || ChatPromptBuilder.shouldForceExecutionFollowup(
                userInput: userInput,
                content: currentContent,
                hasToolCalls: false
            )
            || (
                indicatesUnfinishedExecutionSummary(currentContent)
                && !isPureContinuationOrRecoverySummary(currentContent)
            )
            || (
                requestLikelyRequiresMutation(userInput)
                && !hasObservedSuccessfulMutation
                && indicatesNoChangeConclusion(currentContent)
            )

        guard shouldRecoverExecution else { return currentResponse }
        
        let shouldPreserve = await shouldPreserveNoToolHandoffWithoutIncompletePlan(
            content: currentContent,
            conversationId: conversationId
        )
        guard !shouldPreserve else { return currentResponse }
"""

if content.contains(target) {
    content = content.replacingOccurrences(of: target, with: replacement)
    try content.write(toFile: path, atomically: true, encoding: .utf8)
    print("Patched successfully")
} else {
    print("Not found")
}
