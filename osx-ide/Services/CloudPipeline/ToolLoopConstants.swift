import Foundation

/// Centralized constants for tool loop processing.
/// Eliminates magic numbers scattered across handlers and improves maintainability.
enum ToolLoopConstants {
    // MARK: - Iteration Limits

    /// Maximum tool loop iterations for agent mode (OpenRouter/large models)
    static let maxAgentIterations = 50

    /// Maximum tool loop iterations for non-agent modes
    static let maxNonAgentIterations = 10

    /// Maximum tool loop iterations for MLX/local models
    /// Tuned for Gemma 4 with RAG context + ToolLoopHandler stall detection
    static let maxMLXIterations = 10

    /// Maximum times BranchReviewNode can route back to ToolLoopNode when the model
    /// returns no tool calls. Prevents infinite graph cycles where the plan is incomplete
    /// but the model never produces tool calls to make progress.
    static let maxExecutionCycles = 5

    /// Maximum number of graph-level re-entries triggered solely by soft signals
    /// (indicates-unfinished / needs-work). These are capped separately from
    /// maxExecutionCycles to prevent mindless re-entry loops while still allowing
    /// the model a limited number of "one more try" opportunities.
    static let maxNeedsWorkReentries = 2

    /// Returns the appropriate max iterations based on mode and model capability
    static func maxIterations(for mode: AIMode?, isMLX: Bool = false) -> Int {
        if isMLX {
            return maxMLXIterations
        }
        switch mode {
        case .agent:
            return maxAgentIterations
        case .chat, .coder, .none:
            return maxNonAgentIterations
        }
    }

    // MARK: - Stall Detection Thresholds

    /// Number of repeated tool batches before stall detection triggers
    static let repeatedBatchStallThreshold = 4

    /// Number of repeated already-completed tool signature rounds before forcing finalization.
    static let repeatedCompletedSignatureStallThreshold = 5

    /// Number of consecutive empty responses before stall detection triggers
    static let emptyResponseStallThreshold = 3

    /// Number of consecutive read-only iterations before nudge is added
    static let readOnlyIterationNudgeThreshold = 5

    /// Number of consecutive read-only iterations before stall detection triggers
    static let readOnlyIterationStallThreshold = 10

    /// Number of repeated read-only batches before stall detection triggers
    static let repeatedReadOnlyBatchStallThreshold = 3

    /// Number of non-mutating iterations allowed after at least one successful write/mutation.
    static let postWriteNonMutationStallThreshold = 3

    /// Number of repeated content occurrences for textual tool call patterns
    static let textualPatternRepeatedThreshold = 3

    /// Number of repeated content occurrences for normal patterns
    static let normalPatternRepeatedThreshold = 4

    /// Number of consecutive iterations with the same write targets before forcing diversification
    static let repeatedWriteTargetStallThreshold = 4

    // MARK: - Convergence / progress (Context Access Layer, RC6)

    /// Maximum consecutive read-only iterations since the last successful mutation
    /// before the loop is considered stalled (the model is re-reading without converging).
    static let maxReadsWithoutMutation = 15

    /// Maximum wall-clock duration for a single tool-loop execution (seconds).
    /// When exceeded the loop forces a final summary regardless of model state.
    /// Set to 10 minutes — generous for complex tasks, but prevents unattended runaway.
    static let maxToolLoopDuration: TimeInterval = 600

    // MARK: - Text Truncation Limits

    /// Character limit for tool result previews in summaries
    static let toolResultPreviewLimit = 1000

    /// Character limit for tool output previews in snapshots
    static let toolOutputSnapshotLimit = 2000

    /// Character limit for failure reason previews
    static let failurePreviewLimit = 500

    /// Character limit for tool result content before truncation
    static let toolResultContentLimit = 2000

    /// Character allowance when enforcing budget on tool results
    static let toolResultBudgetAllowance = 1000

    // MARK: - Message Truncation

    /// Maximum characters per tool result (defined in MessageTruncationPolicy)
    /// Reduced from 5000 to minimize context bloat from repeated file reads.
    /// 2000 chars captures imports, types, and function signatures — enough
    /// for the model to understand file structure without full file bodies.
    static let maxToolResultCharacters = 2000

    /// Maximum total message characters (defined in MessageTruncationPolicy)
    static let maxTotalMessageCharacters = 120_000
}
