import Foundation

/// Lightweight task tracker that persists the current objective across tool calls.
///
/// WHY THIS EXISTS:
///   The agent loses track of the main task after 2-3 tool calls. It forgets what
///   it's trying to accomplish and spirals into exploration loops (directory listings,
///   re-reading already-read files, re-trying failed approaches).
///
/// HOW IT WORKS:
///   At the start of each turn, the orchestrator injects:
///     1. The current task (what we're trying to do)
///     2. What's been done (completed tool calls with results)
///     3. What's left (remaining steps)
///
///   After each tool call, the tracker updates the plan.
///   If the model goes off-task (e.g., starts exploring unrelated files), the
///   tracker surfaces the discrepancy.
///
actor TaskPlanTracker {
    private var conversations: [String: TaskState] = [:]

    struct TaskState: Sendable {
        let objective: String
        var completedSteps: [CompletedStep] = []
        var remainingSteps: [String] = []
        var errors: [String] = []
        var startedAt: Date
        var maxTurns: Int
    }

    struct CompletedStep: Sendable {
        let description: String
        let toolName: String
        let result: String
        let timestamp: Date
    }

    // MARK: - Public API

    /// Start tracking a new task.
    func startTask(
        conversationId: String,
        objective: String,
        remainingSteps: [String] = [],
        maxTurns: Int = 30
    ) {
        conversations[conversationId] = TaskState(
            objective: objective,
            remainingSteps: remainingSteps,
            startedAt: Date(),
            maxTurns: maxTurns
        )
    }

    /// Record a completed step.
    func recordStep(
        conversationId: String,
        description: String,
        toolName: String,
        result: String
    ) {
        guard var state = conversations[conversationId] else { return }
        let step = CompletedStep(
            description: description,
            toolName: toolName,
            result: result.truncated(200),
            timestamp: Date()
        )
        state.completedSteps.append(step)
        conversations[conversationId] = state
    }

    /// Record an error.
    func recordError(conversationId: String, error: String) {
        guard var state = conversations[conversationId] else { return }
        state.errors.append(error)
        conversations[conversationId] = state
    }

    /// Generate the task progress summary for the model's context.
    func progressSummary(conversationId: String) -> String {
        guard let state = conversations[conversationId] else {
            return ""
        }

        var lines: [String] = []
        lines.append("## Current Task")
        lines.append("Objective: \(state.objective)")
        lines.append("")

        if !state.completedSteps.isEmpty {
            lines.append("### Completed Steps (\(state.completedSteps.count))")
            for (i, step) in state.completedSteps.enumerated() {
                let shortResult = step.result.truncated(100)
                lines.append("  \(i + 1). \(step.description)")
                lines.append("     Tool: \(step.toolName) → \(shortResult)")
            }
            lines.append("")
        }

        if !state.remainingSteps.isEmpty {
            lines.append("### Remaining Steps")
            for step in state.remainingSteps {
                lines.append("  - \(step)")
            }
            lines.append("")
        }

        if !state.errors.isEmpty {
            lines.append("### Errors (need recovery or alternative approach)")
            for error in state.errors.suffix(3) {
                lines.append("  - ⚠ \(error)")
            }
            lines.append("")
        }

        let elapsed = Int(Date().timeIntervalSince(state.startedAt))
        lines.append("Elapsed: \(elapsed)s | Turns used: \(state.completedSteps.count)/\(state.maxTurns)")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    /// Check if the agent is off-task based on what it's doing vs the objective.
    func isOffTask(conversationId: String, currentToolName: String, currentArguments: [String: ToolValue]) -> OffTaskAssessment {
        guard let state = conversations[conversationId] else {
            return .onTask("No task context")
        }

        // Detect exploration loops: 3+ consecutive list_dir calls
        let recentListDirs = state.completedSteps.suffix(3).filter { $0.toolName == "list_dir" || $0.toolName == "list_files" }.count
        if recentListDirs >= 3 {
            return .warning("You've listed directories 3+ times in a row. Check the project structure you already have and move to the next step.")
        }

        // Detect reading the same file multiple times
        let recentReads = state.completedSteps.suffix(4).filter { $0.toolName == "read_file" }
        if recentReads.count >= 3 {
            return .warning("You've read several files. Review what you already know and take action.")
        }

        // Detect repeated tool errors
        let recentErrors = state.errors.suffix(3)
        if recentErrors.count >= 3 {
            return .abort("Same approach has failed \(recentErrors.count) times. Try a fundamentally different strategy.")
        }

        return .onTask("Proceed with the current plan")
    }

    enum OffTaskAssessment: Sendable, Equatable {
        case onTask(String)
        case warning(String)
        case abort(String)
    }
}

// MARK: - String Truncation

private extension String {
    func truncated(_ maxLength: Int) -> String {
        if count <= maxLength { return self }
        return String(prefix(maxLength)) + "..."
    }
}
