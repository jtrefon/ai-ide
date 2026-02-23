import Foundation

/// Factory for assembling system prompts from fragmented components
public actor PromptFactory {
    
    // MARK: - Dependencies
    private let settingsStore: any OpenRouterSettingsLoading
    
    init(settingsStore: any OpenRouterSettingsLoading = OpenRouterSettingsStore()) {
        self.settingsStore = settingsStore
    }
    
    // MARK: - Main Assembly Method
    
    /// Assembles a complete system prompt from all components
    public func assembleSystemPrompt(
        tools: [EnhancedAITool]?,
        mode: AIMode?,
        projectRoot: URL?,
        reasoningEnabled: Bool,
        stage: AIRequestStage?
    ) async throws -> String {
        var components: [PromptComponent] = []
        
        // 1. Base system prompt
        components.append(await loadBaseSystemPrompt())
        
        // 2. Tool descriptions (if available)
        if let tools = tools, !tools.isEmpty {
            components.append(buildToolDescriptionsComponent(tools: tools))
        }
        
        // 3. Mode-specific instructions
        if let mode = mode {
            components.append(buildModeComponent(mode: mode))
        }
        
        // 4. Project context
        if let projectRoot = projectRoot {
            components.append(buildProjectContextComponent(projectRoot: projectRoot))
        }
        
        // 5. Reasoning instructions
        if let reasoningComponent = try await buildReasoningComponent(
            enabled: reasoningEnabled,
            mode: mode,
            stage: stage
        ) {
            components.append(reasoningComponent)
        }
        
        // 6. Custom user prompt override
        if let customPrompt = await loadCustomSystemPrompt() {
            components.insert(customPrompt, at: 1) // After base prompt
        }
        
        return assembleComponents(components)
    }
    
    // MARK: - Component Builders
    
    private func loadBaseSystemPrompt() async -> PromptComponent {
        let path = "Prompts/System/base-system-prompt.md"
        
        do {
            let content = try String(
                contentsOfFile: path,
                encoding: .utf8
            )
            return PromptComponent(
                type: .baseSystem,
                content: content,
                priority: 100
            )
        } catch {
            // Fallback to hardcoded base prompt
            return PromptComponent(
                type: .baseSystem,
                content: """
                You are an expert AI software engineer assistant integrated into an IDE.
                
                ## Core Principles
                
                - **Use tools, don't describe actions**: When tools are available, you MUST return real structured tool calls
                - **Index-first discovery**: Always use codebase index tools for file discovery
                - **Read before editing**: Understand existing code before making changes
                - **Prefer precise operations**: Use targeted edits over full file rewrites
                """,
                priority: 100
            )
        }
    }
    
    private func buildToolDescriptionsComponent(tools: [EnhancedAITool]) -> PromptComponent {
        let descriptions = ToolPromptBuilder.buildToolDescriptionsSection(for: tools)
        return PromptComponent(
            type: .toolDescriptions,
            content: descriptions,
            priority: 200
        )
    }
    
    private func buildModeComponent(mode: AIMode) -> PromptComponent {
        let content: String
        
        switch mode {
        case .chat:
            content = """
            ## Chat Mode
            
            You are in chat mode. Focus on providing helpful information and guidance.
            Read-only tools are available for exploration and information gathering.
            Do not make modifications to files or run commands unless explicitly requested.
            """
        case .agent:
            content = """
            ## Agent Mode
            
            You are in agent mode with full tool access. Take initiative to complete tasks:
            
            - **Proactive execution**: When users ask for changes, immediately use tools to implement them
            - **Structured responses**: Always use tool calls for actions, not prose descriptions
            - **Verification**: Confirm tool results before proceeding to next steps
            - **Planning**: Break complex tasks into sequential tool operations
            """
        }
        
        return PromptComponent(
            type: .modeSpecific,
            content: content,
            priority: 300
        )
    }
    
    private func buildProjectContextComponent(projectRoot: URL) -> PromptComponent {
        let projectName = projectRoot.lastPathComponent
        return PromptComponent(
            type: .projectContext,
            content: """
            ## Project Context
            
            **Project Root**: `\(projectRoot.path)`
            **Project Name**: \(projectName)
            
            All file operations are relative to this project root unless absolute paths are specified.
            You are sandboxed to this directory and its subdirectories.
            """,
            priority: 400
        )
    }
    
    private func buildReasoningComponent(
        enabled: Bool,
        mode: AIMode?,
        stage: AIRequestStage?
    ) async throws -> PromptComponent? {
        guard enabled, mode == .agent else { return nil }
        
        let reasoningPrompt = try await loadReasoningPrompt(stage: stage)
        return PromptComponent(
            type: .reasoning,
            content: reasoningPrompt,
            priority: 500
        )
    }
    
    private func loadCustomSystemPrompt() async -> PromptComponent? {
        let settings = settingsStore.load(includeApiKey: false)
        guard !settings.systemPrompt.isEmpty else { return nil }
        
        return PromptComponent(
            type: .customOverride,
            content: settings.systemPrompt,
            priority: 150 // High priority, but after base
        )
    }
    
    // MARK: - Assembly Logic
    
    private func assembleComponents(_ components: [PromptComponent]) -> String {
        // Sort by priority and join with proper spacing
        let sorted = components.sorted { $0.priority < $1.priority }
        var sections: [String] = []
        
        for component in sorted {
            if !sections.isEmpty {
                sections.append("") // Add blank line between components
            }
            sections.append(component.content)
        }
        
        return sections.joined(separator: "\n")
    }
    
    // MARK: - Helper Methods
    
    private func loadReasoningPrompt(stage: AIRequestStage?) async throws -> String {
        // Load reasoning prompt based on stage
        switch stage {
        case .initial_response:
            return """
                ## Reasoning Instructions
                
                You are in the initial response stage. Provide a high-level plan before execution:
                
                1. **Analysis**: Understand the user's request and current state
                2. **Planning**: Outline the approach and tools needed
                3. **Next Steps**: Specify immediate tool calls to begin implementation
                
                Use the `<ide_reasoning>` tag to structure your analysis.
                """
        case .tool_loop:
            return """
                ## Reasoning Instructions
                
                You are in the tool loop stage. Focus on execution:
                
                1. **Execute**: Make the necessary tool calls
                2. **Verify**: Check results and handle errors
                3. **Continue**: Proceed with next steps or complete the task
                
                Do not include reasoning in this stage - focus on tool execution.
                """
        default:
            return """
                ## Reasoning Instructions
                
                Use structured reasoning to plan and execute tasks effectively.
                Include analysis, planning, and next steps in your reasoning.
                """
        }
    }
}

// MARK: - Supporting Types

public struct PromptComponent {
    let type: ComponentType
    let content: String
    let priority: Int
}

public enum ComponentType {
    case baseSystem
    case customOverride
    case toolDescriptions
    case modeSpecific
    case projectContext
    case reasoning
    case stageSpecific
}
