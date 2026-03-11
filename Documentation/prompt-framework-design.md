# Comprehensive Prompt Framework Design

## Overview

This document describes the new comprehensive prompt framework designed to solve the tool calling issues and provide a robust, maintainable system for AI agent orchestration.

## Problem Statement

The current system has several critical issues:

1. **Inadequate Tool Descriptions**: Tools only have brief descriptions, not comprehensive usage guidance
2. **Static System Prompts**: Tool descriptions are hardcoded in system prompts instead of dynamically assembled
3. **No Tool Usage Documentation**: Models don't understand when/how to use specific tools
4. **Inconsistent Prompt Assembly**: Different logic between OpenRouter and MLX services
5. **Missing Tool Output Documentation**: No clear documentation of what tools return

## Solution Architecture

### Design Principles

1. **Factory Pattern**: Centralized prompt assembly with configurable components
2. **Strategy Pattern**: Different prompt strategies for different modes and stages
3. **Template Method**: Consistent assembly process with customizable components
4. **Separation of Concerns**: Tool descriptions, system prompts, and orchestration logic are separate
5. **Markdown-Based Prompts**: All prompts stored in markdown files for easy editing

### Core Components

#### 1. Enhanced AITool Protocol

```swift
public protocol EnhancedAITool: AITool {
    var comprehensiveDescription: String { get }
    var whenToUse: String { get }
    var whenNotToUse: String { get }
    var parameterDescriptions: [String: String] { get }
    var usageExamples: String { get }
    var outputStructure: String { get }
    var successIndicators: String { get }
    var errorHandling: String { get }
    var bestPractices: String { get }
    var integrationNotes: String { get }
}
```

#### 2. Prompt Factory

```swift
public actor PromptFactory {
    public func assembleSystemPrompt(
        tools: [EnhancedAITool]?,
        mode: AIMode?,
        projectRoot: URL?,
        reasoningEnabled: Bool,
        stage: AIRequestStage?
    ) async throws -> String
}
```

#### 3. Component-Based Assembly

- **Base System Prompt**: Core principles and instructions
- **Tool Descriptions**: Dynamically generated from tool metadata
- **Mode-Specific Instructions**: Chat vs Agent mode guidance
- **Project Context**: Current project information
- **Reasoning Instructions**: Stage-specific reasoning guidance
- **Custom Overrides**: User-provided system prompts

### File Structure

```
Prompts/
├── System/
│   ├── base-system-prompt.md
│   ├── chat-mode-instructions.md
│   ├── agent-mode-instructions.md
│   └── reasoning-instructions.md
├── Tools/
│   ├── template.md
│   ├── write_files.md
│   ├── replace_in_file.md
│   ├── read_file.md
│   └── ...
└── ConversationFlow/
    ├── Corrections/
    ├── DeliveryGate/
    └── QA/
```

## Implementation Details

### 1. Tool Description Framework

Each tool provides comprehensive documentation including:

- **Purpose**: What the tool does
- **When to Use**: Specific scenarios and use cases
- **When NOT to Use**: Anti-patterns and alternatives
- **Parameters**: Detailed parameter descriptions
- **Usage Examples**: Real JSON examples
- **Output Structure**: Expected response format
- **Success Indicators**: How to verify successful execution
- **Error Handling**: Common errors and recovery
- **Best Practices**: Usage guidelines
- **Integration Notes**: Side effects and interactions

### 2. Prompt Assembly Process

```swift
// Priority-based component assembly
let components = [
    baseSystemPrompt,           // Priority: 100
    customOverride,            // Priority: 150
    toolDescriptions,          // Priority: 200
    modeSpecific,              // Priority: 300
    projectContext,            // Priority: 400
    reasoningInstructions      // Priority: 500
]
```

### 3. Template Variables

Base system prompt uses template variables for dynamic insertion:

```markdown
{{TOOL_DESCRIPTIONS}}
{{MODE_SPECIFIC_INSTRUCTIONS}}
{{PROJECT_ROOT_CONTEXT}}
{{REASONING_INSTRUCTIONS}}
```

### 4. Integration Points

#### OpenRouter Service Integration

```swift
let promptFactory = PromptFactory(settingsStore: settingsStore, fileSystemService: fileSystemService)
let systemContent = try await promptFactory.assembleSystemPrompt(
    tools: enhancedTools,
    mode: request.mode,
    projectRoot: request.projectRoot,
    reasoningEnabled: settings.reasoningEnabled,
    stage: request.stage
)
```

#### Tool Provider Enhancement

```swift
func availableTools(mode: AIMode, pathValidator: PathValidator) -> [EnhancedAITool] {
    let filteredTools = mode.allowedTools(from: allTools(pathValidator: pathValidator))
    return filteredTools.compactMap { $0 as? EnhancedAITool }
}
```

## Benefits

### 1. Improved Tool Calling

- **Clear Instructions**: Models understand exactly when and how to use tools
- **Comprehensive Examples**: Real JSON examples show proper usage
- **Output Documentation**: Models know what to expect from tool responses
- **Error Guidance**: Models can handle tool failures appropriately

### 2. Maintainability

- **Markdown-Based**: Easy to edit prompts without code changes
- **Modular Design**: Components can be updated independently
- **Type Safety**: Enhanced protocol ensures all required information is provided
- **Testability**: Each component can be tested in isolation

### 3. Extensibility

- **New Tools**: Easy to add comprehensive tool descriptions
- **New Modes**: Mode-specific instructions are modular
- **New Stages**: Reasoning instructions can be added per stage
- **Custom Prompts**: Users can override system prompts

### 4. Consistency

- **Unified Assembly**: Same factory used by OpenRouter and MLX services
- **Standardized Format**: All tools follow the same description structure
- **Priority System**: Consistent component ordering across services

## Migration Strategy

### Phase 1: Core Framework

1. Implement `EnhancedAITool` protocol and `PromptFactory`
2. Create base system prompt template
3. Update `WriteFilesTool` with enhanced descriptions
4. Integrate factory into OpenRouter service

### Phase 2: Tool Enhancement

1. Add enhanced descriptions to all file operation tools
2. Add enhanced descriptions to index tools
3. Add enhanced descriptions to execution tools
4. Update tool provider to return enhanced tools

### Phase 3: Prompt Optimization

1. Create comprehensive tool description markdown files
2. Add mode-specific instruction files
3. Add reasoning instruction files
4. Optimize prompts based on testing results

### Phase 4: Full Integration

1. Replace old prompt assembly logic
2. Update MLX service to use same factory
3. Add prompt versioning and A/B testing
4. Document best practices and guidelines

## Testing Strategy

### 1. Unit Tests

- Test prompt factory assembly with different configurations
- Test tool description generation
- Test template variable substitution
- Test component priority ordering

### 2. Integration Tests

- Test OpenRouter service with new prompts
- Test MLX service with new prompts
- Test tool calling with enhanced descriptions
- Test error handling scenarios

### 3. End-to-End Tests

- Test React app creation with enhanced prompts
- Test complex multi-file operations
- Test error recovery and fallback scenarios
- Test performance with large tool sets

## Success Metrics

### 1. Tool Calling Accuracy

- **Target**: 95% of tool calls are correctly structured
- **Current**: ~60% (models respond with text instead of tool calls)
- **Measurement**: Automated analysis of tool call patterns

### 2. Task Completion Rate

- **Target**: 90% of multi-file tasks complete successfully
- **Current**: ~40% (models don't use tools properly)
- **Measurement**: Harness test success rates

### 3. Prompt Maintainability

- **Target**: Prompt changes require no code modifications
- **Current**: Prompt changes require code updates
- **Measurement**: Number of code changes needed for prompt updates

## Conclusion

This comprehensive prompt framework addresses the root cause of tool calling issues by providing models with clear, detailed instructions on when and how to use tools. The modular, template-based design ensures maintainability and extensibility while the factory pattern provides consistent assembly across all AI services.

The framework transforms the current brittle, hardcoded prompt system into a robust, maintainable solution that can evolve with the product's needs.
