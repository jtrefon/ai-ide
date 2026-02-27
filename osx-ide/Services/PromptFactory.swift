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
        components.append(try loadBaseSystemPrompt(projectRoot: projectRoot))
        
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
            stage: stage,
            projectRoot: projectRoot
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
    
    private func loadBaseSystemPrompt(projectRoot: URL?) throws -> PromptComponent {
        let content = try PromptRepository.shared.prompt(
            key: "System/base-system-prompt",
            projectRoot: projectRoot
        )
        return PromptComponent(
            type: .baseSystem,
            content: content,
            priority: 100
        )
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
        stage: AIRequestStage?,
        projectRoot: URL?
    ) async throws -> PromptComponent? {
        guard enabled, mode == .agent else { return nil }
        if stage == .initial_response { return nil }
        
        let reasoningPrompt = try loadReasoningPrompt(stage: stage, projectRoot: projectRoot)
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
    
    private func loadReasoningPrompt(stage: AIRequestStage?, projectRoot: URL?) throws -> String {
        let key: String = {
            if stage == .tool_loop {
                return "ConversationFlow/Corrections/reasoning_optional_tool_loop"
            }
            return "ConversationFlow/Corrections/reasoning_optional_general"
        }()
        return try PromptRepository.shared.prompt(key: key, projectRoot: projectRoot)
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
