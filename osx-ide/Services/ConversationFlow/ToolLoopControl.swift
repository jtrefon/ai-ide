//
//  ToolLoopControl.swift
//  osx-ide
//
//  Tool loop control logic for managing iterations and termination conditions
//

import Foundation

/// Manages tool loop iteration control and termination conditions
@MainActor
class ToolLoopControl {
    private(set) var toolIteration: Int = 0
    private(set) var consecutiveEmptyToolCallResponses: Int = 0
    private(set) var repeatedToolBatchCount: Int = 0
    private(set) var repeatedNoToolCallContentCount: Int = 0
    private(set) var consecutiveReadOnlyToolIterations: Int = 0
    private(set) var repeatedReadOnlyToolBatchCount: Int = 0
    
    private var previousToolBatchSignature: String?
    private var previousNoToolCallContentSignature: String?
    private var previousReadOnlyToolBatchSignature: String?
    
    let maxIterations: Int
    
    init(maxIterations: Int = 50) {
        self.maxIterations = maxIterations
    }
    
    /// Reset control state for a new tool loop
    func reset() {
        toolIteration = 0
        consecutiveEmptyToolCallResponses = 0
        repeatedToolBatchCount = 0
        repeatedNoToolCallContentCount = 0
        consecutiveReadOnlyToolIterations = 0
        repeatedReadOnlyToolBatchCount = 0
        
        previousToolBatchSignature = nil
        previousNoToolCallContentSignature = nil
        previousReadOnlyToolBatchSignature = nil
    }
    
    /// Increment iteration counter and return current count
    func incrementIteration() -> Int {
        toolIteration += 1
        return toolIteration
    }
    
    /// Check if the loop should continue based on tool calls
    func shouldContinue(with toolCalls: [AIToolCall]?) -> Bool {
        guard let toolCalls = toolCalls, !toolCalls.isEmpty else {
            return false
        }
        return toolIteration < maxIterations
    }
    
    /// Update batch tracking and check for repeated batches
    func updateBatchTracking(toolCalls: [AIToolCall]) -> Bool {
        let currentBatchSignature = ToolLoopDeduplication.toolBatchSignature(toolCalls)
        
        if let previousSignature = previousToolBatchSignature,
           previousSignature == currentBatchSignature {
            repeatedToolBatchCount += 1
        } else {
            repeatedToolBatchCount = 0
        }
        
        previousToolBatchSignature = currentBatchSignature
        return repeatedToolBatchCount > 0
    }
    
    /// Update content tracking for responses without tool calls
    func updateContentTracking(content: String?) -> Bool {
        let currentSignature = ToolLoopDeduplication.normalizedNoToolCallContentSignature(content)
        
        if let previousSignature = previousNoToolCallContentSignature,
           previousSignature == currentSignature {
            repeatedNoToolCallContentCount += 1
        } else {
            repeatedNoToolCallContentCount = 0
        }
        
        previousNoToolCallContentSignature = currentSignature
        return repeatedNoToolCallContentCount > 0
    }
    
    /// Check if the loop should stop due to repeated content
    func shouldStopForRepeatedContent() -> Bool {
        return repeatedNoToolCallContentCount >= 3
    }
    
    /// Update read-only tool tracking
    func updateReadOnlyTracking(toolCalls: [AIToolCall]) -> Bool {
        let isReadOnlyBatch = ToolLoopDeduplication.areReadOnlyToolCalls(toolCalls)
        
        if isReadOnlyBatch {
            consecutiveReadOnlyToolIterations += 1
            
            let currentSignature = ToolLoopDeduplication.readOnlyToolBatchSignature(toolCalls)
            if let previousSignature = previousReadOnlyToolBatchSignature,
               previousSignature == currentSignature {
                repeatedReadOnlyToolBatchCount += 1
            } else {
                repeatedReadOnlyToolBatchCount = 0
            }
            
            previousReadOnlyToolBatchSignature = currentSignature
        } else {
            consecutiveReadOnlyToolIterations = 0
            repeatedReadOnlyToolBatchCount = 0
            previousReadOnlyToolBatchSignature = nil
        }
        
        return consecutiveReadOnlyToolIterations >= 5
    }
    
    /// Check if the loop should stop due to read-only tool stall
    func shouldStopForReadOnlyStall() -> Bool {
        return consecutiveReadOnlyToolIterations >= 5 || repeatedReadOnlyToolBatchCount >= 3
    }
    
    /// Check if the loop should stop due to repeated tool batches
    func shouldStopForRepeatedBatches() -> Bool {
        return repeatedToolBatchCount >= 3
    }
    
    /// Check if the loop should stop due to empty tool call responses
    func shouldStopForEmptyResponses() -> Bool {
        return consecutiveEmptyToolCallResponses >= 3
    }
    
    /// Increment empty response counter
    func incrementEmptyResponses() {
        consecutiveEmptyToolCallResponses += 1
    }
    
    /// Get a summary of the loop control state
    var summary: String {
        return """
        Tool Loop Control Summary:
        - Iterations: \(toolIteration)/\(maxIterations)
        - Consecutive Empty Responses: \(consecutiveEmptyToolCallResponses)
        - Repeated Tool Batches: \(repeatedToolBatchCount)
        - Repeated Content: \(repeatedNoToolCallContentCount)
        - Consecutive Read-Only Iterations: \(consecutiveReadOnlyToolIterations)
        - Repeated Read-Only Batches: \(repeatedReadOnlyToolBatchCount)
        """
    }
}
