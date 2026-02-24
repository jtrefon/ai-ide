//
//  ModelCapability.swift
//  osx-ide
//
//  Created by AI Assistant on 20/02/2026.
//  Defines model capability levels for routing decisions
//

import Foundation

/// Protocol defining what capabilities a model supports
public protocol ModelCapability: Sendable {
    /// Whether the model supports advanced orchestration (multiple tool loop iterations, planning nodes)
    var supportsAdvancedOrchestration: Bool { get }
    
    /// Whether the model supports complex structured reasoning (6-section ide_reasoning blocks)
    var supportsComplexReasoning: Bool { get }
    
    /// Maximum context tokens the model can handle
    var maxContextTokens: Int { get }
    
    /// Recommended maximum tool loop iterations for this model
    var recommendedMaxIterations: Int { get }
    
    /// Whether the model can reliably emit structured tool calls
    var supportsStructuredToolCalls: Bool { get }
    
    /// Whether the model should use the full RAG system
    var supportsFullRAG: Bool { get }
}

/// OpenRouter model capabilities - large models with full feature support
public struct OpenRouterCapability: ModelCapability {
    public let supportsAdvancedOrchestration: Bool = true
    public let supportsComplexReasoning: Bool = true
    public let maxContextTokens: Int = 128_000
    public let recommendedMaxIterations: Int = 12
    public let supportsStructuredToolCalls: Bool = true
    public let supportsFullRAG: Bool = true
    
    public init() {}
}

/// MLX local model capabilities - small models with limited feature support
public struct MLXCapability: ModelCapability {
    public let supportsAdvancedOrchestration: Bool = false
    public let supportsComplexReasoning: Bool = false
    public let maxContextTokens: Int = 4096
    public let recommendedMaxIterations: Int = 3
    public let supportsStructuredToolCalls: Bool = false
    public let supportsFullRAG: Bool = true  // RAG still works, just not agent mode
    
    public init() {}
}

/// Factory for creating model capabilities based on configuration
public enum ModelCapabilityFactory {
    /// Creates the appropriate capability based on whether offline mode is enabled
    public static func capability(isOfflineMode: Bool, hasLocalModel: Bool) -> any ModelCapability {
        if isOfflineMode || hasLocalModel {
            return MLXCapability()
        }
        return OpenRouterCapability()
    }
}
