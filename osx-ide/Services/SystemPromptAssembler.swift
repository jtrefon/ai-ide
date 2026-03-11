import Foundation

struct SystemPromptAssembler {
    struct Input {
        let systemPromptOverride: String
        let hasTools: Bool
        let toolPromptMode: ToolPromptMode
        let mode: AIMode?
        let projectRoot: URL?
        let reasoningMode: ReasoningMode
        let stage: AIRequestStage?
        let includeModelReasoning: Bool
    }

    func assemble(input: Input) throws -> String {
        var sections: [String] = []

        let systemPromptOverride = input.systemPromptOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if systemPromptOverride.isEmpty {
            sections.append(try PromptRepository.shared.prompt(
                key: "System/base-system-prompt",
                projectRoot: input.projectRoot
            ))
        } else {
            sections.append(systemPromptOverride)
        }

        if input.hasTools {
            sections.append(try PromptRepository.shared.prompt(
                key: input.toolPromptMode == .fullStatic
                    ? "System/tool-system-prompt-full"
                    : "System/tool-system-prompt-concise",
                projectRoot: input.projectRoot
            ))
        }

        if let mode = input.mode {
            sections.append(try PromptRepository.shared.prompt(
                key: mode == .agent ? "System/mode-agent" : "System/mode-chat",
                projectRoot: input.projectRoot
            ))
        }

        if let projectRoot = input.projectRoot {
            let projectRootContextTemplate = try PromptRepository.shared.prompt(
                key: "System/project-root-context",
                projectRoot: projectRoot
            )
            sections.append(
                projectRootContextTemplate.replacingOccurrences(
                    of: "{{PROJECT_ROOT_PATH}}",
                    with: projectRoot.path
                )
            )
        }

        if input.includeModelReasoning {
            sections.append(try PromptRepository.shared.prompt(
                key: input.reasoningMode.modelReasoningPromptKey,
                projectRoot: input.projectRoot
            ))
        }

        if let reasoningPrompt = try AIRequestStage.reasoningPromptIfNeeded(
            reasoningMode: input.reasoningMode,
            mode: input.mode,
            stage: input.stage,
            projectRoot: input.projectRoot
        ) {
            sections.append(reasoningPrompt)
        }

        return sections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
