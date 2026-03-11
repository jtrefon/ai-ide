import Foundation

@MainActor
struct OrchestrationState: Sendable {
    struct BranchExecution: Sendable {
        struct Branch: Sendable, Equatable {
            let id: String
            let title: String
            let checklistItems: [String]
        }

        let plan: String
        let globalInvariants: [String]
        let branches: [Branch]
        var activeBranchIndex: Int

        var activeBranch: Branch? {
            guard branches.indices.contains(activeBranchIndex) else { return nil }
            return branches[activeBranchIndex]
        }

        var hasAdditionalBranches: Bool {
            activeBranchIndex + 1 < branches.count
        }

        func advanced() -> BranchExecution {
            BranchExecution(
                plan: plan,
                globalInvariants: globalInvariants,
                branches: branches,
                activeBranchIndex: min(activeBranchIndex + 1, max(0, branches.count - 1))
            )
        }

        func makeContext(baseExplicitContext: String?) -> String? {
            var parts: [String] = []

            if let baseExplicitContext {
                let trimmedBase = baseExplicitContext.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedBase.isEmpty {
                    parts.append(trimmedBase)
                }
            }

            guard let activeBranch else {
                return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
            }

            var branchSections: [String] = []
            branchSections.append("BRANCH EXECUTION CONTEXT:")
            branchSections.append("Active branch \(activeBranchIndex + 1)/\(branches.count): \(activeBranch.title)")

            if !globalInvariants.isEmpty {
                branchSections.append("Global invariants:")
                branchSections.append(globalInvariants.map { "- \($0)" }.joined(separator: "\n"))
            }

            if !activeBranch.checklistItems.isEmpty {
                branchSections.append("Branch checklist:")
                branchSections.append(activeBranch.checklistItems.map { "- [ ] \($0)" }.joined(separator: "\n"))
            }

            branchSections.append("Plan reference:")
            branchSections.append(plan)
            parts.append(branchSections.joined(separator: "\n"))

            return parts.joined(separator: "\n\n")
        }
    }

    struct Transition: Sendable {
        let nextNodeId: String?

        static func next(_ id: String) -> Transition {
            Transition(nextNodeId: id)
        }

        static let end = Transition(nextNodeId: nil)
    }

    let request: SendRequest

    var response: AIServiceResponse?
    var lastToolResults: [ChatMessage]
    var branchExecution: BranchExecution?

    var transition: Transition

    var effectiveExplicitContext: String? {
        branchExecution?.makeContext(baseExplicitContext: request.explicitContext) ?? request.explicitContext
    }

    init(
        request: SendRequest,
        response: AIServiceResponse? = nil,
        lastToolResults: [ChatMessage] = [],
        branchExecution: BranchExecution? = nil,
        transition: Transition
    ) {
        self.request = request
        self.response = response
        self.lastToolResults = lastToolResults
        self.branchExecution = branchExecution
        self.transition = transition
    }
}
