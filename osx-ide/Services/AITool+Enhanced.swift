import Foundation

/// Enhanced AITool protocol with comprehensive prompt support
public protocol EnhancedAITool: AITool {
    /// Comprehensive tool description for system prompts
    var comprehensiveDescription: String { get }
    
    /// When to use this tool (detailed guidance)
    var whenToUse: String { get }
    
    /// When NOT to use this tool (anti-patterns)
    var whenNotToUse: String { get }
    
    /// Detailed parameter descriptions
    var parameterDescriptions: [String: String] { get }
    
    /// Usage examples in markdown format
    var usageExamples: String { get }
    
    /// Expected output structure description
    var outputStructure: String { get }
    
    /// Success indicators for tool execution
    var successIndicators: String { get }
    
    /// Error handling guidance
    var errorHandling: String { get }
    
    /// Best practices for using this tool
    var bestPractices: String { get }
    
    /// Integration notes and side effects
    var integrationNotes: String { get }
}

/// Default implementation for tools that don't provide enhanced descriptions
public extension EnhancedAITool {
    var comprehensiveDescription: String {
        return description
    }
    
    var whenToUse: String {
        return "Use when you need to perform this operation."
    }
    
    var whenNotToUse: String {
        return "Avoid using when alternative tools are more appropriate."
    }
    
    var parameterDescriptions: [String: String] {
        return [:]
    }
    
    var usageExamples: String {
        return "No specific examples available."
    }
    
    var outputStructure: String {
        return "Returns standard tool response with status and message."
    }
    
    var successIndicators: String {
        return "Tool completes without errors and returns expected results."
    }
    
    var errorHandling: String {
        return "Check tool output for error messages and handle appropriately."
    }
    
    var bestPractices: String {
        return "Use tool as intended and verify results before proceeding."
    }
    
    var integrationNotes: String {
        return "Standard tool integration."
    }
}

/// Tool prompt builder for assembling comprehensive tool descriptions
public struct ToolPromptBuilder {
    public static func buildToolDescription(for tool: EnhancedAITool) -> String {
        var sections: [String] = []
        
        sections.append("### \(tool.name)")
        sections.append("")
        sections.append("**Purpose**: \(tool.comprehensiveDescription)")
        sections.append("")
        
        sections.append("**When to Use**:")
        sections.append(tool.whenToUse)
        sections.append("")
        
        sections.append("**When NOT to Use**:")
        sections.append(tool.whenNotToUse)
        sections.append("")
        
        if !tool.parameterDescriptions.isEmpty {
            sections.append("**Parameters**:")
            for (param, desc) in tool.parameterDescriptions {
                sections.append("- `\(param)`: \(desc)")
            }
            sections.append("")
        }
        
        sections.append("**Usage Examples**:")
        sections.append(tool.usageExamples)
        sections.append("")
        
        sections.append("**Expected Output**:")
        sections.append(tool.outputStructure)
        sections.append("")
        
        sections.append("**Success Indicators**:")
        sections.append(tool.successIndicators)
        sections.append("")
        
        sections.append("**Error Handling**:")
        sections.append(tool.errorHandling)
        sections.append("")
        
        sections.append("**Best Practices**:")
        sections.append(tool.bestPractices)
        sections.append("")
        
        sections.append("**Integration Notes**:")
        sections.append(tool.integrationNotes)
        sections.append("")
        
        return sections.joined(separator: "\n")
    }
    
    public static func buildToolDescriptionsSection(for tools: [EnhancedAITool]) -> String {
        var sections: [String] = []
        
        sections.append("## Available Tools")
        sections.append("")
        
        for tool in tools {
            sections.append(buildToolDescription(for: tool))
            sections.append("---")
            sections.append("")
        }
        
        return sections.joined(separator: "\n")
    }
}
