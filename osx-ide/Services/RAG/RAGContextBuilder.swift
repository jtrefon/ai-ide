import Foundation

public enum RAGContextBuilder {
    /// Stage-aware token budgets (approximate character limits)
    private static let stageBudgets: [AIRequestStage: Int] = [
        .initial_response: 32_000,      // 8K tokens * 4 chars/token
        .tool_loop: 16_000,             // 4K tokens * 4 chars/token
        .final_response: 8_000,         // 2K tokens * 4 chars/token
        .warmup: 32_000,
        .strategic_planning: 24_000,
        .tactical_planning: 24_000,
        .qa_tool_output_review: 16_000,
        .qa_quality_review: 16_000,
        .other: 32_000
    ]
    
    public static func buildContext(
        userInput: String,
        explicitContext: String?,
        retriever: (any RAGRetriever)?,
        projectRoot: URL?,
        stage: AIRequestStage? = nil,
        conversationId: String? = nil,
        eventBus: (any EventBusProtocol)? = nil
    ) async -> String? {
        var parts: [String] = []

        if let executionEnvironmentContext = buildExecutionEnvironmentContext(projectRoot: projectRoot) {
            parts.append(executionEnvironmentContext)
        }

        if let explicitContext {
            let trimmed = explicitContext.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append(trimmed)
            }
        }

        guard let retriever else {
            return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        }
        
        // Get budget for current stage
        let budget = stage.flatMap { stageBudgets[$0] } ?? 32_000

        // Publish retrieval started event
        eventBus?.publish(RAGRetrievalStartedEvent(userInputPreview: userInput))

        // Wrap RAG retrieval with power management to prevent sleep during long operations
        let retrieval = await AgentActivityCoordinator.shared.withActivity(type: .ragRetrieval) {
            await retriever.retrieve(
                RAGRetrievalRequest(
                    userInput: userInput,
                    projectRoot: projectRoot,
                    stage: stage?.rawValue,
                    conversationId: conversationId
                )
            )
        }
        var ragBlock = formatRAGBlock(retrieval)

        eventBus?.publish(
            RetrievalEvidencePreparedEvent(
                evidenceCount: retrieval.evidenceCards.count,
                retrievalIntent: retrieval.intent.rawValue,
                retrievalConfidence: retrieval.retrievalConfidence
            )
        )

        // Apply budget trimming if needed
        let explicitContextSize = parts.joined(separator: "\n\n").count
        let availableBudget = budget - explicitContextSize
        
        if let trimmedBlock = ragBlock, trimmedBlock.count > availableBudget {
            ragBlock = trimContextToBudget(trimmedBlock, budget: availableBudget, retrieval: retrieval)
            print("[RAGContext] Trimmed RAG context from \(trimmedBlock.count) to \(ragBlock?.count ?? 0) chars to fit budget \(budget)")
        }

        // Publish retrieval completed event
        eventBus?.publish(RAGRetrievalCompletedEvent(
            symbolCount: retrieval.symbolLines.count,
            overviewCount: retrieval.projectOverviewLines.count,
            memoryCount: retrieval.memoryLines.count,
            segmentCount: retrieval.segmentLines.count,
            evidenceCount: retrieval.evidenceCards.count,
            retrievalIntent: retrieval.intent.rawValue,
            retrievalConfidence: retrieval.retrievalConfidence,
            contextCharCount: ragBlock?.count ?? 0
        ))

        // DIAGNOSTIC: Log RAG context size
        if let ragBlock {
            print("[RAGContext] Added \(ragBlock.count) chars from RAG: symbols=\(retrieval.symbolLines.count), overview=\(retrieval.projectOverviewLines.count), memory=\(retrieval.memoryLines.count)")
            parts.append(ragBlock)
        }

        let result = parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        if let result {
            print("[RAGContext] Total context size: \(result.count) chars (budget: \(budget))")
        }
        return result
    }
    
    private static func trimContextToBudget(_ context: String, budget: Int, retrieval: RAGRetrievalResult) -> String? {
        guard budget > 0 else { return nil }
        
        // Priority order: memory > overview > symbols > segments > reuse
        var sections: [(priority: Int, content: String)] = []
        
        if !retrieval.memoryLines.isEmpty {
            sections.append((priority: 1, content: "PROJECT MEMORY (long-term rules):\n" + retrieval.memoryLines.joined(separator: "\n")))
        }
        
        if !retrieval.projectOverviewLines.isEmpty {
            sections.append((priority: 2, content: "PROJECT OVERVIEW (Key Files):\n" + retrieval.projectOverviewLines.joined(separator: "\n")))
        }
        
        if !retrieval.symbolLines.isEmpty {
            sections.append((priority: 3, content: "CODEBASE INDEX (matching symbols):\n" + retrieval.symbolLines.joined(separator: "\n")))
        }
        
        if !retrieval.segmentLines.isEmpty {
            sections.append((priority: 4, content: "CODE SEGMENTS (high-signal snippets):\n" + retrieval.segmentLines.joined(separator: "\n")))
        }
        
        if !retrieval.reuseCandidateLines.isEmpty {
            sections.append((priority: 5, content: "REUSE CANDIDATES (must consider before new implementation):\n" + retrieval.reuseCandidateLines.joined(separator: "\n")))
        }
        
        // Build context within budget
        var result = "RAG CONTEXT:\n"
        var remainingBudget = budget - result.count
        
        for section in sections.sorted(by: { $0.priority < $1.priority }) {
            let sectionWithSeparator = section.content + "\n\n"
            if sectionWithSeparator.count <= remainingBudget {
                result += sectionWithSeparator
                remainingBudget -= sectionWithSeparator.count
            } else if remainingBudget > 100 {
                // Include partial section if we have room
                let truncated = String(section.content.prefix(remainingBudget - 20)) + "...\n\n"
                result += truncated
                break
            } else {
                break
            }
        }
        
        return result.isEmpty ? nil : result
    }

    private static func formatRAGBlock(_ retrieval: RAGRetrievalResult) -> String? {
        var sections: [String] = []

        if !retrieval.projectOverviewLines.isEmpty {
            sections.append("PROJECT OVERVIEW (Key Files):\n" + retrieval.projectOverviewLines.joined(separator: "\n"))
        }

        if !retrieval.symbolLines.isEmpty {
            sections.append("CODEBASE INDEX (matching symbols):\n" + retrieval.symbolLines.joined(separator: "\n"))
        }

        if !retrieval.memoryLines.isEmpty {
            sections.append("PROJECT MEMORY (long-term rules):\n" + retrieval.memoryLines.joined(separator: "\n"))
        }

        if !retrieval.segmentLines.isEmpty {
            sections.append("CODE SEGMENTS (high-signal snippets):\n" + retrieval.segmentLines.joined(separator: "\n"))
        }

        if !retrieval.reuseCandidateLines.isEmpty {
            sections.append("REUSE CANDIDATES (must consider before new implementation):\n" + retrieval.reuseCandidateLines.joined(separator: "\n"))
        }

        guard !sections.isEmpty else { return nil }
        return "RAG CONTEXT:\n" + sections.joined(separator: "\n\n")
    }

    private static func buildExecutionEnvironmentContext(projectRoot: URL?) -> String? {
        let processInfo = ProcessInfo.processInfo
        let operatingSystemVersion = processInfo.operatingSystemVersion
        let operatingSystemSummary = processInfo.operatingSystemVersionString
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let shell = processInfo.environment["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let architecture = processInfo.environment["PROCESSOR_ARCHITECTURE"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? processInfo.environment["HOSTTYPE"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "apple_silicon_or_intel_mac"

        var lines: [String] = [
            "EXECUTION ENVIRONMENT:",
            "Platform: macOS",
            "macOS Version: \(operatingSystemVersion.majorVersion).\(operatingSystemVersion.minorVersion).\(operatingSystemVersion.patchVersion)",
            "OS Summary: \(operatingSystemSummary)",
            "Architecture: \(architecture)",
            "Shell: \(shell?.isEmpty == false ? shell! : "/bin/zsh")"
        ]

        if let projectRoot {
            lines.append("Project Root: \(projectRoot.path)")
            lines.append("Working Directory Scope: Use the project root unless a tool contract requires another path.")
        }

        lines.append("CLI Guidance: Prefer macOS-compatible shell commands and paths. Do not assume Linux-only utilities or package-manager behavior.")
        return lines.joined(separator: "\n")
    }
}
