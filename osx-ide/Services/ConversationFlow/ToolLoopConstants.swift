import Foundation

/// Centralized constants for tool loop processing.
/// Eliminates magic numbers scattered across handlers and improves maintainability.
enum ToolLoopConstants {
    // MARK: - Iteration Limits
    
    /// Maximum tool loop iterations for agent mode
    static let maxAgentIterations = 12
    
    /// Maximum tool loop iterations for non-agent modes
    static let maxNonAgentIterations = 5
    
    // MARK: - Stall Detection Thresholds
    
    /// Number of repeated tool batches before stall detection triggers
    static let repeatedBatchStallThreshold = 2
    
    /// Number of consecutive empty responses before stall detection triggers
    static let emptyResponseStallThreshold = 2
    
    /// Number of consecutive read-only iterations before nudge is added
    static let readOnlyIterationNudgeThreshold = 2
    
    /// Number of consecutive read-only iterations before stall detection triggers
    static let readOnlyIterationStallThreshold = 3
    
    /// Number of repeated read-only batches before stall detection triggers
    static let repeatedReadOnlyBatchStallThreshold = 2
    
    /// Number of repeated content occurrences for textual tool call patterns
    static let textualPatternRepeatedThreshold = 1
    
    /// Number of repeated content occurrences for normal patterns
    static let normalPatternRepeatedThreshold = 2
    
    // MARK: - Text Truncation Limits
    
    /// Character limit for tool result previews in summaries
    static let toolResultPreviewLimit = 400
    
    /// Character limit for tool output previews in snapshots
    static let toolOutputSnapshotLimit = 1200
    
    /// Character limit for failure reason previews
    static let failurePreviewLimit = 300
    
    /// Character limit for tool result content before truncation
    static let toolResultContentLimit = 500
    
    /// Character allowance when enforcing budget on tool results
    static let toolResultBudgetAllowance = 500
    
    // MARK: - Message Truncation
    
    /// Maximum characters per tool result (defined in MessageTruncationPolicy)
    static let maxToolResultCharacters = 2000
    
    /// Maximum total message characters (defined in MessageTruncationPolicy)
    static let maxTotalMessageCharacters = 12_000
}
