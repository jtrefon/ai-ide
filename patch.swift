import Foundation

let path = "osx-ide/Services/ConversationFlow/ToolLoopHandler.swift"
var content = try String(contentsOfFile: path)
content = content.replacingOccurrences(of: """
    private func shouldForceContinuationForIncompletePlan(conversationId: String, content: String?) async -> Bool {
        guard let plan = await ConversationPlanStore.shared.get(conversationId: conversationId),
              !plan.isEmpty else {
            return false
        }

        let progress = PlanChecklistTracker.progress(in: plan)
        guard progress.total > 0, !progress.isComplete else {
            return false
        }

        let deliveryStatus = ChatPromptBuilder.deliveryStatus(from: content ?? "")
        return deliveryStatus != .done
    }
""", with: """
    private func shouldForceContinuationForIncompletePlan(conversationId: String, content: String?) async -> Bool {
        guard let plan = await ConversationPlanStore.shared.get(conversationId: conversationId),
              !plan.isEmpty else {
            print("DEBUG shouldForceContinuationForIncompletePlan: plan is empty or nil")
            return false
        }

        let progress = PlanChecklistTracker.progress(in: plan)
        print("DEBUG shouldForceContinuationForIncompletePlan: progress total=\\(progress.total) completed=\\(progress.completed) isComplete=\\(progress.isComplete)")
        guard progress.total > 0, !progress.isComplete else {
            print("DEBUG shouldForceContinuationForIncompletePlan: progress is complete or 0 total")
            return false
        }

        let deliveryStatus = ChatPromptBuilder.deliveryStatus(from: content ?? "")
        print("DEBUG shouldForceContinuationForIncompletePlan: deliveryStatus=\\(deliveryStatus)")
        return deliveryStatus != .done
    }
""")
try content.write(toFile: path, atomically: true, encoding: .utf8)
